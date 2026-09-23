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
    sed -E \
        -e 's/((JWT_SECRET|SESSION_SECRET|COOKIE_SECRET|CLIENT_SECRET|API_KEY|APIKEY|ACCESS_TOKEN|REFRESH_TOKEN|TOKEN|PASSWORD|PASS|PRIVATE_KEY|CLOUDINARY_API_SECRET|DATABASE_URL|MONGO_URI|MONGODB_URI|REDIS_URL)[[:space:]]*[:=][[:space:]]*)[^[:space:]"]+/\1[REMOVIDO]/Ig' \
        -e 's/(Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+)[A-Za-z0-9._~+\/-]+=*/\1[REMOVIDO]/Ig' \
        -e 's#(mongodb(\+srv)?|postgres(ql)?|mysql|redis)://[^/@:[:space:]]+:[^/@[:space:]]+@#\1://[CREDENCIAIS_REMOVIDAS]@#Ig' \
        -e 's/(-----BEGIN [A-Z ]*PRIVATE KEY-----).*/\1 [CONTEÚDO REMOVIDO]/g'
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
    if [ "$assinatura" = "${DIAGNOSTIC_LAST_SIGNATURE:-}" ] && [ "$agora_epoch" = "${DIAGNOSTIC_LAST_EPOCH:-0}" ]; then
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

selecionar_erro_arquivo() {
    local categoria="$1" arquivo="$2" nome_exibido="$3" nome_saida="$4"
    local -a linhas=() textos=()
    local registro numero conteudo i escolha

    while IFS= read -r registro; do
        [ -n "$registro" ] || continue
        numero="${registro%%:*}"
        conteudo="${registro#*:}"
        linhas+=("$numero")
        textos+=("$conteudo")
    done < <(listar_correspondencias_erro "$arquivo" 25)

    while true; do
        detectar_terminal
        cabecalho_tela "🧩 Erros detectados" "$nome_exibido"
        if [ "${#linhas[@]}" -eq 0 ]; then
            caixa_simples "Nenhum padrão de erro reconhecido" \
                "O log existe, mas não contém palavras de erro conhecidas." \
                "Você ainda pode exportar o arquivo completo." \
                "Tamanho: $(tamanho_legivel_arquivo "$arquivo")"
        else
            caixa_diagnostico_inicio "Selecione um registro"
            for ((i=0; i<${#linhas[@]}; i++)); do
                linha_diagnostico "$((i+1))) Linha ${linhas[$i]} — $(truncar_visivel "${textos[$i]}" $((LARGURA_CAIXA - 18)))"
            done
            caixa_diagnostico_fim
        fi
        caixa_simples "Ações" \
            "[A] Exportar o log completo" \
            "[0] Voltar" \
            "Os relatórios são copiados para Downloads."
        rodape_atalhos "[número] Exportar erro  •  [A] Log completo  •  [0] Voltar"
        ui_buffer_flush
        read -r escolha
        case "${escolha,,}" in
            0) return ;;
            a) exportar_trecho_diagnostico "$categoria" "$arquivo" 0 "$nome_saida" ;;
            *)
                if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le "${#linhas[@]}" ]; then
                    exportar_trecho_diagnostico "$categoria" "$arquivo" "${linhas[$((escolha-1))]}" "$nome_saida"
                else
                    feedback_curto "Opção inválida."
                fi
                ;;
        esac
    done
}

menu_erros_manager() {
    local -a arquivos=() nomes=()
    local f escolha i erros
    while true; do
        arquivos=(); nomes=()
        [ -s "$MANAGER_INCIDENT_INDEX" ] && arquivos+=("$MANAGER_INCIDENT_INDEX") && nomes+=("Índice de falhas técnicas")
        [ -s "$LOG_FILE" ] && arquivos+=("$LOG_FILE") && nomes+=("Log principal do Manager")
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            arquivos+=("$f")
            nomes+=("Incidente $(basename "$f" .txt | sed 's/^erro-//')")
        done < <(find "$MANAGER_INCIDENT_DIR" -maxdepth 1 -type f -name 'erro-*.txt' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 20 | cut -d' ' -f2-)

        cabecalho_tela "🧠 Erros do Manager" "Falhas internas e mensagens registradas"
        if [ "${#arquivos[@]}" -eq 0 ]; then
            caixa_simples "Nenhum registro disponível" "O Manager ainda não registrou erros técnicos."
        else
            caixa_diagnostico_inicio "Registros disponíveis"
            for ((i=0; i<${#arquivos[@]}; i++)); do
                erros="$(contar_erros_arquivo "${arquivos[$i]}")"
                linha_diagnostico "$((i+1))) ${nomes[$i]}"
                linha_diagnostico "   ${erros} ocorrência(s) • $(tamanho_legivel_arquivo "${arquivos[$i]}") • $(data_arquivo_curta "${arquivos[$i]}")" "$C_DIM"
            done
            caixa_diagnostico_fim
        fi
        rodape_atalhos "[número] Abrir  •  [0] Voltar"
        ui_buffer_flush
        read -r escolha
        [ "$escolha" = 0 ] && return
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le "${#arquivos[@]}" ]; then
            i=$((escolha-1))
            selecionar_erro_arquivo "Manager" "${arquivos[$i]}" "${nomes[$i]}" "manager-${nomes[$i]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}

menu_logs_projetos() {
    local -a arquivos=() nomes=()
    local f escolha i erros
    while true; do
        arquivos=(); nomes=()
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            arquivos+=("$f")
            nomes+=("$(basename "$f" .log)")
        done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' ! -name 'manager.log' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

        cabecalho_tela "🚀 Logs de projetos" "Frontend, backend e processos executados"
        if [ "${#arquivos[@]}" -eq 0 ]; then
            caixa_simples "Nenhum log de projeto" \
                "Execute um projeto pelo Manager para gerar registros." \
                "Somente logs existentes aparecem nesta lista."
        else
            caixa_diagnostico_inicio "Projetos registrados"
            for ((i=0; i<${#arquivos[@]}; i++)); do
                erros="$(contar_erros_arquivo "${arquivos[$i]}")"
                linha_diagnostico "$((i+1))) ${nomes[$i]}"
                linha_diagnostico "   ${erros} erro(s) reconhecido(s) • $(tamanho_legivel_arquivo "${arquivos[$i]}") • $(data_arquivo_curta "${arquivos[$i]}")" "$C_DIM"
            done
            caixa_diagnostico_fim
        fi
        rodape_atalhos "[número] Abrir  •  [0] Voltar"
        ui_buffer_flush
        read -r escolha
        [ "$escolha" = 0 ] && return
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le "${#arquivos[@]}" ]; then
            i=$((escolha-1))
            selecionar_erro_arquivo "Projeto" "${arquivos[$i]}" "${nomes[$i]}" "projeto-${nomes[$i]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}


# ============================================================================
# COLETA DE LOGS DO TESTE DE PROJETO
# ============================================================================

ULTIMO_RELATORIO_TESTE=""

coletar_logs_teste_projeto() {
    # coletar_logs_teste_projeto <projeto> [processo_frontend] [processo_backend] [motivo]
    local projeto="$1" nome_front="${2:-}" nome_back="${3:-}" motivo="${4:-Falha durante o teste do projeto}"
    resolver_downloads_diagnostico || return 1

    local carimbo slug destino front_log="" back_log="" front_meta="" back_meta=""
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    slug="$(sanitizar_nome_arquivo "$(basename "$projeto")")"
    destino="$DOWNLOADS_DIR/${slug}-teste-erro-$carimbo.txt"

    [ -n "$nome_front" ] && front_log="$LOG_DIR/${nome_front}.log" && front_meta="$PID_DIR/${nome_front}.meta"
    [ -n "$nome_back" ] && back_log="$LOG_DIR/${nome_back}.log" && back_meta="$PID_DIR/${nome_back}.meta"

    {
        printf '%s
' '========== TESTE DE PROJETO — TERMUX MANAGER =========='
        printf 'Gerado em: %s
' "$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date)"
        printf 'Manager: %s
' "${MANAGER_VERSION:-desconhecida}"
        printf 'Projeto: %s
' "$(basename "$projeto")"
        printf 'Diretório: %s
' "$(caminho_home_relativo "$projeto")"
        printf 'Motivo: %s
' "$motivo"
        printf 'Node: %s
' "$(node --version 2>/dev/null || printf 'indisponível')"
        printf 'npm: %s
' "$(npm --version 2>/dev/null || printf 'indisponível')"
        printf 'Shell: %s
' "${SHELL:-indisponível}"
        printf '
%s
        printf '\n%s\n' '========== RESOLUÇÃO DO PROJETO =========='
        printf 'Projeto selecionado: %s\n' "$(caminho_home_relativo "$projeto")"
        if declare -F detectar_estrutura_projeto >/dev/null 2>&1; then
            detectar_estrutura_projeto "$projeto" >/dev/null 2>&1 || true
            [ -n "${BACK_DIR:-}" ] && printf 'Backend resolvido: %s\n' "$(caminho_home_relativo "$BACK_DIR")"
            [ -n "${FRONT_DIR:-}" ] && printf 'Frontend resolvido: %s\n' "$(caminho_home_relativo "$FRONT_DIR")"
            [ -n "${BACK_DIR:-}" ] && printf 'Cache backend: %s\n' "$(caminho_home_relativo "$(dependency_stamp_path "$BACK_DIR")")"
            [ -n "${FRONT_DIR:-}" ] && printf 'Cache frontend: %s\n' "$(caminho_home_relativo "$(dependency_stamp_path "$FRONT_DIR")")"
        fi
' '========== ESTADO DOS PROCESSOS =========='

        local nome meta pidf pid estado componente cmd porta esp
        for nome in "$nome_back" "$nome_front"; do
            [ -n "$nome" ] || continue
            meta="$PID_DIR/${nome}.meta"; pidf="$PID_DIR/${nome}.pid"
            pid="$(cat "$pidf" 2>/dev/null || printf 'indisponível')"
            componente="$(meta_valor "$meta" COMPONENT 2>/dev/null || printf 'desconhecido')"
            estado="$(meta_valor "$meta" STATE 2>/dev/null || printf 'desconhecido')"
            cmd="$(meta_valor "$meta" CMD 2>/dev/null || printf 'indisponível')"
            porta="$(meta_valor "$meta" PORT 2>/dev/null || true)"
            esp="$(meta_valor "$meta" EXPECTED_PORT 2>/dev/null || true)"
            printf '%s — %s
' "$componente" "$nome"
            printf 'PID: %s
Estado: %s
Comando: %s
' "$pid" "$estado" "$cmd"
            [ -n "$esp" ] && printf 'Porta esperada: %s
' "$esp"
            [ -n "$porta" ] && printf 'Porta detectada: %s
' "$porta"
            printf '%s
' '------------------------------------------'
        done

        printf '
%s
' '========== LOG BACKEND =========='
        if [ -n "$back_log" ] && [ -f "$back_log" ]; then
            cat "$back_log"
        else
            printf 'Log do backend não encontrado: %s
' "$(caminho_home_relativo "${back_log:-não definido}")"
        fi

        printf '
%s
' '========== LOG FRONTEND =========='
        if [ -n "$front_log" ] && [ -f "$front_log" ]; then
            cat "$front_log"
        else
            printf 'Log do frontend não encontrado: %s
' "$(caminho_home_relativo "${front_log:-não definido}")"
        fi

        printf '
%s
' '========== LOG DO MANAGER — ÚLTIMAS 250 LINHAS =========='
        tail -n 250 "$LOG_FILE" 2>/dev/null || printf 'Log principal indisponível.
'

        printf '
%s
' '========== VARIÁVEIS DECLARADAS (.env) =========='
        local envf
        for envf in "$projeto/.env" "$projeto/backend/.env" "$projeto/server/.env" "$projeto/frontend/.env" "$projeto/client/.env"; do
            [ -f "$envf" ] || continue
            printf '%s:
' "$(caminho_home_relativo "$envf")"
            # Somente os nomes das variáveis; nunca os valores.
            sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/  \1=[REMOVIDO]/p' "$envf"
        done
        printf '
%s
' '==================== FIM ======================'
    } | redigir_segredos > "$destino"

    ULTIMO_RELATORIO_TESTE="$destino"
    log "INFO" "Logs do teste exportados para $(caminho_home_relativo "$destino")"
    return 0
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

menu_logs_termux() {
    local -a arquivos=() nomes=()
    local snapshot escolha i erros
    while true; do
        arquivos=(); nomes=()
        snapshot="$(gerar_snapshot_termux)"
        arquivos+=("$snapshot"); nomes+=("Diagnóstico atual do Termux")
        [ -s "${TERMUX_SETUP_LOG:-}" ] && arquivos+=("$TERMUX_SETUP_LOG") && nomes+=("Instalações e atualizações do pkg")
        [ -s "${TERMUX_DIAGNOSTIC_LOG:-}" ] && arquivos+=("$TERMUX_DIAGNOSTIC_LOG") && nomes+=("Último diagnóstico de falha do pkg")

        cabecalho_tela "📱 Diagnóstico do Termux" "Pacotes, ambiente e falhas do sistema"
        caixa_diagnostico_inicio "Fontes disponíveis"
        for ((i=0; i<${#arquivos[@]}; i++)); do
            erros="$(contar_erros_arquivo "${arquivos[$i]}")"
            linha_diagnostico "$((i+1))) ${nomes[$i]}"
            linha_diagnostico "   ${erros} ocorrência(s) • $(tamanho_legivel_arquivo "${arquivos[$i]}") • $(data_arquivo_curta "${arquivos[$i]}")" "$C_DIM"
        done
        caixa_diagnostico_fim
        caixa_simples "Limite" \
            "Esta área cobre o ambiente do Termux e o sistema de pacotes." \
            "Logs internos do Android (logcat) exigem permissões externas."
        rodape_atalhos "[número] Abrir  •  [0] Voltar"
        ui_buffer_flush
        read -r escolha
        [ "$escolha" = 0 ] && return
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le "${#arquivos[@]}" ]; then
            i=$((escolha-1))
            selecionar_erro_arquivo "Termux" "${arquivos[$i]}" "${nomes[$i]}" "termux-${nomes[$i]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}

copiar_sanitizado() {
    local origem="$1" destino="$2"
    [ -f "$origem" ] || return 0
    mkdir -p "$(dirname "$destino")"
    redigir_segredos < "$origem" > "$destino"
}

exportar_todos_relatorios() {
    resolver_downloads_diagnostico || return 1
    inicializar_diagnosticos
    local carimbo destino f snapshot total=0
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    destino="$DOWNLOADS_DIR/TermuxManager-Relatorios-$carimbo"
    mkdir -p "$destino/manager" "$destino/projetos" "$destino/termux" || return 1

    [ -f "$LOG_FILE" ] && copiar_sanitizado "$LOG_FILE" "$destino/manager/log-principal.txt" && total=$((total+1))
    [ -f "$MANAGER_INCIDENT_INDEX" ] && copiar_sanitizado "$MANAGER_INCIDENT_INDEX" "$destino/manager/indice-incidentes.txt" && total=$((total+1))
    for f in "$MANAGER_INCIDENT_DIR"/erro-*.txt; do
        [ -f "$f" ] || continue
        copiar_sanitizado "$f" "$destino/manager/$(basename "$f")"
        total=$((total+1))
    done
    for f in "$LOG_DIR"/*.log; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = manager.log ] && continue
        copiar_sanitizado "$f" "$destino/projetos/$(basename "$f" .log).txt"
        total=$((total+1))
    done
    [ -f "${TERMUX_SETUP_LOG:-}" ] && copiar_sanitizado "$TERMUX_SETUP_LOG" "$destino/termux/operacoes-pkg.txt" && total=$((total+1))
    [ -f "${TERMUX_DIAGNOSTIC_LOG:-}" ] && copiar_sanitizado "$TERMUX_DIAGNOSTIC_LOG" "$destino/termux/ultimo-diagnostico-pkg.txt" && total=$((total+1))
    snapshot="$(gerar_snapshot_termux)"
    copiar_sanitizado "$snapshot" "$destino/termux/ambiente-atual.txt" && total=$((total+1))

    {
        cabecalho_relatorio_diagnostico "Exportação completa" "Manager + projetos + Termux" "todos"
        printf 'Relatórios exportados: %s\n' "$total"
        printf 'Estrutura: manager/ projetos/ termux/\n'
        printf 'Destino: %s\n' "$(caminho_curto "$destino")"
    } > "$destino/LEIA-ME.txt"

    caixa_simples "📤 Todos os relatórios exportados" \
        "Arquivos: $total" \
        "Pastas: manager, projetos e termux" \
        "Segredos comuns: removidos" \
        "Destino: $(caminho_curto "$destino")"
    pause
}

exportar_pacote_diagnostico_completo() {
    resolver_downloads_diagnostico || return 1
    inicializar_diagnosticos
    local carimbo tmp pacote formato f snapshot
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    tmp="$SESSION_TMP_DIR/diagnostico-$carimbo"
    rm -rf "$tmp" 2>/dev/null || true
    mkdir -p "$tmp/manager" "$tmp/projetos" "$tmp/termux"

    copiar_sanitizado "$LOG_FILE" "$tmp/manager/manager.log"
    copiar_sanitizado "$MANAGER_INCIDENT_INDEX" "$tmp/manager/incidentes.log"
    for f in "$MANAGER_INCIDENT_DIR"/erro-*.txt; do
        [ -f "$f" ] || continue
        copiar_sanitizado "$f" "$tmp/manager/$(basename "$f")"
    done
    for f in "$LOG_DIR"/*.log; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = manager.log ] && continue
        copiar_sanitizado "$f" "$tmp/projetos/$(basename "$f")"
    done
    [ -f "${TERMUX_SETUP_LOG:-}" ] && copiar_sanitizado "$TERMUX_SETUP_LOG" "$tmp/termux/termux-setup.log"
    [ -f "${TERMUX_DIAGNOSTIC_LOG:-}" ] && copiar_sanitizado "$TERMUX_DIAGNOSTIC_LOG" "$tmp/termux/ultimo-diagnostico.txt"
    snapshot="$(gerar_snapshot_termux)"
    copiar_sanitizado "$snapshot" "$tmp/termux/ambiente-atual.txt"

    {
        cabecalho_relatorio_diagnostico "Pacote completo" "Manager + projetos + Termux" "todos"
        printf 'Arquivos do Manager: %s\n' "$(find "$tmp/manager" -type f 2>/dev/null | wc -l | tr -d ' ')"
        printf 'Logs de projetos: %s\n' "$(find "$tmp/projetos" -type f 2>/dev/null | wc -l | tr -d ' ')"
        printf 'Arquivos do Termux: %s\n' "$(find "$tmp/termux" -type f 2>/dev/null | wc -l | tr -d ' ')"
        printf 'Diretório do Manager: %s\n' "${BASE_DIR:-indisponível}"
        printf 'Diretório do Painel: %s\n' "$(caminho_curto "$PAINEL_DIR")"
    } > "$tmp/LEIA-ME.txt"
    [ -f "$BASE_DIR/MANIFEST.json" ] && cp -f "$BASE_DIR/MANIFEST.json" "$tmp/manager/MANIFEST.json"

    if command -v zip >/dev/null 2>&1; then
        pacote="$DOWNLOADS_DIR/termux-manager-diagnostico-$carimbo.zip"
        (cd "$tmp" && zip -qr "$pacote" .) || return 1
        formato="ZIP"
    else
        pacote="$DOWNLOADS_DIR/termux-manager-diagnostico-$carimbo.tar.gz"
        tar -czf "$pacote" -C "$tmp" . || return 1
        formato="TAR.GZ"
    fi
    rm -rf "$tmp" 2>/dev/null || true

    caixa_simples "📦 Pacote de diagnóstico criado" \
        "Arquivo: $(basename "$pacote")" \
        "Formato: $formato • Tamanho: $(tamanho_legivel_arquivo "$pacote")" \
        "Categorias: Manager, projetos e Termux" \
        "Segredos comuns: removidos" \
        "Destino: $(caminho_curto "$DOWNLOADS_DIR")"
    pause
}



# Diagnóstico do aparelho Android via Rish/Shizuku.
# Mantém a coleta leve separada dos testes de I/O para evitar relatórios enormes.
localizar_rish_diagnostico() {
    local candidato
    for candidato in "$HOME/rish/rish" "$HOME/rish" "$HOME/bin/rish"; do
        [ -f "$candidato" ] && { printf '%s' "$candidato"; return 0; }
    done
    return 1
}

executar_rish_diagnostico() {
    local comando="$1" rish
    rish="$(localizar_rish_diagnostico)" || return 2
    sh "$rish" -c "$comando" 2>&1
}

verificar_shizuku_diagnostico() {
    local saida
    saida="$(executar_rish_diagnostico 'id' 2>/dev/null)" || return 1
    printf '%s' "$saida" | grep -q 'uid=2000(shell)'
}

coletar_android_shizuku() {
    resolver_downloads_diagnostico || return 1
    cabecalho_tela "📱 Diagnóstico Android" "CPU, memória, térmica, bateria e processos"

    if ! localizar_rish_diagnostico >/dev/null; then
        caixa_simples "Rish não encontrado" \
            "Esperado em: ~/rish/rish" \
            "Configure o Rish do Shizuku e tente novamente."
        pause; return 1
    fi
    if ! verificar_shizuku_diagnostico; then
        caixa_simples "Shizuku não está ativo" \
            "Abra o Shizuku e inicie o serviço." \
            "Depois volte ao Manager e execute a coleta novamente." \
            "O app não precisa permanecer na tela; o serviço precisa continuar ativo."
        pause; return 1
    fi

    local carimbo destino cmd
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    destino="$DOWNLOADS_DIR/android-diagnostico-$carimbo.txt"
    cmd='echo "=== IDENTIDADE ==="; id; echo; echo "=== BUILD ==="; getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.product.device; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.build.fingerprint; echo; echo "=== CPU ==="; cat /proc/cpuinfo; echo; for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_{cur,min,max}_freq; do [ -r "$f" ] && echo "$f=$(cat "$f")"; done; echo; echo "=== MEMORIA ==="; cat /proc/meminfo; echo; dumpsys meminfo | grep -A 18 "Total RAM"; echo; echo "=== PROCESSOS RSS ==="; dumpsys meminfo | head -80; echo; echo "=== OOM ==="; dumpsys activity oom | head -180; echo; echo "=== ARMAZENAMENTO ==="; df -h /data /sdcard 2>/dev/null; echo; cat /proc/diskstats; echo; echo "=== BATERIA ==="; dumpsys battery; echo; echo "=== TERMICA ==="; dumpsys thermalservice; echo; echo "=== POWER ==="; dumpsys power | head -180; echo; echo "=== ZRAM ==="; cat /proc/swaps; echo; echo "=== FIM ==="'

    {
        cabecalho_relatorio_diagnostico "Android via Shizuku" "Rish (uid 2000/shell)" "coleta compacta"
        printf 'Observação: teste de velocidade de armazenamento não está incluído nesta coleta.\n\n'
        executar_rish_diagnostico "$cmd"
    } | redigir_segredos > "$destino"

    caixa_simples "📥 Diagnóstico Android criado" \
        "Arquivo: $(basename "$destino")" \
        "Tamanho: $(tamanho_legivel_arquivo "$destino")" \
        "Destino: $(caminho_curto "$DOWNLOADS_DIR")" \
        "Teste de armazenamento: separado"
    pause
}

teste_armazenamento_android() {
    resolver_downloads_diagnostico || return 1
    cabecalho_tela "💾 Teste de armazenamento" "Escrita e cópia separados do diagnóstico"
    local carimbo destino teste copia tamanho_mb=128 inicio fim ms bytes mib_s
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    destino="$DOWNLOADS_DIR/android-storage-test-$carimbo.txt"
    teste="$DOWNLOADS_DIR/.manager-io-test-$carimbo.bin"
    copia="$DOWNLOADS_DIR/.manager-io-copy-$carimbo.bin"

    caixa_simples "Teste temporário" \
        "Arquivo de teste: ${tamanho_mb} MiB" \
        "Mede escrita sequencial e cópia local." \
        "Os arquivos temporários serão apagados ao final."

    medir() {
        local rotulo="$1"; shift
        inicio="$(date +%s%3N 2>/dev/null || date +%s000)"
        "$@" >/dev/null 2>&1
        local rc=$?
        fim="$(date +%s%3N 2>/dev/null || date +%s000)"
        ms=$((fim-inicio)); [ "$ms" -lt 1 ] && ms=1
        bytes=$((tamanho_mb*1024*1024))
        mib_s=$((bytes*1000/ms/1024/1024))
        printf '%s: %s MiB/s (%s ms)\n' "$rotulo" "$mib_s" "$ms" >> "$destino"
        return $rc
    }

    {
        cabecalho_relatorio_diagnostico "Teste de armazenamento" "Downloads" "${tamanho_mb} MiB"
        printf 'Aviso: resultado é indicativo e varia com cache, temperatura e carga do sistema.\n\n'
    } > "$destino"
    medir "Escrita sequencial" dd if=/dev/zero of="$teste" bs=1M count="$tamanho_mb" conv=fsync
    medir "Cópia local" cp "$teste" "$copia"
    rm -f "$teste" "$copia" 2>/dev/null || true
    sync 2>/dev/null || true

    caixa_simples "💾 Teste concluído" \
        "Relatório: $(basename "$destino")" \
        "$(tail -n 2 "$destino" | tr '\n' ' ')" \
        "Arquivos temporários: removidos"
    pause
}

status_central_diagnosticos() {
    local incidentes projetos tamanho
    incidentes=$(find "$MANAGER_INCIDENT_DIR" -maxdepth 1 -type f -name 'erro-*.txt' 2>/dev/null | wc -l | tr -d ' ')
    projetos=$(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' ! -name manager.log 2>/dev/null | wc -l | tr -d ' ')
    tamanho=$(du -sh "$LOG_DIR" "${BASE_DIR:-$HOME/scripts/manager}/logs" 2>/dev/null | awk '{s=s " " $1} END {gsub(/^ /, "", s); print s}')
    caixa_simples "Resumo atual" \
        "Incidentes internos: ${incidentes:-0}" \
        "Logs de projetos: ${projetos:-0}" \
        "Log do Termux: $([ -s "${TERMUX_SETUP_LOG:-}" ] && printf 'disponível' || printf 'vazio')" \
        "Espaço usado: ${tamanho:-0 B}"
}

limpar_registros_diagnosticos() {
    cabecalho_tela "🧹 Limpar diagnósticos" "Projetos e configurações serão preservados"
    caixa_simples "Será removido" \
        "• Incidentes técnicos capturados" \
        "• Logs de projetos em ~/Painel/.logs" \
        "• Logs de operações do pkg" \
        "• Diagnósticos temporários" \
        "Não remove projetos, pacotes ou configurações."
    confirmar_acao "Deseja apagar todos os registros de diagnóstico?" || return
    find "$LOG_DIR" -maxdepth 1 -type f -name '*.log*' -delete 2>/dev/null || true
    rm -rf "$DIAGNOSTICS_DIR" 2>/dev/null || true
    rm -f "${TERMUX_SETUP_LOG:-}" "${TERMUX_DIAGNOSTIC_LOG:-}" 2>/dev/null || true
    setup_dirs
    inicializar_diagnosticos
    ok "Registros de diagnóstico removidos."
    pause
}

menu_central_diagnosticos() {
    inicializar_diagnosticos
    while true; do
        menu_unificado "🩺 Central de Diagnóstico" "Erros separados por origem e exportação para Downloads" "[0] Voltar  •  [1–9] Selecionar" \
            "1|🧠|Erros do Manager|Falhas internas, comandos e mensagens registradas" \
            "2|🚀|Erros dos projetos|Frontend, backend e demais processos" \
            "3|📱|Erros do Termux|pkg, dpkg, ambiente e armazenamento" \
            "4|📤|Exportar todos os relatórios|Arquivos separados em manager, projetos e termux" \
            "5|📦|Pacote completo de suporte|Todos os relatórios compactados em um arquivo" \
            "6|📊|Resumo dos registros|Quantidade, disponibilidade e espaço usado" \
            "7|🧹|Limpar diagnósticos|Preserva projetos, pacotes e configurações" \
            "8|📱|Diagnóstico do Android|CPU, RAM, térmica, bateria e processos via Shizuku" \
            "9|💾|Teste de armazenamento|Velocidade de escrita e cópia em relatório separado"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) menu_erros_manager ;;
            2) menu_logs_projetos ;;
            3) menu_logs_termux ;;
            4) exportar_todos_relatorios ;;
            5) exportar_pacote_diagnostico_completo ;;
            6) cabecalho_tela "📊 Resumo dos diagnósticos" "Estado atual"; status_central_diagnosticos; pause ;;
            7) limpar_registros_diagnosticos ;;
            8) coletar_android_shizuku ;;
            9) teste_armazenamento_android ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
