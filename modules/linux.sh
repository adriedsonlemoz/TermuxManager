# Módulo: linux.sh
# Linux no celular — proot-distro + Termux:X11

LINUX_STATE_DIR="$PAINEL_DIR/linux"
LINUX_LOG="$LOG_DIR/linux.log"
TERMUX_X11_APK_URL="https://github.com/termux/termux-x11/releases/download/nightly/termux-x11-universal-debug.apk"
TERMUX_X11_APK_NAME="termux-x11-universal-debug.apk"

linux_log() {
    mkdir -p "$LINUX_STATE_DIR" "$(dirname "$LINUX_LOG")" 2>/dev/null || true
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LINUX_LOG"
}

linux_mem_total_kb() {
    awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0'
}

linux_mem_disponivel_kb() {
    awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0'
}

linux_espaco_livre_kb() {
    df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4; exit}' || printf '0'
}

linux_formatar_gb_kb() {
    local kb="${1:-0}"
    awk -v kb="$kb" 'BEGIN { printf "%.1f GB", kb/1024/1024 }'
}

linux_cpu_nucleos() {
    if command -v nproc >/dev/null 2>&1; then
        nproc 2>/dev/null || printf '1'
    else
        grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf '1'
    fi
}

linux_arquitetura() {
    if command -v dpkg >/dev/null 2>&1; then
        dpkg --print-architecture 2>/dev/null || uname -m
    else
        uname -m
    fi
}

linux_android_versao() {
    if command -v getprop >/dev/null 2>&1; then
        getprop ro.build.version.release 2>/dev/null | head -1
    else
        printf 'desconhecida'
    fi
}

linux_avaliar_aparelho() {
    local ram_kb livre_kb cores
    ram_kb="$(linux_mem_total_kb)"
    livre_kb="$(linux_espaco_livre_kb)"
    cores="$(linux_cpu_nucleos)"
    [[ "$ram_kb" =~ ^[0-9]+$ ]] || ram_kb=0
    [[ "$livre_kb" =~ ^[0-9]+$ ]] || livre_kb=0
    [[ "$cores" =~ ^[0-9]+$ ]] || cores=1

    LINUX_RAM_KB="$ram_kb"
    LINUX_FREE_KB="$livre_kb"
    LINUX_CPU_CORES="$cores"
    LINUX_PROFILE="DESKTOP"
    LINUX_PROFILE_ICON="🟢"
    LINUX_PROFILE_MSG="Boa margem para uma distribuição Linux e interface gráfica leve."
    LINUX_PROFILE_RECOMMEND="Termux:X11 + XFCE pode ser usado; ainda assim o desempenho varia por aparelho."

    # Heurística conservadora. Não tenta inferir potência real da CPU apenas por núcleos.
    if [ "$ram_kb" -lt $((3 * 1024 * 1024)) ] || [ "$livre_kb" -lt $((5 * 1024 * 1024)) ]; then
        LINUX_PROFILE="BÁSICO"
        LINUX_PROFILE_ICON="🔴"
        LINUX_PROFILE_MSG="O aparelho tem pouca margem para um desktop Linux completo."
        LINUX_PROFILE_RECOMMEND="Prefira Linux em modo terminal. Interface gráfica pode apresentar travamentos e falta de memória."
    elif [ "$ram_kb" -lt $((6 * 1024 * 1024)) ] || [ "$livre_kb" -lt $((10 * 1024 * 1024)) ] || [ "$cores" -le 4 ]; then
        LINUX_PROFILE="INTERMEDIÁRIO"
        LINUX_PROFILE_ICON="🟡"
        LINUX_PROFILE_MSG="Linux deve funcionar bem, mas o desktop precisa ser leve."
        LINUX_PROFILE_RECOMMEND="XFCE é a opção indicada. Evite muitas aplicações pesadas abertas ao mesmo tempo."
    fi
}

linux_mostrar_perfil() {
    detectar_variante_termux 2>/dev/null || true
    linux_avaliar_aparelho
    cabecalho_tela "📱 Capacidade para Linux" "Estimativa local antes da instalação"
    caixa_simples "Hardware detectado" \
        "RAM total: $(linux_formatar_gb_kb "$LINUX_RAM_KB")" \
        "RAM disponível agora: $(linux_formatar_gb_kb "$(linux_mem_disponivel_kb)")" \
        "CPU: ${LINUX_CPU_CORES} núcleo(s)" \
        "Arquitetura: $(linux_arquitetura)" \
        "Espaço livre: $(linux_formatar_gb_kb "$LINUX_FREE_KB")" \
        "Android: $(linux_android_versao)" \
        "Termux: $(termux_origem_resumida)"
    caixa_simples "${LINUX_PROFILE_ICON} Perfil estimado: ${LINUX_PROFILE}" \
        "$LINUX_PROFILE_MSG" \
        "$LINUX_PROFILE_RECOMMEND" \
        "Esta avaliação é orientativa; não substitui um benchmark do aparelho."
    pause
}

linux_garantir_proot_distro() {
    command -v proot-distro >/dev/null 2>&1 && return 0

    if declare -F pacote_disponivel_termux >/dev/null 2>&1 && ! pacote_disponivel_termux proot-distro; then
        cabecalho_tela "🐧 Preparar Linux" "Compatibilidade do Termux"
        caixa_simples "⚠ proot-distro indisponível" \
            "O pacote proot-distro não aparece nos repositórios configurados nesta edição do Termux." \
            "Atualize os repositórios ou use uma edição do Termux que ofereça esse pacote."
        return 1
    fi

    cabecalho_tela "🐧 Preparar Linux" "Instalar gerenciador de distribuições"
    caixa_simples "proot-distro não encontrado" \
        "O Manager usa o proot-distro oficial para instalar Linux sem root." \
        "Ele será instalado pelo gerenciador de pacotes do Termux."
    confirmar_acao "Instalar proot-distro agora?" "s" || return 1

    if executar_pkg_monitorado "Instalando proot-distro" 15 92 \
        "Preparando suporte a distribuições Linux..." \
        "A instalação pode levar alguns minutos." -- install -y proot-distro; then
        ok "proot-distro instalado."
        linux_log "proot-distro instalado"
        return 0
    fi

    mostrar_erro_pkg "Não foi possível instalar proot-distro."
    return 1
}

linux_listar_distros() {
    linux_garantir_proot_distro || { pause; return 1; }
    cabecalho_tela "🐧 Distribuições Linux" "Lista fornecida pelo proot-distro instalado"
    echo
    proot-distro list 2>&1 | tee -a "$LINUX_LOG"
    echo
    caixa_simples "Como usar" \
        "Use o alias mostrado pelo proot-distro, por exemplo: debian ou ubuntu." \
        "A disponibilidade pode mudar conforme a versão do proot-distro."
    pause
}

linux_ler_alias() {
    local prompt="${1:-Alias da distribuição}"
    ui_preparar_prompt
    printf '%s: ' "$prompt"
    IFS= read -r LINUX_DISTRO_ALIAS
    LINUX_DISTRO_ALIAS="${LINUX_DISTRO_ALIAS,,}"
    if ! [[ "$LINUX_DISTRO_ALIAS" =~ ^[a-z0-9][a-z0-9._+-]{0,63}$ ]]; then
        warn "Alias inválido. Use somente letras, números, ponto, +, _ ou -."
        return 1
    fi
    return 0
}

linux_instalar_distro() {
    linux_garantir_proot_distro || { pause; return 1; }
    linux_avaliar_aparelho
    cabecalho_tela "⬇️ Instalar distribuição" "Linux sem root pelo proot-distro"
    caixa_simples "Antes de instalar" \
        "Perfil do aparelho: ${LINUX_PROFILE_ICON} ${LINUX_PROFILE}" \
        "Espaço livre: $(linux_formatar_gb_kb "$LINUX_FREE_KB")" \
        "$LINUX_PROFILE_RECOMMEND"
    echo
    proot-distro list 2>/dev/null || true
    echo
    linux_ler_alias "Digite o alias que deseja instalar" || { pause; return 1; }

    caixa_simples "Distribuição selecionada" \
        "Alias: $LINUX_DISTRO_ALIAS" \
        "A imagem será baixada pela fonte configurada no proot-distro." \
        "A instalação pode consumir vários GB após atualizações e programas."
    confirmar_acao "Instalar '$LINUX_DISTRO_ALIAS'?" || return 0

    mkdir -p "$(dirname "$LINUX_LOG")"
    cabecalho_tela "⬇️ Instalando $LINUX_DISTRO_ALIAS" "Não feche o Termux durante a extração"
    if proot-distro install "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG"; then
        linux_log "distribuição instalada: $LINUX_DISTRO_ALIAS"
        ok "Distribuição '$LINUX_DISTRO_ALIAS' instalada."
        caixa_simples "Próximo passo" \
            "Você já pode iniciar esta distribuição em modo terminal." \
            "Se quiser interface gráfica, configure o Termux:X11 pelo menu Linux."
    else
        error "A instalação de '$LINUX_DISTRO_ALIAS' falhou."
        printf 'Log: %s\n' "$(caminho_curto "$LINUX_LOG")"
    fi
    pause
}

linux_abrir_terminal_distro() {
    linux_garantir_proot_distro || { pause; return 1; }
    cabecalho_tela "⌨️ Iniciar Linux" "Abrir uma distribuição em modo terminal"
    proot-distro list 2>/dev/null || true
    echo
    linux_ler_alias "Alias da distribuição instalada" || { pause; return 1; }
    caixa_simples "Sessão Linux" \
        "Distribuição: $LINUX_DISTRO_ALIAS" \
        "Digite exit para voltar ao Termux Manager."
    sleep 1
    linux_log "iniciando terminal: $LINUX_DISTRO_ALIAS"
    if ! proot-distro login "$LINUX_DISTRO_ALIAS"; then
        error "Não foi possível iniciar '$LINUX_DISTRO_ALIAS'."
        pause
    fi
}

linux_remover_distro() {
    linux_garantir_proot_distro || { pause; return 1; }
    cabecalho_tela "🗑️ Remover distribuição" "Esta operação apaga o sistema Linux escolhido"
    proot-distro list 2>/dev/null || true
    echo
    linux_ler_alias "Alias da distribuição que será removida" || { pause; return 1; }
    caixa_simples "⚠ Exclusão permanente" \
        "Distribuição: $LINUX_DISTRO_ALIAS" \
        "Arquivos mantidos somente dentro dessa distribuição serão apagados." \
        "Faça backup antes se houver dados importantes."
    confirmar_acao "Remover '$LINUX_DISTRO_ALIAS' permanentemente?" || return 0
    ui_preparar_prompt
    printf "Digite o alias '%s' novamente para confirmar: " "$LINUX_DISTRO_ALIAS"
    local confirmar_alias
    IFS= read -r confirmar_alias
    [ "$confirmar_alias" = "$LINUX_DISTRO_ALIAS" ] || { warn "Confirmação diferente. Operação cancelada."; pause; return 0; }

    if proot-distro remove "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG"; then
        linux_log "distribuição removida: $LINUX_DISTRO_ALIAS"
        ok "Distribuição removida."
    else
        error "Falha ao remover a distribuição."
    fi
    pause
}

linux_resetar_distro() {
    linux_garantir_proot_distro || { pause; return 1; }
    cabecalho_tela "🩺 Reparar / reinstalar" "Reset do proot-distro"
    proot-distro list 2>/dev/null || true
    echo
    linux_ler_alias "Alias da distribuição" || { pause; return 1; }
    caixa_simples "⚠ Reinstalação destrutiva" \
        "O comando reset remove a distribuição e instala uma cópia nova." \
        "Todos os dados internos da distribuição serão perdidos."
    confirmar_acao "Resetar '$LINUX_DISTRO_ALIAS'?" || return 0
    if proot-distro reset "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG"; then
        linux_log "distribuição resetada: $LINUX_DISTRO_ALIAS"
        ok "Distribuição reinstalada."
    else
        error "Falha ao reinstalar a distribuição."
    fi
    pause
}

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

linux_instalar_desktop_xfce() {
    linux_garantir_proot_distro || { pause; return 1; }
    linux_avaliar_aparelho
    cabecalho_tela "🪟 Instalar XFCE" "Desktop gráfico dentro da distribuição"
    caixa_simples "Perfil do aparelho" \
        "${LINUX_PROFILE_ICON} ${LINUX_PROFILE}" \
        "$LINUX_PROFILE_RECOMMEND"
    [ "$LINUX_PROFILE" = "BÁSICO" ] && caixa_simples "⚠ Atenção" \
        "Neste aparelho, um desktop gráfico pode ficar lento ou encerrar por falta de memória." \
        "O modo terminal é mais indicado. Você ainda pode continuar se quiser testar."
    proot-distro list 2>/dev/null || true
    echo
    linux_ler_alias "Alias da distribuição instalada" || { pause; return 1; }
    confirmar_acao "Instalar XFCE dentro de '$LINUX_DISTRO_ALIAS'?" || return 0

    local guest_script
    guest_script='set -e
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y xfce4 dbus-x11
elif command -v pacman >/dev/null 2>&1; then
  pacman -Sy --noconfirm xfce4 xfce4-goodies dbus
elif command -v apk >/dev/null 2>&1; then
  apk update
  apk add xfce4 xfce4-terminal dbus
else
  echo "Gerenciador de pacotes não reconhecido para instalação automática do XFCE." >&2
  exit 65
fi'

    cabecalho_tela "🪟 Instalando XFCE" "A instalação dentro do Linux pode ser demorada"
    if proot-distro login "$LINUX_DISTRO_ALIAS" -- /bin/sh -lc "$guest_script" 2>&1 | tee -a "$LINUX_LOG"; then
        linux_log "XFCE instalado em $LINUX_DISTRO_ALIAS"
        ok "XFCE instalado em '$LINUX_DISTRO_ALIAS'."
    else
        error "Não foi possível instalar XFCE automaticamente."
        caixa_simples "Compatibilidade" \
            "A automação reconhece distribuições baseadas em apt, pacman e apk." \
            "Outras distribuições ainda podem usar desktop, mas exigem instalação manual."
    fi
    pause
}

linux_iniciar_xfce() {
    linux_garantir_proot_distro || { pause; return 1; }
    cabecalho_tela "🖥️ Iniciar desktop Linux" "Termux:X11 + XFCE"
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

    proot-distro list 2>/dev/null || true
    echo
    linux_ler_alias "Alias da distribuição com XFCE" || { pause; return 1; }
    caixa_simples "Sessão gráfica" \
        "Distribuição: $LINUX_DISTRO_ALIAS" \
        "Display: :1" \
        "O Manager compartilhará /tmp com a distribuição para o X11." \
        "Feche a sessão do XFCE para retornar ao Manager."
    confirmar_acao "Iniciar o desktop agora?" "s" || return 0

    pkill -f 'termux-x11 :1' 2>/dev/null || true
    XDG_RUNTIME_DIR="${TMPDIR:-$PREFIX/tmp}" termux-x11 :1 >/dev/null 2>&1 &
    sleep 1
    command -v am >/dev/null 2>&1 && am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
    linux_log "sessão X11 iniciada para $LINUX_DISTRO_ALIAS"

    local session_cmd='export DISPLAY=:1; export XDG_RUNTIME_DIR=/tmp; if command -v dbus-launch >/dev/null 2>&1; then exec dbus-launch --exit-with-session xfce4-session; else exec xfce4-session; fi'
    if ! proot-distro login "$LINUX_DISTRO_ALIAS" --shared-tmp -- /bin/sh -lc "$session_cmd"; then
        error "A sessão gráfica terminou com erro."
        caixa_simples "Dicas" \
            "Confirme que XFCE foi instalado dentro da distribuição." \
            "Se aparecer tela preta, consulte a opção Diagnóstico X11 no menu."
        pause
    fi
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
            "4|🪟|Instalar XFCE na distro|Desktop leve dentro do Linux" \
            "5|▶️|Iniciar desktop|Abrir XFCE pelo Termux:X11" \
            "6|⏹️|Parar sessão gráfica|Encerrar servidor X11" \
            "7|🩺|Diagnóstico X11|Tela preta, cores e lentidão"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) linux_status_x11 ;;
            2) linux_instalar_x11_companion ;;
            3) linux_baixar_x11_apk ;;
            4) linux_instalar_desktop_xfce ;;
            5) linux_iniciar_xfce ;;
            6) linux_parar_x11 ;;
            7) linux_diagnostico_x11 ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

menu_linux_celular() {
    while true; do
        linux_avaliar_aparelho
        local proot_status="ausente" x11_status="ausente"
        command -v proot-distro >/dev/null 2>&1 && proot_status="pronto"
        linux_x11_companion_instalado && x11_status="pronto"
        menu_unificado "🐧 LINUX NO CELULAR" "PRoot sem root • perfil ${LINUX_PROFILE}" \
            "[0] Voltar  •  [1–8] Selecionar" \
            "1|📱|Ver compatibilidade|RAM, CPU, espaço e recomendação" \
            "2|📚|Ver distribuições|Lista dinâmica do proot-distro" \
            "3|⬇️|Instalar distribuição|Debian, Ubuntu e outras disponíveis" \
            "4|⌨️|Iniciar Linux|Abrir uma distro em modo terminal" \
            "5|🖥️|Termux:X11|Configurar e iniciar interface gráfica" \
            "6|🩺|Reparar / reinstalar distro|Reset destrutivo com confirmação" \
            "7|🗑️|Remover distribuição|Excluir uma distro instalada" \
            "8|ℹ️|Status|proot-distro: $proot_status • X11: $x11_status"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) linux_mostrar_perfil ;;
            2) linux_listar_distros ;;
            3) linux_instalar_distro ;;
            4) linux_abrir_terminal_distro ;;
            5) menu_termux_x11 ;;
            6) linux_resetar_distro ;;
            7) linux_remover_distro ;;
            8)
                cabecalho_tela "ℹ️ Linux no celular" "Estado dos componentes"
                caixa_simples "Status" \
                    "Perfil: ${LINUX_PROFILE_ICON} ${LINUX_PROFILE}" \
                    "proot-distro: $proot_status" \
                    "Termux:X11 companion: $x11_status" \
                    "Termux:X11 Android: $(linux_x11_apk_instalado && echo instalado || echo não detectado)" \
                    "Log: $(caminho_curto "$LINUX_LOG")"
                pause
                ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}
