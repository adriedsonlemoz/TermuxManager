# Módulo: runtime_processes.sh
# Processos, portas, execução e saúde de servidores.

pid_ativo() {
    local arquivo_pid="$1" pid
    [ -f "$arquivo_pid" ] || return 1
    pid="$(cat "$arquivo_pid" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

limpar_pidfiles_inativos() {
    local arquivo_pid nome
    mkdir -p "$PID_DIR"
    for arquivo_pid in "$PID_DIR"/*.pid; do
        [ -e "$arquivo_pid" ] || continue
        if ! pid_ativo "$arquivo_pid"; then
            nome="$(basename "$arquivo_pid" .pid)"
            rm -f "$arquivo_pid" "$PID_DIR/${nome}.meta"
        fi
    done
}

# ============================================================================
# IDENTIDADE E METADADOS DE PROCESSOS
# ============================================================================

id_projeto() {
    # Identidade interna baseada no caminho absoluto/canônico do projeto.
    # Isso impede colisões entre ~/Painel e ~/Painel/projetos/<nome>, mesmo
    # quando ambos possuem backend/, frontend/ ou o mesmo nome de package.
    local projeto="$1" base caminho soma
    base="$(printf '%s' "$(basename "$projeto")" | tr -cs '[:alnum:]_-' '_')"
    caminho="$(cd "$projeto" 2>/dev/null && pwd -P || readlink -f "$projeto" 2>/dev/null || printf '%s' "$projeto")"
    if comando_existe sha256sum; then
        soma="$(printf '%s' "$caminho" | sha256sum | cut -c1-12)"
    elif comando_existe shasum; then
        soma="$(printf '%s' "$caminho" | shasum -a 256 | cut -c1-12)"
    else
        soma="$(printf '%s' "$caminho" | cksum | awk '{print $1}')"
    fi
    ID_PROJETO="${base}_${soma}"
    CAMINHO_PROJETO_CANONICO="$caminho"
}

nome_processo_projeto() {
    local projeto="$1" componente="$2"
    id_projeto "$projeto"
    NOME_PROCESSO="${ID_PROJETO}_${componente}"
}

meta_valor() {
    local arquivo="$1" chave="$2"
    [ -f "$arquivo" ] || return 1
    sed -n "s/^${chave}=//p" "$arquivo" | head -n 1
}

meta_definir() {
    local arquivo="$1" chave="$2" valor="$3" tmp
    mkdir -p "$(dirname "$arquivo")"
    tmp="${arquivo}.tmp.$$"
    if [ -f "$arquivo" ]; then
        grep -v "^${chave}=" "$arquivo" > "$tmp" 2>/dev/null || true
    else
        : > "$tmp"
    fi
    printf '%s=%s\n' "$chave" "$valor" >> "$tmp"
    mv "$tmp" "$arquivo"
}


rotulo_processo() {
    local nome="$1" valor
    local meta="$PID_DIR/${nome}.meta"
    valor="$(meta_valor "$meta" LABEL 2>/dev/null || true)"
    if [ -z "$valor" ]; then
        valor="${nome%_frontend}"
        valor="${valor%_backend}"
    fi
    printf '%s' "$valor"
}

componente_processo() {
    local nome="$1" valor
    local meta="$PID_DIR/${nome}.meta"
    valor="$(meta_valor "$meta" COMPONENT 2>/dev/null || true)"
    if [ -z "$valor" ]; then
        [[ "$nome" == *_frontend ]] && valor="frontend"
        [[ "$nome" == *_backend ]] && valor="backend"
    fi
    printf '%s' "${valor:-processo}"
}

# ============================================================================
# EXECUÇÃO E SAÚDE DOS SERVIDORES
# ============================================================================

detectar_porta_frontend() {
    case "$DETECT_FRAMEWORK" in
        Vite|React|Svelte) printf '5173' ;;
        Next.js|Nuxt) printf '3000' ;;
        Vue) printf '8080' ;;
        Angular) printf '4200' ;;
        *) printf '3000' ;;
    esac
}

abrir_navegador() {
    local url="$1"
    if [ "${ABRIR_NAVEGADOR_AUTO:-true}" != true ]; then
        info "Servidor disponível em: $url"
        return 0
    fi
    info "Abrindo navegador em: $url"
    if comando_existe termux-open-url; then
        termux-open-url "$url" >>"$LOG_FILE" 2>&1 || true
    elif comando_existe termux-open; then
        termux-open "$url" >>"$LOG_FILE" 2>&1 || true
    else
        warn "termux-open não está disponível. URL: $url"
    fi
}

porta_esperada_execucao() {
    local dir="$1" cmd="$2" componente="$3" porta=""
    if [ -f "$dir/.env" ]; then
        porta="$(grep -E '^[[:space:]]*PORT[[:space:]]*=' "$dir/.env" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -cd '0-9')"
    fi
    if ! porta_valida "$porta"; then
        porta="$(printf '%s' "$cmd" | sed -nE 's/.*--port[=[:space:]]+([0-9]{2,5}).*/\\1/p' | tail -n 1)"
    fi
    if ! porta_valida "$porta" && [[ "$cmd" =~ http\.server[[:space:]]+([0-9]{2,5}) ]]; then
        porta="${BASH_REMATCH[1]}"
    fi
    if ! porta_valida "$porta" && [ "$componente" = frontend ]; then
        porta="$(detectar_porta_frontend)"
    fi
    porta_valida "$porta" && printf '%s' "$porta"
}

executar_em_background() {
    # executar_em_background <diretorio> <comando> <nome> [projeto] [componente]
    local dir="$1" cmd="$2" nome="$3" projeto="${4:-$1}" componente="${5:-processo}"
    local logfile="$LOG_DIR/${nome}.log" pidfile="$PID_DIR/${nome}.pid" metafile="$PID_DIR/${nome}.meta"
    local pid porta_esperada=""

    porta_esperada="$(porta_esperada_execucao "$dir" "$cmd" "$componente" 2>/dev/null || true)"
    mkdir -p "$LOG_DIR" "$PID_DIR"
    if pid_ativo "$pidfile"; then
        warn "'$nome' já está ativo (PID $(cat "$pidfile"))."
        return 0
    fi

    rotacionar_log "$logfile"
    : > "$logfile"
    (
        cd "$dir" || exit 1
        nohup bash -lc "exec $cmd" >>"$logfile" 2>&1 </dev/null &
        printf '%s\n' "$!" > "$pidfile"
    ) || {
        error "Não foi possível iniciar '$nome'."
        return 1
    }

    pid="$(cat "$pidfile" 2>/dev/null || true)"
    {
        printf 'DIR=%s\n' "$dir"
        printf 'PROJECT=%s\n' "$projeto"
        printf 'LABEL=%s\n' "$(basename "$projeto")"
        printf 'COMPONENT=%s\n' "$componente"
        printf 'CMD=%s\n' "$cmd"
        printf 'START=%s\n' "$(date +%s)"
        printf 'STATE=starting\n'
        [ -n "$porta_esperada" ] && printf 'EXPECTED_PORT=%s\n' "$porta_esperada"
    } > "$metafile"

    # Evita esperar 1 segundo fixo. Em aparelhos lentos ainda damos uma curta
    # janela para detectar encerramento imediato, mas seguimos em ~200 ms.
    sleep 0.2
    if ! pid_ativo "$pidfile"; then
        error "'$nome' encerrou logo após iniciar."
        [ "${MOSTRAR_LOG_FALHA:-true}" = true ] && [ -f "$logfile" ] && { echo; tail -n 16 "$logfile"; echo; }
        rm -f "$pidfile" "$metafile"
        return 1
    fi

    ok "'$nome' iniciado (PID $pid)."
    info "Log: $(caminho_home_relativo "$logfile")"
    log "INFO" "Processo iniciado: $nome PID=$pid componente=$componente"
    return 0
}

log_indica_falha_servidor() {
    local logf="$1"
    [ -s "$logf" ] || return 1
    tail -n 80 "$logf" 2>/dev/null | grep -qiE \
        '(Failed running|Unhandled .error.|EADDRINUSE|Cannot find module|MODULE_NOT_FOUND|SyntaxError:|ReferenceError:|TypeError:|node:events:.*|throw er;|Traceback \(most recent call last\)|address already in use|segmentation fault|panic:)'
}

porta_em_escuta() {
    local porta="$1"
    porta_valida "$porta" || return 1
    if comando_existe ss; then
        ss -ltnH 2>/dev/null | awk -v p=":$porta" '$4 ~ p"$" {achou=1; exit} END{exit !achou}' && return 0
    fi
    if comando_existe curl; then
        curl -sS --connect-timeout 1 --max-time 2 -o /dev/null "http://127.0.0.1:$porta/" >/dev/null 2>&1 && return 0
    fi
    if comando_existe nc; then
        nc -z 127.0.0.1 "$porta" >/dev/null 2>&1 && return 0
    fi
    return 1
}

estado_servidor_processo() {
    # Define ESTADO_PROCESSO, ICONE_PROCESSO e PORTA_PROCESSO.
    local nome="$1" porta
    local pf="$PID_DIR/${nome}.pid" logf="$LOG_DIR/${nome}.log"
    ESTADO_PROCESSO="encerrado"; ICONE_PROCESSO="🔴"; PORTA_PROCESSO="?"
    pid_ativo "$pf" || return 1
    porta="$(porta_processo "$nome")"
    PORTA_PROCESSO="$porta"
    if porta_valida "$porta" && porta_em_escuta "$porta"; then
        ESTADO_PROCESSO="servidor disponível"; ICONE_PROCESSO="🟢"
        return 0
    fi
    if log_indica_falha_servidor "$logf"; then
        ESTADO_PROCESSO="processo ativo • servidor falhou"; ICONE_PROCESSO="🟡"
    else
        ESTADO_PROCESSO="processo ativo • servidor não confirmado"; ICONE_PROCESSO="🟡"
    fi
    return 2
}

aguardar_servidor_processo() {
    local nome="$1" tentativas="${2:-20}" porta
    local logf="$LOG_DIR/${nome}.log" meta="$PID_DIR/${nome}.meta"
    while [ "$tentativas" -gt 0 ]; do
        if ! pid_ativo "$PID_DIR/${nome}.pid"; then
            error "O processo '$nome' encerrou antes de disponibilizar o servidor."
            meta_definir "$meta" STATE "stopped" || true
            return 1
        fi
        porta="$(porta_processo "$nome")"
        if porta_valida "$porta" && porta_em_escuta "$porta"; then
            meta_definir "$meta" PORT "$porta" || true
            meta_definir "$meta" STATE "healthy" || true
            ok "Servidor disponível na porta $porta."
            return 0
        fi
        if log_indica_falha_servidor "$logf"; then
            if log_indica_dependencia_corrompida "$logf"; then
                meta_definir "$meta" STATE "dependency_error" || true
                error "O processo continua ativo, mas há falha de dependência na inicialização."
            else
                meta_definir "$meta" STATE "degraded" || true
                error "O processo continua ativo, mas o servidor falhou ao iniciar."
            fi
            info "Consulte o log: $(caminho_home_relativo "$logf")"
            if [ "${MOSTRAR_LOG_FALHA:-true}" = true ]; then
                if [ "$UI_LIVE_BOX_ACTIVE" = true ]; then
                    info "Detalhes completos disponíveis na Central de Diagnóstico."
                else
                    echo; tail -n 18 "$logf"; echo
                fi
            fi
            return 1
        fi
        sleep 0.35
        tentativas=$((tentativas-1))
    done
    meta_definir "$meta" STATE "degraded" || true
    warn "O processo está ativo, mas nenhuma porta de servidor foi confirmada."
    info "Ele aparecerá em 'Em execução' com estado amarelo."
    return 1
}

aguardar_backend_local() {
    local _dir="$1" nome="$2" tentativas="${3:-25}"
    info "Aguardando backend disponibilizar o servidor..."
    aguardar_servidor_processo "$nome" "$tentativas"
}

esperar_porta_e_abrir() {
    local nome="$1" porta
    info "Aguardando servidor frontend iniciar..."
    if ! aguardar_servidor_processo "$nome" "${TEMPO_DETECTAR_PORTA:-30}"; then
        return 1
    fi
    porta="$(porta_processo "$nome")"
    porta_valida "$porta" || {
        warn "Servidor ativo, mas a porta não pôde ser identificada."
        return 1
    }
    abrir_navegador "http://127.0.0.1:$porta"
}

confirmar_inicio() {
    local projeto="$1" acao="$2"
    [ "${CONFIRMAR_EXECUCAO:-true}" = true ] || return 0
    cabecalho_tela "🚀 Confirmar execução" "$(basename "$projeto")"
    caixa_linha_topo
    caixa_linha_texto "Ação: $acao"
    [ -n "$FRONT_DIR" ] && caixa_linha_texto "Frontend: $FRONT_FRAMEWORK"
    [ -n "$BACK_DIR" ] && caixa_linha_texto "Backend: $BACK_FRAMEWORK"
    caixa_linha_baixo
    rodape_atalhos "[0] Voltar  •  [Enter] Iniciar"
    ui_buffer_flush
    read -r RESPOSTA_MENU
    [ -z "$RESPOSTA_MENU" ]
}

menu_executar_projeto() {
    local projeto="$1" nome_front="" nome_back="" op
    local itens=()
    if [ -n "$FRONT_DIR" ]; then
        nome_processo_projeto "$projeto" frontend; nome_front="$NOME_PROCESSO"
        itens+=("1|🌐|Executar frontend|Iniciar $FRONT_FRAMEWORK")
    fi
    if [ -n "$BACK_DIR" ]; then
        nome_processo_projeto "$projeto" backend; nome_back="$NOME_PROCESSO"
        itens+=("2|🧰|Executar backend|Iniciar $BACK_FRAMEWORK")
    fi
    [ -n "$FRONT_DIR" ] && [ -n "$BACK_DIR" ] && itens+=("3|🧩|Executar sistema|Iniciar os dois componentes")
    itens+=("0|🔙|Cancelar|Voltar sem iniciar")
    menu_unificado "🚀 Executar projeto" "$(basename "$projeto")" "[0] Cancelar  •  [1–3] Executar" "${itens[@]}"
    ler_opcao; op="$RESPOSTA_MENU"
    case "$op" in
        1)
            [ -n "$FRONT_DIR" ] || { error "Frontend não detectado."; pause; return; }
            confirmar_inicio "$projeto" "Iniciar frontend" || return
            DETECT_FRAMEWORK="$FRONT_FRAMEWORK"
            executar_em_background "$FRONT_DIR" "$FRONT_RUN_CMD" "$nome_front" "$projeto" frontend || { pause; return; }
            esperar_porta_e_abrir "$nome_front"
            ;;
        2)
            [ -n "$BACK_DIR" ] || { error "Backend não detectado."; pause; return; }
            confirmar_inicio "$projeto" "Iniciar backend" || return
            executar_em_background "$BACK_DIR" "$BACK_RUN_CMD" "$nome_back" "$projeto" backend || { pause; return; }
            aguardar_backend_local "$BACK_DIR" "$nome_back" 20 || true
            ;;
        3)
            [ -n "$FRONT_DIR" ] && [ -n "$BACK_DIR" ] || { error "Sistema completo não detectado."; pause; return; }
            confirmar_inicio "$projeto" "Iniciar sistema completo" || return
            executar_em_background "$BACK_DIR" "$BACK_RUN_CMD" "$nome_back" "$projeto" backend || { pause; return; }
            DETECT_FRAMEWORK="$FRONT_FRAMEWORK"
            executar_em_background "$FRONT_DIR" "$FRONT_RUN_CMD" "$nome_front" "$projeto" frontend || { parar_processo "$nome_back" >/dev/null 2>&1 || true; pause; return; }
            if ! aguardar_backend_local "$BACK_DIR" "$nome_back" 25; then
                warn "Backend indisponível; encerrando o frontend iniciado em paralelo."
                parar_processo "$nome_front" >/dev/null 2>&1 || true
                pause; return
            fi
            esperar_porta_e_abrir "$nome_front"
            ;;
        0) info "Execução cancelada." ;;
        *) warn "Opção inválida." ;;
    esac
    pause
}

porta_valida() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

porta_pid_direto() {
    local pid="$1" porta=""
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    if comando_existe ss; then
        porta=$(ss -ltnpH 2>/dev/null | awk -v pid="$pid" '
            index($0, "pid=" pid ",") {
                addr=$4
                sub(/^.*:/, "", addr)
                if (addr ~ /^[0-9]+$/) { print addr; exit }
            }')
    fi

    if [ -z "$porta" ] && comando_existe lsof; then
        porta=$(lsof -Pan -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null             | awk 'NR>1 {addr=$9; sub(/^.*:/, "", addr); if (addr ~ /^[0-9]+$/) {print addr; exit}}')
    fi

    porta_valida "$porta" && printf '%s' "$porta"
}

porta_arvore_pid() {
    local pid="$1" porta filho
    porta="$(porta_pid_direto "$pid" 2>/dev/null || true)"
    if porta_valida "$porta"; then
        printf '%s' "$porta"
        return 0
    fi
    while IFS= read -r filho; do
        [ -n "$filho" ] || continue
        porta="$(porta_arvore_pid "$filho" 2>/dev/null || true)"
        if porta_valida "$porta"; then
            printf '%s' "$porta"
            return 0
        fi
    done < <(pgrep -P "$pid" 2>/dev/null || true)
    return 1
}

porta_log_estrita() {
    local logf="$1" porta=""
    [ -f "$logf" ] || return 1

    # URLs explícitas: exige dois-pontos e uma porta; nunca extrai o último octeto do IP.
    porta=$(grep -oE '(https?://)?(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]):[0-9]{2,5}' "$logf" 2>/dev/null         | grep -oE '[0-9]{2,5}$' | tail -n 1)

    # Frases comuns de servidores. Evita o padrão amplo "port + qualquer número".
    if [ -z "$porta" ]; then
        porta=$(grep -oiE '(listening|running|started|server|local)[^[:cntrl:]]{0,32}(port|porta|:)[[:space:]]*[0-9]{2,5}' "$logf" 2>/dev/null             | grep -oE '[0-9]{2,5}$' | tail -n 1)
    fi

    porta_valida "$porta" && printf '%s' "$porta"
}

porta_processo() {
    local nome="$1"
    local logf="$LOG_DIR/${nome}.log" meta="$PID_DIR/${nome}.meta"
    local pid porta=""

    porta="$(meta_valor "$meta" PORT 2>/dev/null || true)"
    if porta_valida "$porta" && porta_em_escuta "$porta"; then
        printf '%s
' "$porta"
        return 0
    fi

    porta="$(meta_valor "$meta" EXPECTED_PORT 2>/dev/null || true)"
    if porta_valida "$porta" && porta_em_escuta "$porta"; then
        meta_definir "$meta" PORT "$porta" || true
        printf '%s\n' "$porta"
        return 0
    fi

    pid=$(cat "$PID_DIR/${nome}.pid" 2>/dev/null || true)
    porta="$(porta_arvore_pid "$pid" 2>/dev/null || true)"
    if ! porta_valida "$porta" || ! porta_em_escuta "$porta"; then
        porta="$(porta_log_estrita "$logf" 2>/dev/null || true)"
    fi

    if porta_valida "$porta" && porta_em_escuta "$porta"; then
        meta_definir "$meta" PORT "$porta" || true
        printf '%s
' "$porta"
    else
        meta_definir "$meta" PORT "" || true
        printf '?
'
    fi
}

encerrar_arvore_processo() {
    local pid="$1" sinal="${2:-TERM}" filho
    while IFS= read -r filho; do
        [ -n "$filho" ] && encerrar_arvore_processo "$filho" "$sinal"
    done < <(pgrep -P "$pid" 2>/dev/null || true)
    kill -"$sinal" "$pid" 2>/dev/null || true
}

parar_processo() {
    local nome="$1" pid
    local pf="$PID_DIR/${nome}.pid"
    if ! pid_ativo "$pf"; then
        rm -f "$pf"
        warn "O processo '$nome' já não está ativo."
        return 1
    fi
    pid=$(cat "$pf")
    encerrar_arvore_processo "$pid" TERM
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        encerrar_arvore_processo "$pid" KILL
    fi
    rm -f "$pf" "$PID_DIR/${nome}.meta"
    ok "Processo '$nome' encerrado."
    log "INFO" "Processo encerrado: $nome PID=$pid"
}

mostrar_log_processo() {
    local nome="$1"
    local logf="$LOG_DIR/${nome}.log"
    cabecalho_tela "📋 Log da execução" "$nome"
    if [ -f "$logf" ]; then
        tail -n 40 "$logf"
    else
        warn "Log não encontrado: $logf"
    fi
    pause
}

abrir_frontend_ativo() {
    local nome="$1" porta
    porta=$(porta_processo "$nome")
    if [ "$porta" = "?" ]; then
        warn "A porta ainda não foi identificada. Consulte o log."
        pause
        return
    fi
    abrir_navegador "http://127.0.0.1:$porta"
}

tela_execucao() {
    local nome="$1" componente projeto_base porta op outro
    componente="$(componente_processo "$nome")"
    [ "$componente" = frontend ] && componente="Frontend"
    [ "$componente" = backend ] && componente="Backend"
    projeto_base="$(rotulo_processo "$nome")"
    local grupo="${nome%_frontend}"; grupo="${grupo%_backend}"

    while pid_ativo "$PID_DIR/${nome}.pid"; do
        estado_servidor_processo "$nome" >/dev/null 2>&1 || true
        porta="$PORTA_PROCESSO"
        local estado_atual="$ESTADO_PROCESSO" icone_atual="$ICONE_PROCESSO"
        if [ "$componente" = "Frontend" ]; then
            outro="${grupo}_backend"
            local itens=()
            if porta_valida "$porta" && porta_em_escuta "$porta"; then
                itens+=("1|🌐|Abrir no navegador|http://127.0.0.1:$porta")
            else
                itens+=("1|⚠️|Servidor indisponível|A porta do frontend não está respondendo")
            fi
            itens+=("2|📋|Ver log|Mostrar as últimas 40 linhas" "3|🛑|Parar frontend|Encerrar somente este componente")
            pid_ativo "$PID_DIR/${outro}.pid" && itens+=("4|🛑|Parar sistema completo|Encerrar frontend e backend deste projeto")
            menu_unificado "$icone_atual $projeto_base — $componente" "PID $(cat "$PID_DIR/${nome}.pid") • Porta $porta • $estado_atual" "[0] Voltar" "${itens[@]}"
            ler_opcao; op="$RESPOSTA_MENU"
            case "$op" in
                1) if porta_valida "$porta" && porta_em_escuta "$porta"; then abrir_frontend_ativo "$nome"; else warn "Servidor indisponível. Consulte o log."; pause; fi ;;
                2) mostrar_log_processo "$nome" ;;
                3) parar_processo "$nome"; pause; return ;;
                4)
                    pid_ativo "$PID_DIR/${outro}.pid" || { error "O backend não está ativo."; pause; continue; }
                    confirmar_acao "Encerrar frontend e backend de '$projeto_base'?" || continue
                    parar_processo "$nome"; parar_processo "$outro"; pause; return
                    ;;
                0) return ;;
                *) warn "Opção inválida."; pause ;;
            esac
        else
            outro="${grupo}_frontend"
            local itens=(
                "1|📋|Ver log|Mostrar as últimas 40 linhas"
                "2|🛑|Parar backend|Encerrar somente este componente"
            )
            pid_ativo "$PID_DIR/${outro}.pid" && itens+=("3|🛑|Parar sistema completo|Encerrar backend e frontend deste projeto")
            menu_unificado "$icone_atual $projeto_base — $componente" "PID $(cat "$PID_DIR/${nome}.pid") • Porta $porta • $estado_atual" "[0] Voltar" "${itens[@]}"
            ler_opcao; op="$RESPOSTA_MENU"
            case "$op" in
                1) mostrar_log_processo "$nome" ;;
                2) parar_processo "$nome"; pause; return ;;
                3)
                    pid_ativo "$PID_DIR/${outro}.pid" || { error "O frontend não está ativo."; pause; continue; }
                    confirmar_acao "Encerrar backend e frontend de '$projeto_base'?" || continue
                    parar_processo "$nome"; parar_processo "$outro"; pause; return
                    ;;
                0) return ;;
                *) warn "Opção inválida."; pause ;;
            esac
        fi
    done
}

menu_processos_ativos() {
    while true; do
        limpar_pidfiles_inativos
        local nomes=() pf nome i=1
        for pf in "$PID_DIR"/*.pid; do
            [ -e "$pf" ] || continue
            pid_ativo "$pf" || continue
            nomes+=("$(basename "$pf" .pid)")
        done
        if [ ${#nomes[@]} -eq 0 ]; then
            cabecalho_tela "🚦 Projetos em execução" "Nenhum processo gerenciado está ativo"
            caixa_simples "📭 Ambiente livre" "Inicie um projeto pelo menu de gerenciamento."
            pause; return
        fi
        cabecalho_tela "🚦 Projetos em execução" "${#nomes[@]} componente(s) ativo(s)"
        caixa_linha_topo
        for nome in "${nomes[@]}"; do
            local comp porta rotulo estado icone detalhe
            comp="$(componente_processo "$nome")"
            [ "$comp" = frontend ] && comp="Frontend"
            [ "$comp" = backend ] && comp="Backend"
            rotulo="$(rotulo_processo "$nome")"
            estado_servidor_processo "$nome" >/dev/null 2>&1 || true
            porta="$PORTA_PROCESSO"; estado="$ESTADO_PROCESSO"; icone="$ICONE_PROCESSO"
            if porta_valida "$porta"; then
                detalhe="$comp • PID $(cat "$PID_DIR/${nome}.pid") • Porta $porta • $estado"
            else
                detalhe="$comp • PID $(cat "$PID_DIR/${nome}.pid") • $estado"
            fi
            menu_opcao "$i" "$icone" "$rotulo" "$detalhe"
            i=$((i+1))
        done
        caixa_linha_baixo
        rodape_atalhos "[0] Voltar  •  [A] Parar todos  •  [número] Gerenciar"
        ler_opcao
        case "$RESPOSTA_MENU" in
            0) return ;;
            a|A)
                confirmar_acao "Encerrar todos os processos gerenciados?" || continue
                for nome in "${nomes[@]}"; do parar_processo "$nome"; done
                pause
                ;;
            *)
                if [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] && [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#nomes[@]} ]; then
                    tela_execucao "${nomes[$((RESPOSTA_MENU-1))]}"
                else
                    warn "Opção inválida."; pause
                fi
                ;;
        esac
    done
}

