# Módulo: ui.sh
# Manager.sh — módulo

# ============================================================================
# HELPERS DE CAIXA / DESENHO (visual moderno, compatível com Termux)
# ============================================================================

# Repete um caractere N vezes. Evita `tr` de propósito: caracteres de caixa
# (─ █ ░ etc.) são multibyte em UTF-8, e `tr` corrompe multibyte porque opera
# byte a byte.
repetir_char() {
    local ch="$1" n="$2"
    [ "$n" -le 0 ] && return
    local out="" i
    for (( i=0; i<n; i++ )); do
        out+="$ch"
    done
    printf '%s' "$out"
}

# Remove códigos de cor ANSI (ESC[...m) de uma string, para poder medir
# corretamente quantos caracteres realmente aparecem na tela.
strip_ansi() {
    shopt -s extglob
    local s="$1"
    local esc=$'\033'
    s="${s//${esc}\[*([0-9;])m/}"
    shopt -u extglob
    printf '%s' "$s"
}

# Calcula o "tamanho visível" de uma string: remove códigos de cor e trata
# emojis/ícones comuns como largura 2 (o resto como largura 1) — suficiente
# para alinhar caixas no Termux sem depender de libs externas.
largura_visivel() {
    local s
    s="$(strip_ansi "$1")"
    # Seletores de variação (caracteres invisíveis, às vezes usados para
    # forçar um símbolo a aparecer colorido) não ocupam nenhuma coluna na
    # tela, mas ${#s} os contava como 1 caractere — isso fazia essas linhas
    # parecerem mais largas do que realmente são e desalinhava a borda
    # direita da caixa de forma inconsistente entre ícones diferentes.
    # O projeto não usa mais ícones que dependam desse seletor (trocados por
    # emojis de largura previsível), mas a limpeza fica como proteção extra.
    s="${s//$'\uFE0F'/}"
    s="${s//$'\uFE0E'/}"
    local len=${#s}
    local extras=0
    # Ícones de largura dupla usados no projeto — tratados como 2 colunas
    # para o alinhamento das caixas dar certo no Termux.
    local ch resto
    # Lista tokenizada: evita fatiar uma string UTF-8 por índice, algo que
    # varia conforme o locale disponível no Android/Termux.
    for ch in 📦 📁 ⚡ ✅ ❌ ⚠ 🔧 📂 🧩 🗑 📋 🔍 🔎 💾 🚀 🌐 🖥 📊 🧰 ℹ ⏳ ⏸ ⏹ ⏭ ⏱ ↩ ⌨ ▶ ○ ☕ ♻ ✔ ✘ ✨ ❓ ➜ ⬆ ⬇ 🔼 🎨 🏷 🐍 🐘 👋 📄 📍 📖 📚 📝 📥 📭 🔄 🔐 🔔 🕒 🕘 🗂 🗄 🚦 🚫 🛑 🛟 🟢 🧭 🧹 🧽 🩺 📘 🧪; do
        resto="$s"
        while [[ "$resto" == *"$ch"* ]]; do
            resto="${resto#*"$ch"}"
            extras=$((extras + 1))
        done
    done
    echo $((len + extras))
}

# Corta um texto para caber em uma largura visível máxima, adicionando "…"
# quando necessário. Remove um caractere por vez (em vez de cortar direto
# pela contagem de caracteres) porque, perto do limite, um emoji de largura
# dupla que sobre no pedaço cortado pode deixar o resultado 1 coluna mais
# largo do que o previsto — foi isso que causava uma borda "│" solta
# vazando para a linha seguinte em textos truncados com ícones.
truncar_visivel() {
    local texto="$1" limite="$2" vis
    texto="$(strip_ansi "$texto")"
    vis=$(largura_visivel "$texto")
    if [ "$vis" -le "$limite" ]; then
        printf '%s' "$texto"
        return
    fi
    while [ -n "$texto" ]; do
        texto="${texto:0:$((${#texto} - 1))}"
        vis=$(largura_visivel "$texto")
        [ $((vis + 1)) -le "$limite" ] && break
    done
    printf '%s…' "$texto"
}

largura_caixa_atual() {
    if [ "${UI_LIVE_BOX_ACTIVE:-false}" = true ] && [ "${UI_LIVE_BOX_WIDTH:-0}" -gt 0 ] 2>/dev/null; then
        printf '%s' "$UI_LIVE_BOX_WIDTH"
    else
        printf '%s' "$LARGURA_CAIXA"
    fi
}

caixa_linha_topo() {
    local largura; largura="$(largura_caixa_atual)"
    echo -ne "${C_CYAN}╭$(repetir_char '─' $((largura - 2)))╮${C_RESET}\n"
}
caixa_linha_sep() {
    local largura; largura="$(largura_caixa_atual)"
    echo -ne "${C_CYAN}├$(repetir_char '─' $((largura - 2)))┤${C_RESET}\n"
}
caixa_linha_baixo() {
    local largura; largura="$(largura_caixa_atual)"
    echo -ne "${C_CYAN}╰$(repetir_char '─' $((largura - 2)))╯${C_RESET}\n"
}
# caixa_linha_texto "texto" [centralizar]
caixa_linha_texto() {
    local texto="$1"
    local centralizar="${2:-false}"
    local largura; largura="$(largura_caixa_atual)"
    local largura_util=$((largura - 4))
    local vis
    vis=$(largura_visivel "$texto")
    # Nunca permite que uma linha invada a borda em telas estreitas.
    # Linhas maiores são reduzidas com reticências; cores são removidas apenas
    # nessa situação para evitar cortar uma sequência ANSI no meio.
    if [ "$vis" -gt "$largura_util" ]; then
        texto="$(truncar_visivel "$texto" "$largura_util")"
        vis=$(largura_visivel "$texto")
    fi
    local espacos=$((largura_util - vis))
    [ "$espacos" -lt 0 ] && espacos=0
    if [ "$centralizar" == true ]; then
        local esq=$((espacos / 2))
        local dir=$((espacos - esq))
        echo -ne "${C_CYAN}│${C_RESET} $(repetir_char ' ' "$esq")${texto}$(repetir_char ' ' "$dir") ${C_CYAN}│${C_RESET}\n"
    else
        echo -ne "${C_CYAN}│${C_RESET} ${texto}$(repetir_char ' ' "$espacos") ${C_CYAN}│${C_RESET}\n"
    fi
}

# caixa_simples "titulo" "linha1" "linha2" ...
caixa_simples() {
    local titulo="$1"; shift
    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}${titulo}${C_RESET}" true
    caixa_linha_sep
    local l
    for l in "$@"; do
        caixa_linha_texto "$l"
    done
    caixa_linha_baixo
}

separador() {
    echo -e "${C_DIM}$(repetir_char '─' "$LARGURA_CAIXA")${C_RESET}"
}

# ============================================================================
# FUNÇÕES DE LOG / UI
# ============================================================================

log() {
    # log <nivel> <mensagem>
    local nivel="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    rotacionar_log "$LOG_FILE"
    echo "[$ts] [$nivel] $msg" >> "$LOG_FILE"
}

# Painel vivo: permite que operações longas continuem mostrando progresso,
# mas mantém todas as mensagens dentro da mesma moldura visual.
UI_LIVE_BOX_ACTIVE=false
UI_LIVE_BOX_SECTION_COUNT=0
UI_LIVE_BOX_WIDTH=0

ui_live_box_begin() {
    local titulo="$1" subtitulo="${2:-}"
    ui_buffer_flush
    [ "$UI_LIVE_BOX_ACTIVE" = true ] && ui_live_box_end
    echo
    # Recalcula a largura imediatamente antes de abrir um painel vivo, para
    # acompanhar rotação/redimensionamento do terminal. Em seguida congela a
    # largura durante a operação: mensagens curtas ou longas nunca movem a
    # borda direita; apenas o conteúdo recebe padding/truncamento.
    detectar_terminal
    UI_LIVE_BOX_WIDTH="$LARGURA_CAIXA"
    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}${C_WHITE}${titulo}${C_RESET}" true
    [ -n "$subtitulo" ] && caixa_linha_texto "${C_DIM}${subtitulo}${C_RESET}" true
    caixa_linha_sep
    UI_LIVE_BOX_ACTIVE=true
    UI_LIVE_BOX_SECTION_COUNT=0
}

ui_live_box_section() {
    local titulo="$1"
    [ "$UI_LIVE_BOX_ACTIVE" = true ] || return 0
    [ "$UI_LIVE_BOX_SECTION_COUNT" -gt 0 ] && caixa_linha_sep
    caixa_linha_texto "${C_BOLD}${titulo}${C_RESET}" true
    caixa_linha_sep
    UI_LIVE_BOX_SECTION_COUNT=$((UI_LIVE_BOX_SECTION_COUNT + 1))
}

ui_live_box_end() {
    [ "$UI_LIVE_BOX_ACTIVE" = true ] || return 0
    caixa_linha_baixo
    echo
    UI_LIVE_BOX_ACTIVE=false
    UI_LIVE_BOX_SECTION_COUNT=0
    UI_LIVE_BOX_WIDTH=0
}

ui_live_box_message() {
    local cor="$1" icone="$2"; shift 2
    caixa_linha_texto "${cor}${icone}${C_RESET} $*"
}

info() {
    ui_buffer_flush
    if [ "$UI_LIVE_BOX_ACTIVE" = true ]; then ui_live_box_message "$C_CYAN" "➜" "$*"; else echo -e "${C_CYAN}➜${C_RESET} $*"; fi
    log "INFO" "$*"
}
ok() {
    ui_buffer_flush
    if [ "$UI_LIVE_BOX_ACTIVE" = true ]; then ui_live_box_message "$C_GREEN" "✔" "$*"; else echo -e "${C_GREEN}✔${C_RESET} $*"; fi
    log "OK" "$*"
}
warn() {
    ui_buffer_flush
    if [ "$UI_LIVE_BOX_ACTIVE" = true ]; then ui_live_box_message "$C_YELLOW" "⚠" "$*"; else echo -e "${C_YELLOW}⚠${C_RESET} $*"; fi
    log "WARN" "$*"
}
error() {
    ui_buffer_flush
    if [ "$UI_LIVE_BOX_ACTIVE" = true ]; then ui_live_box_message "$C_RED" "✘" "$*"; else echo -e "${C_RED}✘${C_RESET} $*"; fi
    log "ERROR" "$*"
}

title() {
    [ "$UI_LIVE_BOX_ACTIVE" = true ] && ui_live_box_end
    echo
    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}${C_WHITE}$*${C_RESET}" true
    caixa_linha_baixo
    echo
}

ui_preparar_prompt() {
    ui_buffer_flush
    printf '\033[?25h\r\033[2K'
}

pause() {
    local _
    [ "$UI_LIVE_BOX_ACTIVE" = true ] && ui_live_box_end
    ui_preparar_prompt
    printf '%s' "Pressione ENTER para continuar..."
    IFS= read -r _
    printf '\r\033[2K'
    tela_limpar
}


# Sistema unificado de interface. Todos os módulos novos usam estas funções,
# mantendo os helpers antigos como compatibilidade para recursos existentes.
# Buffer global de renderização. Telas construídas por vários helpers são
# acumuladas temporariamente e enviadas ao terminal em uma única escrita.
# Isso elimina o efeito de linhas "caindo" nos menus do Termux.
UI_BUFFER_ACTIVE=false
UI_BUFFER_FILE=""
UI_BUFFER_FD=""

ui_buffer_begin() {
    [ "$UI_BUFFER_ACTIVE" = true ] && ui_buffer_flush
    local dir="${TMP_DIR:-${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}}"
    mkdir -p "$dir" 2>/dev/null || true
    UI_BUFFER_FILE="$(mktemp "$dir/manager-ui.XXXXXX" 2>/dev/null || printf '%s/manager-ui-%s.tmp' "$dir" "$$")"
    : > "$UI_BUFFER_FILE"
    exec {UI_BUFFER_FD}>&1
    exec > "$UI_BUFFER_FILE"
    UI_BUFFER_ACTIVE=true
}

ui_buffer_flush() {
    [ "$UI_BUFFER_ACTIVE" = true ] || return 0
    exec >&"$UI_BUFFER_FD"
    exec {UI_BUFFER_FD}>&-
    UI_BUFFER_ACTIVE=false
    if [ -f "$UI_BUFFER_FILE" ]; then
        cat "$UI_BUFFER_FILE"
        rm -f "$UI_BUFFER_FILE"
    fi
    UI_BUFFER_FILE=""
    UI_BUFFER_FD=""
}

restaurar_terminal_manager() {
    # Volta o terminal para um estado previsível após barras de progresso,
    # prompts do apt/dpkg e uso da tela alternativa.
    printf '\033[0m\033[?25h\033[r\033[?7h'
    stty sane 2>/dev/null || true
    # Limpa a tela visível e o histórico de rolagem da tela atual. Isso evita
    # que restos do wizard sejam misturados ao menu principal no Termux.
    printf '\033[H\033[2J\033[3J'
    sleep 0.05
    detectar_terminal
}

tela_limpar() {
    restaurar_terminal_manager
}

rodape_atalhos() {
    local texto="${1:-[0] Voltar  •  [Enter] Confirmar}"
    echo
    caixa_linha_topo
    caixa_linha_texto "${C_DIM}${texto}${C_RESET}" true
    caixa_linha_baixo
}

# tela_caixa_unica "Título" "Subtítulo" "Rodapé" "linha1" ...
# Renderiza uma tela inteira em uma única caixa: cabeçalho, conteúdo e atalhos.
# Use em avisos, confirmações e fluxos curtos para evitar caixas empilhadas.
tela_caixa_unica() {
    local titulo="$1" subtitulo="${2:-}" rodape="${3:-}"; shift 3
    ui_buffer_begin
    tela_limpar
    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}${C_WHITE}${titulo}${C_RESET}" true
    [ -n "$subtitulo" ] && caixa_linha_texto "${C_DIM}${subtitulo}${C_RESET}" true
    caixa_linha_sep
    local linha
    for linha in "$@"; do
        caixa_linha_texto "$linha"
    done
    if [ -n "$rodape" ]; then
        caixa_linha_sep
        caixa_linha_texto "${C_DIM}${rodape}${C_RESET}" true
    fi
    caixa_linha_baixo
}

cabecalho_tela() {
    local titulo="$1" subtitulo="${2:-}"
    ui_buffer_begin
    tela_limpar
    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}${C_WHITE}${titulo}${C_RESET}" true
    [ -n "$subtitulo" ] && caixa_linha_texto "${C_DIM}${subtitulo}${C_RESET}" true
    caixa_linha_baixo
    echo
}

resumir_descricao_menu() {
    # Mantém descrições de menu curtas e encerra em palavra completa.
    # Isso evita linhas cortadas de forma estranha em telas estreitas.
    local texto="${1:-}" largura limite cortado base candidato
    [ -n "$texto" ] || return 0
    largura="$(largura_caixa_atual)"
    limite=$((largura - 8))
    [ "$limite" -gt 48 ] && limite=48
    [ "$limite" -lt 18 ] && limite=18
    texto="$(strip_ansi "$texto")"
    if [ "$(largura_visivel "$texto")" -le "$limite" ]; then
        printf '%s' "$texto"
        return 0
    fi
    cortado="$(truncar_visivel "$texto" "$limite")"
    base="${cortado%…}"
    if [[ "$base" == *" "* ]]; then
        candidato="${base% *}"
        if [ "$(largura_visivel "$candidato")" -ge 12 ]; then
            base="$candidato"
        fi
    fi
    printf '%s…' "${base% }"
}

menu_opcao() {
    # menu_opcao <numero> <icone> <titulo> <descricao>
    local numero="$1" icone="$2" titulo="$3" descricao="${4:-}"
    [ "$ICONES_ATIVADOS" = true ] || icone=""
    caixa_linha_texto "${C_BOLD}${numero}) ${icone:+$icone }${titulo}${C_RESET}"
    if [ "$DESCRICOES_ATIVADAS" = true ] && [ -n "$descricao" ]; then
        descricao="$(resumir_descricao_menu "$descricao")"
        caixa_linha_texto "   ${C_DIM}${descricao}${C_RESET}"
    fi
}

menu_unificado() {
    # menu_unificado "Título" "Subtítulo" "rodapé" "1|📦|Título|Descrição" ...
    # Monta toda a interface em memória e só então imprime. Isso evita o
    # efeito visual de opções "caindo" linha por linha em terminais móveis.
    local titulo="$1" subtitulo="$2" rodape="$3"; shift 3
    ui_buffer_flush
    local tela item numero icone nome descricao
    tela="$(
        caixa_linha_topo
        caixa_linha_texto "${C_BOLD}${C_WHITE}${titulo}${C_RESET}" true
        [ -n "$subtitulo" ] && caixa_linha_texto "${C_DIM}${subtitulo}${C_RESET}" true
        caixa_linha_baixo
        echo
        caixa_linha_topo
        for item in "$@"; do
            IFS='|' read -r numero icone nome descricao <<< "$item"
            menu_opcao "$numero" "$icone" "$nome" "$descricao"
        done
        caixa_linha_baixo
        echo
        caixa_linha_topo
        caixa_linha_texto "${C_DIM}${rodape}${C_RESET}" true
        caixa_linha_baixo
    )"
    tela_limpar
    printf '%s
' "$tela"
}

ler_opcao() {
    local prompt="${1:-Escolha uma opção: }"
    ui_preparar_prompt
    printf '%s' "$prompt"
    IFS= read -r RESPOSTA_MENU
    printf '\r\033[2K'
}

confirmar_acao() {
    local pergunta="$1" padrao="${2:-n}" resposta
    ui_preparar_prompt
    if [ "$padrao" = "s" ]; then
        printf '%s' "$pergunta (S/n): "
        IFS= read -r resposta
        [[ -z "$resposta" || "$resposta" =~ ^[sS]$ ]]
    else
        printf '%s' "$pergunta (s/N): "
        IFS= read -r resposta
        [[ "$resposta" =~ ^[sS]$ ]]
    fi
}

wizard_cabecalho() {
    local etapa="$1" total="$2" titulo="$3" descricao="${4:-}"
    cabecalho_tela "🧭 ${titulo}" "Etapa ${etapa} de ${total}"
    [ -n "$descricao" ] && caixa_simples "📘  Orientação" "$descricao"
    echo
}

icone_tipo_item() {
    local caminho="$1"
    if [ -d "$caminho" ]; then ICON_ITEM="📁"; TIPO_ITEM="Pasta"
    elif [[ "${caminho,,}" == *.zip ]]; then ICON_ITEM="📦"; TIPO_ITEM="Arquivo ZIP"
    elif [ -f "$caminho" ]; then ICON_ITEM="📄"; TIPO_ITEM="Arquivo"
    else ICON_ITEM="❓"; TIPO_ITEM="Item desconhecido"
    fi
}

valor_legivel_bool() { [ "$1" = true ] && echo "Sim" || echo "Não"; }

caminho_curto() {
    local caminho="$1"
    if declare -F caminho_home_relativo >/dev/null 2>&1; then
        caminho="$(caminho_home_relativo "$caminho")"
    else
        caminho="${caminho/#$HOME/~}"
    fi
    truncar_caminho "$caminho" $((LARGURA_CAIXA - 6))
}

