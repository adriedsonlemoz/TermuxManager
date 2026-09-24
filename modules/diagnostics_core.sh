# Módulo: diagnostics.sh
# Central de diagnóstico, captura de falhas e exportação segura de logs.

DIAGNOSTICS_DIR="$LOG_DIR/diagnostics"
MANAGER_INCIDENT_DIR="$DIAGNOSTICS_DIR/manager"
MANAGER_INCIDENT_INDEX="$DIAGNOSTICS_DIR/manager-incidents.log"
DIAGNOSTIC_MAX_INCIDENTS=60
DIAGNOSTIC_TRAP_ACTIVE=0
DIAGNOSTIC_LAST_SIGNATURE=""
DIAGNOSTIC_LAST_EPOCH=0


caixa_diagnostico_inicio() {
    local titulo="$1"
    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}${titulo}${C_RESET}" true
    caixa_linha_sep
}

linha_diagnostico() {
    local texto="$1" cor="${2:-}"
    caixa_linha_texto "${cor}${texto}${C_RESET}"
}

caixa_diagnostico_fim() {
    caixa_linha_baixo
}

DIAGNOSTIC_ERROR_REGEX='(^|[^[:alpha:]])(error|erro|failed|failure|falha|fatal|exception|traceback|command not found|permission denied|not found|refused|timeout|timed out|eaddrinuse|unhandled|panic|segmentation fault|sigterm|sigkill|npm err|syntaxerror|typeerror|referenceerror|mongooseerror|mongoerror)([^[:alpha:]]|$)'

inicializar_diagnosticos() {
    mkdir -p "$DIAGNOSTICS_DIR" "$MANAGER_INCIDENT_DIR" 2>/dev/null || true
    : >> "$MANAGER_INCIDENT_INDEX" 2>/dev/null || true
}

sanitizar_nome_arquivo() {
    local nome="${1:-registro}"
    nome="$(printf '%s' "$nome" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g; s/-+/-/g')"
    [ -n "$nome" ] || nome="registro"
    printf '%s' "$nome"
}

redigir_segredos() {
    # Remove segredos comuns sem modificar o arquivo original.
    # Primeiro elimina o corpo completo de blocos PEM; depois redige tokens,
    # inclusive valores entre aspas duplas com espaços.
    awk '
        /-----BEGIN [A-Z ]*PRIVATE KEY-----/ {
            print $0 " [CONTEÚDO REMOVIDO]"
            em_chave=1
            next
        }
        em_chave {
            if (/-----END [A-Z ]*PRIVATE KEY-----/) {
                print
                em_chave=0
            }
            next
        }
        { print }
    ' | sed -E \
        -e 's/((JWT_SECRET|SESSION_SECRET|COOKIE_SECRET|CLIENT_SECRET|API_KEY|APIKEY|ACCESS_TOKEN|REFRESH_TOKEN|TOKEN|PASSWORD|PASS|PRIVATE_KEY|CLOUDINARY_API_SECRET|DATABASE_URL|MONGO_URI|MONGODB_URI|REDIS_URL)[[:space:]]*[:=][[:space:]]*)("[^"]*"|[^[:space:]]+)/\1[REMOVIDO]/Ig' \
        -e 's/(Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+)[A-Za-z0-9._~+\/-]+=*/\1[REMOVIDO]/Ig' \
        -e 's#(mongodb(\+srv)?|postgres(ql)?|mysql|redis)://[^/@:[:space:]]+:[^/@[:space:]]+@#\1://[CREDENCIAIS_REMOVIDAS]@#Ig'
}
podar_incidentes_manager() {
    local total remover
    [ -d "$MANAGER_INCIDENT_DIR" ] || return 0
    total=$(find "$MANAGER_INCIDENT_DIR" -maxdepth 1 -type f -name 'erro-*.txt' 2>/dev/null | wc -l | tr -d ' ')
    [ "${total:-0}" -le "$DIAGNOSTIC_MAX_INCIDENTS" ] && return 0
    remover=$((total - DIAGNOSTIC_MAX_INCIDENTS))
    find "$MANAGER_INCIDENT_DIR" -maxdepth 1 -type f -name 'erro-*.txt' -printf '%T@ %p\n' 2>/dev/null \
        | sort -n | head -n "$remover" | cut -d' ' -f2- | while IFS= read -r arquivo; do
            rm -f -- "$arquivo" 2>/dev/null || true
        done
}

erro_shell_esperado() {
    local codigo="$1" comando="$2"
    # Status usados como controle de fluxo não são falhas técnicas.
    if [ "$codigo" = 130 ] || [ "$codigo" = 141 ]; then
        return 0
    fi
    [[ "$comando" =~ ^[[:space:]]*(return([[:space:]]|$)|break([[:space:]]|$)|continue([[:space:]]|$)|\[|\[\[|test[[:space:]]|\(\(|false$|read([[:space:]]|$)|command[[:space:]]+-v|kill[[:space:]]+-0|grep([[:space:]]|$)|awk([[:space:]]|$)|find([[:space:]]|$)|stat([[:space:]]|$)|du([[:space:]]|$)|tput([[:space:]]|$)|stty([[:space:]]|$)) ]] && return 0
    [[ "$comando" == *"stty size"* || "$comando" == *"tput cols"* || "$comando" == *"awk '{print \$2}'"* ]] && return 0
    return 1
}

capturar_erro_manager() {
    local codigo="${1:-1}" linha="${2:-0}" comando="${3:-desconhecido}" funcao="${4:-main}"
    [ "${DIAGNOSTIC_TRAP_ACTIVE:-0}" = 1 ] && return 0
    [ "$codigo" = 0 ] && return 0
    erro_shell_esperado "$codigo" "$comando" && return 0

    # O trap ERR pode subir da função para o chamador e repetir a mesma falha.
    # Deduplica a mesma assinatura dentro do mesmo segundo.
    local agora_epoch assinatura
    agora_epoch="$(date +%s 2>/dev/null || printf '0')"
    assinatura="${codigo}|${comando}"
    # A propagação do trap ERR pode ocorrer somente depois que o primeiro
    # relatório termina de ser gravado. Em aparelhos lentos isso atravessa a
    # virada de segundo e a comparação anterior (mesmo segundo) gerava dois
    # incidentes para a mesma falha. Considera duplicada a mesma assinatura
    # registrada nos últimos 5 segundos.
    local ultimo_epoch="${DIAGNOSTIC_LAST_EPOCH:-0}" delta_epoch=999
    if [[ "$agora_epoch" =~ ^[0-9]+$ && "$ultimo_epoch" =~ ^[0-9]+$ ]]; then
        delta_epoch=$((agora_epoch - ultimo_epoch))
        [ "$delta_epoch" -lt 0 ] && delta_epoch=$(( -delta_epoch ))
    fi
    if [ "$assinatura" = "${DIAGNOSTIC_LAST_SIGNATURE:-}" ] && [ "$delta_epoch" -le 5 ]; then
        return 0
    fi
    DIAGNOSTIC_LAST_SIGNATURE="$assinatura"
    DIAGNOSTIC_LAST_EPOCH="$agora_epoch"
    DIAGNOSTIC_TRAP_ACTIVE=1

    inicializar_diagnosticos
    local agora carimbo arquivo origem
    agora="$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date)"
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)-$$-${RANDOM:-0}"
    arquivo="$MANAGER_INCIDENT_DIR/erro-$carimbo.txt"
    origem="${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-${SELF_PATH:-manager.sh}}}"

    {
        printf '%s\n' '========== ERRO CAPTURADO PELO MANAGER =========='
        printf 'Data: %s\n' "$agora"
        printf 'Versão: %s\n' "${MANAGER_VERSION:-desconhecida}"
        printf 'Código de saída: %s\n' "$codigo"
        printf 'Arquivo: %s\n' "$(caminho_curto "$origem")"
        printf 'Linha: %s\n' "$linha"
        printf 'Função: %s\n' "$funcao"
        printf 'Comando: %s\n' "$comando"
        printf 'Shell: %s\n' "${SHELL:-desconhecido}"
        printf 'Diretório: %s\n' "$PWD"
        printf 'PID: %s\n' "$$"
        printf '%s\n' '-----------------------------------------------'
        printf '%s\n' 'ÚLTIMAS LINHAS DO LOG PRINCIPAL:'
        tail -n 25 "$LOG_FILE" 2>/dev/null || true
        printf '%s\n' '==================== FIM ======================'
    } | redigir_segredos > "$arquivo" 2>/dev/null || true

    printf '[%s] rc=%s arquivo=%s linha=%s função=%s comando=%s incidente=%s\n' \
        "$agora" "$codigo" "$origem" "$linha" "$funcao" "$comando" "$arquivo" \
        | redigir_segredos >> "$MANAGER_INCIDENT_INDEX" 2>/dev/null || true

    podar_incidentes_manager
    DIAGNOSTIC_TRAP_ACTIVE=0
    return 0
}

ativar_captura_diagnosticos() {
    inicializar_diagnosticos
    # ERR é herdado pelas funções porque manager.sh usa set -E.
    trap 'rc=$?; capturar_erro_manager "$rc" "$LINENO" "$BASH_COMMAND" "${FUNCNAME[0]:-main}"' ERR
}

arquivo_tem_erros() {
    local arquivo="$1"
    [ -s "$arquivo" ] || return 1
    grep -qiE "$DIAGNOSTIC_ERROR_REGEX" "$arquivo" 2>/dev/null
}

contar_erros_arquivo() {
    local arquivo="$1" qtd
    [ -s "$arquivo" ] || { printf '0'; return 0; }
    qtd="$(grep -iEc "$DIAGNOSTIC_ERROR_REGEX" "$arquivo" 2>/dev/null || true)"
    printf '%s' "${qtd:-0}"
}

tamanho_legivel_arquivo() {
    local arquivo="$1"
    if [ -f "$arquivo" ]; then
        du -h "$arquivo" 2>/dev/null | awk '{print $1}'
    else
        printf '0 B'
    fi
}

data_arquivo_curta() {
    local arquivo="$1"
    stat -c '%y' "$arquivo" 2>/dev/null | cut -d'.' -f1 | sed 's/^[0-9]\{4\}-//; s/ / • /' || printf 'sem data'
}

listar_correspondencias_erro() {
    local arquivo="$1" limite="${2:-40}"
    grep -inE "$DIAGNOSTIC_ERROR_REGEX" "$arquivo" 2>/dev/null | tail -n "$limite" || true
}

resolver_downloads_diagnostico() {
    if ! resolver_downloads_dir >/dev/null 2>&1; then
        error "Downloads indisponível. Execute termux-setup-storage."
        return 1
    fi
    mkdir -p "$DOWNLOADS_DIR" 2>/dev/null || return 1
}

cabecalho_relatorio_diagnostico() {
    local categoria="$1" fonte="$2" linha="${3:-completo}"
    printf '%s\n' '========== RELATÓRIO DO TERMUX MANAGER =========='
    printf 'Gerado em: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date)"
    printf 'Manager: %s\n' "${MANAGER_VERSION:-desconhecida}"
    printf 'Categoria: %s\n' "$categoria"
    printf 'Fonte: %s\n' "$fonte"
    printf 'Linha selecionada: %s\n' "$linha"
    declare -F detectar_variante_termux >/dev/null 2>&1 && detectar_variante_termux
    printf 'Termux: %s\n' "${TERMUX_VERSION:-indisponível}"
    printf 'Origem do Termux: %s\n' "${TERMUX_VARIANT_LABEL:-indisponível}"
    printf 'Repositório: %s\n' "${TERMUX_REPO_PRIMARY:-indisponível}"
    printf 'Sistema: %s\n' "$(uname -a 2>/dev/null || printf 'indisponível')"
    printf '%s\n' 'Observação: segredos comuns foram removidos da cópia.'
    printf '%s\n' '--------------------------------------------------'
}

exportar_trecho_diagnostico() {
    local categoria="$1" fonte="$2" linha="${3:-0}" nome_base="${4:-diagnostico}"
    resolver_downloads_diagnostico || return 1
    [ -f "$fonte" ] || { error "Arquivo de log não encontrado."; return 1; }

    local carimbo slug destino inicio fim
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    slug="$(sanitizar_nome_arquivo "$nome_base")"
    destino="$DOWNLOADS_DIR/${slug}-erro-$carimbo.txt"

    {
        cabecalho_relatorio_diagnostico "$categoria" "$fonte" "$([ "$linha" -gt 0 ] 2>/dev/null && printf '%s' "$linha" || printf 'log completo')"
        if [ "$linha" -gt 0 ] 2>/dev/null; then
            inicio=$((linha - 20)); [ "$inicio" -lt 1 ] && inicio=1
            fim=$((linha + 20))
            printf 'Contexto: linhas %s a %s\n\n' "$inicio" "$fim"
            sed -n "${inicio},${fim}p" "$fonte"
        else
            cat "$fonte"
        fi
        printf '\n%s\n' '==================== FIM ======================'
    } | redigir_segredos > "$destino"

    caixa_simples "📥 Diagnóstico exportado" \
        "Arquivo: $(basename "$destino")" \
        "Tamanho: $(tamanho_legivel_arquivo "$destino")" \
        "Destino: $(caminho_curto "$DOWNLOADS_DIR")" \
        "Segredos comuns: removidos"
    pause
}


gerar_snapshot_termux() {
    inicializar_diagnosticos
    local destino="$DIAGNOSTICS_DIR/termux-atual.txt"
    {
        printf '%s\n' '========== DIAGNÓSTICO ATUAL DO TERMUX =========='
        printf 'Data: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date)"
        printf 'Manager: %s\n' "${MANAGER_VERSION:-desconhecida}"
        declare -F detectar_variante_termux >/dev/null 2>&1 && detectar_variante_termux
        printf 'Termux: %s\n' "${TERMUX_VERSION:-indisponível}"
        printf 'Origem do Termux: %s\n' "${TERMUX_VARIANT_LABEL:-indisponível}"
        printf 'Repositório: %s\n' "${TERMUX_REPO_PRIMARY:-indisponível}"
        printf 'PREFIX: %s\n' "${PREFIX:-indisponível}"
        printf 'Shell: %s\n' "${SHELL:-indisponível}"
        printf 'Arquitetura: %s\n' "$(dpkg --print-architecture 2>/dev/null || uname -m 2>/dev/null)"
        printf 'Sistema: %s\n' "$(uname -a 2>/dev/null)"
        printf 'Espaço em HOME: %s\n' "$(df -h "$HOME" 2>/dev/null | awk 'NR==2 {print $4 " livres de " $2}')"
        printf 'Pacotes instalados: %s\n' "$(dpkg-query -W 2>/dev/null | wc -l | tr -d ' ')"
        printf '%s\n' '-------------------------------------------------'
        printf '%s\n' 'DPKG AUDIT:'
        dpkg --audit 2>/dev/null || true
        printf '%s\n' '-------------------------------------------------'
        printf '%s\n' 'TERMUX-INFO:'
        if command -v termux-info >/dev/null 2>&1; then
            termux-info 2>&1 || true
        else
            printf '%s\n' 'termux-info não está disponível.'
        fi
        printf '%s\n' '-------------------------------------------------'
        printf '%s\n' 'ÚLTIMAS LINHAS DO LOG DE PACOTES:'
        tail -n 80 "${TERMUX_SETUP_LOG:-/arquivo/inexistente}" 2>/dev/null || true
        printf '%s\n' '==================== FIM ======================='
    } | redigir_segredos > "$destino"
    printf '%s' "$destino"
}

