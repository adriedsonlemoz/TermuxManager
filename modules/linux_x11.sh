# Módulo: linux_x11.sh
# Termux:X11 e ambientes gráficos das distribuições Linux.
# Extraído de linux.sh para reduzir acoplamento e facilitar manutenção.

TERMUX_X11_APK_URL="https://github.com/termux/termux-x11/releases/download/nightly/termux-x11-universal-debug.apk"
TERMUX_X11_APK_NAME="termux-x11-universal-debug.apk"

linux_x11_android_compativel() {
    local versao major
    versao="$(linux_android_versao)"
    major="${versao%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || return 0
    [ "$major" -ge 8 ]
}

linux_x11_apk_instalado() {
    command -v pm >/dev/null 2>&1 && pm path com.termux.x11 2>/dev/null | grep -q '^package:'
}

linux_x11_companion_instalado() {
    command -v termux-x11 >/dev/null 2>&1
}

linux_instalar_x11_companion() {
    cabecalho_tela "🖥️ Termux:X11" "Instalar componentes no Termux"
    if ! linux_x11_android_compativel; then
        caixa_simples "⚠ Android incompatível" \
            "O Termux:X11 requer Android 8 ou superior." \
            "Android detectado: $(linux_android_versao)"
        pause
        return 1
    fi
    if declare -F pacote_disponivel_termux >/dev/null 2>&1 && ! pacote_disponivel_termux x11-repo; then
        caixa_simples "⚠ x11-repo indisponível" \
            "O repositório gráfico não está disponível nos repositórios atuais do Termux." \
            "O Manager não tentará forçar uma instalação incompatível."
        pause
        return 1
    fi
    caixa_simples "Componentes" \
        "1. Repositório gráfico: x11-repo" \
        "2. Pacote companion: termux-x11-nightly" \
        "O aplicativo Android é instalado em uma etapa separada."
    confirmar_acao "Instalar componentes do Termux:X11?" "s" || return 0

    executar_pkg_monitorado "Preparando Termux:X11" 10 45 \
        "Habilitando repositório gráfico..." "Instalando x11-repo." -- install -y x11-repo || {
            mostrar_erro_pkg "Não foi possível instalar x11-repo."
            pause
            return 1
        }
    executar_pkg_monitorado "Preparando Termux:X11" 50 95 \
        "Instalando o companion do X11..." "Pacote termux-x11-nightly." -- install -y termux-x11-nightly || {
            mostrar_erro_pkg "Não foi possível instalar termux-x11-nightly."
            pause
            return 1
        }
    linux_log "Termux:X11 companion instalado"
    ok "Componentes do Termux:X11 instalados."
    pause
}

linux_baixar_x11_apk() {
    resolver_downloads_dir >/dev/null 2>&1 || true
    cabecalho_tela "📲 Aplicativo Termux:X11" "Baixar APK oficial nightly"
    caixa_simples "Origem" \
        "Projeto oficial: termux/termux-x11" \
        "Arquivo: $TERMUX_X11_APK_NAME" \
        "Destino: $(caminho_curto "$DOWNLOADS_DIR/$TERMUX_X11_APK_NAME")" \
        "O Android pedirá sua confirmação para instalar o APK."
    confirmar_acao "Baixar o APK oficial agora?" "s" || return 0

    if ! command -v curl >/dev/null 2>&1; then
        warn "curl não está instalado."
        confirmar_acao "Instalar curl agora?" "s" || return 1
        executar_pkg_monitorado "Instalando curl" 20 95 "Preparando download..." "Dependência necessária." -- install -y curl || return 1
    fi

    mkdir -p "$DOWNLOADS_DIR"
    local destino="$DOWNLOADS_DIR/$TERMUX_X11_APK_NAME" tmp="${DOWNLOADS_DIR}/.${TERMUX_X11_APK_NAME}.part"
    rm -f "$tmp"
    if curl -fL --retry 3 --connect-timeout 20 --max-time 600 \
        -o "$tmp" "$TERMUX_X11_APK_URL" 2>&1 | tee -a "$LINUX_LOG"; then
        mv -f "$tmp" "$destino"
        linux_log "APK Termux:X11 baixado: $destino"
        ok "APK salvo em $(caminho_curto "$destino")."
        caixa_simples "Instalação no Android" \
            "O Manager pode abrir o instalador, mas não confirma a tela do Android por você." \
            "Se o Android bloquear, permita 'Instalar apps desconhecidos' para o Termux."
        if command -v termux-open >/dev/null 2>&1; then
            confirmar_acao "Abrir o instalador do Android agora?" "s" && \
                termux-open --view --content-type application/vnd.android.package-archive "$destino" >/dev/null 2>&1 || true
        else
            warn "Abra o APK manualmente pelo gerenciador de arquivos em Downloads."
        fi
    else
        rm -f "$tmp"
        error "Falha ao baixar o APK do Termux:X11."
        printf 'Endereço usado: %s\n' "$TERMUX_X11_APK_URL"
    fi
    pause
}

linux_status_x11() {
    detectar_variante_termux 2>/dev/null || true
    cabecalho_tela "🖥️ Status Termux:X11" "Componentes necessários"
    caixa_simples "Termux:X11" \
        "Companion no Termux: $(linux_x11_companion_instalado && echo instalado || echo ausente)" \
        "Aplicativo Android: $(linux_x11_apk_instalado && echo instalado || echo não detectado)" \
        "Origem do Termux: $(termux_origem_resumida)" \
        "Android: $(linux_android_versao)"
    caixa_simples "Observação" \
        "O APK padrão funciona independentemente de sharedUid." \
        "O modo sharedUid só deve ser usado com builds compatíveis e assinaturas correspondentes." \
        "O Manager usa o APK padrão por segurança e compatibilidade."
    pause
}

linux_detectar_gerenciador_distro() {
    local alias="${1:-}"
    [ -n "$alias" ] || return 1
    mkdir -p "$(dirname "$LINUX_LOG")" 2>/dev/null || true
    proot-distro login "$alias" -- /bin/sh -lc '
if command -v apt-get >/dev/null 2>&1; then
  printf "apt\n"
elif command -v pacman >/dev/null 2>&1; then
  printf "pacman\n"
elif command -v apk >/dev/null 2>&1; then
  printf "apk\n"
elif command -v dnf >/dev/null 2>&1; then
  printf "dnf\n"
elif command -v zypper >/dev/null 2>&1; then
  printf "zypper\n"
else
  printf "desconhecido\n"
fi' 2>>"$LINUX_LOG" | tail -n 1
}

linux_descrever_gerenciador_distro() {
    case "${1:-desconhecido}" in
        apt) printf 'APT (Debian/Ubuntu)' ;;
        pacman) printf 'Pacman (Arch)' ;;
        apk) printf 'APK (Alpine)' ;;
        dnf) printf 'DNF (Fedora/Rocky)' ;;
        zypper) printf 'Zypper (openSUSE)' ;;
        *) printf 'Não reconhecido' ;;
    esac
}

linux_desktop_nome() {
    case "${1:-}" in
        xfce) printf 'XFCE' ;;
        lxqt) printf 'LXQt' ;;
        lxde) printf 'LXDE' ;;
        mate) printf 'MATE' ;;
        openbox) printf 'Openbox' ;;
        i3) printf 'i3' ;;
        kde) printf 'KDE Plasma' ;;
        gnome) printf 'GNOME' ;;
        *) printf '%s' "${1:-desconhecido}" ;;
    esac
}

linux_desktop_launcher() {
    case "${1:-}" in
        xfce) printf 'xfce4-session' ;;
        lxqt) printf 'startlxqt' ;;
        lxde) printf 'startlxde' ;;
        mate) printf 'mate-session' ;;
        openbox) printf 'openbox-session' ;;
        i3) printf 'i3' ;;
        kde) printf 'startplasma-x11' ;;
        gnome) printf 'gnome-session' ;;
        *) return 1 ;;
    esac
}

linux_desktop_peso() {
    case "${1:-}" in
        openbox|i3) printf 'muito leve' ;;
        lxde) printf 'muito leve' ;;
        xfce|lxqt) printf 'leve' ;;
        mate) printf 'médio' ;;
        kde) printf 'pesado' ;;
        gnome) printf 'muito pesado' ;;
        *) printf 'desconhecido' ;;
    esac
}

linux_desktop_descricao() {
    case "${1:-}" in
        xfce) printf 'Leve, completo e com ótima compatibilidade' ;;
        lxqt) printf 'Leve e com visual moderno' ;;
        lxde) printf 'Muito leve para aparelhos modestos' ;;
        mate) printf 'Desktop tradicional com consumo médio' ;;
        openbox) printf 'Janela mínima e extremamente leve' ;;
        i3) printf 'Tiling muito leve, focado em teclado' ;;
        kde) printf 'Visual avançado, exige mais RAM e CPU' ;;
        gnome) printf 'Completo, pesado e mais limitado em PRoot' ;;
        *) printf 'Ambiente gráfico' ;;
    esac
}

linux_desktop_recomendado_perfil() {
    local desktop="${1:-}" perfil="${2:-$LINUX_PROFILE}"
    case "$perfil:$desktop" in
        BÁSICO:lxde|BÁSICO:openbox|BÁSICO:i3) return 0 ;;
        INTERMEDIÁRIO:xfce|INTERMEDIÁRIO:lxqt) return 0 ;;
        DESKTOP:xfce|DESKTOP:lxqt|DESKTOP:mate) return 0 ;;
        *) return 1 ;;
    esac
}

linux_desktop_aviso_perfil() {
    local desktop="${1:-}" peso
    peso="$(linux_desktop_peso "$desktop")"
    if [ "$LINUX_PROFILE" = "BÁSICO" ] && [[ "$desktop" =~ ^(mate|kde|gnome)$ ]]; then
        printf '⚠ Muito pesado para o perfil BÁSICO; travamentos e encerramentos são prováveis.'
    elif [ "$LINUX_PROFILE" = "INTERMEDIÁRIO" ] && [[ "$desktop" =~ ^(kde|gnome)$ ]]; then
        printf '⚠ Pode consumir muita RAM/CPU neste aparelho; use apenas para testar.'
    elif [ "$desktop" = "gnome" ]; then
        printf '⚠ GNOME pode ter limitações extras em PRoot por depender de serviços do sistema.'
    elif [ "$desktop" = "kde" ]; then
        printf 'ℹ KDE Plasma é mais pesado que XFCE/LXQt e pode demorar mais para iniciar.'
    else
        printf 'Consumo estimado: %s.' "$peso"
    fi
}

linux_escolher_desktop() {
    local titulo="${1:-🖥️ Escolher ambiente gráfico}" subtitulo="${2:-Selecione o desktop}" rec=""
    linux_avaliar_aparelho
    local -a itens=()
    local id nome desc peso marcador
    for id in xfce lxqt lxde mate openbox i3 kde gnome; do
        nome="$(linux_desktop_nome "$id")"
        desc="$(linux_desktop_descricao "$id")"
        peso="$(linux_desktop_peso "$id")"
        marcador=""
        linux_desktop_recomendado_perfil "$id" && marcador=" • recomendado"
        itens+=("$(( ${#itens[@]} + 1 ))|🖥️|$nome|$desc • $peso$marcador")
    done
    menu_unificado "$titulo" "$subtitulo • perfil ${LINUX_PROFILE}" \
        "[0] Voltar  •  [1–8] Selecionar" "${itens[@]}"
    ler_opcao
    case "$RESPOSTA_MENU" in
        1) LINUX_DESKTOP_ID="xfce" ;;
        2) LINUX_DESKTOP_ID="lxqt" ;;
        3) LINUX_DESKTOP_ID="lxde" ;;
        4) LINUX_DESKTOP_ID="mate" ;;
        5) LINUX_DESKTOP_ID="openbox" ;;
        6) LINUX_DESKTOP_ID="i3" ;;
        7) LINUX_DESKTOP_ID="kde" ;;
        8) LINUX_DESKTOP_ID="gnome" ;;
        0) return 1 ;;
        *) warn "Opção inválida."; sleep 1; return 2 ;;
    esac
    LINUX_DESKTOP_NOME="$(linux_desktop_nome "$LINUX_DESKTOP_ID")"
    LINUX_DESKTOP_LAUNCHER="$(linux_desktop_launcher "$LINUX_DESKTOP_ID")"
    return 0
}

linux_desktop_instalado() {
    local alias="${1:-}" desktop="${2:-}" launcher
    [ -n "$alias" ] && [ -n "$desktop" ] || return 1
    launcher="$(linux_desktop_launcher "$desktop" 2>/dev/null)" || return 1
    mkdir -p "$(dirname "$LINUX_LOG")" 2>/dev/null || true
    proot-distro login "$alias" -- /bin/sh -lc "command -v '$launcher' >/dev/null 2>&1" \
        >>"$LINUX_LOG" 2>&1
}

linux_xfce_instalado() {
    linux_desktop_instalado "${1:-}" xfce
}

linux_desktops_instalados() {
    local alias="${1:-}" id
    [ -n "$alias" ] || return 1
    for id in xfce lxqt lxde mate openbox i3 kde gnome; do
        linux_desktop_instalado "$alias" "$id" && printf '%s\n' "$id"
    done
}

linux_desktops_instalados_resumo() {
    local alias="${1:-}" id nomes=""
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        nomes+="${nomes:+, }$(linux_desktop_nome "$id")"
    done < <(linux_desktops_instalados "$alias" 2>/dev/null || true)
    [ -n "$nomes" ] && printf '%s' "$nomes" || printf 'nenhum'
}

linux_desktop_guest_script() {
    local desktop="${1:-}" launcher
    launcher="$(linux_desktop_launcher "$desktop" 2>/dev/null)" || return 1
    cat <<EOF
set -e
DESKTOP_ID='$desktop'
LAUNCHER='$launcher'
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  case \"\$DESKTOP_ID\" in
    xfce) apt-get install -y xfce4 xfce4-terminal dbus-x11 ;;
    lxqt) apt-get install -y lxqt qterminal dbus-x11 || apt-get install -y lxqt-core qterminal dbus-x11 ;;
    lxde) apt-get install -y lxde-core lxterminal dbus-x11 || apt-get install -y lxde lxterminal dbus-x11 ;;
    mate) apt-get install -y mate-desktop-environment-core mate-terminal dbus-x11 || apt-get install -y mate-desktop-environment mate-terminal dbus-x11 ;;
    openbox) apt-get install -y openbox tint2 lxterminal dbus-x11 ;;
    i3) apt-get install -y i3-wm i3status dmenu xterm dbus-x11 || apt-get install -y i3 xterm dbus-x11 ;;
    kde) apt-get install -y plasma-desktop konsole dbus-x11 || apt-get install -y kde-plasma-desktop konsole dbus-x11 ;;
    gnome) apt-get install -y gnome-session gnome-shell gnome-terminal dbus-x11 ;;
  esac
elif command -v pacman >/dev/null 2>&1; then
  pacman -Sy --noconfirm
  case \"\$DESKTOP_ID\" in
    xfce) pacman -S --needed --noconfirm xfce4 xfce4-goodies dbus ;;
    lxqt) pacman -S --needed --noconfirm lxqt qterminal dbus ;;
    lxde) pacman -S --needed --noconfirm lxde lxterminal dbus ;;
    mate) pacman -S --needed --noconfirm mate mate-extra dbus ;;
    openbox) pacman -S --needed --noconfirm openbox tint2 xterm dbus ;;
    i3) pacman -S --needed --noconfirm i3-wm i3status dmenu xterm dbus ;;
    kde) pacman -S --needed --noconfirm plasma-desktop konsole dbus ;;
    gnome) pacman -S --needed --noconfirm gnome gnome-terminal dbus ;;
  esac
elif command -v apk >/dev/null 2>&1; then
  apk update
  case \"\$DESKTOP_ID\" in
    xfce) apk add xfce4 xfce4-terminal dbus ;;
    lxqt) apk add lxqt-desktop qterminal dbus || apk add lxqt qterminal dbus ;;
    lxde) apk add lxde lxterminal dbus ;;
    mate) apk add mate-desktop-environment mate-terminal dbus || apk add mate-desktop mate-session-manager mate-panel mate-terminal dbus ;;
    openbox) apk add openbox tint2 xterm dbus ;;
    i3) apk add i3wm i3status dmenu xterm dbus ;;
    kde) apk add plasma-desktop konsole dbus ;;
    gnome) apk add gnome-shell gnome-session gnome-terminal dbus ;;
  esac
elif command -v dnf >/dev/null 2>&1; then
  case \"\$DESKTOP_ID\" in
    xfce) dnf -y install @xfce-desktop-environment dbus-x11 || dnf -y group install \"Xfce Desktop\" || dnf -y install xfce4-session xfce4-panel xfce4-settings xfce4-terminal dbus-x11 ;;
    lxqt) dnf -y group install \"LXQt Desktop\" || dnf -y install lxqt-session lxqt-panel pcmanfm-qt qterminal dbus-x11 ;;
    lxde) dnf -y group install \"LXDE Desktop\" || dnf -y install lxde-common lxsession openbox lxterminal dbus-x11 ;;
    mate) dnf -y group install \"MATE Desktop\" || dnf -y install mate-session-manager mate-panel mate-terminal dbus-x11 ;;
    openbox) dnf -y install openbox tint2 xterm dbus-x11 ;;
    i3) dnf -y install i3 i3status dmenu xterm dbus-x11 ;;
    kde) dnf -y group install \"KDE Plasma Workspaces\" || dnf -y install plasma-workspace plasma-desktop konsole dbus-x11 ;;
    gnome) dnf -y group install \"GNOME Desktop Environment\" || dnf -y install gnome-session gnome-shell gnome-terminal dbus-x11 ;;
  esac
elif command -v zypper >/dev/null 2>&1; then
  zypper --non-interactive refresh
  case \"\$DESKTOP_ID\" in
    xfce) zypper --non-interactive install -t pattern xfce || zypper --non-interactive install xfce4-session xfce4-panel xfce4-settings xfce4-terminal dbus-1-x11 ;;
    lxqt) zypper --non-interactive install -t pattern lxqt || zypper --non-interactive install lxqt-session lxqt-panel pcmanfm-qt qterminal dbus-1-x11 ;;
    lxde) zypper --non-interactive install -t pattern lxde || zypper --non-interactive install lxsession openbox lxterminal dbus-1-x11 ;;
    mate) zypper --non-interactive install -t pattern mate || zypper --non-interactive install mate-session-manager mate-panel mate-terminal dbus-1-x11 ;;
    openbox) zypper --non-interactive install openbox tint2 xterm dbus-1-x11 ;;
    i3) zypper --non-interactive install i3 i3status dmenu xterm dbus-1-x11 ;;
    kde) zypper --non-interactive install -t pattern kde_plasma || zypper --non-interactive install plasma5-session plasma5-workspace konsole dbus-1-x11 ;;
    gnome) zypper --non-interactive install -t pattern gnome || zypper --non-interactive install gnome-session gnome-shell gnome-terminal dbus-1-x11 ;;
  esac
else
  echo \"Gerenciador de pacotes não reconhecido para instalação automática.\" >&2
  exit 65
fi
command -v \"\$LAUNCHER\" >/dev/null 2>&1
EOF
}

linux_instalar_desktop_na_distro() {
    local alias="${1:-}" desktop="${2:-}" gerenciador guest_script nome launcher aviso
    [ -n "$alias" ] && [ -n "$desktop" ] || return 1
    nome="$(linux_desktop_nome "$desktop")"
    launcher="$(linux_desktop_launcher "$desktop")"
    gerenciador="$(linux_detectar_gerenciador_distro "$alias" 2>/dev/null || printf 'desconhecido')"
    [ -n "$gerenciador" ] || gerenciador="desconhecido"

    if linux_desktop_instalado "$alias" "$desktop"; then
        cabecalho_tela "✅ $nome já instalado" "$alias"
        caixa_simples "Desktop encontrado" \
            "Distribuição: $alias" \
            "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
            "Inicializador: $launcher" \
            "Nenhuma reinstalação é necessária."
        linux_log "$nome já presente em $alias; reinstalação evitada"
        return 0
    fi

    if [ "$gerenciador" = "desconhecido" ]; then
        cabecalho_tela "⚠ Desktop não automatizado" "$alias"
        caixa_simples "Gerenciador não reconhecido" \
            "O Manager não encontrou apt, pacman, apk, dnf ou zypper nesta distribuição." \
            "A instalação automática foi interrompida para evitar comandos incompatíveis."
        linux_log "gerenciador de pacotes desconhecido em $alias"
        return 65
    fi

    linux_avaliar_aparelho
    aviso="$(linux_desktop_aviso_perfil "$desktop")"
    cabecalho_tela "🪟 Preparando $nome" "$alias"
    caixa_simples "Ambiente gráfico" \
        "Distribuição: $alias" \
        "Desktop: $nome" \
        "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
        "Perfil do aparelho: ${LINUX_PROFILE_ICON} ${LINUX_PROFILE}" \
        "$aviso"
    if [ "$desktop" = "gnome" ]; then
        caixa_simples "⚠ Compatibilidade GNOME" \
            "GNOME foi mantido como opção avançada." \
            "Algumas funções dependem de serviços do sistema que não existem em PRoot." \
            "Se houver problemas, prefira XFCE, LXQt ou MATE."
    fi
    confirmar_acao "Instalar $nome dentro de '$alias'?" || return 2

    guest_script="$(linux_desktop_guest_script "$desktop")" || return 1
    cabecalho_tela "🪟 Instalando $nome" "A instalação dentro do Linux pode ser demorada"
    caixa_simples "Instalação inteligente" \
        "Distribuição: $alias" \
        "Desktop: $nome" \
        "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
        "O Manager validará '$launcher' ao terminar." \
        "Não feche o Termux durante esta etapa."
    if proot-distro login "$alias" -- /bin/sh -lc "$guest_script" 2>&1 | tee -a "$LINUX_LOG"; then
        if linux_desktop_instalado "$alias" "$desktop"; then
            linux_log "$nome instalado e validado em $alias via $gerenciador"
            ok "$nome instalado e validado em '$alias'."
            return 0
        fi
        error "A instalação terminou, mas '$launcher' não foi encontrado."
        linux_log "instalação $nome terminou sem $launcher em $alias via $gerenciador"
        return 1
    fi

    error "Não foi possível instalar $nome automaticamente."
    caixa_simples "Compatibilidade" \
        "Gerenciador detectado: $(linux_descrever_gerenciador_distro "$gerenciador")" \
        "O pacote ou grupo pode ter outro nome nesta versão da distribuição." \
        "Consulte o log para ver qual pacote não foi encontrado." \
        "XFCE e LXQt são as opções com melhor cobertura automática."
    linux_log "falha ao instalar $nome em $alias via $gerenciador"
    return 1
}

linux_instalar_xfce_na_distro() {
    linux_instalar_desktop_na_distro "${1:-}" xfce
}

linux_instalar_ambiente_grafico() {
    linux_garantir_proot_distro || { pause; return 1; }
    linux_avaliar_aparelho
    cabecalho_tela "🪟 Instalar ambiente gráfico" "Escolha o desktop para a distribuição"
    caixa_simples "Perfil do aparelho" \
        "${LINUX_PROFILE_ICON} ${LINUX_PROFILE}" \
        "$LINUX_PROFILE_RECOMMEND" \
        "Você pode instalar mais de um ambiente na mesma distribuição."
    linux_selecionar_instalada "🪟 Instalar ambiente gráfico" "Escolha a distribuição" || return 0
    linux_escolher_desktop "🖥️ Escolher ambiente gráfico" "$LINUX_DISTRO_ALIAS" || return 0
    linux_instalar_desktop_na_distro "$LINUX_DISTRO_ALIAS" "$LINUX_DESKTOP_ID"
    local rc=$?
    [ "$rc" -eq 2 ] || pause
    return 0
}

linux_instalar_desktop_xfce() {
    linux_instalar_ambiente_grafico
}

linux_selecionar_desktop_instalado() {
    local alias="${1:-}" titulo="${2:-🖥️ Ambiente instalado}" id nome indice=0
    local -a ids=() itens=()
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        ids+=("$id")
        indice=$((indice + 1))
        nome="$(linux_desktop_nome "$id")"
        itens+=("$indice|🖥️|$nome|$(linux_desktop_descricao "$id")")
    done < <(linux_desktops_instalados "$alias" 2>/dev/null || true)
    [ ${#ids[@]} -gt 0 ] || return 1
    if [ ${#ids[@]} -eq 1 ]; then
        LINUX_DESKTOP_ID="${ids[0]}"
        LINUX_DESKTOP_NOME="$(linux_desktop_nome "$LINUX_DESKTOP_ID")"
        LINUX_DESKTOP_LAUNCHER="$(linux_desktop_launcher "$LINUX_DESKTOP_ID")"
        return 0
    fi
    menu_unificado "$titulo" "$alias • escolha qual iniciar" \
        "[0] Voltar  •  [1–${#ids[@]}] Selecionar" "${itens[@]}"
    ler_opcao
    [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] || return 2
    [ "$RESPOSTA_MENU" -eq 0 ] && return 2
    [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#ids[@]} ] || return 2
    LINUX_DESKTOP_ID="${ids[$((RESPOSTA_MENU - 1))]}"
    LINUX_DESKTOP_NOME="$(linux_desktop_nome "$LINUX_DESKTOP_ID")"
    LINUX_DESKTOP_LAUNCHER="$(linux_desktop_launcher "$LINUX_DESKTOP_ID")"
    return 0
}

linux_iniciar_desktop() {
    local alias_preselecionado="${1:-}"
    linux_garantir_proot_distro || { pause; return 1; }
    cabecalho_tela "🖥️ Iniciar desktop Linux" "Termux:X11 + ambiente gráfico"
    if ! linux_x11_companion_instalado; then
        warn "O companion termux-x11 não está instalado."
        caixa_simples "Como corrigir" "Abra Termux:X11 > Instalar componentes do X11."
        pause
        return 1
    fi
    if ! linux_x11_apk_instalado; then
        warn "O aplicativo Android Termux:X11 não foi detectado."
        caixa_simples "Como corrigir" "Baixe o APK oficial pelo menu Termux:X11 e conclua a instalação no Android."
        pause
        return 1
    fi

    if [ -n "$alias_preselecionado" ]; then
        LINUX_DISTRO_ALIAS="$alias_preselecionado"
    else
        linux_selecionar_instalada "🖥️ Iniciar desktop Linux" "Escolha a distribuição para o desktop" || return 0
    fi
    linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" false
    if [ "$LINUX_INFO_HEALTH" != "ok" ]; then
        cabecalho_tela "⚠ Desktop indisponível" "$LINUX_DISTRO_ALIAS"
        caixa_simples "Distribuição com problema"             "Motivo: ${LINUX_DIAG_REASON:-falha ao iniciar}"             "Use Diagnóstico ou Reparar antes do desktop."
        pause
        return 1
    fi
    local instalados
    instalados="$(linux_desktops_instalados_resumo "$LINUX_DISTRO_ALIAS")"
    if [ "$instalados" = "nenhum" ]; then
        local gerenciador
        gerenciador="$(linux_detectar_gerenciador_distro "$LINUX_DISTRO_ALIAS" 2>/dev/null || printf 'desconhecido')"
        cabecalho_tela "⚠ Nenhum desktop instalado" "$LINUX_DISTRO_ALIAS"
        caixa_simples "Ambiente gráfico ausente" \
            "Distribuição: $LINUX_DISTRO_ALIAS" \
            "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
            "Você pode escolher XFCE, LXQt, LXDE, MATE, Openbox, i3, KDE ou GNOME."
        if confirmar_acao "Escolher e instalar um ambiente agora?" "s"; then
            linux_escolher_desktop "🖥️ Escolher ambiente gráfico" "$LINUX_DISTRO_ALIAS" || return 0
            linux_instalar_desktop_na_distro "$LINUX_DISTRO_ALIAS" "$LINUX_DESKTOP_ID"
            local rc=$?
            if [ "$rc" -ne 0 ]; then
                [ "$rc" -eq 2 ] || pause
                return 0
            fi
        else
            return 0
        fi
    else
        linux_selecionar_desktop_instalado "$LINUX_DISTRO_ALIAS" "🖥️ Ambientes instalados" || return 0
    fi

    local desktop="$LINUX_DESKTOP_ID" nome="$LINUX_DESKTOP_NOME" launcher="$LINUX_DESKTOP_LAUNCHER"
    cabecalho_tela "🖥️ Iniciar desktop Linux" "Termux:X11 + $nome"
    caixa_simples "Sessão gráfica" \
        "Distribuição: $LINUX_DISTRO_ALIAS" \
        "Desktop: $nome" \
        "Inicializador: $launcher" \
        "Display: :1" \
        "O Manager compartilhará /tmp com a distribuição para o X11." \
        "Feche a sessão gráfica para retornar ao Manager."
    confirmar_acao "Iniciar $nome agora?" "s" || return 0

    pkill -f 'termux-x11 :1' 2>/dev/null || true
    XDG_RUNTIME_DIR="${TMPDIR:-$PREFIX/tmp}" termux-x11 :1 >/dev/null 2>&1 &
    sleep 1
    command -v am >/dev/null 2>&1 && am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
    linux_log "sessão X11 iniciada para $LINUX_DISTRO_ALIAS desktop=$desktop"

    local session_cmd
    session_cmd="export DISPLAY=:1; export XDG_RUNTIME_DIR=/tmp; if command -v dbus-launch >/dev/null 2>&1; then exec dbus-launch --exit-with-session '$launcher'; else exec '$launcher'; fi"
    if ! proot-distro login "$LINUX_DISTRO_ALIAS" --shared-tmp -- /bin/sh -lc "$session_cmd"; then
        error "A sessão gráfica terminou com erro."
        caixa_simples "Dicas" \
            "$nome foi verificado antes da abertura da sessão." \
            "Se aparecer tela preta, consulte Diagnóstico X11." \
            "Ambientes pesados como KDE/GNOME podem exigir mais memória."
        pause
    fi
}

linux_iniciar_xfce() {
    linux_iniciar_desktop
}

linux_parar_x11() {
    cabecalho_tela "⏹️ Parar sessão gráfica" "Encerrar servidor Termux:X11"
    pkill -f 'com.termux.x11' 2>/dev/null || true
    pkill -f 'termux-x11' 2>/dev/null || true
    command -v am >/dev/null 2>&1 && am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
    linux_log "sessão X11 encerrada"
    ok "Solicitação de encerramento enviada ao Termux:X11."
    pause
}

linux_diagnostico_x11() {
    cabecalho_tela "🩺 Diagnóstico X11" "Orientações para problemas comuns"
    caixa_simples "Tela preta ou cursor apenas" \
        "Teste iniciar o servidor com: termux-x11 :1 -legacy-drawing" \
        "Alguns aparelhos precisam desse modo de desenho."
    caixa_simples "Cores trocadas" \
        "Teste: termux-x11 :1 -force-bgra"
    caixa_simples "Desktop lento" \
        "O Android pode limitar CPU quando o Termux fica em segundo plano." \
        "Mantenha o Termux ativo quando possível e use um desktop leve." \
        "O APK sharedUid pode reduzir esse problema, mas só é compatível com builds específicas do Termux."
    caixa_simples "PRoot + X11" \
        "O Manager inicia a distribuição com --shared-tmp." \
        "DISPLAY usado: :1"
    pause
}

menu_termux_x11() {
    while true; do
        local companion="ausente" app="ausente"
        linux_x11_companion_instalado && companion="instalado"
        linux_x11_apk_instalado && app="instalado"
        menu_unificado "🖥️ TERMUX:X11" "Interface gráfica para Linux" \
            "[0] Voltar  •  [1–7] Selecionar" \
            "1|📋|Status|Companion: $companion • App: $app" \
            "2|📦|Instalar componentes|x11-repo + termux-x11-nightly" \
            "3|📲|Baixar aplicativo Android|APK oficial nightly" \
            "4|🪟|Ambientes gráficos|XFCE, LXQt, LXDE, MATE, Openbox, i3, KDE e GNOME" \
            "5|▶️|Iniciar desktop|Escolher um ambiente instalado e abrir no X11" \
            "6|⏹️|Parar sessão gráfica|Encerrar servidor X11" \
            "7|🩺|Diagnóstico X11|Tela preta, cores e lentidão"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) linux_status_x11 ;;
            2) linux_instalar_x11_companion ;;
            3) linux_baixar_x11_apk ;;
            4) linux_instalar_ambiente_grafico ;;
            5) linux_iniciar_desktop ;;
            6) linux_parar_x11 ;;
            7) linux_diagnostico_x11 ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}
