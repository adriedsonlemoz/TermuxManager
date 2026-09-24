# Módulo: termux.sh
# Manager.sh — módulo

# ============================================================================
# ATUALIZAÇÕES E INSTALAÇÃO DE PACOTES
# ============================================================================

TERMUX_SETUP_LOG="${BASE_DIR:-$HOME/scripts/manager}/logs/termux-setup.log"
TERMUX_DIAGNOSTIC_LOG="${BASE_DIR:-$HOME/scripts/manager}/logs/ultimo-diagnostico.txt"
LAST_PKG_COMMAND=""
LAST_PKG_EXIT_CODE=""
TERMUX_UI_DRAWN=false
TERMUX_UI_LAST_SIGNATURE=""
WIZARD_MODE=false
PKG_LAST_NONEMPTY_LINES=""
LAST_PKG_LOG_START_OFFSET=0
PKG_ACTIVE_PID=""
PKG_CANCEL_REQUESTED=false
TERMUX_VARIANT_ID=""
TERMUX_VARIANT_LABEL=""
TERMUX_VARIANT_SOURCE=""
TERMUX_REPO_PRIMARY=""
TERMUX_REPO_SUMMARY=""

first_run_stage_done() {
    local etapa="$1"
    [ -f "${FIRST_RUN_STATE_FILE:-}" ] || return 1
    grep -Fxq "${etapa}=done" "$FIRST_RUN_STATE_FILE" 2>/dev/null
}

first_run_mark_stage() {
    local etapa="$1"
    [ -n "${FIRST_RUN_STATE_FILE:-}" ] || return 0
    mkdir -p "$(dirname "$FIRST_RUN_STATE_FILE")" 2>/dev/null || true
    first_run_stage_done "$etapa" || printf '%s=done\n' "$etapa" >> "$FIRST_RUN_STATE_FILE"
}

first_run_progress_summary() {
    local etapa status linhas=()
    for etapa in storage update tools shortcut; do
        if first_run_stage_done "$etapa"; then status="✔"; else status="○"; fi
        case "$etapa" in
            storage) linhas+=("$status Armazenamento") ;;
            update) linhas+=("$status Atualização do Termux") ;;
            tools) linhas+=("$status Ferramentas recomendadas") ;;
            shortcut) linhas+=("$status Atalho global") ;;
        esac
    done
    printf '%s\n' "${linhas[@]}"
}

coletar_repositorios_termux() {
    local -a fontes=()
    local arquivo prefixo="${PREFIX:-}"
    [ -n "$prefixo" ] || return 0
    [ -r "$prefixo/etc/apt/sources.list" ] && fontes+=("$prefixo/etc/apt/sources.list")
    for arquivo in "$prefixo"/etc/apt/sources.list.d/*.list; do
        [ -r "$arquivo" ] && fontes+=("$arquivo")
    done
    [ ${#fontes[@]} -gt 0 ] || return 0
    awk '/^[[:space:]]*deb[[:space:]]+https?:\/\// {print $2}' "${fontes[@]}" 2>/dev/null | awk '!seen[$0]++'
}

detectar_variante_termux() {
    if [ -n "${TERMUX_VARIANT_ID:-}" ] && [ -n "${TERMUX_VARIANT_LABEL:-}" ]; then
        return 0
    fi

    local versao="${TERMUX_VERSION:-}" repos="" repo_primario=""
    repos="$(coletar_repositorios_termux | paste -sd ', ' - 2>/dev/null || true)"
    repo_primario="$(printf '%s' "$repos" | awk -F', ' 'NF{print $1; exit}')"
    [ -n "$repo_primario" ] || repo_primario="indisponível"

    TERMUX_VARIANT_ID="unknown"
    TERMUX_VARIANT_LABEL="Origem não identificada"
    TERMUX_VARIANT_SOURCE="Indefinida"
    TERMUX_REPO_PRIMARY="$repo_primario"
    TERMUX_REPO_SUMMARY="${repos:-indisponível}"

    case "$versao" in
        googleplay.*)
            TERMUX_VARIANT_ID="google-play"
            TERMUX_VARIANT_LABEL="Google Play"
            TERMUX_VARIANT_SOURCE="Google Play"
            ;;
        *)
            case "$repos $versao" in
                *termux.net*)
                    TERMUX_VARIANT_ID="google-play"
                    TERMUX_VARIANT_LABEL="Google Play"
                    TERMUX_VARIANT_SOURCE="Google Play"
                    ;;
                *packages.termux.dev*|*packages-cf.termux.dev*|*grimler.se*|*termux.dev*)
                    TERMUX_VARIANT_ID="github-fdroid"
                    TERMUX_VARIANT_LABEL="GitHub/F-Droid"
                    TERMUX_VARIANT_SOURCE="GitHub/F-Droid"
                    ;;
            esac
            ;;
    esac

    if [ "$TERMUX_VARIANT_ID" = "unknown" ] && [ -n "$versao" ] && [[ "$versao" =~ ^[0-9] ]]; then
        TERMUX_VARIANT_ID="github-fdroid"
        TERMUX_VARIANT_LABEL="GitHub/F-Droid"
        TERMUX_VARIANT_SOURCE="GitHub/F-Droid"
    fi
}

termux_origem_resumida() {
    detectar_variante_termux
    printf '%s' "${TERMUX_VARIANT_LABEL:-indisponível}"
}

termux_repositorio_resumido() {
    detectar_variante_termux
    printf '%s' "${TERMUX_REPO_PRIMARY:-indisponível}"
}

pacote_disponivel_termux() {
    local pacote="$1"
    command -v apt-cache >/dev/null 2>&1 || return 0
    apt-cache show "$pacote" 2>/dev/null | grep -q '^Package:[[:space:]]'
}

status_pacote() {
    local pacote="$1"
    if dpkg -s "$pacote" >/dev/null 2>&1; then
        printf 'Instalado'
    else
        printf 'Não instalado'
    fi
}

barra_percentual_simples() {
    local pct="${1:-0}" largura=$((LARGURA_CAIXA - 14))
    [ "$largura" -lt 12 ] && largura=12
    [ "$pct" -lt 0 ] && pct=0
    [ "$pct" -gt 100 ] && pct=100
    local cheio vazio
    cheio=$((largura * pct / 100))
    vazio=$((largura - cheio))
    printf '[%s%s] %3d%%' "$(repetir_char '=' "$cheio")" "$(repetir_char '-' "$vazio")" "$pct"
}

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
    linha_conteudo "$n" "$(barra_percentual_simples "$pct")" "$C_CYAN"; n=$((n+1))
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
    } | sed -E $'s/\x1B\[[0-9;?]*[ -\/]*[@-~]//g; s/\r//g' > "$TERMUX_DIAGNOSTIC_LOG"
}


exportar_logs_downloads() {
    local destino
    if ! resolver_downloads_dir >/dev/null 2>&1; then
        printf '%s\n' "❌ Pasta Download indisponível. Execute termux-setup-storage."
        return 1
    fi
    destino="$DOWNLOADS_DIR"
    mkdir -p "$destino" 2>/dev/null || return 1
    [ -f "$TERMUX_SETUP_LOG" ] && cp -f "$TERMUX_SETUP_LOG" "$destino/termux-setup.log"
    [ -f "$TERMUX_DIAGNOSTIC_LOG" ] && cp -f "$TERMUX_DIAGNOSTIC_LOG" "$destino/ultimo-diagnostico.txt"
    printf '%s\n' "✔ Logs copiados para: $(caminho_curto "$destino")"
    printf '%s\n' "  • termux-setup.log"
    printf '%s\n' "  • ultimo-diagnostico.txt"
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
    [ -f "$TERMUX_SETUP_LOG" ] && cp -f "$TERMUX_SETUP_LOG" "$tmp/"
    [ -f "$TERMUX_DIAGNOSTIC_LOG" ] && cp -f "$TERMUX_DIAGNOSTIC_LOG" "$tmp/"
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
            printf '\033[2J\033[H\033[?25h'
            detectar_terminal
            caixa_simples "⚠ Ação necessária" "$titulo requer interação." "Responda diretamente abaixo."
            trap - INT
            "${comando_exec[@]}" 2>&1 | tee -a "$TERMUX_SETUP_LOG"
            rc=${PIPESTATUS[0]}
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

atualizar_pacotes_termux() {
    local inicio fim
    inicio=$(date +%s)
    mkdir -p "$(dirname "$TERMUX_SETUP_LOG")"
    : >> "$TERMUX_SETUP_LOG"

    if [ "${WIZARD_MODE:-false}" != true ]; then
        aviso_repositorios_termux || return 1
    fi

    # Corrige um dpkg interrompido antes de consultar ou atualizar pacotes.
    if [ -n "$(dpkg --audit 2>/dev/null)" ]; then
        if ! reparar_dpkg_automaticamente "Reparando instalação anterior interrompida"; then
            LAST_PKG_COMMAND="dpkg --configure -a; apt-get -f install"
            LAST_PKG_EXIT_CODE="1"
            mostrar_erro_pkg "Não foi possível reparar o sistema de pacotes antes da atualização."
            return 1
        fi
    fi

    if ! executar_pkg_monitorado "Preparando Ambiente Termux" 10 44         "Sincronizando repositórios..." "Usando mirrors oficiais do Termux." -- update -y; then
        if [ "${WIZARD_MODE:-false}" = true ] && [ "${LAST_PKG_EXIT_CODE:-}" = 130 ]; then
            log "INFO" "Atualização do wizard pausada pelo usuário durante apt-get update."
            return 130
        fi
        mostrar_erro_pkg "Falha ao consultar os repositórios do Termux."
        [ "${WIZARD_MODE:-false}" = true ] || pause
        return 1
    fi

    if ! executar_pkg_monitorado "Preparando Ambiente Termux" 45 89 \
        "Atualizando o sistema do Termux..." "Verificando pacotes instalados." -- upgrade -y; then
        if [ "${WIZARD_MODE:-false}" = true ] && [ "${LAST_PKG_EXIT_CODE:-}" = 130 ]; then
            log "INFO" "Atualização do wizard pausada pelo usuário durante apt-get upgrade."
            return 130
        fi
        # Se o dpkg ficou interrompido, tenta reparar e repete o upgrade uma
        # única vez. Isso cobre interrupções reais sem criar loop infinito.
        if log_pkg_tem_dpkg_interrompido "$TERMUX_SETUP_LOG" "${LAST_PKG_LOG_START_OFFSET:-0}"; then
            if reparar_dpkg_automaticamente "Reparando atualização interrompida"; then
                if ! executar_pkg_monitorado "Preparando Ambiente Termux" 55 89 \
                    "Retomando a atualização do Termux..." "Pacotes pendentes foram reparados." -- upgrade -y; then
                    mostrar_erro_pkg "A atualização falhou novamente após o reparo automático."
                    [ "${WIZARD_MODE:-false}" = true ] || pause
                    return 1
                fi
            else
                mostrar_erro_pkg "O dpkg foi interrompido e o reparo automático não conseguiu concluir."
                [ "${WIZARD_MODE:-false}" = true ] || pause
                return 1
            fi
        else
            mostrar_erro_pkg "Falha ao atualizar os pacotes do Termux."
            [ "${WIZARD_MODE:-false}" = true ] || pause
            return 1
        fi
    fi

    # Confirma a consistência depois do upgrade e tenta reparar antes de falhar.
    if [ -n "$(dpkg --audit 2>/dev/null)" ]; then
        if ! reparar_dpkg_automaticamente "Finalizando pacotes pendentes após a atualização"; then
            LAST_PKG_COMMAND="dpkg --audit"
            LAST_PKG_EXIT_CODE="1"
            mostrar_erro_pkg "Ainda existem pacotes pendentes após o reparo automático."
            return 1
        fi
    fi

    tela_operacao_termux "Preparando Ambiente Termux" 90 "Finalizando manutenção..." "Limpando arquivos temporários." "✔ Repositórios sincronizados" "✔ Pacotes atualizados" "⏳ Limpando cache" "Quase concluído."
    pkg clean >>"$TERMUX_SETUP_LOG" 2>&1 || true
    fim=$(date +%s)

    local resumo_linhas mirror atualizaveis
    resumo_linhas="$(ultimas_linhas_pkg "$TERMUX_SETUP_LOG" 5)"
    mirror="$(grep -Eo 'https?://[^ ]+' "$TERMUX_SETUP_LOG" 2>/dev/null | tail -n 1 | sed 's/[),]$//' || true)"
    [ -n "$mirror" ] || mirror="repositório configurado"
    atualizaveis="$(apt list --upgradable 2>/dev/null | awk 'NR>1 && NF{n++} END{print n+0}')"

    tela_operacao_termux "Ambiente Termux preparado" 100 "Atualização concluída." "Tempo: $(formatar_tempo $((fim-inicio)))" "✔ Repositórios sincronizados" "✔ Pacotes atualizados" "✔ Cache limpo" "O ambiente está pronto." "$resumo_linhas"
    encerrar_ui_termux
    cabecalho_tela "✅ Ambiente Termux preparado" "Atualização concluída em $(formatar_tempo $((fim-inicio)))"
    caixa_simples "Resumo" \
        "Mirror/repositório: $(printf '%s' "$mirror" | cut -c1-60)" \
        "Pacotes ainda atualizáveis: $atualizaveis" \
        "Configurações existentes: preservadas" \
        "Cache: limpo"
    local -a mensagens_resumo=()
    while IFS= read -r linha; do
        [ -n "$linha" ] && mensagens_resumo+=("$linha")
    done < <(printf '%s\n' "$resumo_linhas" | head -n 4)
    [ ${#mensagens_resumo[@]} -gt 0 ] || mensagens_resumo=("Nenhuma mensagem pendente.")
    caixa_simples "Últimas mensagens" "${mensagens_resumo[@]}"
    printf '\nLog completo: %s\n' "$(caminho_curto "$TERMUX_SETUP_LOG")"
    if [ "${WIZARD_MODE:-false}" = true ]; then
        echo
        caixa_simples "➡ Próxima etapa"             "A atualização do Termux já terminou."             "O assistente vai continuar automaticamente para instalar as ferramentas recomendadas."             "Se esta tela continuar visível por alguns segundos, isso não é travamento."             "Não use Ctrl+C aqui, a menos que realmente queira interromper a configuração."
        printf '\nProsseguindo automaticamente em 3 segundos...\n'
        sleep 3
    else
        printf '\nPressione ENTER para continuar...'
        read -r _
    fi
    return 0
}

configurar_armazenamento() {
    resolver_downloads_dir >/dev/null 2>&1 || true
    cabecalho_tela "🔐 Armazenamento" "Permissões do Android"
    if [ -d "$HOME/storage" ]; then
        caixa_simples "✅ Acesso encontrado" "~/storage está disponível" "Downloads: $(caminho_curto "$DOWNLOADS_DIR")"
        confirmar_acao "Executar termux-setup-storage novamente?" || return
    else
        caixa_simples "⚠ Acesso ausente" "O Android ainda não liberou os arquivos." "Aceite a permissão na próxima tela."
    fi
    if command -v termux-setup-storage >/dev/null 2>&1; then
        termux-setup-storage
        sleep 2
        resolver_downloads_dir || true
        [ -d "$HOME/storage" ] && ok "Armazenamento configurado." || warn "A permissão ainda não foi detectada."
    else
        error "termux-setup-storage não foi encontrado."
    fi
    [ "${WIZARD_MODE:-false}" = true ] || pause
}

verificar_ambiente_termux() {
    resolver_downloads_dir >/dev/null 2>&1 || true
    detectar_variante_termux
    cabecalho_tela "🔎 Diagnóstico do ambiente" "Ferramentas detectadas no aparelho"

    versao_cmd() {
        local cmd="$1"; shift
        if command -v "$cmd" >/dev/null 2>&1; then
            "$@" 2>&1 | head -1 | sed 's/^[[:space:]]*//'
        else
            printf 'não instalado'
        fi
    }

    caixa_simples "📱 Termux"         "Origem: $(termux_origem_resumida)"         "Versão: ${TERMUX_VERSION:-indisponível}"         "Repositório: $(termux_repositorio_resumido)"         "PREFIX: $(caminho_curto "${PREFIX:-indisponível}")"

    caixa_simples "📂 Acesso"         "Armazenamento: $([ -d "$HOME/storage" ] && echo OK || echo ausente)"         "Downloads: $([ -d "$DOWNLOADS_DIR" ] && echo acessível || echo indisponível)"         "Espaço livre: $(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $4}')"

    caixa_simples "🌐 Web"         "Git: $(versao_cmd git git --version)"         "Node: $(versao_cmd node node --version)"         "npm: $(versao_cmd npm npm --version)"         "pnpm: $(versao_cmd pnpm pnpm --version)"         "Yarn: $(versao_cmd yarn yarn --version)"         "PHP: $(versao_cmd php php --version)"         "Composer: $(versao_cmd composer composer --version)"

    caixa_simples "📝 Terminal e editores"         "Nano: $(versao_cmd nano nano --version)"         "Micro: $(versao_cmd micro micro --version)"         "Fish: $(versao_cmd fish fish --version)"         "Bash: $(versao_cmd bash bash --version)"

    caixa_simples "🐍 Python e Java"         "Python: $(versao_cmd python python --version)"         "pip: $(versao_cmd pip pip --version)"         "Java: $(versao_cmd java java -version)"         "Gradle: $(versao_cmd gradle gradle --version)"         "Maven: $(versao_cmd mvn mvn -version)"

    caixa_simples "🔧 Compilação e dados"         "Clang: $(versao_cmd clang clang --version)"         "Make: $(versao_cmd make make --version)"         "CMake: $(versao_cmd cmake cmake --version)"         "SQLite: $(versao_cmd sqlite3 sqlite3 --version)"         "PostgreSQL: $(versao_cmd psql psql --version)"         "MariaDB: $(versao_cmd mariadb mariadb --version)"
    pause
}
pacote_ja_funcional() {
    local pacote="${1:-}"
    case "$pacote" in
        nodejs) command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 ;;
        python) command -v python >/dev/null 2>&1 ;;
        php) command -v php >/dev/null 2>&1 ;;
        composer) command -v composer >/dev/null 2>&1 ;;
        golang) command -v go >/dev/null 2>&1 ;;
        rust) command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1 ;;
        ruby) command -v ruby >/dev/null 2>&1 ;;
        openjdk-*) command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1 ;;
        maven) command -v mvn >/dev/null 2>&1 ;;
        postgresql) command -v psql >/dev/null 2>&1 ;;
        sqlite) command -v sqlite3 >/dev/null 2>&1 ;;
        redis) command -v redis-server >/dev/null 2>&1 ;;
        openssh) command -v ssh >/dev/null 2>&1 ;;
        *) command -v "$pacote" >/dev/null 2>&1 ;;
    esac
}

pacote_instalado_ou_funcional() {
    local pacote="${1:-}"
    [ -n "$pacote" ] || return 1
    pacote_ja_funcional "$pacote" || dpkg -s "$pacote" >/dev/null 2>&1
}

instalar_lista_pacotes() {
    local titulo="$1"; shift
    local pacotes=("$@") faltando=() indisponiveis=() p
    local auto="${TERMUX_INSTALL_NONINTERACTIVE:-false}"
    detectar_variante_termux
    for p in "${pacotes[@]}"; do
        if pacote_instalado_ou_funcional "$p"; then
            continue
        elif pacote_disponivel_termux "$p"; then
            faltando+=("$p")
        else
            indisponiveis+=("$p")
            log "WARN" "Pacote não disponível nesta variante do Termux: $p (${TERMUX_VARIANT_LABEL:-desconhecida})"
        fi
    done

    if [ ${#faltando[@]} -eq 0 ]; then
        cabecalho_tela "🧰 Instalar ferramentas" "$titulo"
        if [ ${#indisponiveis[@]} -gt 0 ]; then
            caixa_simples "ℹ Compatibilidade" \
                "Origem: $(termux_origem_resumida)" \
                "Indisponíveis: ${#indisponiveis[@]}" \
                "${indisponiveis[*]}"
        else
            caixa_simples "✅ Nada a instalar" "Todos os componentes já estão disponíveis."
        fi
        if [ "$auto" != true ] && [ "${WIZARD_MODE:-false}" != true ]; then pause; fi
        return 0
    fi

    cabecalho_tela "🧰 Instalar ferramentas" "$titulo"
    caixa_simples "Sistema do Termux" \
        "Origem: $(termux_origem_resumida)" \
        "Repositório: $(termux_repositorio_resumido)" \
        "Pacotes ausentes: ${#faltando[@]}"
    caixa_simples "Instalação em lote" "${faltando[*]}"
    if [ ${#indisponiveis[@]} -gt 0 ]; then
        caixa_simples "Compatibilidade" \
            "Pacotes indisponíveis serão ignorados." \
            "${indisponiveis[*]}"
    fi
    if [ "$auto" != true ] && [ "${WIZARD_MODE:-false}" != true ]; then
        confirmar_acao "Continuar com a instalação?" || return 1
    fi

    mkdir -p "$(dirname "$TERMUX_SETUP_LOG")"
    local rc=0 instalados=0 falhas=0 pulados=0 p_rc escolha

    # Primeiro tenta tudo de uma vez. Isso reduz resolução repetida de
    # dependências, abertura do apt e espera por lock entre cada pacote.
    if executar_pkg_monitorado "Instalando Ferramentas" 10 90 \
        "Pacotes: ${#faltando[@]}" "Instalação em lote pelo pkg." -- install -y "${faltando[@]}"; then
        instalados=${#faltando[@]}
    else
        rc=$?
        if [ "$rc" -eq 130 ] && [ "${WIZARD_MODE:-false}" = true ]; then
            encerrar_ui_termux
            cabecalho_tela "⏸ Instalação pausada" "$titulo"
            caixa_simples "Ctrl+C recebido" \
                "O Manager continua aberto." \
                "Você pode tentar de novo ou retomar depois."
            printf '\n[1] Tentar novamente  [2] Retomar depois\n> '
            IFS= read -r escolha
            case "$escolha" in
                1) instalar_lista_pacotes "$titulo" "${pacotes[@]}"; return $? ;;
                *) return 130 ;;
            esac
        fi

        # Um lote pode falhar por apenas um pacote. Repara o dpkg quando
        # necessário e tenta somente os itens que ainda faltarem.
        [ -n "$(dpkg --audit 2>/dev/null)" ] && reparar_dpkg_automaticamente "Reparando antes do fallback" || true
        log "WARN" "Instalação em lote falhou para '$titulo'; iniciando fallback individual."
        for p in "${faltando[@]}"; do
            if pacote_instalado_ou_funcional "$p"; then
                instalados=$((instalados + 1))
                continue
            fi
            if executar_pkg_monitorado "Instalando Ferramentas" 10 95 \
                "Fallback: $p" "Tentativa individual." -- install -y "$p"; then
                instalados=$((instalados + 1))
                continue
            fi
            p_rc=$?
            if [ "$p_rc" -eq 130 ] && [ "${WIZARD_MODE:-false}" = true ]; then
                encerrar_ui_termux
                cabecalho_tela "⏸ Instalação pausada" "Pacote: $p"
                printf '\n[1] Tentar novamente  [2] Pular  [3] Retomar depois\n> '
                IFS= read -r escolha
                case "$escolha" in
                    1) TERMUX_INSTALL_NONINTERACTIVE="$auto" instalar_lista_pacotes "$titulo" "${pacotes[@]}"; return $? ;;
                    2) pulados=$((pulados + 1)); continue ;;
                    *) return 130 ;;
                esac
            fi
            falhas=$((falhas + 1))
            log "ERROR" "Falha ao instalar pacote Termux: $p"
        done
    fi

    tela_operacao_termux "Instalando Ferramentas" 100 \
        "Instalação concluída." \
        "$instalados instalado(s) • $falhas falha(s) • $pulados pulado(s)" \
        "✔ Processamento finalizado" \
        "$([ "$falhas" -gt 0 ] && echo "⚠ Falhas: $falhas" || echo "✔ Nenhuma falha")" \
        "Log: $(caminho_curto "$TERMUX_SETUP_LOG")"

    if [ "$falhas" -eq 0 ]; then
        caixa_simples "✅ $titulo" \
            "Instalados: $instalados" \
            "Indisponíveis: ${#indisponiveis[@]}" \
            "Gerenciador: pkg do Termux"
    else
        caixa_simples "⚠ $titulo" \
            "Instalados: $instalados" \
            "Falhas: $falhas" \
            "Log: $(caminho_curto "$TERMUX_SETUP_LOG")"
    fi
    if [ "$auto" != true ] && [ "${WIZARD_MODE:-false}" != true ]; then pause; fi
    [ "$falhas" -eq 0 ]
}



versao_ferramenta_instalada() {
    local cmd="$1"; shift
    command -v "$cmd" >/dev/null 2>&1 || return 1
    local out
    out=$("$@" 2>&1 | head -n 1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$out" ] || out="instalado"
    printf '%s' "$out"
}

mostrar_lista_ferramentas_detectadas() {
    local -a linguagens=() web=() shells=() compilacao=() bancos=() utilitarios=() java=()
    local v total=0

    adicionar_ferramenta() {
        local categoria="$1" nome="$2" cmd="$3"; shift 3
        command -v "$cmd" >/dev/null 2>&1 || return 0
        local versao
        versao=$(versao_ferramenta_instalada "$cmd" "$@" 2>/dev/null || printf 'instalado')
        case "$categoria" in
            linguagens) linguagens+=("$nome: $versao") ;;
            web) web+=("$nome: $versao") ;;
            shells) shells+=("$nome: $versao") ;;
            compilacao) compilacao+=("$nome: $versao") ;;
            bancos) bancos+=("$nome: $versao") ;;
            utilitarios) utilitarios+=("$nome: $versao") ;;
            java) java+=("$nome: $versao") ;;
        esac
        total=$((total + 1))
    }

    adicionar_ferramenta linguagens "Python" python python --version
    adicionar_ferramenta linguagens "pip" pip pip --version
    adicionar_ferramenta linguagens "PHP" php php --version
    adicionar_ferramenta linguagens "Ruby" ruby ruby --version
    adicionar_ferramenta linguagens "Perl" perl perl -v
    adicionar_ferramenta linguagens "Go" go go version
    adicionar_ferramenta linguagens "Rust" rustc rustc --version

    adicionar_ferramenta web "Node.js" node node --version
    adicionar_ferramenta web "npm" npm npm --version
    adicionar_ferramenta web "pnpm" pnpm pnpm --version
    adicionar_ferramenta web "Yarn" yarn yarn --version
    adicionar_ferramenta web "Composer" composer composer --version
    adicionar_ferramenta web "Git" git git --version
    adicionar_ferramenta web "GitHub CLI" gh gh --version

    adicionar_ferramenta java "Java" java java -version
    adicionar_ferramenta java "Javac" javac javac -version
    adicionar_ferramenta java "Gradle" gradle gradle --version
    adicionar_ferramenta java "Maven" mvn mvn -version

    adicionar_ferramenta shells "Fish" fish fish --version
    adicionar_ferramenta shells "Bash" bash bash --version
    adicionar_ferramenta shells "Zsh" zsh zsh --version
    adicionar_ferramenta shells "Nano" nano nano --version
    adicionar_ferramenta shells "Micro" micro micro --version
    adicionar_ferramenta shells "Vim" vim vim --version
    adicionar_ferramenta shells "Neovim" nvim nvim --version

    adicionar_ferramenta compilacao "Clang" clang clang --version
    adicionar_ferramenta compilacao "GCC" gcc gcc --version
    adicionar_ferramenta compilacao "Make" make make --version
    adicionar_ferramenta compilacao "CMake" cmake cmake --version
    adicionar_ferramenta compilacao "pkg-config" pkg-config pkg-config --version

    adicionar_ferramenta bancos "SQLite" sqlite3 sqlite3 --version
    adicionar_ferramenta bancos "PostgreSQL" psql psql --version
    adicionar_ferramenta bancos "MariaDB" mariadb mariadb --version
    adicionar_ferramenta bancos "Redis" redis-server redis-server --version
    adicionar_ferramenta bancos "Mongo Shell" mongosh mongosh --version

    adicionar_ferramenta utilitarios "curl" curl curl --version
    adicionar_ferramenta utilitarios "wget" wget wget --version
    adicionar_ferramenta utilitarios "rsync" rsync rsync --version
    adicionar_ferramenta utilitarios "zip" zip zip -v
    adicionar_ferramenta utilitarios "unzip" unzip unzip -v
    adicionar_ferramenta utilitarios "jq" jq jq --version
    adicionar_ferramenta utilitarios "OpenSSL" openssl openssl version
    adicionar_ferramenta utilitarios "SSH" ssh ssh -V
    adicionar_ferramenta utilitarios "tmux" tmux tmux -V

    cabecalho_tela "📋 Ferramentas instaladas" "Somente ferramentas detectadas no Termux"
    caixa_simples "Resumo"         "Ferramentas detectadas: $total"         "Pacotes instalados no Termux: $(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | wc -l | tr -d ' ')"         "PREFIX: $(caminho_curto "$PREFIX")"
    caixa_simples "Ambientes"         "Web: $(ambiente_status_comandos node git curl)"         "Python: $(ambiente_status_comandos python)"         "Java: $(ambiente_status_comandos java)"         "Go: $(ambiente_status_comandos go)"         "Rust: $(ambiente_status_comandos cargo rustc)"         "PHP: $(ambiente_status_comandos php composer)"

    exibir_categoria_instalada() {
        local titulo="$1"; shift
        [ "$#" -gt 0 ] || return 0
        caixa_simples "$titulo" "$@"
    }

    exibir_categoria_instalada "🐍 Linguagens" "${linguagens[@]}"
    exibir_categoria_instalada "🌐 Web e versionamento" "${web[@]}"
    exibir_categoria_instalada "☕ Java" "${java[@]}"
    exibir_categoria_instalada "📝 Shells e editores" "${shells[@]}"
    exibir_categoria_instalada "🔧 Compilação" "${compilacao[@]}"
    exibir_categoria_instalada "💾 Bancos de dados" "${bancos[@]}"
    exibir_categoria_instalada "📦 Utilitários" "${utilitarios[@]}"

    if [ "$total" -eq 0 ]; then
        caixa_simples "Nenhuma ferramenta detectada"             "O Termux possui apenas os componentes básicos."             "Use Instalar ferramentas para adicionar pacotes."
    fi

    unset -f adicionar_ferramenta exibir_categoria_instalada
    pause
}

ambiente_dev_configurar() {
    local id="${1:-}"
    AMB_DEV_ID="$id"
    AMB_DEV_TITULO=""
    AMB_DEV_ICONE="🧰"
    AMB_DEV_COMANDOS=()
    AMB_DEV_ROTULOS=()
    AMB_DEV_PACOTES=()
    case "$id" in
        web)
            AMB_DEV_TITULO="Desenvolvimento Web"; AMB_DEV_ICONE="🌐"
            AMB_DEV_COMANDOS=(node npm git curl)
            AMB_DEV_ROTULOS=("Node.js" npm Git curl)
            AMB_DEV_PACOTES=(nodejs git curl wget)
            ;;
        python)
            AMB_DEV_TITULO="Python"; AMB_DEV_ICONE="🐍"
            AMB_DEV_COMANDOS=(python pip)
            AMB_DEV_ROTULOS=(Python pip)
            AMB_DEV_PACOTES=(python)
            ;;
        java)
            AMB_DEV_TITULO="Java"; AMB_DEV_ICONE="☕"
            AMB_DEV_COMANDOS=(java javac)
            AMB_DEV_ROTULOS=(Java Javac)
            AMB_DEV_PACOTES=()
            ;;
        go)
            AMB_DEV_TITULO="Go"; AMB_DEV_ICONE="🐹"
            AMB_DEV_COMANDOS=(go git)
            AMB_DEV_ROTULOS=(Go Git)
            AMB_DEV_PACOTES=(golang git)
            ;;
        rust)
            AMB_DEV_TITULO="Rust"; AMB_DEV_ICONE="🦀"
            AMB_DEV_COMANDOS=(cargo rustc)
            AMB_DEV_ROTULOS=(Cargo Rustc)
            AMB_DEV_PACOTES=(rust clang pkg-config git)
            ;;
        ruby)
            AMB_DEV_TITULO="Ruby"; AMB_DEV_ICONE="💎"
            AMB_DEV_COMANDOS=(ruby)
            AMB_DEV_ROTULOS=(Ruby)
            AMB_DEV_PACOTES=(ruby clang make pkg-config)
            ;;
        php)
            AMB_DEV_TITULO="PHP"; AMB_DEV_ICONE="🐘"
            AMB_DEV_COMANDOS=(php composer)
            AMB_DEV_ROTULOS=(PHP Composer)
            AMB_DEV_PACOTES=(php composer git)
            ;;
        build)
            AMB_DEV_TITULO="Compilação"; AMB_DEV_ICONE="🔧"
            AMB_DEV_COMANDOS=(clang make cmake pkg-config)
            AMB_DEV_ROTULOS=(Clang Make CMake pkg-config)
            AMB_DEV_PACOTES=(clang make cmake pkg-config)
            ;;
        *) return 1 ;;
    esac
}

ambiente_dev_contar() {
    local id="${1:-}" cmd presentes=0 total=0
    ambiente_dev_configurar "$id" || return 1
    for cmd in "${AMB_DEV_COMANDOS[@]}"; do
        total=$((total + 1))
        command -v "$cmd" >/dev/null 2>&1 && presentes=$((presentes + 1))
    done
    AMB_DEV_PRESENTES="$presentes"
    AMB_DEV_TOTAL="$total"
    AMB_DEV_FALTAM=$((total - presentes))
}

ambiente_dev_status() {
    local id="${1:-}"
    ambiente_dev_contar "$id" || { printf 'Desconhecido'; return 1; }
    if [ "$AMB_DEV_FALTAM" -eq 0 ]; then
        printf '✅ Completo'
    elif [ "$AMB_DEV_PRESENTES" -eq 0 ]; then
        printf '○ Não instalado'
    else
        printf '⚠ Incompleto (%d falta)' "$AMB_DEV_FALTAM"
    fi
}

ambiente_dev_faltantes() {
    local id="${1:-}" i cmd saida=""
    ambiente_dev_configurar "$id" || return 1
    for ((i=0; i<${#AMB_DEV_COMANDOS[@]}; i++)); do
        cmd="${AMB_DEV_COMANDOS[$i]}"
        if ! command -v "$cmd" >/dev/null 2>&1; then
            saida+="${saida:+, }${AMB_DEV_ROTULOS[$i]}"
        fi
    done
    printf '%s' "${saida:-nenhum}"
}

versao_comando_curta() {
    local cmd="${1:-}" out=""
    command -v "$cmd" >/dev/null 2>&1 || { printf 'ausente'; return; }
    case "$cmd" in
        java) out="$(java -version 2>&1 | head -n1)" ;;
        javac) out="$(javac -version 2>&1 | head -n1)" ;;
        go) out="$(go version 2>&1 | head -n1)" ;;
        php) out="$(php --version 2>&1 | head -n1)" ;;
        git) out="$(git --version 2>&1 | head -n1)" ;;
        curl) out="$(curl --version 2>&1 | head -n1)" ;;
        make) out="$(make --version 2>&1 | head -n1)" ;;
        *) out="$("$cmd" --version 2>&1 | head -n1 || true)" ;;
    esac
    [ -n "$out" ] || out="instalado"
    printf '%s' "$out"
}

instalar_faltantes_ambiente_dev() {
    local id="${1:-}"
    ambiente_dev_configurar "$id" || return 1
    if [ "$id" = java ]; then
        instalar_jdk_recomendado
        return $?
    fi
    instalar_lista_pacotes "$AMB_DEV_TITULO" "${AMB_DEV_PACOTES[@]}"
}

menu_detalhe_ambiente_dev() {
    local id="${1:-}" escolha i cmd rotulo linha
    while true; do
        ambiente_dev_contar "$id" || return 1
        local -a linhas=()
        for ((i=0; i<${#AMB_DEV_COMANDOS[@]}; i++)); do
            cmd="${AMB_DEV_COMANDOS[$i]}"; rotulo="${AMB_DEV_ROTULOS[$i]}"
            if command -v "$cmd" >/dev/null 2>&1; then
                linha="✅ $rotulo: $(versao_comando_curta "$cmd")"
            else
                linha="○ $rotulo: ausente"
            fi
            linhas+=("$linha")
        done
        cabecalho_tela "$AMB_DEV_ICONE $AMB_DEV_TITULO" "$(ambiente_dev_status "$id")"
        caixa_simples_wrap "Componentes" "${linhas[@]}"
        if [ "$AMB_DEV_FALTAM" -gt 0 ]; then
            caixa_simples "Faltando" "$(ambiente_dev_faltantes "$id")"
        fi
        rodape_atalhos "[0] Voltar  •  [1] Instalar o que falta"
        ui_buffer_flush
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) instalar_faltantes_ambiente_dev "$id" ;;
            0|"") return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

mostrar_ferramentas_instaladas() {
    local escolha id completos incompletos ausentes status
    while true; do
        completos=0; incompletos=0; ausentes=0
        for id in web python java go rust ruby php build; do
            ambiente_dev_contar "$id" || continue
            if [ "$AMB_DEV_FALTAM" -eq 0 ]; then
                completos=$((completos + 1))
            elif [ "$AMB_DEV_PRESENTES" -eq 0 ]; then
                ausentes=$((ausentes + 1))
            else
                incompletos=$((incompletos + 1))
            fi
        done
        menu_unificado "📋 Painel de ferramentas" \
            "$completos completos • $incompletos incompletos • $ausentes ausentes" \
            "[0] Voltar  •  [1–9] Abrir" \
            "1|🌐|Web|$(ambiente_dev_status web)" \
            "2|🐍|Python|$(ambiente_dev_status python)" \
            "3|☕|Java|$(ambiente_dev_status java)" \
            "4|🐹|Go|$(ambiente_dev_status go)" \
            "5|🦀|Rust|$(ambiente_dev_status rust)" \
            "6|💎|Ruby|$(ambiente_dev_status ruby)" \
            "7|🐘|PHP|$(ambiente_dev_status php)" \
            "8|🔧|Compilação|$(ambiente_dev_status build)" \
            "9|📦|Todas as ferramentas|Lista completa detectada"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) menu_detalhe_ambiente_dev web ;;
            2) menu_detalhe_ambiente_dev python ;;
            3) menu_detalhe_ambiente_dev java ;;
            4) menu_detalhe_ambiente_dev go ;;
            5) menu_detalhe_ambiente_dev rust ;;
            6) menu_detalhe_ambiente_dev ruby ;;
            7) menu_detalhe_ambiente_dev php ;;
            8) menu_detalhe_ambiente_dev build ;;
            9) mostrar_lista_ferramentas_detectadas ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

status_comando_curto() {
    local cmd="${1:-}"
    if command -v "$cmd" >/dev/null 2>&1; then
        printf 'Instalado'
    else
        printf 'Ausente'
    fi
}

ambiente_status_comandos() {
    local faltam=0 total=0 cmd
    for cmd in "$@"; do
        total=$((total + 1))
        command -v "$cmd" >/dev/null 2>&1 || faltam=$((faltam + 1))
    done
    if [ "$faltam" -eq 0 ]; then
        printf 'Completo'
    elif [ "$faltam" -eq "$total" ]; then
        printf 'Não instalado'
    else
        printf 'Incompleto (%d falta)' "$faltam"
    fi
}

java_pacote_recomendado() {
    if pacote_disponivel_termux openjdk-17; then
        printf 'openjdk-17'
    elif pacote_disponivel_termux openjdk-21; then
        printf 'openjdk-21'
    else
        printf 'openjdk-17'
    fi
}

menu_java_versoes() {
    local -a opcoes=() pacotes=()
    local n=1 p escolha
    for p in openjdk-17 openjdk-21; do
        pacote_disponivel_termux "$p" || continue
        opcoes+=("$n|☕|$p|$(status_pacote "$p")")
        pacotes+=("$p")
        n=$((n + 1))
    done
    if [ ${#pacotes[@]} -eq 0 ]; then
        cabecalho_tela "☕ Java" "Versões disponíveis"
        caixa_simples "Nenhum JDK listado" "O repositório atual não anunciou OpenJDK 17/21."
        pause
        return
    fi
    while true; do
        menu_unificado "☕ Versões do Java" "Somente versões disponíveis" "[0] Voltar" "${opcoes[@]}"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        [ "$escolha" = 0 ] && return
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#pacotes[@]} ]; then
            instalar_lista_pacotes "${pacotes[$((escolha-1))]}" "${pacotes[$((escolha-1))]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}

instalar_jdk_recomendado() {
    local jdk
    if command -v java >/dev/null 2>&1; then
        cabecalho_tela "☕ Java" "JDK"
        caixa_simples "✅ Java detectado" "Um JDK já está disponível no Termux." "Use Outras versões somente se quiser instalar outra versão."
        pause
        return 0
    fi
    jdk="$(java_pacote_recomendado)"
    instalar_lista_pacotes "JDK recomendado" "$jdk"
}

instalar_java_completo() {
    local jdk
    if command -v java >/dev/null 2>&1; then
        instalar_lista_pacotes "Ambiente Java completo" gradle maven
    else
        jdk="$(java_pacote_recomendado)"
        instalar_lista_pacotes "Ambiente Java completo" "$jdk" gradle maven
    fi
}

menu_java() {
    local jdk
    while true; do
        jdk="$(java_pacote_recomendado)"
        menu_unificado "☕ Ambiente Java" "Java: $(status_comando_curto java)" "[0] Voltar" \
            "1|☕|JDK recomendado|$jdk" \
            "2|📚|Outras versões|OpenJDK disponíveis" \
            "3|🐘|Gradle|$(status_comando_curto gradle)" \
            "4|📦|Maven|$(status_comando_curto mvn)" \
            "5|🧰|Java completo|JDK, Gradle e Maven"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_jdk_recomendado ;;
            2) menu_java_versoes ;;
            3) instalar_lista_pacotes "Gradle" gradle ;;
            4) instalar_lista_pacotes "Maven" maven ;;
            5) instalar_java_completo ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

instalar_gerenciadores_js() {
    local -a por_pkg=() por_npm=()
    local p
    for p in pnpm yarn; do
        if command -v "$p" >/dev/null 2>&1; then
            continue
        elif pacote_disponivel_termux "$p"; then
            por_pkg+=("$p")
        else
            por_npm+=("$p")
        fi
    done
    [ ${#por_pkg[@]} -gt 0 ] && instalar_lista_pacotes "Gerenciadores JavaScript" "${por_pkg[@]}"
    if [ ${#por_npm[@]} -gt 0 ]; then
        command -v npm >/dev/null 2>&1 || instalar_lista_pacotes "Node.js" nodejs || return 1
        cabecalho_tela "🌐 JavaScript" "Gerenciadores adicionais"
        caixa_simples "Instalação via npm" "Pacotes: ${por_npm[*]}" "Serão instalados globalmente."
        confirmar_acao "Instalar via npm?" "s" || return 0
        npm install -g "${por_npm[@]}" >>"$TERMUX_SETUP_LOG" 2>&1 \
            && ok "Gerenciadores JavaScript instalados." \
            || error "Falha ao instalar gerenciadores JavaScript."
        pause
    fi
    if [ ${#por_pkg[@]} -eq 0 ] && [ ${#por_npm[@]} -eq 0 ]; then
        cabecalho_tela "🌐 JavaScript" "Gerenciadores"
        caixa_simples "✅ Pronto" "pnpm e Yarn já estão disponíveis."
        pause
    fi
}

menu_web_dev() {
    while true; do
        menu_unificado "🌐 Desenvolvimento Web" "Node: $(status_comando_curto node) • Git: $(status_comando_curto git)" "[0] Voltar" \
            "1|🧰|Essenciais|Node.js, Git, curl e wget" \
            "2|⬢|Node.js|$(status_comando_curto node)" \
            "3|📦|pnpm / Yarn|Gerenciadores JavaScript" \
            "4|🌐|Git / GitHub|Git e GitHub CLI" \
            "5|✅|Web completo|Essenciais + GitHub CLI"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_lista_pacotes "Web essencial" nodejs git curl wget ;;
            2) instalar_lista_pacotes "Node.js" nodejs ;;
            3) instalar_gerenciadores_js ;;
            4) instalar_lista_pacotes "Git e GitHub" git gh ;;
            5) instalar_lista_pacotes "Web completo" nodejs git curl wget gh ; instalar_gerenciadores_js ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_python_dev() {
    while true; do
        menu_unificado "🐍 Ambiente Python" "Python: $(status_comando_curto python)" "[0] Voltar" \
            "1|🐍|Python básico|Interpretador e pip" \
            "2|🔧|Compilação nativa|Clang, Make e pkg-config" \
            "3|🧰|Python completo|Básico + compilação nativa"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_lista_pacotes "Python básico" python ;;
            2) instalar_lista_pacotes "Compilação para Python" clang make pkg-config ;;
            3) instalar_lista_pacotes "Python completo" python clang make pkg-config ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_compilacao_dev() {
    while true; do
        menu_unificado "🔧 Compilação" "Ferramentas nativas" "[0] Voltar" \
            "1|🔧|Kit básico|Clang, Make e pkg-config" \
            "2|🏗️|CMake|$(status_comando_curto cmake)" \
            "3|🧰|Kit completo|Clang, Make, CMake e pkg-config"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_lista_pacotes "Compilação básica" clang make pkg-config ;;
            2) instalar_lista_pacotes "CMake" cmake ;;
            3) instalar_lista_pacotes "Compilação completa" clang make cmake pkg-config ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_bancos_dev() {
    while true; do
        menu_unificado "💾 Bancos de dados" "Instale somente o necessário" "[0] Voltar" \
            "1|📄|SQLite|Leve • $(status_comando_curto sqlite3)" \
            "2|🐘|PostgreSQL|Servidor • $(status_comando_curto psql)" \
            "3|🗄️|MariaDB|Servidor • $(status_comando_curto mariadb)" \
            "4|⚡|Redis|Cache • $(status_comando_curto redis-server)"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_lista_pacotes "SQLite" sqlite ;;
            2) instalar_lista_pacotes "PostgreSQL" postgresql ;;
            3) instalar_lista_pacotes "MariaDB" mariadb ;;
            4) instalar_lista_pacotes "Redis" redis ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

adicionar_pacote_unico() {
    local pacote="$1"; shift
    local existente
    for existente in "$@"; do [ "$existente" = "$pacote" ] && return 1; done
    return 0
}

ferramentas_recomendadas_projetos() {
    local raiz="${PAINEL_DIR:-$HOME/Painel}" arquivo base dir jdk
    local -a arquivos=() pacotes=() motivos=()
    local node=0 python=0 php=0 go=0 rust=0 java_maven=0 java_gradle=0 projetos=0
    [ -d "$raiz" ] || {
        cabecalho_tela "🧠 Recomendado" "Análise dos projetos"
        caixa_simples "Nenhum Painel encontrado" "Ainda não há projetos para analisar."
        pause
        return 0
    }
    while IFS= read -r arquivo; do arquivos+=("$arquivo"); done < <(
        find "$raiz" -maxdepth 6 -type f \
            \( -name package.json -o -name requirements.txt -o -name pyproject.toml -o -name composer.json -o -name go.mod -o -name Cargo.toml -o -name pom.xml -o -name build.gradle -o -name build.gradle.kts \) \
            -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' 2>/dev/null | head -n 300
    )
    declare -A vistos=()
    for arquivo in "${arquivos[@]}"; do
        dir="$(dirname "$arquivo")"
        [ -z "${vistos[$dir]:-}" ] && { vistos[$dir]=1; projetos=$((projetos + 1)); }
        base="$(basename "$arquivo")"
        case "$base" in
            package.json) node=$((node + 1)) ;;
            requirements.txt|pyproject.toml) python=$((python + 1)) ;;
            composer.json) php=$((php + 1)) ;;
            go.mod) go=$((go + 1)) ;;
            Cargo.toml) rust=$((rust + 1)) ;;
            pom.xml) java_maven=$((java_maven + 1)) ;;
            build.gradle|build.gradle.kts) java_gradle=$((java_gradle + 1)) ;;
        esac
    done

    if [ "$node" -gt 0 ]; then
        command -v node >/dev/null 2>&1 || pacotes+=(nodejs)
        command -v git >/dev/null 2>&1 || pacotes+=(git)
    fi
    if [ "$python" -gt 0 ]; then command -v python >/dev/null 2>&1 || pacotes+=(python); fi
    if [ "$php" -gt 0 ]; then
        command -v php >/dev/null 2>&1 || pacotes+=(php)
        command -v composer >/dev/null 2>&1 || pacotes+=(composer)
    fi
    if [ "$go" -gt 0 ]; then command -v go >/dev/null 2>&1 || pacotes+=(golang); fi
    if [ "$rust" -gt 0 ]; then command -v cargo >/dev/null 2>&1 || pacotes+=(rust); fi
    if [ "$java_maven" -gt 0 ] || [ "$java_gradle" -gt 0 ]; then
        if ! command -v java >/dev/null 2>&1; then jdk="$(java_pacote_recomendado)"; pacotes+=("$jdk"); fi
        if [ "$java_maven" -gt 0 ]; then command -v mvn >/dev/null 2>&1 || pacotes+=(maven); fi
        if [ "$java_gradle" -gt 0 ]; then command -v gradle >/dev/null 2>&1 || pacotes+=(gradle); fi
    fi

    # Remove duplicatas preservando a ordem.
    local -a unicos=()
    local item achou u
    for item in "${pacotes[@]}"; do
        achou=false
        for u in "${unicos[@]}"; do [ "$u" = "$item" ] && { achou=true; break; }; done
        [ "$achou" = false ] && unicos+=("$item")
    done

    cabecalho_tela "🧠 Recomendado" "Ferramentas para seus projetos"
    caixa_simples "Projetos detectados" \
        "Pastas analisadas: $projetos" \
        "Node: $node • Python: $python • PHP: $php" \
        "Go: $go • Rust: $rust • Java: $((java_maven + java_gradle))"
    if [ ${#unicos[@]} -eq 0 ]; then
        caixa_simples "✅ Ambiente pronto" "Nenhuma ferramenta obrigatória está faltando."
        pause
        return 0
    fi
    caixa_simples "Faltando" "${unicos[*]}"
    confirmar_acao "Instalar somente o que falta?" "s" || return 0
    instalar_lista_pacotes "Recomendado para projetos" "${unicos[@]}"
}

menu_instalar_ferramentas() {
    while true; do
        menu_unificado "🧰 Instalar ferramentas" "Ambientes de desenvolvimento" "[0] Voltar  •  [1–9/A–E] Selecionar" \
            "1|📋|Ferramentas instaladas|Versões e ambientes" \
            "2|🧠|Recomendado|Analisar seus projetos" \
            "3|🌐|Web|$(ambiente_status_comandos node git curl)" \
            "4|🐍|Python|$(ambiente_status_comandos python)" \
            "5|☕|Java|$(ambiente_status_comandos java)" \
            "6|🐹|Go|$(ambiente_status_comandos go)" \
            "7|🦀|Rust|$(ambiente_status_comandos cargo rustc)" \
            "8|💎|Ruby|$(ambiente_status_comandos ruby)" \
            "9|🐘|PHP|$(ambiente_status_comandos php composer)" \
            "A|🔧|Compilação|Clang, Make e CMake" \
            "B|💾|Bancos|SQLite, PostgreSQL e outros" \
            "C|📦|Arquivos e dados|ZIP, unzip e jq" \
            "D|📝|Terminal e editores|Nano, Micro e Fish" \
            "E|🧩|Pacote manual|Nomes do pkg"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) mostrar_ferramentas_instaladas ;;
            2) ferramentas_recomendadas_projetos ;;
            3) menu_web_dev ;;
            4) menu_python_dev ;;
            5) menu_java ;;
            6) instalar_lista_pacotes "Ambiente Go" golang git ;;
            7) instalar_lista_pacotes "Ambiente Rust" rust clang pkg-config git ;;
            8) instalar_lista_pacotes "Ambiente Ruby" ruby clang make pkg-config ;;
            9) instalar_lista_pacotes "Ambiente PHP" php composer git ;;
            [Aa]) menu_compilacao_dev ;;
            [Bb]) menu_bancos_dev ;;
            [Cc]) instalar_lista_pacotes "Arquivos e dados" zip unzip jq ;;
            [Dd]) instalar_lista_pacotes "Terminal e editores" nano micro fish ;;
            [Ee])
                cabecalho_tela "📝 Instalação manual" "Use nomes válidos do pkg"
                local -a manuais=()
                read -rp "Pacotes separados por espaço: " -a manuais
                [ ${#manuais[@]} -gt 0 ] && instalar_lista_pacotes "Pacotes selecionados" "${manuais[@]}"
                ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_manutencao_termux() {
    while true; do
        menu_unificado "🧹 Manutenção" "Limpeza e inspeção" "[0] Voltar" \
            "1|🧹|Limpar cache|Executar pkg clean" \
            "2|📋|Desatualizados|Listar pacotes atualizáveis" \
            "3|🩺|Corrigir pacotes|Executar dpkg --configure -a" \
            "4|📊|Uso de espaço|Mostrar armazenamento do Termux"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) pkg clean >/dev/null 2>&1 && ok "Cache limpo."; pause ;;
            2) cabecalho_tela "📋 Pacotes desatualizados" "Consulta do apt"; apt list --upgradable 2>/dev/null; pause ;;
            3) dpkg --configure -a >>"$LOG_FILE" 2>&1 && ok "Configuração reparada." || error "Falha ao reparar."; pause ;;
            4) cabecalho_tela "📊 Espaço do Termux" "$PREFIX"; df -h "$HOME" "$PREFIX" 2>/dev/null; du -sh "$PREFIX" "$HOME/Painel" 2>/dev/null; pause ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

menu_ambiente_termux() {
    while true; do
        menu_unificado "🔧 Ambiente do Termux" "Preparação e manutenção" "[0] Voltar  •  [1–4] Selecionar" \
            "1|📦|Atualizar pacotes|Atualizar ambiente do Termux" \
            "2|🔐|Armazenamento|Configurar acesso aos arquivos" \
            "3|🔎|Verificar ambiente|Diagnóstico rápido" \
            "4|🧹|Manutenção|Cache, pacotes e espaço"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) atualizar_pacotes_termux ;;
            2) configurar_armazenamento ;;
            3) verificar_ambiente_termux ;;
            4) menu_manutencao_termux ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}


tela_conclusao_primeira_execucao() {
    # Primeira tela: conclusão isolada, sem prompts ou menus misturados.
    tela_caixa_unica "✅ Instalação concluída"         "Manager.sh ${MANAGER_VERSION}"         "Configuração inicial finalizada"         "${C_GREEN}✔${C_RESET} Versão instalada: ${MANAGER_VERSION}"         "${C_GREEN}✔${C_RESET} Ferramentas recomendadas verificadas"         "${C_GREEN}✔${C_RESET} Armazenamento preparado"         "${C_GREEN}✔${C_RESET} Atalho global configurado"         ""         "${C_DIM}As alterações já foram salvas no sistema.${C_RESET}"
    pause

    while true; do
        menu_unificado "🔄 Aplicar alterações"             "Reinício do shell recomendado"             "[1] Reiniciar agora  •  [2] Continuar  •  [0] Sair"             "1|🔄|Reiniciar o shell agora|Aplicar todas as alterações"             "2|▶️|Continuar para o Manager|Aplicar depois"             "0|🚪|Sair sem reiniciar|Voltar ao terminal atual"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1)
                tela_caixa_unica "🔄 Reiniciando o shell"                     "Manager.sh ${MANAGER_VERSION}"                     "A sessão atual será encerrada"                     "${C_GREEN}✔${C_RESET} Configuração salva"                     "${C_YELLOW}➜${C_RESET} Abra uma nova sessão do Termux após o encerramento"
                sleep 1
                liberar_bloqueio 2>/dev/null || true
                encerrar_ui_termux 2>/dev/null || true
                restaurar_terminal_manager 2>/dev/null || true
                trap - EXIT INT TERM
                if [ -n "${PPID:-}" ] && [ "$PPID" -gt 1 ] 2>/dev/null; then
                    kill -TERM "$PPID" 2>/dev/null || true
                fi
                exit 0
                ;;
            2)
                tela_caixa_unica "▶️ Continuando"                     "Abrindo o menu principal"                     "Reinicie o shell mais tarde para aplicar tudo"                     "${C_GREEN}✔${C_RESET} Manager pronto para uso"                     "${C_DIM}Comando de acesso: manager${C_RESET}"
                sleep 0.8
                return 0
                ;;
            0)
                tela_caixa_unica "👋 Configuração salva"                     "Manager.sh ${MANAGER_VERSION}"                     "Reinicie o Termux quando desejar"                     "${C_GREEN}✔${C_RESET} Nenhuma configuração será perdida"                     "${C_DIM}Para abrir novamente, execute: manager${C_RESET}"
                sleep 0.8
                liberar_bloqueio 2>/dev/null || true
                exit 0
                ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

assistente_primeira_execucao() {
    [ -f "$FIRST_RUN_FILE" ] && return 0

    detectar_variante_termux
    cabecalho_tela "👋 Bem-vindo ao Manager.sh" "Configuração inicial"
    caixa_simples "Termux detectado"         "Origem: $(termux_origem_resumida)"         "Versão: ${TERMUX_VERSION:-indisponível}"         "Repositório: $(termux_repositorio_resumido)"

    caixa_simples "Etapas do assistente" \
        "1. Liberar acesso ao armazenamento" \
        "2. Atualizar os pacotes do Termux" \
        "3. Instalar ferramentas recomendadas" \
        "4. Configurar o atalho global"

    if [ -f "${FIRST_RUN_STATE_FILE:-}" ]; then
        local -a progresso=()
        while IFS= read -r linha; do [ -n "$linha" ] && progresso+=("$linha"); done < <(first_run_progress_summary)
        caixa_simples "↩ Retomando configuração" \
            "Etapas concluídas não serão repetidas." \
            "${progresso[@]}"
    fi

    if ! confirmar_acao "Iniciar/continuar a configuração guiada agora?" "s"; then
        caixa_simples "Configuração adiada" \
            "Nada foi marcado como concluído." \
            "O assistente aparecerá novamente na próxima abertura."
        pause
        return 0
    fi

    WIZARD_MODE=true

    # Etapa 1 — armazenamento. Não bloqueia o restante se a permissão ainda
    # depender da confirmação visual do Android, mas só marca a etapa quando
    # ~/storage realmente existir.
    if ! first_run_stage_done storage; then
        if [ ! -d "$HOME/storage" ]; then
            configurar_armazenamento
        fi
        if [ -d "$HOME/storage" ]; then
            first_run_mark_stage storage
        else
            log "WARN" "Wizard: armazenamento ainda não foi liberado; etapa seguirá pendente."
        fi
    fi

    # Etapa 2 — atualização do sistema. Uma vez concluída, não é repetida ao
    # retomar o wizard depois de uma interrupção na instalação das ferramentas.
    if ! first_run_stage_done update; then
        if ! atualizar_pacotes_termux; then
            WIZARD_MODE=false
            cabecalho_tela "⚠ Configuração pausada" "Atualização do Termux não foi concluída"
            caixa_simples "Progresso preservado" \
                "O Manager pode ser usado normalmente." \
                "O assistente retomará esta etapa na próxima abertura." \
                "Log: $(caminho_curto "$TERMUX_SETUP_LOG")"
            pause
            return 0
        fi
        first_run_mark_stage update
    fi

    # Etapa 3 — cada pacote já instalado é detectado automaticamente. Ctrl+C
    # abre opções dentro da etapa e não encerra o Manager.
    if ! first_run_stage_done tools; then
        local ferramentas_rc=0
        if instalar_lista_pacotes "Ferramentas recomendadas" nano micro fish git curl wget zip unzip jq; then
            ferramentas_rc=0
        else
            ferramentas_rc=$?
        fi
        if [ "$ferramentas_rc" -eq 130 ]; then
            WIZARD_MODE=false
            cabecalho_tela "⏸ Configuração pausada" "Você escolheu retomar depois"
            caixa_simples "Progresso preservado" \
                "Pacotes já instalados não serão reinstalados." \
                "A atualização do Termux também não será repetida." \
                "O assistente continuará do pacote pendente na próxima abertura."
            pause
            return 0
        elif [ "$ferramentas_rc" -ne 0 ]; then
            WIZARD_MODE=false
            cabecalho_tela "⚠ Configuração incompleta" "Algumas ferramentas não foram instaladas"
            caixa_simples "Consulte o log" \
                "$(caminho_curto "$TERMUX_SETUP_LOG")" \
                "O progresso foi preservado e o assistente retomará na próxima abertura."
            pause
            return 0
        fi
        first_run_mark_stage tools
    fi

    WIZARD_MODE=false

    # Etapa 4 — cria um comando global independente do Bash/Fish.
    if ! first_run_stage_done shortcut; then
        configurar_atalho_primeira_execucao
        first_run_mark_stage shortcut
    fi

    # Só conclui definitivamente quando o armazenamento também estiver
    # disponível. As demais etapas permanecem salvas e não serão repetidas.
    if ! first_run_stage_done storage; then
        cabecalho_tela "⚠ Configuração quase concluída" "Falta liberar o armazenamento"
        caixa_simples "Progresso preservado"             "Atualização, ferramentas e atalhos já concluídos não serão repetidos."             "Na próxima abertura, aceite a permissão de armazenamento do Android."             "Depois disso o assistente finalizará automaticamente."
        pause
        return 0
    fi

    touch "$FIRST_RUN_FILE" 2>/dev/null || true
    rm -f "${FIRST_RUN_STATE_FILE:-}" 2>/dev/null || true

    tela_conclusao_primeira_execucao
}

