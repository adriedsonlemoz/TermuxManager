# Módulo: termux_packages_ui.sh
# UI, diagnóstico, exportação e reparo do subsistema pkg/apt.

tela_operacao_termux() {
    # Renderização em área fixa com POSICIONAMENTO ABSOLUTO por linha
    # (\033[N;1H), a mesma técnica segura que a versão original desse
    # arquivo já usava — e que existia justamente para evitar este problema:
    # se qualquer linha estourasse a largura do terminal, o auto-wrap
    # deslocava as linhas seguintes (escritas de forma relativa, uma embaixo
    # da outra) e os quadros ficavam empilhados/desalinhados a cada redesenho.
    # Aqui cada linha é posicionada de forma absoluta e o texto é cortado com
    # segurança (via largura_visivel/strip_ansi de ui.sh, que já leva em
    # conta emojis de largura dupla) antes de ser escrito — então um estouro
    # de largura nunca mais deveria mover as linhas seguintes.
    local titulo="$1" pct="$2" atividade="$3" detalhe="${4:-}"
    local status1="${5:-}" status2="${6:-}" status3="${7:-}"
    local info_extra="${8:-}" linhas_pkg="${9:-${PKG_PREVIEW_LINES:-}}"

    # Largura calculada localmente e sempre atualizada nesta função (não usa
    # a LARGURA_CAIXA global, para não depender de quando outra tela chamou
    # detectar_terminal pela última vez).
    local cols_tput cols_stty cols
    cols_tput=$(tput cols 2>/dev/null || echo 0)
    cols_stty=$(stty size 2>/dev/null | awk '{print $2}'); cols_stty=${cols_stty:-0}
    if [ "$cols_tput" -gt 0 ] 2>/dev/null && [ "$cols_stty" -gt 0 ] 2>/dev/null; then
        [ "$cols_tput" -lt "$cols_stty" ] && cols=$cols_tput || cols=$cols_stty
    elif [ "$cols_stty" -gt 0 ] 2>/dev/null; then
        cols=$cols_stty
    else
        cols=$cols_tput
    fi
    [ "$cols" -gt 0 ] 2>/dev/null || cols=40
    [ "$cols" -lt 30 ] && cols=30
    # -1 de margem de segurança: alguns terminais quebram a linha sozinhos
    # se algo for escrito exatamente na última coluna.
    local largura=$((cols - 1))
    local interno=$((largura - 4))

    if [ "${TERMUX_UI_DRAWN:-false}" != true ]; then
        # Tela alternativa: impede que cada atualização entre no histórico e
        # elimina a sensação de que o terminal está "caindo".
        printf '\033[?1049h\033[2J\033[H\033[?25l'
        TERMUX_UI_DRAWN=true
    fi

    # Corta o texto pela largura VISÍVEL (considerando emojis de largura
    # dupla) e completa com espaços até $interno, garantindo que toda linha
    # tenha sempre o mesmo comprimento renderizado — sem isso, cada quadro
    # fecharia a borda direita em uma coluna diferente.
    ajustar_conteudo() {
        local t vis
        t="$(strip_ansi "$1")"
        vis=$(largura_visivel "$t")
        if [ "$vis" -gt "$interno" ]; then
            t="$(truncar_visivel "$t" "$interno")"
            vis=$(largura_visivel "$t")
        fi
        local espacos=$((interno - vis))
        [ "$espacos" -lt 0 ] && espacos=0
        printf '%s%s' "$t" "$(repetir_char ' ' "$espacos")"
    }

    linha_borda() {
        local n="$1" tipo="$2"
        local esq="├" dir="┤"
        [ "$tipo" = topo ] && esq="╭" && dir="╮"
        [ "$tipo" = base ] && esq="╰" && dir="╯"
        printf '\033[%d;1H\033[2K%s%s%s%s%s' \
            "$n" "$C_CYAN" "$esq" "$(repetir_char '─' $((largura - 2)))" "$dir" "$C_RESET"
    }

    linha_conteudo() {
        local n="$1" texto="$2" cor="${3:-}"
        printf '\033[%d;1H\033[2K%s│%s %s%s%s %s│%s' \
            "$n" "$C_CYAN" "$C_RESET" "$cor" "$(ajustar_conteudo "$texto")" "$C_RESET" "$C_CYAN" "$C_RESET"
    }

    local n=1
    linha_borda "$n" topo; n=$((n+1))
    linha_conteudo "$n" "🚀 ${titulo}" "$C_BOLD"; n=$((n+1))
    linha_conteudo "$n" "$(barra_percentual_simples "$pct" "$interno")" "$C_CYAN"; n=$((n+1))
    linha_conteudo "$n" "$atividade"; n=$((n+1))
    linha_conteudo "$n" "$detalhe" "$C_DIM"; n=$((n+1))
    linha_borda "$n" meio; n=$((n+1))
    linha_conteudo "$n" "${status1}${status1:+${status2:+  •  }}${status2}" "$C_GREEN"; n=$((n+1))
    linha_conteudo "$n" "$status3" "$C_GREEN"; n=$((n+1))
    linha_borda "$n" meio; n=$((n+1))
    linha_conteudo "$n" "Últimas linhas do pkg" "$C_DIM"; n=$((n+1))

    local linha count=0
    while IFS= read -r linha && [ "$count" -lt 3 ]; do
        [ -n "$linha" ] || continue
        linha_conteudo "$n" "  $linha" "$C_DIM"; n=$((n+1))
        count=$((count + 1))
    done <<< "$linhas_pkg"
    while [ "$count" -lt 3 ]; do linha_conteudo "$n" ""; n=$((n+1)); count=$((count + 1)); done

    linha_borda "$n" meio; n=$((n+1))
    linha_conteudo "$n" "${info_extra:-Log: $(caminho_curto "$TERMUX_SETUP_LOG")}" "$C_DIM"; n=$((n+1))
    linha_conteudo "$n" "Não feche o Termux nesta etapa." "$C_YELLOW"; n=$((n+1))
    linha_borda "$n" base; n=$((n+1))

    # Limpa qualquer sobra abaixo do quadro (ex.: quadro anterior mais alto).
    printf '\033[%d;1H\033[0J' "$n"
    unset -f ajustar_conteudo linha_borda linha_conteudo
}

encerrar_ui_termux() {
    if [ "${TERMUX_UI_DRAWN:-false}" = true ]; then
        # Sai da tela alternativa e restaura atributos, região de rolagem,
        # quebra automática e cursor antes de qualquer tela comum.
        printf '\033[0m\033[?25h\033[r\033[?7h\033[?1049l'
    fi
    TERMUX_UI_DRAWN=false
    TERMUX_UI_LAST_SIGNATURE=""
    stty sane 2>/dev/null || true
    printf '\033[H\033[2J\033[3J'
    detectar_terminal
}


sanitizar_saida_termux() {
    # A Central de Diagnóstico normalmente fornece redigir_segredos().
    # Este fallback mantém os relatórios do subsistema Termux seguros mesmo
    # quando o módulo é carregado/testado isoladamente.
    if declare -F redigir_segredos >/dev/null 2>&1; then
        redigir_segredos
    else
        sed -E \
            -e 's/((API_KEY|APIKEY|ACCESS_TOKEN|REFRESH_TOKEN|TOKEN|PASSWORD|PASS|SECRET)[[:space:]]*[:=][[:space:]]*)[^[:space:]"]+/\1[REMOVIDO]/Ig' \
            -e 's/(Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+)[A-Za-z0-9._~+\/-]+=*/\1[REMOVIDO]/Ig' \
            -e 's#(https?://)[^/@:[:space:]]+:[^/@[:space:]]+@#\1[CREDENCIAIS_REMOVIDAS]@#Ig'
    fi
}

gerar_diagnostico_pkg() {
    local contexto="$1"
    local codigo="${LAST_PKG_EXIT_CODE:-desconhecido}"
    local comando="${LAST_PKG_COMMAND:-pkg (comando não registrado)}"
    local data sistema arquitetura versao_termux origem_termux repositorio_termux

    mkdir -p "$(dirname "$TERMUX_DIAGNOSTIC_LOG")"
    data="$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date)"
    sistema="$(uname -a 2>/dev/null || printf 'indisponível')"
    arquitetura="$(dpkg --print-architecture 2>/dev/null || uname -m 2>/dev/null || printf 'indisponível')"
    versao_termux="${TERMUX_VERSION:-indisponível}"
    detectar_variante_termux
    origem_termux="${TERMUX_VARIANT_LABEL:-indisponível}"
    repositorio_termux="${TERMUX_REPO_PRIMARY:-indisponível}"

    {
        printf '%s\n' '========== DIAGNÓSTICO DO MANAGER =========='
        printf 'Data: %s\n' "$data"
        printf 'Manager: %s\n' "${MANAGER_VERSION:-desconhecida}"
        printf 'Contexto: %s\n' "$contexto"
        printf 'Comando: %s\n' "$comando"
        printf 'Código de saída: %s\n' "$codigo"
        printf 'Termux: %s\n' "$versao_termux"
        printf 'Arquitetura: %s\n' "$arquitetura"
        printf 'Sistema: %s\n' "$sistema"
        printf 'Log completo: %s\n' "$(caminho_curto "$TERMUX_SETUP_LOG")"
        printf '%s\n' '--------------------------------------------'
        printf '%s\n' 'LINHAS PROVAVELMENTE RELEVANTES:'
        if [ -f "$TERMUX_SETUP_LOG" ]; then
            grep -iE '(^|[^[:alpha:]])(error|erro|failed|failure|falha|unable|broken|dpkg|conflict|lock|permission denied|not found|404|403|signature|certificate|repository|held packages)([^[:alpha:]]|$)' "$TERMUX_SETUP_LOG" 2>/dev/null | tail -n 30 || true
        fi
        printf '%s\n' '--------------------------------------------'
        printf '%s\n' 'ÚLTIMAS 50 LINHAS DO LOG:'
        if [ -f "$TERMUX_SETUP_LOG" ]; then
            tail -n 50 "$TERMUX_SETUP_LOG" 2>/dev/null || true
        else
            printf '%s\n' 'O arquivo de log não foi encontrado.'
        fi
        printf '%s\n' '========== FIM DO DIAGNÓSTICO ============='
    } | sed -E $'s/\x1B\[[0-9;?]*[ -\/]*[@-~]//g; s/\r//g' \
        | sanitizar_saida_termux > "$TERMUX_DIAGNOSTIC_LOG"
}


copiar_log_termux_sanitizado() {
    local origem="${1:-}" destino="${2:-}"
    [ -f "$origem" ] || return 1
    mkdir -p "$(dirname "$destino")" 2>/dev/null || return 1
    sanitizar_saida_termux < "$origem" > "$destino"
}

copiar_log_setup_downloads() {
    local destino
    TERMUX_SETUP_LOG_EXPORTADO=""
    if ! resolver_downloads_dir >/dev/null 2>&1; then
        return 1
    fi
    [ -f "${TERMUX_SETUP_LOG:-}" ] || return 1
    destino="$DOWNLOADS_DIR/termux-setup.log"
    if copiar_log_termux_sanitizado "$TERMUX_SETUP_LOG" "$destino"; then
        TERMUX_SETUP_LOG_EXPORTADO="$destino"
        return 0
    fi
    return 1
}

exportar_logs_downloads() {
    local destino
    if ! resolver_downloads_dir >/dev/null 2>&1; then
        printf '%s\n' "❌ Pasta Download indisponível. Execute termux-setup-storage."
        return 1
    fi
    destino="$DOWNLOADS_DIR"
    mkdir -p "$destino" 2>/dev/null || return 1
    local -a copiados=()
    if [ -f "$TERMUX_SETUP_LOG" ] && copiar_log_termux_sanitizado "$TERMUX_SETUP_LOG" "$destino/termux-setup.log"; then
        copiados+=("termux-setup.log")
    fi
    if [ -f "$TERMUX_DIAGNOSTIC_LOG" ] && copiar_log_termux_sanitizado "$TERMUX_DIAGNOSTIC_LOG" "$destino/ultimo-diagnostico.txt"; then
        copiados+=("ultimo-diagnostico.txt")
    fi
    if [ ${#copiados[@]} -eq 0 ]; then
        printf '%s\n' "⚠ Nenhum log disponível para exportação."
        return 1
    fi
    printf '%s\n' "✔ Logs copiados para: $(caminho_curto "$destino")"
    local nome
    for nome in "${copiados[@]}"; do
        printf '  • %s (sanitizado)\n' "$nome"
    done
}

exportar_pacote_suporte() {
    local destino carimbo tmp pacote
    if ! resolver_downloads_dir >/dev/null 2>&1; then
        printf '%s\n' "❌ Pasta Download indisponível. Execute termux-setup-storage."
        return 1
    fi
    destino="$DOWNLOADS_DIR"
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    tmp="${BASE_DIR:-$HOME/scripts/manager}/tmp/suporte-$carimbo"
    pacote="$destino/manager-suporte-$carimbo.zip"
    rm -rf "$tmp" && mkdir -p "$tmp" || return 1
    [ -f "$TERMUX_SETUP_LOG" ] && copiar_log_termux_sanitizado "$TERMUX_SETUP_LOG" "$tmp/termux-setup.log"
    [ -f "$TERMUX_DIAGNOSTIC_LOG" ] && copiar_log_termux_sanitizado "$TERMUX_DIAGNOSTIC_LOG" "$tmp/ultimo-diagnostico.txt"
    [ -f "${BASE_DIR:-$HOME/scripts/manager}/MANIFEST.json" ] && cp -f "${BASE_DIR:-$HOME/scripts/manager}/MANIFEST.json" "$tmp/"
    {
        printf 'Manager: %s\n' "${MANAGER_VERSION:-desconhecida}"
        printf 'Termux: %s\n' "${TERMUX_VERSION:-indisponível}"
        printf 'Arquitetura: %s\n' "$(dpkg --print-architecture 2>/dev/null || uname -m)"
        printf 'Sistema: %s\n' "$(uname -a 2>/dev/null)"
        printf 'dpkg: %s\n' "$(dpkg --version 2>/dev/null | head -n1)"
        printf 'apt: %s\n' "$(apt --version 2>/dev/null | head -n1)"
        printf 'pkg: %s\n' "$(pkg --version 2>/dev/null | head -n1)"
    } > "$tmp/ambiente.txt"
    dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null > "$tmp/pacotes-instalados.txt" || true
    if command -v zip >/dev/null 2>&1; then
        (cd "$tmp" && zip -qr "$pacote" .) || { rm -rf "$tmp"; return 1; }
        rm -rf "$tmp"
        printf '%s\n' "✔ Pacote de suporte criado:"
        printf '%s\n' "$pacote"
        return 0
    fi
    mkdir -p "$destino/manager-suporte-$carimbo"
    cp -Rf "$tmp"/. "$destino/manager-suporte-$carimbo/"
    rm -rf "$tmp"
    printf '%s\n' "⚠ zip ainda não está instalado."
    printf '%s\n' "✔ Arquivos de suporte copiados para:"
    printf '%s\n' "$(caminho_curto "$destino/manager-suporte-$carimbo")"
}

reparar_dpkg_automaticamente() {
    local contexto="${1:-Reparo automático do sistema de pacotes}" rc=0
    encerrar_ui_termux
    printf '\n🔧 %s\n' "$contexto"
    printf '%s\n' "Configurando pacotes interrompidos..."
    LAST_PKG_COMMAND="env DEBIAN_FRONTEND=noninteractive dpkg --configure -a --force-confdef --force-confold"
    env DEBIAN_FRONTEND=noninteractive dpkg --configure -a --force-confdef --force-confold >>"$TERMUX_SETUP_LOG" 2>&1 || rc=$?
    printf '%s\n' "Corrigindo dependências quebradas..."
    LAST_PKG_COMMAND="env DEBIAN_FRONTEND=noninteractive apt-get -f install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
    env DEBIAN_FRONTEND=noninteractive apt-get -f install -y \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold >>"$TERMUX_SETUP_LOG" 2>&1 || rc=$?
    if [ -n "$(dpkg --audit 2>/dev/null)" ]; then
        LAST_PKG_EXIT_CODE="${rc:-1}"
        [ "$LAST_PKG_EXIT_CODE" = 0 ] && LAST_PKG_EXIT_CODE=1
        printf '%s\n' "❌ Ainda existem pacotes pendentes."
        return 1
    fi
    LAST_PKG_EXIT_CODE=0
    printf '%s\n' "✔ Sistema de pacotes reparado."
    return 0
}

mostrar_erro_pkg() {
    local contexto="$1" escolha
    gerar_diagnostico_pkg "$contexto"
    encerrar_ui_termux

    printf '\033[2J\033[H'
    detectar_terminal
    caixa_simples "❌ Falha no pkg" \
        "$contexto" \
        "Código de saída: ${LAST_PKG_EXIT_CODE:-desconhecido}" \
        "Comando: ${LAST_PKG_COMMAND:-não registrado}"

    printf '\n%s\n' "${C_BOLD}Copie e envie o bloco abaixo:${C_RESET}"
    printf '%s\n' '──────────────── DIAGNÓSTICO ────────────────'
    cat "$TERMUX_DIAGNOSTIC_LOG"
    printf '%s\n' '──────────────── FIM ────────────────────────'
    printf '\nArquivo salvo em: %s\n' "$(caminho_curto "$TERMUX_DIAGNOSTIC_LOG")"

    if command -v termux-clipboard-set >/dev/null 2>&1; then
        termux-clipboard-set < "$TERMUX_DIAGNOSTIC_LOG" 2>/dev/null && \
            printf '%s\n' "${C_GREEN}✔ Diagnóstico copiado para a área de transferência.${C_RESET}"
    fi

    log "ERROR" "$contexto — diagnóstico: $TERMUX_DIAGNOSTIC_LOG"
    while true; do
        printf '\n[ENTER] Continuar  [L] Logs no Download  [E] Pacote de suporte  [R] Reparar dpkg  [Q] Sair\n> '
        IFS= read -r escolha
        case "${escolha,,}" in
            '') break ;;
            l) exportar_logs_downloads ;;
            e) exportar_pacote_suporte ;;
            r)
                if reparar_dpkg_automaticamente "Tentando reparar a falha"; then
                    printf '%s\n' "✔ Reparo concluído. Execute novamente a etapa do wizard."
                else
                    gerar_diagnostico_pkg "O reparo automático não resolveu todas as pendências."
                    printf '%s\n' "❌ O reparo não foi suficiente. Exporte o pacote de suporte com E."
                fi
                ;;
            q) return 2 ;;
            *) printf '%s\n' "Opção inválida." ;;
        esac
    done
}

