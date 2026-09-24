# Módulo: termux_packages_actions.sh
# Ações públicas de atualização, ambiente e instalação de pacotes.

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
