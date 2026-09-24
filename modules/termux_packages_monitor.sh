# Módulo: termux_packages_monitor.sh
# Monitoramento seguro de processos pkg/apt e interação com o usuário.

aviso_repositorios_termux() {
    cabecalho_tela "🌐 Repositórios do Termux" "Aviso antes da atualização"
    caixa_simples "Tela oficial do Termux" \
        "Na primeira utilização, o Termux pode" \
        "pedir que você escolha um mirror." \
        "Essa seleção não pertence ao Manager." \
        "Escolha uma opção e confirme para continuar."
    caixa_simples "O que será atualizado" \
        "• Índices dos repositórios do Termux" \
        "• Pacotes e bibliotecas já instalados" \
        "• Ferramentas escolhidas no assistente" \
        "Bash/Fish só mudam se forem pacotes atualizados."
    rodape_atalhos "[Enter] Continuar  •  [0] Cancelar"
        ui_buffer_flush
        read -r RESPOSTA_MENU
    [ "$RESPOSTA_MENU" != 0 ]
}

ultimas_linhas_pkg() {
    local arquivo="$1" quantidade="${2:-5}" linhas
    [ -f "$arquivo" ] || { printf '%s' "${PKG_LAST_NONEMPTY_LINES:-Nenhuma saída recente.}"; return 0; }
    # Cada etapa do pipe é blindada com 2>/dev/null: durante um upgrade em
    # andamento, bibliotecas do próprio Termux podem ficar temporariamente
    # inconsistentes (ex.: dpkg trocando libc++/libncurses no meio da
    # transação) e fazer coreutils como awk/cut falharem ao iniciar. Sem essa
    # blindagem, o erro do linker dinâmico ("CANNOT LINK EXECUTABLE...")
    # vazava direto para dentro do quadro fixo desta tela.
    # O dpkg reaproveita a mesma linha do terminal para o progresso de
    # "Reading database ... N%" usando \r em vez de \n. Convertemos o \r em
    # quebra de linha (em vez de apenas apagá-lo) para que cada atualização
    # vire sua própria linha — sem isso, os fragmentos ficavam colados uns
    # nos outros (ex.: "(Reading database ... (Reading database ... 5%(Readi").
    linhas="$(tail -n 80 "$arquivo" 2>/dev/null \
        | sed -E $'s/\x1B\[[0-9;?]*[ -\/]*[@-~]//g' 2>/dev/null \
        | tr '\r' '\n' 2>/dev/null \
        | awk 'NF { linhas[++n]=$0 } END { inicio=n-'"$quantidade"'+1; if (inicio<1) inicio=1; for (i=inicio;i<=n;i++) print linhas[i] }' 2>/dev/null \
        | cut -c1-120 2>/dev/null)"
    if [ -n "$linhas" ]; then
        PKG_LAST_NONEMPTY_LINES="$linhas"
        printf '%s' "$linhas"
    elif [ -n "${PKG_LAST_NONEMPTY_LINES:-}" ]; then
        printf '%s' "$PKG_LAST_NONEMPTY_LINES"
    else
        printf '%s' "Nenhuma saída recente."
    fi
}

pid_estado_pkg() {
    local pid="$1"
    awk '/^State:/{print $2; exit}' "/proc/$pid/status" 2>/dev/null || true
}

pids_gerenciador_pacotes_ativos() {
    local proc pid nome estado
    for proc in /proc/[0-9]*; do
        [ -r "$proc/comm" ] || continue
        IFS= read -r nome < "$proc/comm" || continue
        case "$nome" in
            apt|apt-get|dpkg|dpkg-deb)
                pid="${proc##*/}"
                estado="$(pid_estado_pkg "$pid")"
                [ "$estado" = Z ] && continue
                printf '%s ' "$pid"
                ;;
        esac
    done
}

pid_ou_filho_parado() {
    # Prompts interativos geralmente ficam em apt/dpkg/termux-change-repo,
    # filhos do processo pkg. Verificar só o PID principal não os detecta.
    local raiz="$1" atual estado filho
    local -a fila=("$raiz")
    while [ "${#fila[@]}" -gt 0 ]; do
        atual="${fila[0]}"
        fila=("${fila[@]:1}")
        estado="$(pid_estado_pkg "$atual")"
        if [ "$estado" = T ] || [ "$estado" = t ]; then
            return 0
        fi
        while IFS= read -r filho; do
            [ -n "$filho" ] && fila+=("$filho")
        done < <(pgrep -P "$atual" 2>/dev/null || true)
    done
    return 1
}

encerrar_arvore_pid() {
    local raiz="$1" filho
    while IFS= read -r filho; do
        [ -n "$filho" ] && encerrar_arvore_pid "$filho"
    done < <(pgrep -P "$raiz" 2>/dev/null || true)
    kill -TERM "$raiz" 2>/dev/null || true
}

trecho_log_desde_offset() {
    local arquivo="$1" inicio="${2:-0}" quantidade="${3:-60}"
    [ -f "$arquivo" ] || return 0
    if [ "$inicio" -gt 0 ]; then
        tail -c +$((inicio + 1)) "$arquivo" 2>/dev/null | tail -n "$quantidade"
    else
        tail -n "$quantidade" "$arquivo" 2>/dev/null
    fi
}

log_pkg_exige_interacao() {
    local arquivo="$1" inicio="${2:-0}"
    [ -f "$arquivo" ] || return 1

    # Analisa somente a saída produzida pelo comando atual. Antes, a busca
    # examinava o log acumulado e tratava a frase informativa
    # "Configuration file ... Keeping old config file" como um prompt.
    # Isso encerrava o apt durante o unpack do libc++ e deixava o dpkg
    # interrompido. Agora só prompts realmente pendentes acionam a pausa.
    trecho_log_desde_offset "$arquivo" "$inicio" 60 | grep -qiE \
        '^\*\*\* .+ \(Y/I/N/O/D/Z\) \[default=[^]]*\] \?[[:space:]]*$|what would you like to do about it[[:space:]]*\?|what do you want to do about it[[:space:]]*\?|choose[^[:alnum:]]+.*mirror|select[^[:alnum:]]+.*mirror|termux-change-repo'
}

log_pkg_tem_dpkg_interrompido() {
    local arquivo="$1" inicio="${2:-0}"
    trecho_log_desde_offset "$arquivo" "$inicio" 100 | grep -qiF \
        "dpkg was interrupted, you must manually run 'dpkg --configure -a'"
}

executar_pkg_interativo() {
    local titulo="$1"; shift
    encerrar_ui_termux
    printf '\033[2J\033[H\033[?25h'
    detectar_terminal
    caixa_simples "⚠ Ação necessária" \
        "$titulo abriu uma pergunta do pkg/dpkg." \
        "Responda diretamente abaixo." \
        "O Manager continuará quando o comando terminar."
    printf '\n'

    # O comando precisa enxergar um TTY real. Um pipe simples para tee faria
    # alguns seletores interativos desaparecerem novamente.
    if command -v script >/dev/null 2>&1; then
        local comando="pkg"
        local arg
        for arg in "$@"; do printf -v comando '%s %q' "$comando" "$arg"; done
        script -q -a -c "$comando" "$TERMUX_SETUP_LOG"
        return $?
    fi

    pkg "$@"
    return $?
}

executar_pkg_monitorado() {
    # executar_pkg_monitorado <titulo> <pct_inicial> <pct_limite> <atividade> <detalhe> -- <args pkg...>
    local titulo="$1" pct="$2" limite="$3" atividade="$4" detalhe="$5"
    shift 5
    [ "${1:-}" = "--" ] && shift
    local args=("$@") pid rc linhas assinatura iter=0
    local lock_pids lock_inicio=$SECONDS lock_decorrido lock_timeout="${TERMUX_MANAGER_PKG_LOCK_TIMEOUT:-180}"
    local old_int inicio_exec=$SECONDS ultimo_tamanho=0 atividade_em=$SECONDS tamanho_atual ocioso decorrido aviso_atividade
    old_int="$(trap -p INT || true)"
    PKG_CANCEL_REQUESTED=false
    PKG_ACTIVE_PID=""
    trap 'PKG_CANCEL_REQUESTED=true' INT

    restaurar_trap_pkg() {
        PKG_ACTIVE_PID=""
        PKG_CANCEL_REQUESTED=false
        if [ -n "$old_int" ]; then eval "$old_int"; else trap - INT; fi
        unset -f restaurar_trap_pkg
    }

    while :; do
        if [ "$PKG_CANCEL_REQUESTED" = true ]; then
            LAST_PKG_COMMAND="aguardar liberação do apt/dpkg"
            LAST_PKG_EXIT_CODE=130
            log "WARN" "Usuário interrompeu a espera pelo gerenciador de pacotes."
            encerrar_ui_termux
            restaurar_trap_pkg
            return 130
        fi
        lock_pids="$(pids_gerenciador_pacotes_ativos)"
        lock_pids="${lock_pids% }"
        [ -z "$lock_pids" ] && break
        lock_decorrido=$((SECONDS - lock_inicio))
        if [ "$lock_decorrido" -ge "$lock_timeout" ]; then
            LAST_PKG_COMMAND="aguardar liberação do apt/dpkg"
            LAST_PKG_EXIT_CODE=75
            log "ERROR" "Gerenciador de pacotes ocupado por PID(s): $lock_pids após ${lock_decorrido}s"
            encerrar_ui_termux
            restaurar_trap_pkg
            return 75
        fi
        tela_operacao_termux "$titulo" "$pct" \
            "Aguardando o gerenciador de pacotes..." \
            "Outra instalação/atualização está em andamento." \
            "⏳ apt/dpkg ocupado" "PID(s): $lock_pids" \
            "O Manager continuará automaticamente quando for liberado." \
            "Tempo de espera: ${lock_decorrido}s de ${lock_timeout}s" \
            "Ctrl+C abre opções sem encerrar o Manager."
        sleep 2
    done

    local -a apt_opcoes=(-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o DPkg::Lock::Timeout=30)
    local -a comando_exec=()
    case "${args[0]:-}" in
        update)
            comando_exec=(apt-get "${apt_opcoes[@]}" update)
            ;;
        upgrade)
            comando_exec=(env DEBIAN_FRONTEND=noninteractive apt-get "${apt_opcoes[@]}" upgrade -y
                -o Dpkg::Options::=--force-confdef
                -o Dpkg::Options::=--force-confold)
            ;;
        install)
            comando_exec=(env DEBIAN_FRONTEND=noninteractive apt-get "${apt_opcoes[@]}" install -y
                -o Dpkg::Options::=--force-confdef
                -o Dpkg::Options::=--force-confold)
            comando_exec+=("${args[@]:2}")
            ;;
        *)
            comando_exec=(pkg "${args[@]}")
            ;;
    esac
    LAST_PKG_COMMAND=""
    local arg
    for arg in "${comando_exec[@]}"; do
        printf -v LAST_PKG_COMMAND '%s%q ' "$LAST_PKG_COMMAND" "$arg"
    done
    LAST_PKG_COMMAND="${LAST_PKG_COMMAND% }"
    LAST_PKG_EXIT_CODE=""
    mkdir -p "$(dirname "$TERMUX_SETUP_LOG")"
    : >> "$TERMUX_SETUP_LOG"
    LAST_PKG_LOG_START_OFFSET="$(wc -c < "$TERMUX_SETUP_LOG" 2>/dev/null || printf '0')"
    ultimo_tamanho="$LAST_PKG_LOG_START_OFFSET"
    atividade_em=$SECONDS
    inicio_exec=$SECONDS

    "${comando_exec[@]}" >>"$TERMUX_SETUP_LOG" 2>&1 &
    pid=$!
    PKG_ACTIVE_PID="$pid"
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$PKG_CANCEL_REQUESTED" = true ]; then
            encerrar_arvore_pid "$pid"
            wait "$pid" 2>/dev/null || true
            LAST_PKG_EXIT_CODE=130
            log "WARN" "Operação de pacote interrompida pelo usuário: $LAST_PKG_COMMAND"
            encerrar_ui_termux
            restaurar_trap_pkg
            return 130
        fi

        if log_pkg_exige_interacao "$TERMUX_SETUP_LOG" "$LAST_PKG_LOG_START_OFFSET" || pid_ou_filho_parado "$pid"; then
            encerrar_arvore_pid "$pid"
            wait "$pid" 2>/dev/null || true
            encerrar_ui_termux
            # O comando monitorado usa DEBIAN_FRONTEND=noninteractive. Antes,
            # ao detectar um prompt, o Manager repetia exatamente esse mesmo
            # comando e portanto continuava sem oferecer um TTY interativo de
            # verdade. Retoma agora pelo `pkg` original em uma sessão ligada ao
            # terminal, preservando o log quando o utilitário `script` existe.
            trap - INT
            executar_pkg_interativo "$titulo" "${args[@]}"
            rc=$?
            LAST_PKG_EXIT_CODE="$rc"
            restaurar_trap_pkg
            return "$rc"
        fi

        tamanho_atual="$(wc -c < "$TERMUX_SETUP_LOG" 2>/dev/null || printf '%s' "$ultimo_tamanho")"
        if [ "$tamanho_atual" != "$ultimo_tamanho" ]; then
            ultimo_tamanho="$tamanho_atual"
            atividade_em=$SECONDS
        fi
        decorrido=$((SECONDS - inicio_exec))
        ocioso=$((SECONDS - atividade_em))
        if [ "$ocioso" -ge 30 ]; then
            aviso_atividade="⚠ Sem nova saída há ${ocioso}s • rede/repositório pode estar lento"
        else
            aviso_atividade="✔ Processo ativo • última saída há ${ocioso}s"
        fi

        linhas="$(ultimas_linhas_pkg "$TERMUX_SETUP_LOG" 5)"
        assinatura="$pct|$linhas|$decorrido|$ocioso"
        if [ "$assinatura" != "${TERMUX_UI_LAST_SIGNATURE:-}" ]; then
            TERMUX_UI_LAST_SIGNATURE="$assinatura"
            PKG_PREVIEW_LINES="$linhas" tela_operacao_termux "$titulo" "$pct" "$atividade" "$detalhe" \
                "⏳ pkg em execução" "PID: $pid • ${decorrido}s" "$aviso_atividade" \
                "Ctrl+C abre opções seguras; não encerra o Manager." "$linhas"
        fi
        iter=$((iter + 1))
        if [ "$pct" -lt "$limite" ] && [ $((iter % 2)) -eq 0 ]; then pct=$((pct + 1)); fi
        sleep 1
    done
    wait "$pid"; rc=$?
    LAST_PKG_EXIT_CODE="$rc"
    encerrar_ui_termux
    restaurar_trap_pkg
    return "$rc"
}

executar_pkg_com_log() {
    local titulo="$1"; shift
    if executar_pkg_monitorado "$titulo" 20 95 "Executando pkg..." "Comando: pkg $1" -- "$@"; then
        tela_operacao_termux "$titulo" 100 "Operação concluída." "Log salvo para diagnóstico." \
            "✔ pkg finalizado" "✔ Log atualizado" "✔ Interface restaurada" "Operação concluída." "$(ultimas_linhas_pkg "$TERMUX_SETUP_LOG" 5)"
        ok "$titulo concluído."
        return 0
    fi
    mostrar_erro_pkg "A operação '$titulo' falhou."
    return 1
}

