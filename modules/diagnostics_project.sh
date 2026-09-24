# Módulo: diagnostics_project.sh
# Coleta de logs de falha durante testes de projetos.

ULTIMO_RELATORIO_TESTE=""

coletar_logs_teste_projeto() {
    # coletar_logs_teste_projeto <projeto> [processo_frontend] [processo_backend] [motivo]
    local projeto="$1" nome_front="${2:-}" nome_back="${3:-}" motivo="${4:-Falha durante o teste do projeto}"
    resolver_downloads_diagnostico || return 1

    local carimbo slug destino front_log="" back_log=""
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    slug="$(sanitizar_nome_arquivo "$(basename "$projeto")")"
    destino="$DOWNLOADS_DIR/${slug}-teste-erro-$carimbo.txt"

    [ -n "$nome_front" ] && front_log="$LOG_DIR/${nome_front}.log"
    [ -n "$nome_back" ] && back_log="$LOG_DIR/${nome_back}.log"

    {
        printf '%s\n' '========== TESTE DE PROJETO — TERMUX MANAGER =========='
        printf 'Gerado em: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date)"
        printf 'Manager: %s\n' "${MANAGER_VERSION:-desconhecida}"
        printf 'Projeto: %s\n' "$(basename "$projeto")"
        printf 'Diretório: %s\n' "$(caminho_home_relativo "$projeto")"
        printf 'Motivo: %s\n' "$motivo"
        printf 'Node: %s\n' "$(node --version 2>/dev/null || printf 'indisponível')"
        printf 'npm: %s\n' "$(npm --version 2>/dev/null || printf 'indisponível')"
        printf 'Shell: %s\n' "${SHELL:-indisponível}"

        printf '\n%s\n' '========== RESOLUÇÃO DO PROJETO =========='
        printf 'Projeto selecionado: %s\n' "$(caminho_home_relativo "$projeto")"
        if declare -F detectar_estrutura_projeto >/dev/null 2>&1; then
            detectar_estrutura_projeto "$projeto" >/dev/null 2>&1 || true
            [ -n "${BACK_DIR:-}" ] && printf 'Backend resolvido: %s\n' "$(caminho_home_relativo "$BACK_DIR")"
            [ -n "${FRONT_DIR:-}" ] && printf 'Frontend resolvido: %s\n' "$(caminho_home_relativo "$FRONT_DIR")"
            if declare -F dependency_stamp_path >/dev/null 2>&1; then
                [ -n "${BACK_DIR:-}" ] && printf 'Cache backend: %s\n' "$(caminho_home_relativo "$(dependency_stamp_path "$BACK_DIR")")"
                [ -n "${FRONT_DIR:-}" ] && printf 'Cache frontend: %s\n' "$(caminho_home_relativo "$(dependency_stamp_path "$FRONT_DIR")")"
            fi
        fi

        printf '\n%s\n' '========== ESTADO DOS PROCESSOS =========='
        local nome meta pidf pid estado componente cmd porta esp
        for nome in "$nome_back" "$nome_front"; do
            [ -n "$nome" ] || continue
            meta="$PID_DIR/${nome}.meta"
            pidf="$PID_DIR/${nome}.pid"
            pid="$(cat "$pidf" 2>/dev/null || printf 'indisponível')"
            componente="$(meta_valor "$meta" COMPONENT 2>/dev/null || printf 'desconhecido')"
            estado="$(meta_valor "$meta" STATE 2>/dev/null || printf 'desconhecido')"
            cmd="$(meta_valor "$meta" CMD 2>/dev/null || printf 'indisponível')"
            porta="$(meta_valor "$meta" PORT 2>/dev/null || true)"
            esp="$(meta_valor "$meta" EXPECTED_PORT 2>/dev/null || true)"
            printf '%s — %s\n' "$componente" "$nome"
            printf 'PID: %s\nEstado: %s\nComando: %s\n' "$pid" "$estado" "$cmd"
            [ -n "$esp" ] && printf 'Porta esperada: %s\n' "$esp"
            [ -n "$porta" ] && printf 'Porta detectada: %s\n' "$porta"
            printf '%s\n' '------------------------------------------'
        done

        printf '\n%s\n' '========== LOG BACKEND =========='
        if [ -n "$back_log" ] && [ -f "$back_log" ]; then
            cat "$back_log"
        else
            printf 'Log do backend não encontrado: %s\n' "$(caminho_home_relativo "${back_log:-não definido}")"
        fi

        printf '\n%s\n' '========== LOG FRONTEND =========='
        if [ -n "$front_log" ] && [ -f "$front_log" ]; then
            cat "$front_log"
        else
            printf 'Log do frontend não encontrado: %s\n' "$(caminho_home_relativo "${front_log:-não definido}")"
        fi

        printf '\n%s\n' '========== LOG DO MANAGER — ÚLTIMAS 250 LINHAS =========='
        tail -n 250 "$LOG_FILE" 2>/dev/null || printf 'Log principal indisponível.\n'

        printf '\n%s\n' '========== VARIÁVEIS DECLARADAS (.env) =========='
        local envf
        for envf in "$projeto/.env" "$projeto/backend/.env" "$projeto/server/.env" "$projeto/frontend/.env" "$projeto/client/.env"; do
            [ -f "$envf" ] || continue
            printf '%s:\n' "$(caminho_home_relativo "$envf")"
            # Somente os nomes das variáveis; nunca os valores.
            sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=.*/  \1=[REMOVIDO]/p' "$envf"
        done
        printf '\n%s\n' '==================== FIM ======================'
    } | redigir_segredos > "$destino"

    ULTIMO_RELATORIO_TESTE="$destino"
    log "INFO" "Logs do teste exportados para $(caminho_home_relativo "$destino")"
    return 0
}
