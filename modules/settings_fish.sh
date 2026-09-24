# Módulo: settings_fish.sh
# Fish Shell e experiência interativa. Carregado por settings.sh.

# ============================================================================
# FISH SHELL
# ============================================================================

fish_instalado() { command -v fish >/dev/null 2>&1; }

caminho_fish() {
    command -v fish 2>/dev/null || printf '%s/bin/fish' "${PREFIX:-/data/data/com.termux/files/usr}"
}

shell_padrao_atual() {
    local shell_link="$HOME/.termux/shell"
    if [ -L "$shell_link" ]; then
        readlink -f "$shell_link" 2>/dev/null || readlink "$shell_link" 2>/dev/null
    elif [ -f "$shell_link" ]; then
        cat "$shell_link" 2>/dev/null
    else
        printf '%s' "${SHELL:-$(command -v bash 2>/dev/null)}"
    fi
}

fish_eh_padrao() {
    local atual fish_bin
    fish_instalado || return 1
    atual="$(shell_padrao_atual)"
    fish_bin="$(caminho_fish)"
    [ "$atual" = "$fish_bin" ] || [ "$(basename "$atual" 2>/dev/null)" = fish ]
}

status_fish() {
    if fish_instalado; then printf 'Instalado'; else printf 'Não instalado'; fi
}

status_fish_padrao() {
    if fish_eh_padrao; then printf 'Fish'; else printf 'Bash/outro'; fi
}

instalar_fish_shell() {
    cabecalho_tela "🐟 Instalar Fish" "Shell moderno para o Termux"
    if fish_instalado; then
        [ "${FISH_CONFIG_COMPLETA:-false}" = true ] || ok "Fish já está instalado em $(caminho_fish)."
        return 0
    fi

    # Reutiliza o mesmo instalador robusto dos ambientes de desenvolvimento.
    # Assim Fish também herda espera de lock, reparo do dpkg, detecção de
    # variante do Termux, fallback individual e suporte a prompts interativos.
    if declare -F instalar_lista_pacotes >/dev/null 2>&1; then
        local auto_anterior="${TERMUX_INSTALL_NONINTERACTIVE:-__unset__}"
        # O menu do Fish já representa uma ação explícita do usuário; evita
        # uma segunda confirmação dentro do instalador comum.
        TERMUX_INSTALL_NONINTERACTIVE=true
        if instalar_lista_pacotes "Fish Shell" fish && fish_instalado; then
            if [ "$auto_anterior" = __unset__ ]; then unset TERMUX_INSTALL_NONINTERACTIVE; else TERMUX_INSTALL_NONINTERACTIVE="$auto_anterior"; fi
            ok "Fish instalado com sucesso."
            return 0
        fi
        if [ "$auto_anterior" = __unset__ ]; then unset TERMUX_INSTALL_NONINTERACTIVE; else TERMUX_INSTALL_NONINTERACTIVE="$auto_anterior"; fi
        error "Falha ao instalar o Fish. Consulte o diagnóstico de pacotes do Termux."
        return 1
    fi

    # Compatibilidade para carregamento isolado do submódulo em instalações
    # antigas: só usa pkg diretamente quando o instalador central não existe.
    command -v pkg >/dev/null 2>&1 || { error "O comando pkg não está disponível."; return 1; }
    if pkg install -y fish && fish_instalado; then
        ok "Fish instalado com sucesso."
        return 0
    fi
    error "Falha ao instalar o Fish. Verifique sua conexão ou o espelho do Termux."
    return 1
}

configurar_sugestoes_fish() {
    fish_instalado || instalar_fish_shell || return 1
    local fish_bin config_dir config_file marker_start marker_end tmp
    fish_bin="$(caminho_fish)"
    config_dir="$HOME/.config/fish"
    config_file="$config_dir/config.fish"
    marker_start="# >>> Manager: Fish sugestões >>>"
    marker_end="# <<< Manager: Fish sugestões <<<"
    mkdir -p "$config_dir"

    # As sugestões e completações são nativas do Fish. Esta configuração
    # garante que permaneçam habilitadas e deixa a experiência mais amigável.
    "$fish_bin" -c 'set -U fish_autosuggestion_enabled 1' >/dev/null 2>&1 || true
    "$fish_bin" -c 'set -U fish_color_autosuggestion 555 brblack' >/dev/null 2>&1 || true

    tmp="$(mktemp)"
    if [ -f "$config_file" ]; then
        awk -v ini="$marker_start" -v fim="$marker_end" '
            $0 == ini {pular=1; next}
            $0 == fim {pular=0; next}
            !pular {print}
        ' "$config_file" > "$tmp"
    fi
    cat >> "$tmp" <<'FISHCFG'
# >>> Manager: Fish sugestões >>>
# Sugestões, realce de sintaxe e completações já vêm integrados ao Fish.
set -g fish_autosuggestion_enabled 1

# Marca o início da sessão para calcular por quanto tempo o Fish ficou aberto.
set -g MANAGER_FISH_SESSION_START (date +%s)

# Mensagem de boas-vindas leve e útil, exibida uma vez por sessão.
function manager_fish_welcome --on-event fish_prompt
    functions -e manager_fish_welcome
    if not set -q MANAGER_FISH_WELCOME_DISABLED
        set_color brcyan
        set -l cols $COLUMNS
        if test -z "$cols"; or test "$cols" -lt 30
            set cols 40
        end
        set -l largura (math "$cols - 2")
        set -l interno (math "$largura - 4")
        set -l borda (string repeat -n (math "$largura - 2") '─')
        printf '╭%s╮\n' "$borda"
        printf '│  %-*s  │\n' $interno '🐟 Bem-vindo ao Fish no Termux!'
        printf '│  %-*s  │\n' $interno 'Digite help para ajuda ou ll para listar.'
        printf '╰%s╯\n' "$borda"
        set_color normal
    end
end

# Ao sair, informa quanto tempo a sessão permaneceu aberta.
function manager_fish_session_time --on-event fish_exit
    if set -q MANAGER_FISH_SESSION_TIME_DISABLED
        return
    end
    if not set -q MANAGER_FISH_SESSION_START
        return
    end
    set -l fim (date +%s)
    set -l total (math "$fim - $MANAGER_FISH_SESSION_START")
    set -l horas (math -s0 "$total / 3600")
    set -l minutos (math -s0 "($total % 3600) / 60")
    set -l segundos (math -s0 "$total % 60")
    set_color brblack
    printf 'Sessão Fish encerrada após %02dh %02dm %02ds.\n' $horas $minutos $segundos
    set_color normal
end

# Atalhos úteis:
# → ou Ctrl+F aceita a sugestão inteira.
# Alt+→ aceita a próxima palavra sugerida.
# Tab abre as completações disponíveis.

# Navegação do histórico conforme o texto já digitado.
bind \e\[A history-prefix-search-backward
bind \e\[B history-prefix-search-forward

# Atalhos seguros e úteis no Termux.
abbr -a -- ll 'ls -lah'
abbr -a -- la 'ls -A'
abbr -a -- .. 'cd ..'
abbr -a -- ... 'cd ../..'
abbr -a -- c clear

# Cria uma pasta e entra nela.
function mkcd
    if test (count $argv) -ne 1
        echo 'Uso: mkcd NOME_DA_PASTA'
        return 1
    end
    mkdir -p -- $argv[1]; and cd -- $argv[1]
end

# Prompt leve com diretório, branch/estado Git e código do último erro.
function fish_prompt
    set -l status_anterior $status
    set_color brcyan
    printf '%s' (prompt_pwd)
    set_color normal

    if command -q git; and command git rev-parse --is-inside-work-tree >/dev/null 2>&1
        set -l branch (command git symbolic-ref --short HEAD 2>/dev/null)
        test -n "$branch"; or set branch (command git rev-parse --short HEAD 2>/dev/null)
        set -l git_estado ''
        if test -n (command git status --porcelain 2>/dev/null)
            set git_estado '*'
        end
        set_color brmagenta
        printf ' (%s%s)' $branch $git_estado
        set_color normal
    end

    if test $status_anterior -ne 0
        set_color brred
        printf ' [%s]' $status_anterior
        set_color normal
    end
    printf ' ❯ '
end
# <<< Manager: Fish sugestões <<<
FISHCFG
    mv "$tmp" "$config_file"
    if [ "${FISH_CONFIG_COMPLETA:-false}" != true ]; then
        ok "Sugestões, completações e prompt do Fish configurados."
        info "O Fish já possui autosugestões nativas; não foi necessário instalar plugin externo."
    fi
}

remover_bloco_fish_bashrc() {
    local bashrc="$HOME/.bashrc" tmp
    [ -f "$bashrc" ] || return 0
    tmp="$(mktemp)"
    awk '
        $0 == "# >>> Manager: iniciar Fish automaticamente >>>" {pular=1; next}
        $0 == "# <<< Manager: iniciar Fish automaticamente <<<" {pular=0; next}
        !pular {print}
    ' "$bashrc" > "$tmp"
    mv "$tmp" "$bashrc"
}

ativar_fish_no_bashrc() {
    local bashrc="$HOME/.bashrc"
    remover_bloco_fish_bashrc
    cat >> "$bashrc" <<'BASHRCFISH'
# >>> Manager: iniciar Fish automaticamente >>>
# Fallback para versões/sessões do Termux que ignoram o shell definido por chsh.
# Só troca o shell em terminal interativo e evita loops ao chamar Bash manualmente.
if [[ $- == *i* ]] && command -v fish >/dev/null 2>&1 \
   && [ -z "${FISH_VERSION:-}" ] && [ -z "${MANAGER_KEEP_BASH:-}" ]; then
    exec fish
fi
# <<< Manager: iniciar Fish automaticamente <<<
BASHRCFISH
}

definir_fish_padrao() {
    fish_instalado || instalar_fish_shell || return 1
    local fish_bin aplicado=false
    fish_bin="$(caminho_fish)"
    mkdir -p "$HOME/.termux"

    # Método oficial do Termux. Não confiamos apenas no código de saída,
    # porque algumas versões mantêm a sessão inicial em Bash.
    if command -v chsh >/dev/null 2>&1; then
        chsh -s "$fish_bin" >/dev/null 2>&1 && aplicado=true
    fi

    # Compatibilidade com versões que usam ~/.termux/shell.
    ln -sfn "$fish_bin" "$HOME/.termux/shell" 2>/dev/null || true

    # Fallback garantido: toda nova sessão Bash interativa passa para o Fish.
    ativar_fish_no_bashrc

    if grep -qF '# >>> Manager: iniciar Fish automaticamente >>>' "$HOME/.bashrc"; then
        if [ "${FISH_CONFIG_COMPLETA:-false}" != true ]; then
            ok "Fish configurado para iniciar automaticamente em novas sessões."
            [ "$aplicado" = true ] && info "O chsh também foi aplicado com sucesso."
            info "Feche todas as sessões do Termux e abra uma nova."
            info "Para abrir Bash sem trocar para Fish: MANAGER_KEEP_BASH=1 bash"
        fi
        return 0
    fi

    error "Não foi possível registrar o Fish no arquivo ~/.bashrc."
    return 1
}

restaurar_bash_padrao() {
    local bash_bin
    bash_bin="$(command -v bash 2>/dev/null || printf '%s/bin/bash' "${PREFIX:-/data/data/com.termux/files/usr}")"
    mkdir -p "$HOME/.termux"

    remover_bloco_fish_bashrc
    if command -v chsh >/dev/null 2>&1; then
        chsh -s "$bash_bin" >/dev/null 2>&1 || true
    fi
    ln -sfn "$bash_bin" "$HOME/.termux/shell" 2>/dev/null || true

    ok "Inicialização automática do Fish removida e Bash restaurado."
    info "Feche todas as sessões do Termux e abra uma nova."
}


status_mensagens_iniciais() {
    if [ -f "$HOME/.hushlogin" ]; then printf 'Ocultas'; else printf 'Visíveis'; fi
}

ocultar_mensagens_iniciais() {
    fish_instalado || instalar_fish_shell || return 1
    local fish_bin config_dir config_file marker
    fish_bin="$(caminho_fish)"
    config_dir="$HOME/.config/fish"
    config_file="$config_dir/config.fish"
    marker="$HOME/.config/manager/hushlogin_criado"

    mkdir -p "$config_dir" "$(dirname "$marker")"

    # O Termux respeita ~/.hushlogin e deixa de imprimir o banner Welcome to Termux.
    if [ ! -e "$HOME/.hushlogin" ]; then
        : > "$HOME/.hushlogin"
        : > "$marker"
    fi

    # Remove a saudação "Welcome to fish..." na sessão atual e nas próximas.
    "$fish_bin" -c "set -U fish_greeting ''" >/dev/null 2>&1 || true
    if ! grep -qF '# Manager: ocultar saudação do Fish' "$config_file" 2>/dev/null; then
        cat >> "$config_file" <<'FISHQUIET'

# Manager: ocultar saudação do Fish
set -g fish_greeting
FISHQUIET
    fi

    if [ "${FISH_CONFIG_COMPLETA:-false}" != true ]; then
        ok "Banner do Termux e saudação do Fish foram ocultados."
        info "Abra uma nova sessão do Termux para confirmar."
    fi
}

restaurar_mensagens_iniciais() {
    local config_file="$HOME/.config/fish/config.fish"
    local marker="$HOME/.config/manager/hushlogin_criado"
    local tmp fish_bin

    # Só remove ~/.hushlogin quando ele foi criado pelo Manager.
    if [ -f "$marker" ]; then
        rm -f "$HOME/.hushlogin" "$marker"
    fi

    if [ -f "$config_file" ]; then
        tmp="$(mktemp)"
        awk '
            $0 == "# Manager: ocultar saudação do Fish" {pular=1; next}
            pular && $0 == "set -g fish_greeting" {pular=0; next}
            !pular {print}
        ' "$config_file" > "$tmp"
        mv "$tmp" "$config_file"
    fi

    if fish_instalado; then
        fish_bin="$(caminho_fish)"
        "$fish_bin" -c 'set -eU fish_greeting' >/dev/null 2>&1 || true
    fi

    ok "Mensagens iniciais restauradas."
    info "Abra uma nova sessão do Termux para visualizar novamente."
}

status_tempo_sessao_fish() {
    local config_file="$HOME/.config/fish/config.fish"
    if grep -qF 'set -gx MANAGER_FISH_SESSION_TIME_DISABLED 1' "$config_file" 2>/dev/null; then
        printf 'Oculto'
    else
        printf 'Visível'
    fi
}

alternar_tempo_sessao_fish() {
    fish_instalado || instalar_fish_shell || return 1
    local config_file="$HOME/.config/fish/config.fish" marker='# Manager: ocultar tempo da sessão'
    mkdir -p "$(dirname "$config_file")"
    if grep -qF 'set -gx MANAGER_FISH_SESSION_TIME_DISABLED 1' "$config_file" 2>/dev/null; then
        sed -i "/^# Manager: ocultar tempo da sessão$/d;/^set -gx MANAGER_FISH_SESSION_TIME_DISABLED 1$/d" "$config_file"
        ok "O tempo da sessão será mostrado ao sair do Fish."
    else
        printf '\n%s\n%s\n' "$marker" 'set -gx MANAGER_FISH_SESSION_TIME_DISABLED 1' >> "$config_file"
        ok "O tempo da sessão foi ocultado."
    fi
    info "A alteração vale para novas sessões do Fish."
}

status_boas_vindas_fish() {
    local config_file="$HOME/.config/fish/config.fish"
    if grep -qF 'set -gx MANAGER_FISH_WELCOME_DISABLED 1' "$config_file" 2>/dev/null; then
        printf 'Oculta'
    else
        printf 'Visível'
    fi
}

alternar_boas_vindas_fish() {
    fish_instalado || instalar_fish_shell || return 1
    local config_file="$HOME/.config/fish/config.fish" marker='# Manager: ocultar boas-vindas personalizadas'
    mkdir -p "$(dirname "$config_file")"
    if grep -qF 'set -gx MANAGER_FISH_WELCOME_DISABLED 1' "$config_file" 2>/dev/null; then
        sed -i "/^# Manager: ocultar boas-vindas personalizadas$/d;/^set -gx MANAGER_FISH_WELCOME_DISABLED 1$/d" "$config_file"
        ok "A mensagem de boas-vindas personalizada foi ativada."
    else
        printf '\n%s\n%s\n' "$marker" 'set -gx MANAGER_FISH_WELCOME_DISABLED 1' >> "$config_file"
        ok "A mensagem de boas-vindas personalizada foi ocultada."
    fi
    info "A alteração vale para novas sessões do Fish."
}

limpar_configuracoes_fish() {
    confirmar_acao "Limpar todas as configurações do Fish e restaurar o Bash? Python, Node, Git, projetos e pacotes não serão removidos." || return

    local backup_dir="$HOME/.config/manager/backups/fish-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    [ -d "$HOME/.config/fish" ] && cp -a "$HOME/.config/fish" "$backup_dir/config-fish" 2>/dev/null || true
    [ -d "$HOME/.local/share/fish" ] && cp -a "$HOME/.local/share/fish" "$backup_dir/share-fish" 2>/dev/null || true
    [ -d "$HOME/.cache/fish" ] && cp -a "$HOME/.cache/fish" "$backup_dir/cache-fish" 2>/dev/null || true

    restaurar_bash_padrao >/dev/null 2>&1 || true
    restaurar_mensagens_iniciais >/dev/null 2>&1 || true
    remover_bloco_fish_bashrc

    rm -rf "$HOME/.config/fish" "$HOME/.local/share/fish" "$HOME/.cache/fish"
    rm -f "$HOME/.config/manager/hushlogin_criado"

    if fish_instalado; then
        local fish_bin
        fish_bin="$(caminho_fish)"
        "$fish_bin" -c 'set -eU fish_greeting; set -eU fish_color_autosuggestion; set -eU fish_autosuggestion_enabled' >/dev/null 2>&1 || true
    fi

    tela_caixa_unica "🧹 Fish limpo" "Configurações removidas com segurança" "Pronto para uma instalação limpa" \
        "${C_GREEN}✔${C_RESET} Configuração do Fish removida" \
        "${C_GREEN}✔${C_RESET} Variáveis universais administradas limpas" \
        "${C_GREEN}✔${C_RESET} Inicialização automática removida" \
        "${C_GREEN}✔${C_RESET} Bash restaurado como padrão" \
        "${C_GREEN}✔${C_RESET} Python, Node, Git e projetos preservados" \
        "" \
        "${C_DIM}Backup: ${backup_dir}${C_RESET}" \
        "${C_YELLOW}Execute Configuração completa para reinstalar o shell do zero.${C_RESET}"
}

encerrar_sessao_para_aplicar_fish() {
    local shell_pai="$PPID"
    printf '\n'
    printf '%b' "${C_YELLOW}A sessão atual será encerrada para aplicar o Fish.${C_RESET}\n"
    printf '%b' "${C_DIM}Depois, feche esta janela/sessão do Termux e abra novamente.${C_RESET}\n\n"
    ui_buffer_flush
    read -r -p "Pressione ENTER para encerrar agora... " _

    # Encerra o shell que iniciou o Manager. Isso fecha a sessão atual,
    # mas não tenta forçar a parada do aplicativo Android.
    if [ -n "$shell_pai" ] && [ "$shell_pai" -gt 1 ] 2>/dev/null; then
        kill -TERM "$shell_pai" 2>/dev/null || true
    fi
    exit 0
}

configurar_fish_completo() {
    local fish_antes=false
    fish_instalado && fish_antes=true
    FISH_CONFIG_COMPLETA=true

    instalar_fish_shell || { FISH_CONFIG_COMPLETA=false; return 1; }
    configurar_sugestoes_fish || { FISH_CONFIG_COMPLETA=false; return 1; }
    ocultar_mensagens_iniciais || { FISH_CONFIG_COMPLETA=false; return 1; }
    definir_fish_padrao || { FISH_CONFIG_COMPLETA=false; return 1; }

    FISH_CONFIG_COMPLETA=false
    local instalacao="Instalado agora"
    [ "$fish_antes" = true ] && instalacao="Já estava instalado"

    tela_caixa_unica "🐟 Fish configurado" "Configuração concluída com sucesso" "A sessão será encerrada" \
        "${C_GREEN}✔${C_RESET} Fish: ${instalacao}" \
        "${C_GREEN}✔${C_RESET} Sugestões e completações ativadas" \
        "${C_GREEN}✔${C_RESET} Histórico inteligente nas setas ↑ e ↓" \
        "${C_GREEN}✔${C_RESET} Prompt com diretório e estado Git" \
        "${C_GREEN}✔${C_RESET} Atalhos: ll, la, .., ..., c e mkcd" \
        "${C_GREEN}✔${C_RESET} Boas-vindas personalizadas ativadas" \
        "${C_GREEN}✔${C_RESET} Tempo da sessão exibido ao sair" \
        "${C_GREEN}✔${C_RESET} Mensagens padrão ocultadas" \
        "${C_GREEN}✔${C_RESET} Inicialização automática habilitada" \
        "" \
        "${C_YELLOW}⚠${C_RESET} Feche a sessão do Termux após o encerramento" \
        "${C_DIM}Bash manual: MANAGER_KEEP_BASH=1 bash${C_RESET}"

    encerrar_sessao_para_aplicar_fish
}

menu_config_fish() {
    while true; do
        menu_unificado "🐟 Fish Shell" "Instalação, padrão e sugestões" "[0] Voltar" \
            "1|✨|Configuração completa|Instalar, configurar sugestões e tornar padrão" \
            "2|📦|Instalar Fish: $(status_fish)|Instalar pelo pkg do Termux" \
            "3|💡|Configurar sugestões|Autosugestões, completações e prompt" \
            "4|⭐|Tornar Fish padrão|Atual: $(status_fish_padrao)" \
            "5|🔇|Ocultar mensagens iniciais|Atual: $(status_mensagens_iniciais)" \
            "6|🔊|Restaurar mensagens iniciais|Mostrar banners novamente" \
            "7|⏱️|Tempo da sessão: $(status_tempo_sessao_fish)|Mostrar duração ao fechar o Fish" \
            "8|👋|Boas-vindas: $(status_boas_vindas_fish)|Mensagem personalizada no início" \
            "9|↩️|Restaurar Bash padrão|Voltar ao shell original" \
            "10|🧹|Limpar configurações do Fish|Preserva programas, pacotes e projetos" \
            "11|▶️|Abrir Fish agora|Iniciar uma sessão sem alterar o padrão"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) configurar_fish_completo ;;
            2) instalar_fish_shell; pause ;;
            3) configurar_sugestoes_fish; pause ;;
            4) definir_fish_padrao; pause ;;
            5) ocultar_mensagens_iniciais; pause ;;
            6) restaurar_mensagens_iniciais; pause ;;
            7) alternar_tempo_sessao_fish; pause ;;
            8) alternar_boas_vindas_fish; pause ;;
            9) restaurar_bash_padrao; pause ;;
            10) limpar_configuracoes_fish; pause ;;
            11) fish_instalado || instalar_fish_shell || { pause; continue; }; "$(caminho_fish)" ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}


