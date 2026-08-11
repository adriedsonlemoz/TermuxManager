# Módulo: settings.sh
# Manager.sh — módulo

# ============================================================================
# CONFIGURAÇÕES
# ============================================================================

estado_bool() { [ "$1" = true ] && printf 'Ativado' || printf 'Desativado'; }

alternar_config_bool() {
    local var="$1"
    if [ "${!var}" = true ]; then printf -v "$var" false; else printf -v "$var" true; fi
    salvar_config
}

menu_config_aparencia() {
    while true; do
        menu_unificado "🎨 Aparência" "Interface do Manager" "[0] Voltar"             "1|🎨|Cores: $(estado_bool "$CORES_ATIVADAS")|Realce ANSI"             "2|📝|Descrições: $(estado_bool "$DESCRICOES_ATIVADAS")|Texto abaixo das opções"             "3|✨|Ícones: $(estado_bool "$ICONES_ATIVADOS")|Símbolos nos menus"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) alternar_config_bool CORES_ATIVADAS; aplicar_cores ;;
            2) alternar_config_bool DESCRICOES_ATIVADAS ;;
            3) alternar_config_bool ICONES_ATIVADOS ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_config_caminhos() {
    while true; do
        menu_unificado "📂 Pastas e caminhos" "Estrutura atual" "[0] Voltar"             "1|📁|Painel|$(caminho_curto "$PAINEL_DIR")"             "2|📁|Projetos|$(caminho_curto "$PROJETOS_DIR")"             "3|💾|Backups de projetos|Download/projetos/backups"             "4|📥|Redetectar Downloads|Localizar pasta acessível"             "5|🔙|Restaurar caminhos padrão|Usar ~/Painel"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1|2|3) caixa_simples "📘 Caminho protegido" "A versão 1.0 mantém a estrutura em ~/Painel." "Isso evita quebrar projetos e PIDs."; pause ;;
            4) resolver_downloads_dir && ok "Downloads: $(caminho_curto "$DOWNLOADS_DIR")" || error "Downloads não encontrado."; pause ;;
            5) PAINEL_DIR="$HOME/Painel"; PROJETOS_DIR="$PAINEL_DIR/projetos"; BACKUPS_DIR="$PAINEL_DIR/backups"; setup_dirs; ok "Caminhos restaurados."; pause ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_config_importacao() {
    while true; do
        menu_unificado "📦 Importação" "Preferências de cópia" "[0] Voltar"             "1|🧹|Exclusões padrão|$EXCLUSOES_PADRAO"             "2|📍|Destino padrão|$DESTINO_IMPORTACAO_PADRAO"             "3|⚠|Conflitos|$CONFLITO_PADRAO"             "4|✅|Confirmar cópia: $(estado_bool "$CONFIRMAR_COPIA")|Revisão antes de copiar"             "5|🧽|Limpar temporários: $(estado_bool "$LIMPAR_TEMPORARIOS_AUTO")|Remover extrações antigas"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) read -rp "Padrões separados por espaço: " novo; [ -n "$novo" ] && EXCLUSOES_PADRAO="$novo"; salvar_config ;;
            2) read -rp "Destino [perguntar/painel/projetos]: " novo; [[ "$novo" =~ ^(perguntar|painel|projetos)$ ]] && DESTINO_IMPORTACAO_PADRAO="$novo"; salvar_config ;;
            3) read -rp "Conflitos [perguntar/substituir/pular/renomear]: " novo; [[ "$novo" =~ ^(perguntar|substituir|pular|renomear)$ ]] && CONFLITO_PADRAO="$novo"; salvar_config ;;
            4) alternar_config_bool CONFIRMAR_COPIA ;;
            5) alternar_config_bool LIMPAR_TEMPORARIOS_AUTO ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_config_execucao() {
    while true; do
        menu_unificado "🚀 Execução" "Comportamento dos projetos" "[0] Voltar"             "1|🌐|Abrir navegador: $(estado_bool "$ABRIR_NAVEGADOR_AUTO")|Após detectar a porta"             "2|✅|Confirmar execução: $(estado_bool "$CONFIRMAR_EXECUCAO")|Revisar antes de iniciar"             "3|📋|Log em falha: $(estado_bool "$MOSTRAR_LOG_FALHA")|Mostrar últimas linhas"             "4|🕒|Tempo de porta: ${TEMPO_DETECTAR_PORTA}s|Espera pelo frontend"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) alternar_config_bool ABRIR_NAVEGADOR_AUTO ;;
            2) alternar_config_bool CONFIRMAR_EXECUCAO ;;
            3) alternar_config_bool MOSTRAR_LOG_FALHA ;;
            4) read -rp "Segundos (5-120): " novo; [[ "$novo" =~ ^[0-9]+$ ]] && [ "$novo" -ge 5 ] && [ "$novo" -le 120 ] && TEMPO_DETECTAR_PORTA="$novo"; salvar_config ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_config_limpeza() {
    while true; do
        menu_unificado "🧹 Exclusões e limpeza" "Arquivos temporários e registros" "[0] Voltar"             "1|🧽|Limpar temporários agora|Remover extrações abandonadas"             "2|📋|Limpar logs antigos|Preservar o log atual"             "3|📦|Limite dos logs: ${LOG_MAX_MB} MB|Rotação automática"             "4|🧹|Exclusões de cópia|$EXCLUSOES_PADRAO"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) rm -rf "$TMP_ROOT"/session_* 2>/dev/null || true; mkdir -p "$SESSION_TMP_DIR"; ok "Temporários limpos."; pause ;;
            2) find "$LOG_DIR" -maxdepth 1 -type f -name '*.log.1' -delete 2>/dev/null; ok "Logs antigos removidos."; pause ;;
            3) read -rp "Limite em MB (1-100): " novo; [[ "$novo" =~ ^[0-9]+$ ]] && [ "$novo" -ge 1 ] && [ "$novo" -le 100 ] && LOG_MAX_MB="$novo" && LOG_MAX_BYTES=$((novo*1024*1024)); salvar_config ;;
            4) read -rp "Padrões separados por espaço: " novo; [ -n "$novo" ] && EXCLUSOES_PADRAO="$novo"; salvar_config ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_config_comportamento() {
    while true; do
        menu_unificado "🔔 Comportamento" "Inicialização e registros" "[0] Voltar"             "1|🔎|Diagnóstico na abertura: $(estado_bool "$DIAGNOSTICO_NA_ABERTURA")|Exibir ambiente ao iniciar"             "2|👋|Executar assistente inicial|Abrir novamente manualmente"             "3|📦|Limite dos logs: ${LOG_MAX_MB} MB|Rotação automática"             "4|⏳|Pausa de erro: ${PAUSA_ERRO_SEGUNDOS}s|Tempo antes de redesenhar"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) alternar_config_bool DIAGNOSTICO_NA_ABERTURA ;;
            2) rm -f "$FIRST_RUN_FILE"; assistente_primeira_execucao ;;
            3) read -rp "Limite em MB (1-100): " novo; [[ "$novo" =~ ^[0-9]+$ ]] && [ "$novo" -ge 1 ] && [ "$novo" -le 100 ] && LOG_MAX_MB="$novo" && LOG_MAX_BYTES=$((novo*1024*1024)); salvar_config ;;
            4) read -rp "Segundos (0-5): " novo; [[ "$novo" =~ ^[0-5]$ ]] && PAUSA_ERRO_SEGUNDOS="$novo"; salvar_config ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}


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
    command -v pkg >/dev/null 2>&1 || { error "O comando pkg não está disponível."; return 1; }
    info "Atualizando a lista de pacotes..."
    if ! pkg update -y; then
        error "Não foi possível atualizar os repositórios."
        return 1
    fi
    info "Instalando Fish..."
    if pkg install -y fish; then
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


# ============================================================================
# ATALHOS GLOBAIS DO MANAGER
# ============================================================================

manager_bin_dir() {
    printf '%s/bin' "${PREFIX:-/data/data/com.termux/files/usr}"
}

manager_atalho_path() {
    printf '%s/%s' "$(manager_bin_dir)" "$1"
}

atalho_manager_valido() {
    local nome="${1:-manager}" arquivo
    arquivo="$(manager_atalho_path "$nome")"
    [ -f "$arquivo" ] && grep -Fq "AL_MANAGER_SHORTCUT" "$arquivo" 2>/dev/null && grep -Fq "$BASE_DIR/manager.sh" "$arquivo" 2>/dev/null
}

status_atalho_manager() {
    if atalho_manager_valido manager; then printf 'Instalado'; else printf 'Não instalado'; fi
}

status_atalho_mm() {
    if atalho_manager_valido mm; then printf 'Instalado'; else printf 'Não instalado'; fi
}

criar_atalho_manager() {
    local nome="${1:-manager}" silencioso="${2:-false}" destino tmp bin_dir
    [[ "$nome" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || { error "Nome de comando inválido."; return 1; }
    bin_dir="$(manager_bin_dir)"
    destino="$bin_dir/$nome"
    mkdir -p "$bin_dir" || { error "Não foi possível acessar $bin_dir."; return 1; }

    if [ -e "$destino" ] && ! grep -Fq "AL_MANAGER_SHORTCUT" "$destino" 2>/dev/null; then
        error "O comando '$nome' já pertence a outro programa."
        return 1
    fi

    tmp="${destino}.tmp.$$"
    cat > "$tmp" <<EOF
#!${PREFIX:-/data/data/com.termux/files/usr}/bin/bash
# AL_MANAGER_SHORTCUT — gerado automaticamente pelo Manager
exec bash $(printf '%q' "$BASE_DIR/manager.sh") "\$@"
EOF
    chmod 755 "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$destino" || { rm -f "$tmp"; error "Falha ao instalar o comando '$nome'."; return 1; }
    hash -r 2>/dev/null || true
    if [ "$silencioso" != true ]; then
        ok "Atalho '$nome' instalado em $(caminho_curto "$destino")."
    else
        log "OK" "Atalho '$nome' instalado em $destino."
    fi
}

remover_atalho_manager() {
    local nome="${1:-manager}" destino
    destino="$(manager_atalho_path "$nome")"
    if [ ! -e "$destino" ]; then
        info "O atalho '$nome' não está instalado."
        return 0
    fi
    if ! grep -Fq "AL_MANAGER_SHORTCUT" "$destino" 2>/dev/null; then
        error "O comando '$nome' não foi criado pelo Manager e não será removido."
        return 1
    fi
    rm -f "$destino" && ok "Atalho '$nome' removido."
    hash -r 2>/dev/null || true
}

reparar_atalhos_existentes() {
    # Chamado após atualizações. Recria somente atalhos que já eram do Manager.
    local nome destino
    for nome in manager mm; do
        destino="$(manager_atalho_path "$nome")"
        if [ -f "$destino" ] && grep -Fq "AL_MANAGER_SHORTCUT" "$destino" 2>/dev/null; then
            criar_atalho_manager "$nome" >/dev/null 2>&1 || true
        fi
    done
}

configurar_atalho_primeira_execucao() {
    cabecalho_tela "⚡ Acesso rápido" "Abra o Manager de qualquer shell"
    caixa_simples "Comando recomendado" \
        "Use: manager" \
        "Funciona no Bash e no Fish" \
        "Não depende de alias ou arquivo de configuração do shell"
    if confirmar_acao "Criar o comando global 'manager' agora?" "s"; then
        criar_atalho_manager manager true
        if confirmar_acao "Criar também o atalho curto 'mm'?" "n"; then
            criar_atalho_manager mm true
        fi
        cabecalho_tela "✅ Acesso rápido configurado" "Comandos globais"
        caixa_simples "Atalhos disponíveis"             "Comando principal: manager"             "Atalho curto: $([ -x "$(manager_atalho_path mm)" ] && echo mm || echo não criado)"             "Funcionam no Bash e no Fish."
    fi
}

menu_atalhos_manager() {
    while true; do
        menu_unificado "⚡ Atalhos do Manager" "Comandos globais para Bash e Fish" "[0] Voltar" \
            "1|🔧|Instalar ou reparar 'manager'|Atual: $(status_atalho_manager)" \
            "2|⚡|Instalar ou reparar 'mm'|Atual: $(status_atalho_mm)" \
            "3|🔎|Verificar atalhos|Testar destino e execução" \
            "4|🗑️|Remover 'manager'|Remove apenas o atalho global" \
            "5|🗑️|Remover 'mm'|Remove apenas o atalho curto"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) criar_atalho_manager manager; pause ;;
            2) criar_atalho_manager mm; pause ;;
            3)
                cabecalho_tela "🔎 Verificação dos atalhos" "Comandos globais"
                caixa_simples "Resultado" \
                    "manager: $(status_atalho_manager)" \
                    "mm: $(status_atalho_mm)" \
                    "Destino: $(manager_bin_dir)" \
                    "Manager: $BASE_DIR/manager.sh"
                pause ;;
            4) remover_atalho_manager manager; pause ;;
            5) remover_atalho_manager mm; pause ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

# ============================================================================
# MANUTENÇÃO DO PRÓPRIO MANAGER
# ============================================================================

limpar_estado_interno_manager() {
    # Remove somente dados internos do Manager. Projetos e backups do usuário
    # permanecem intactos em ~/Painel/projetos e ~/Painel/backups.
    rm -f "$CONFIG_FILE" "$FIRST_RUN_FILE" 2>/dev/null || true
    rm -rf "$PID_DIR" "$TMP_ROOT" "$PAINEL_DIR/.manager.lock" 2>/dev/null || true
    rm -rf "$BASE_DIR/cache" "$BASE_DIR/tmp" "$BASE_DIR/.updates" 2>/dev/null || true
    rm -rf "$LOG_DIR" 2>/dev/null || true

    mkdir -p "$PID_DIR" "$TMP_ROOT" "$LOG_DIR" \
        "$BASE_DIR/cache" "$BASE_DIR/tmp" "$BASE_DIR/.updates"
    : > "$LOG_FILE"
}

restaurar_manager_instalacao_limpa() {
    cabecalho_tela "♻️ Restaurar Manager" "Voltar ao estado da primeira execução"
    caixa_simples "O que será limpo" \
        "Preferências e arquivo de configuração" \
        "Logs, cache, temporários e estado de atualização" \
        "Marcador do assistente de primeira execução" \
        "Projetos e backups serão preservados"
    echo
    confirmar_acao "Restaurar o Manager e abrir novamente o assistente inicial?" || return

    limpar_estado_interno_manager
    liberar_bloqueio

    tela_caixa_unica "♻️ Manager restaurado" \
        "Estado interno removido com segurança" \
        "O assistente inicial será aberto agora" \
        "${C_GREEN}✔${C_RESET} Preferências removidas" \
        "${C_GREEN}✔${C_RESET} Logs e temporários limpos" \
        "${C_GREEN}✔${C_RESET} Projetos preservados" \
        "${C_GREEN}✔${C_RESET} Backups preservados"
    sleep 1

    # Substitui o processo atual por uma nova execução limpa, evitando duas
    # instâncias simultâneas e retornando diretamente à primeira configuração.
    exec bash "$SELF_PATH"
}

desinstalar_manager_completamente() {
    cabecalho_tela "🗑️ Desinstalar Manager" "Remover o aplicativo do Termux"
    caixa_simples "Será removido" \
        "Pasta do Manager: $BASE_DIR" \
        "Preferências, logs e temporários internos" \
        "Marcador de primeira execução" \
        "Projetos e backups do Painel serão preservados"
    echo
    warn "Depois disso, o comando do Manager deixará de existir."
    read -rp "Digite DESINSTALAR para confirmar: " confirmacao
    if [ "$confirmacao" != "DESINSTALAR" ]; then
        info "Cancelado. Nada foi removido."
        pause
        return
    fi

    local helper_base helper
    helper_base="${TMPDIR:-$HOME/.cache}"
    mkdir -p "$helper_base"
    helper="$helper_base/manager_desinstalar_$$.sh"

    cat > "$helper" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
sleep 1
rm -rf -- $(printf '%q' "$BASE_DIR")
rm -f -- $(printf '%q' "$FIRST_RUN_FILE")
rm -rf -- $(printf '%q' "$PID_DIR") $(printf '%q' "$TMP_ROOT") $(printf '%q' "$LOG_DIR")
rm -f -- $(printf '%q' "$CONFIG_FILE")
for atalho in $(printf '%q' "$(manager_atalho_path manager)") $(printf '%q' "$(manager_atalho_path mm)"); do
    if [ -f "\$atalho" ] && grep -Fq "AL_MANAGER_SHORTCUT" "\$atalho" 2>/dev/null; then
        rm -f -- "\$atalho"
    fi
done
rm -f -- "\$0"
EOF
    chmod 700 "$helper"

    tela_caixa_unica "🗑️ Desinstalação preparada" \
        "O Manager será removido ao sair" \
        "Seus projetos e backups continuarão no Painel" \
        "${C_GREEN}✔${C_RESET} Processo auxiliar criado" \
        "${C_GREEN}✔${C_RESET} Projetos preservados" \
        "${C_GREEN}✔${C_RESET} Backups preservados" \
        "${C_YELLOW}➜${C_RESET} Reinstale extraindo um novo ZIP em ~/scripts/manager"

    liberar_bloqueio
    nohup bash "$helper" >/dev/null 2>&1 &
    trap - EXIT INT TERM
    exit 0
}

menu_manutencao_manager() {
    while true; do
        menu_unificado "🛠️ Manutenção do Manager" "Restauração e desinstalação" \
            "[0] Voltar  •  [1–2] Selecionar" \
            "1|♻️|Restaurar instalação|Limpa ajustes e abre o assistente inicial" \
            "2|🗑️|Desinstalar Manager|Remove o aplicativo e preserva projetos"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) restaurar_manager_instalacao_limpa ;;
            2) desinstalar_manager_completamente ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

restaurar_config_padrao() {
    confirmar_acao "Restaurar preferências sem apagar projetos ou backups?" || return
    CORES_ATIVADAS=true; DESCRICOES_ATIVADAS=true; ICONES_ATIVADOS=true
    ABRIR_NAVEGADOR_AUTO=true; CONFIRMAR_EXECUCAO=true; MOSTRAR_LOG_FALHA=true
    DIAGNOSTICO_NA_ABERTURA=false; LIMPAR_TEMPORARIOS_AUTO=true
    TEMPO_DETECTAR_PORTA=15; PAUSA_ERRO_SEGUNDOS=1; LOG_MAX_MB=5
    DESTINO_IMPORTACAO_PADRAO="perguntar"; CONFLITO_PADRAO="perguntar"; CONFIRMAR_COPIA=true
    EXCLUSOES_PADRAO="node_modules .git dist build"
    LOG_MAX_BYTES=$((LOG_MAX_MB*1024*1024)); aplicar_cores; salvar_config
    ok "Configurações restauradas."; pause
}

menu_configuracoes() {
    while true; do
        menu_unificado "🧰 Configurações" "Preferências do Manager" "[0] Voltar  •  [1–12] Selecionar"             "1|🎨|Aparência|Cores, descrições e ícones"             "2|📂|Pastas e caminhos|Painel, projetos e Downloads"             "3|📦|Importação|Exclusões, destino e conflitos"             "4|🚀|Execução de projetos|Navegador, porta e logs"             "5|🧹|Exclusões e limpeza|Temporários e logs"             "6|🔔|Comportamento|Inicialização e confirmações"             "7|🐟|Fish Shell|Instalar, usar como padrão e ativar sugestões"             "8|🔄|Restaurar padrões|Não apaga projetos"             "9|🩺|Central de Diagnóstico|Manager, projetos, Termux e exportação segura"             "10|🧹|Limpeza do Painel|Projeto individual, pasta projetos ou Painel inteiro"             "11|🛠️|Manutenção do Manager|Restaurar ou desinstalar o aplicativo"             "12|⚡|Atalhos do Manager|Instalar manager ou mm para Bash e Fish"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) menu_config_aparencia ;;
            2) menu_config_caminhos ;;
            3) menu_config_importacao ;;
            4) menu_config_execucao ;;
            5) menu_config_limpeza ;;
            6) menu_config_comportamento ;;
            7) menu_config_fish ;;
            8) restaurar_config_padrao ;;
            9) menu_central_diagnosticos ;;
            10) menu_exclusao_painel ;;
            11) menu_manutencao_manager ;;
            12) menu_atalhos_manager ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

# Apaga TODO o conteúdo de ~/Painel (projetos, arquivos soltos, backups e
# configurações) e recria a estrutura de pastas vazia. Ação destrutiva e
# irreversível — exige duas confirmações antes de executar.
excluir_painel_inteiro() {
    title "⚠  Excluir TODA a pasta Painel"
    local qtd_projetos qtd_arquivos qtd_backups tamanho
    qtd_projetos=$(find "$PAINEL_DIR" -mindepth 1 -maxdepth 2 -type f \( -name package.json -o -name pyproject.toml -o -name composer.json -o -name go.mod \) -printf '%h\n' 2>/dev/null | sort -u | wc -l | tr -d ' ')
    qtd_arquivos=$(find "$PAINEL_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    qtd_backups=$(find "$BACKUPS_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    tamanho=$(du -sh "$PAINEL_DIR" 2>/dev/null | cut -f1)
    caixa_simples "Resumo da exclusão" "Projetos: ${qtd_projetos:-0}" "Arquivos: ${qtd_arquivos:-0}" "Backups: ${qtd_backups:-0}" "Tamanho: ${tamanho:-0}"
    warn "Essa ação NÃO pode ser desfeita."
    echo
    read -rp "Para confirmar, digite EXCLUIR (em maiúsculas): " conf
    if [ "$conf" != "EXCLUIR" ]; then
        info "Cancelado. Nada foi apagado."
        pause
        return
    fi
    read -rp "Tem certeza mesmo? Essa é a última confirmação. (s/N): " conf2
    if [[ ! "$conf2" =~ ^[sS]$ ]]; then
        info "Cancelado. Nada foi apagado."
        pause
        return
    fi

    garantir_cwd_fora_do_alvo "$PAINEL_DIR" || { error "Não foi possível mover o terminal para um diretório seguro."; pause; return 1; }
    rm -rf "${PAINEL_DIR:?}"
    setup_dirs
    restaurar_bloqueio_atual
    CORES_ATIVADAS=true
    EXCLUSOES_PADRAO="node_modules .git dist build"
    DESCRICOES_ATIVADAS=true; ICONES_ATIVADOS=true; ABRIR_NAVEGADOR_AUTO=true
    CONFIRMAR_EXECUCAO=true; MOSTRAR_LOG_FALHA=true; DIAGNOSTICO_NA_ABERTURA=false
    LIMPAR_TEMPORARIOS_AUTO=true; TEMPO_DETECTAR_PORTA=15; PAUSA_ERRO_SEGUNDOS=1
    LOG_MAX_MB=5; LOG_MAX_BYTES=$((5*1024*1024))
    DESTINO_IMPORTACAO_PADRAO="perguntar"; CONFLITO_PADRAO="perguntar"; CONFIRMAR_COPIA=true
    aplicar_cores
    salvar_config
    log "INFO" "Pasta Painel inteira excluída e recriada pelo usuário (Configurações)."
    ok "Pasta Painel foi apagada e recriada vazia."
    pause
}

