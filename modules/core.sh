# Módulo: core.sh
# Manager.sh — módulo

# ============================================================================
# CONFIGURAÇÃO GLOBAL
# ============================================================================

PAINEL_DIR="$HOME/Painel"
PROJETOS_DIR="$HOME/Painel/projetos"
DOWNLOADS_DIR="$HOME/storage/downloads"

# Caminho para apresentação ao usuário. Mantém caminhos absolutos internamente,
# mas esconde o prefixo privado do Termux quando o item está sob $HOME.
caminho_home_relativo() {
    local caminho="${1:-}"
    if [ -n "${HOME:-}" ]; then
        case "$caminho" in
            "$HOME") caminho="~" ;;
            "$HOME"/*) caminho="~${caminho#"$HOME"}" ;;
        esac
    fi
    printf '%s' "$caminho"
}
LOG_DIR="$PAINEL_DIR/.logs"
LOG_FILE="$LOG_DIR/manager.log"
PID_DIR="$PAINEL_DIR/.pids"

CONFIG_FILE="$PAINEL_DIR/.manager.conf"
BACKUPS_DIR="$PAINEL_DIR/backups"
TMP_ROOT="$PAINEL_DIR/.import_tmp"
SESSION_TMP_DIR="$TMP_ROOT/session_$$"
INSTANCE_LOCK="$PAINEL_DIR/.manager.lock"
LOG_MAX_BYTES=$((5 * 1024 * 1024))

# Cores (podem ser desativadas em Configurações — ver carregar_config).
# Usamos aspas $'...' (ANSI-C) para guardar o byte ESC real, e não o texto
# literal "\033" — isso permite calcular a largura visível do texto corretamente
# ao montar as caixas (ver strip_ansi / largura_visivel).
C_RESET=$'\033[0m'
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_BLUE=$'\033[1;34m'
C_CYAN=$'\033[1;36m'
C_MAGENTA=$'\033[1;35m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_WHITE=$'\033[1;37m'

# ============================================================================
# CICLO DE VIDA, BLOQUEIO E MANUTENÇÃO
# ============================================================================

rotacionar_log() {
    local arquivo="$1"
    [ -f "$arquivo" ] || return 0
    local tamanho
    tamanho=$(stat -c%s "$arquivo" 2>/dev/null || echo 0)
    [ "$tamanho" -lt "$LOG_MAX_BYTES" ] && return 0
    mv -f "$arquivo" "${arquivo}.1" 2>/dev/null || true
    : > "$arquivo"
}

limpar_temporarios_sessao() {
    [ "$LIMPAR_TEMPORARIOS_AUTO" = true ] || return 0
    [ -n "${SESSION_TMP_DIR:-}" ] && rm -rf "$SESSION_TMP_DIR" 2>/dev/null || true
}

limpar_temporarios_antigos() {
    [ "$LIMPAR_TEMPORARIOS_AUTO" = true ] || return 0
    [ -d "$TMP_ROOT" ] || return 0
    local pasta nome pid
    for pasta in "$TMP_ROOT"/session_*; do
        [ -d "$pasta" ] || continue
        [ "$pasta" = "$SESSION_TMP_DIR" ] && continue
        nome="$(basename "$pasta")"
        pid="${nome#session_}"
        if ! [[ "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
            rm -rf "$pasta" 2>/dev/null || true
        fi
    done
}

processo_inicio_ticks() {
    local pid="$1"
    awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true
}

salvar_bloqueio_atual() {
    printf '%s\n' "$$" > "$INSTANCE_LOCK/pid"
    printf '%s\n' "$(processo_inicio_ticks "$$")" > "$INSTANCE_LOCK/start_ticks"
    printf '%s\n' "${SELF_PATH:-manager.sh}" > "$INSTANCE_LOCK/script"
}

restaurar_bloqueio_atual() {
    mkdir -p "$PAINEL_DIR"
    rm -rf "$INSTANCE_LOCK" 2>/dev/null || true
    mkdir -p "$INSTANCE_LOCK"
    salvar_bloqueio_atual
}

liberar_bloqueio() {
    if [ -d "$INSTANCE_LOCK" ] && [ -f "$INSTANCE_LOCK/pid" ]; then
        [ "$(cat "$INSTANCE_LOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "$INSTANCE_LOCK"
    fi
}

finalizar_manager() {
    # Se uma tela foi interrompida durante a montagem, devolve stdout ao
    # terminal antes de encerrar. Evita sessões aparentemente "travadas".
    if declare -F ui_buffer_flush >/dev/null 2>&1; then
        ui_buffer_flush 2>/dev/null || true
    fi
    limpar_temporarios_sessao
    liberar_bloqueio
}

adquirir_bloqueio() {
    mkdir -p "$PAINEL_DIR"
    if mkdir "$INSTANCE_LOCK" 2>/dev/null; then
        salvar_bloqueio_atual
        return 0
    fi

    local antigo="" cmd_antigo="" inicio_antigo="" inicio_atual=""
    [ -f "$INSTANCE_LOCK/pid" ] && antigo=$(cat "$INSTANCE_LOCK/pid" 2>/dev/null)
    [ -f "$INSTANCE_LOCK/start_ticks" ] && inicio_antigo=$(cat "$INSTANCE_LOCK/start_ticks" 2>/dev/null)
    [ -n "$antigo" ] && inicio_atual="$(processo_inicio_ticks "$antigo")"

    if [ -n "$antigo" ] && kill -0 "$antigo" 2>/dev/null; then
        cmd_antigo=$(tr '\0' ' ' < "/proc/$antigo/cmdline" 2>/dev/null || true)

        # O token de início impede que um PID reutilizado seja confundido com
        # a sessão antiga. Locks de versões anteriores, sem token, continuam
        # compatíveis desde que o cmdline ainda identifique o Manager.
        if { [ -z "$inicio_antigo" ] || [ "$inicio_antigo" = "$inicio_atual" ]; } &&            [[ "$cmd_antigo" == *"manager.sh"* || "$cmd_antigo" == *"${SELF_PATH:-__manager_inexistente__}"* ]]; then
            local processo_exibido="manager.sh"
            [ -n "$cmd_antigo" ] && processo_exibido="$(basename "${SELF_PATH:-manager.sh}")"
            tela_caixa_unica \
                "⚠ Recuperação de sessão" \
                "Uma execução anterior ainda está ativa" \
                "[Enter] Encerrar e continuar  •  [0] Sair" \
                "Processo: $processo_exibido" \
                "PID: $antigo" \
                "Status: em execução" \
                "" \
                "Isso pode ocorrer após fechar o Termux" \
                "durante instalação ou atualização." \
                "" \
                "O Manager encerrará apenas a sessão antiga."
        ui_buffer_flush
        read -r RESPOSTA_MENU
            [ "$RESPOSTA_MENU" = 0 ] && return 1

            kill "$antigo" 2>/dev/null || true
            local espera
            for espera in 1 2 3; do
                kill -0 "$antigo" 2>/dev/null || break
                sleep 1
            done
            kill -0 "$antigo" 2>/dev/null && kill -9 "$antigo" 2>/dev/null || true
        fi
    fi

    rm -rf "$INSTANCE_LOCK" 2>/dev/null || true
    if ! mkdir "$INSTANCE_LOCK" 2>/dev/null; then
        error "Não foi possível criar o bloqueio do Manager."
        return 1
    fi
    salvar_bloqueio_atual
    return 0
}

feedback_curto() {
    local mensagem="$1" segundos="${2:-$PAUSA_ERRO_SEGUNDOS}"
    error "$mensagem"
    sleep "$segundos"
}

# Retorna o shell para um diretório existente quando o CWD deixou de existir.
# Isso pode acontecer se uma pasta aberta no terminal for removida/substituída.
garantir_cwd_existente() {
    if pwd -P >/dev/null 2>&1; then
        return 0
    fi

    if cd "${HOME:-/}" 2>/dev/null || cd / 2>/dev/null; then
        log "WARN" "Diretório atual não existia mais; CWD recuperado para $(pwd -P 2>/dev/null || printf '/')" 2>/dev/null || true
        return 0
    fi
    return 1
}

# Antes de remover ou substituir uma árvore, verifica se o terminal está dentro
# dela. Se estiver, muda para $HOME para impedir um CWD órfão após a operação.
garantir_cwd_fora_do_alvo() {
    local alvo="$1" cwd alvo_abs
    [ -n "$alvo" ] || return 0

    if ! cwd="$(pwd -P 2>/dev/null)"; then
        garantir_cwd_existente || return 1
        cwd="$(pwd -P 2>/dev/null || printf '/')"
    fi

    if command -v realpath >/dev/null 2>&1; then
        alvo_abs="$(realpath -m -- "$alvo" 2>/dev/null || printf '%s' "$alvo")"
    else
        alvo_abs="$alvo"
    fi

    case "$cwd/" in
        "$alvo_abs/"|"$alvo_abs/"*)
            if cd "${HOME:-/}" 2>/dev/null || cd / 2>/dev/null; then
                log "INFO" "CWD movido para local seguro antes de alterar: $alvo_abs" 2>/dev/null || true
                return 0
            fi
            return 1
            ;;
    esac
    return 0
}

# ============================================================================
# INICIALIZAÇÃO DO AMBIENTE
# ============================================================================

garantir_permissoes_manager() {
    [ -f "${SELF_PATH:-}" ] && chmod 700 "$SELF_PATH" 2>/dev/null || true
    [ -d "${MODULES_DIR:-}" ] && find "$MODULES_DIR" -type f -name '*.sh' -exec chmod 600 {} + 2>/dev/null || true
}

setup_dirs() {
    mkdir -p "$PAINEL_DIR" "$PROJETOS_DIR" "$LOG_DIR" "$PID_DIR" "$BACKUPS_DIR" "$TMP_ROOT" "$SESSION_TMP_DIR"
    [ -n "${DIAGNOSTICS_DIR:-}" ] && mkdir -p "$DIAGNOSTICS_DIR" "${MANAGER_INCIDENT_DIR:-$DIAGNOSTICS_DIR/manager}" 2>/dev/null || true
    [ -f "$LOG_FILE" ] || touch "$LOG_FILE"
    garantir_permissoes_manager
}

CANDIDATOS_DOWNLOADS=(
    "$HOME/storage/downloads"
    "$HOME/storage/shared/Download"
    "$HOME/storage/shared/Downloads"
    "/sdcard/Download"
    "/sdcard/Downloads"
    "/storage/emulated/0/Download"
    "/storage/emulated/0/Downloads"
)

# Tenta achar um diretório de Downloads real e com conteúdo.
# Se nenhum tiver conteúdo, usa o primeiro que existir (mesmo vazio).
resolver_downloads_dir() {
    local c
    for c in "${CANDIDATOS_DOWNLOADS[@]}"; do
        if [ -d "$c" ] && [ -n "$(find "$c" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
            DOWNLOADS_DIR="$c"
            return 0
        fi
    done
    for c in "${CANDIDATOS_DOWNLOADS[@]}"; do
        if [ -d "$c" ]; then
            DOWNLOADS_DIR="$c"
            return 0
        fi
    done
    return 1
}

check_storage_access() {
    # O armazenamento só precisa ser configurado uma vez. Nunca reconstrói
    # ~/storage silenciosamente durante importações ou atualizações.
    if [ ! -d "$HOME/storage" ]; then
        cabecalho_tela "🔐 Acesso ao armazenamento" "Configuração necessária somente uma vez"
        caixa_simples "Primeira configuração"             "O Manager precisa acessar a pasta Download."             "Execute termux-setup-storage e aceite a permissão."             "Depois, abra o Manager novamente."
        return 1
    fi

    if ! resolver_downloads_dir; then
        error "Não foi possível localizar nenhuma pasta de Downloads."
        info "Use Ambiente Termux > Configurar armazenamento."
        return 1
    fi

    log "INFO" "DOWNLOADS_DIR resolvido para: $DOWNLOADS_DIR"

    if [ -z "$(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
        warn "A pasta encontrada ($(caminho_home_relativo "$DOWNLOADS_DIR")) existe, mas está vazia ou sem permissão de leitura."
        info "Se você tem arquivos no Download do celular e eles não aparecem, rode: termux-setup-storage"
        info "e confirme a permissão de Armazenamento para o Termux nas configurações do Android."
    fi
    return 0
}

check_base_packages() {
    # Instala somente utilitários realmente necessários ao núcleo.
    # termux-api é opcional e não deve ser instalado automaticamente.
    local pkgs=(coreutils grep sed gawk findutils)
    local faltando=() p
    for p in "${pkgs[@]}"; do
        dpkg -s "$p" >/dev/null 2>&1 || faltando+=("$p")
    done
    [ ${#faltando[@]} -eq 0 ] && return 0

    cabecalho_tela "📦 Componentes básicos" "Sistema do Termux"
    caixa_simples "Pacotes necessários" \
        "${faltando[*]}" \
        "Serão instalados pelo pkg oficial." \
        "O Manager e o shell não serão alterados."
    instalar_lista_pacotes "Componentes básicos do Manager" "${faltando[@]}"
}

# ============================================================================
# UTILITÁRIOS GERAIS
# ============================================================================

comando_existe() {
    command -v "$1" >/dev/null 2>&1
}

instalar_pkg_termux() {
    # instalar_pkg_termux <pacote1> <pacote2> ...
    # Usa o instalador robusto do módulo Termux quando ele já estiver carregado.
    # Isso unifica instalações iniciadas por projetos/GitHub com o mesmo tratamento
    # de disponibilidade, lock, log e recuperação usado no menu de ferramentas.
    local pacotes=("$@")
    if declare -F instalar_lista_pacotes >/dev/null 2>&1; then
        TERMUX_INSTALL_NONINTERACTIVE=true instalar_lista_pacotes "Dependências automáticas" "${pacotes[@]}"
        return $?
    fi
    info "Instalando via pkg (Termux): ${pacotes[*]}"
    pkg install -y "${pacotes[@]}" >>"$LOG_FILE" 2>&1
}

garantir_comando() {
    # garantir_comando <comando> <pacote_termux>
    local cmd="$1" pkg_name="$2"
    if ! comando_existe "$cmd"; then
        warn "'$cmd' não encontrado. Instalando pacote '$pkg_name'..."
        instalar_pkg_termux "$pkg_name"
    fi
}

# Lista diretórios de forma numerada e retorna a escolha em $ESCOLHA
selecionar_da_lista() {
    # selecionar_da_lista "Título" item1 item2 ...
    local titulo="$1"; shift
    local itens=("$@")
    if [ ${#itens[@]} -eq 0 ]; then
        warn "Nenhum item disponível."
        ESCOLHA=""
        return 1
    fi
    echo -e "${C_BOLD}$titulo${C_RESET}"
    local i=1
    for item in "${itens[@]}"; do
        echo "  $i) $item"
        i=$((i+1))
    done
    echo "  0) Voltar"
    read -rp "Escolha uma opção: " op
    if [[ "$op" == "0" ]]; then
        ESCOLHA=""
        return 1
    fi
    if ! [[ "$op" =~ ^[0-9]+$ ]] || [ "$op" -lt 1 ] || [ "$op" -gt ${#itens[@]} ]; then
        warn "Opção inválida."
        ESCOLHA=""
        return 1
    fi
    ESCOLHA="${itens[$((op-1))]}"
    return 0
}

