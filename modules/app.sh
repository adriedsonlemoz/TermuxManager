# Módulo: app.sh
# Manager.sh — módulo


# ============================================================================
# SOBRE O MANAGER
# ============================================================================

abrir_repositorio_manager() {
    if command -v termux-open-url >/dev/null 2>&1; then
        termux-open-url "$MANAGER_REPOSITORY" >/dev/null 2>&1 &
        ok "Repositório aberto no navegador."
    else
        warn "O comando termux-open-url não está disponível."
        info "$MANAGER_REPOSITORY"
    fi
    sleep 1
}

mostrar_changelog_manager() {
    local arquivo="$BASE_DIR/CHANGELOG.md"
    if [ ! -r "$arquivo" ]; then
        cabecalho_tela "📝 Histórico de versões" "Manager $MANAGER_VERSION"
        warn "CHANGELOG.md não encontrado."
        pause
        return
    fi

    local -a linhas=()
    mapfile -t linhas < "$arquivo"
    local total=${#linhas[@]}
    local altura pagina=0 por_pagina inicio fim i resposta total_paginas
    altura=$(tput lines 2>/dev/null || echo 24)
    por_pagina=$((altura - 9))
    [ "$por_pagina" -lt 8 ] && por_pagina=8
    [ "$por_pagina" -gt 24 ] && por_pagina=24
    total_paginas=$(((total + por_pagina - 1) / por_pagina))
    [ "$total_paginas" -lt 1 ] && total_paginas=1

    while true; do
        inicio=$((pagina * por_pagina))
        fim=$((inicio + por_pagina))
        [ "$fim" -gt "$total" ] && fim=$total

        cabecalho_tela "📝 Histórico de versões" "Página $((pagina + 1)) de $total_paginas"
        for ((i=inicio; i<fim; i++)); do
            printf '%s\n' "${linhas[$i]}"
        done
        echo
        separador
        if [ "$total_paginas" -eq 1 ]; then
            echo -e "${C_DIM}[Q] Voltar para a página Sobre${C_RESET}"
        else
            echo -e "${C_DIM}[ENTER/N] Próxima  •  [A] Anterior  •  [Q] Voltar${C_RESET}"
        fi
        ui_buffer_flush
        read -r -p "> " resposta
        case "${resposta,,}" in
            q|0) return ;;
            a|p)
                [ "$pagina" -gt 0 ] && pagina=$((pagina - 1))
                ;;
            ""|n)
                if [ "$pagina" -lt $((total_paginas - 1)) ]; then
                    pagina=$((pagina + 1))
                else
                    return
                fi
                ;;
            *) ;;
        esac
    done
}

menu_sobre_manager() {
    while true; do
        local shell_atual comando_manager status_atalho repo_curto config_curta base_curta
        shell_atual="$(basename "${SHELL:-desconhecido}")"
        comando_manager="$(command -v manager 2>/dev/null || true)"
        if [ -n "$comando_manager" ]; then
            status_atalho="Ativo"
        else
            status_atalho="Não instalado"
        fi

        detectar_variante_termux
        repo_curto="adriedsonlemoz/TermuxManager"
        base_curta="$(caminho_curto "$BASE_DIR")"
        config_curta="$(caminho_curto "${CONFIG_FILE:-não definida}")"

        # Não usa menu_unificado aqui: ele chama cabecalho_tela novamente e
        # apagava as caixas de informações que acabavam de ser desenhadas.
        cabecalho_tela "📘 Sobre o Manager" "Informações, ambiente e suporte"
        caixa_linha_topo
        caixa_linha_texto "${C_BOLD}IDENTIDADE${C_RESET}" true
        caixa_linha_sep
        caixa_linha_texto "Manager.sh  •  versão $MANAGER_VERSION"
        caixa_linha_texto "Canal: $MANAGER_CHANNEL"
        caixa_linha_texto "Desenvolvedor: $MANAGER_DEVELOPER"
        caixa_linha_sep
        caixa_linha_texto "${C_BOLD}PROJETO${C_RESET}" true
        caixa_linha_sep
        caixa_linha_texto "Gerenciador de projetos para Termux"
        caixa_linha_texto "GitHub: $repo_curto"
        caixa_linha_texto "Licença: $MANAGER_LICENSE"
        caixa_linha_sep
        caixa_linha_texto "${C_BOLD}INSTALAÇÃO ATUAL${C_RESET}" true
        caixa_linha_sep
        caixa_linha_texto "Diretório: $base_curta"
        caixa_linha_texto "Shell: $shell_atual"
        caixa_linha_texto "Comando manager: $status_atalho"
        caixa_linha_texto "Origem do Termux: $(termux_origem_resumida)"
        caixa_linha_texto "Repositório APT: $(termux_repositorio_resumido)"
        caixa_linha_texto "Configuração: $config_curta"
        caixa_linha_sep
        caixa_linha_texto "${C_BOLD}AÇÕES${C_RESET}" true
        caixa_linha_sep
        caixa_linha_texto "[1] 🌐 Abrir repositório no GitHub"
        caixa_linha_texto "[2] 📝 Ver histórico de versões"
        caixa_linha_texto "[3] 📋 Mostrar endereço completo"
        caixa_linha_texto "[0] ↩  Voltar ao menu principal"
        caixa_linha_baixo
        rodape_atalhos "[0] Voltar  •  [1–3] Selecionar"

        ler_opcao
        case "$RESPOSTA_MENU" in
            1) abrir_repositorio_manager ;;
            2) mostrar_changelog_manager ;;
            3)
                cabecalho_tela "🌐 Repositório oficial" "TermuxManager"
                caixa_simples "GitHub" "$MANAGER_REPOSITORY"
                pause
                ;;
            0) return ;;
            *) warn "Opção inválida."; pause ;;
        esac
    done
}


# ============================================================================
# CONFIRMAÇÃO PÓS-ATUALIZAÇÃO
# ============================================================================

arquivo_confirmacao_atualizacao_exibida() {
    printf '%s' "$BASE_DIR/.updates/last-update-shown"
}

mostrar_confirmacao_pos_atualizacao() {
    local historico exibido_arquivo
    historico="$(arquivo_status_atualizacao)"
    exibido_arquivo="$(arquivo_confirmacao_atualizacao_exibida)"
    [ -f "$historico" ] || return 0

    local data="" arquivo="" anterior="" nova="" status="" backup=""
    while IFS='=' read -r chave valor; do
        valor="${valor%\"}"; valor="${valor#\"}"
        case "$chave" in
            DATA) data="$valor" ;;
            ARQUIVO) arquivo="$valor" ;;
            VERSAO_ANTERIOR) anterior="$valor" ;;
            VERSAO_NOVA) nova="$valor" ;;
            STATUS) status="$valor" ;;
            BACKUP) backup="$valor" ;;
        esac
    done < "$historico"

    [ "$status" = "confirmada" ] || return 0
    [ "$nova" = "$MANAGER_VERSION" ] || return 0

    local token exibido=""
    token="${nova}|${data}|${arquivo}"
    [ -f "$exibido_arquivo" ] && IFS= read -r exibido < "$exibido_arquivo"
    [ "$exibido" = "$token" ] && return 0

    cabecalho_tela "✅ Atualização aplicada" "A nova versão está em execução"
    caixa_simples "Confirmação de inicialização" \
        "Versão: ${anterior:-?} → ${nova}" \
        "Pacote: ${arquivo:-não informado}" \
        "Data: ${data:-não registrada}" \
        "Reinício: concluído" \
        "Execução: Manager ${MANAGER_VERSION} ativo"
    if [ -n "$backup" ]; then
        echo
        caixa_simples "Backup de segurança" "$backup"
    fi
    echo
    caixa_simples "Teste concluído" \
        "Atualização concluída." \
        "Reinício confirmado." \
        "Saída do terminal restaurada." \
        "Este aviso aparece uma única vez."
    pause

    mkdir -p "$(dirname "$exibido_arquivo")"
    printf '%s\n' "$token" > "$exibido_arquivo"
}

# ============================================================================
# MENU PRINCIPAL
# ============================================================================

menu_projetos_hub() {
    while true; do
        limpar_pidfiles_inativos
        local ativos=0 pf
        for pf in "$PID_DIR"/*.pid; do
            [ -e "$pf" ] && pid_ativo "$pf" && ativos=$((ativos + 1))
        done

        menu_unificado "📁 PROJETOS" "Gerenciar, importar e acompanhar" \
            "[0] Voltar  •  [1–3] Selecionar" \
            "1|📂|Meus projetos|Abrir, testar e organizar" \
            "2|📦|Importar projeto|Pasta, arquivo ou ZIP" \
            "3|🚦|Em execução|$ativos componente(s) ativo(s)"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) gerenciar_projetos ;;
            2) importar_projeto ;;
            3) menu_processos_ativos ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

menu_ambiente_hub() {
    while true; do
        detectar_variante_termux
        menu_unificado "🛠️ AMBIENTE E FERRAMENTAS" "Termux, pacotes e diagnóstico" \
            "[0] Voltar  •  [1–3] Selecionar" \
            "1|🧰|Instalar ferramentas|Ambientes de desenvolvimento" \
            "2|🔧|Ambiente Termux|Atualizar e manter o Termux" \
            "3|🔎|Diagnóstico rápido|$(termux_origem_resumida)"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) menu_instalar_ferramentas ;;
            2) menu_ambiente_termux ;;
            3) verificar_ambiente_termux ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

menu_manager_hub() {
    while true; do
        menu_unificado "⚙️ MANAGER" "Configuração, atualização e suporte" \
            "[0] Voltar  •  [1–4] Selecionar" \
            "1|🔄|Atualizar Manager|GitHub main ou arquivo local" \
            "2|⚙️|Configurações|Preferências e manutenção" \
            "3|📘|Sobre|Versão, ambiente e desenvolvedor" \
            "4|❓|Ajuda|Instalação, atualização e problemas"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) atualizar_manager_local ;;
            2) menu_configuracoes ;;
            3) menu_sobre_manager ;;
            4) menu_ajuda ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

menu_ajuda_sobre_hub() {
    while true; do
        menu_unificado "❓ AJUDA E SOBRE" "Manual, versão e informações do Manager" \
            "[0] Voltar  •  [1–2] Selecionar" \
            "1|❓|Ajuda|Instalação e problemas" \
            "2|📘|Sobre|Versão, ambiente e desenvolvedor"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) menu_ajuda ;;
            2) menu_sobre_manager ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

menu_principal() {
    while true; do
        limpar_pidfiles_inativos
        detectar_variante_termux

        local ativos=0 projetos=0 pf resumo_status
        for pf in "$PID_DIR"/*.pid; do
            [ -e "$pf" ] && pid_ativo "$pf" && ativos=$((ativos + 1))
        done
        if [ -d "$PROJETOS_DIR" ]; then
            projetos="$(find "$PROJETOS_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | wc -l | tr -d ' ')"
        fi
        projetos="${projetos:-0}"
        resumo_status="$(termux_origem_resumida) • Projetos: $projetos • Ativos: $ativos"

        menu_unificado "🧰 MANAGER.SH — VERSÃO $MANAGER_VERSION" "$resumo_status" \
            "[0] Sair  •  [1–8] Selecionar" \
            "1|📁|Gerenciar projetos|Abrir, testar e organizar" \
            "2|🚦|Em execução|$ativos componente(s) ativo(s)" \
            "3|📦|Importar projeto|Pasta, arquivo ou ZIP" \
            "4|🐧|Linux no celular|Distros, PRoot e Termux:X11" \
            "5|🛠️|Ambiente e ferramentas|Termux e pacotes" \
            "6|🔄|Atualizar Manager|GitHub main ou arquivo local" \
            "7|⚙️|Configurações|Preferências e manutenção" \
            "8|❓|Ajuda e Sobre|Manual, versão e desenvolvedor"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) gerenciar_projetos ;;
            2) menu_processos_ativos ;;
            3) importar_projeto ;;
            4) menu_linux_celular ;;
            5) menu_ambiente_hub ;;
            6) atualizar_manager_local ;;
            7) menu_configuracoes ;;
            8) menu_ajuda_sobre_hub ;;
            0) echo -e "${C_GREEN}Até mais!${C_RESET}"; exit 0 ;;
            *) warn "Opção inválida."; pause ;;
        esac
    done
}

# ============================================================================
# PONTO DE ENTRADA
# ============================================================================

main() {
    garantir_cwd_existente || { printf 'Erro: não foi possível recuperar um diretório de trabalho válido.\n' >&2; exit 1; }
    setup_dirs
    inicializar_diagnosticos
    ativar_captura_diagnosticos
    carregar_config
    detectar_terminal
    adquirir_bloqueio || { pause; exit 1; }
    limpar_temporarios_antigos
    trap finalizar_manager EXIT
    trap 'echo; warn "Operação interrompida fora de uma instalação monitorada."; exit 130' INT
    trap 'echo; warn "Sessão encerrada pelo sistema."; exit 143' TERM
    check_base_packages
    rotacionar_log "$LOG_FILE"
    log "INFO" "===== manager.sh v$MANAGER_VERSION iniciado ====="
    assistente_primeira_execucao
    mostrar_confirmacao_pos_atualizacao
    [ "$DIAGNOSTICO_NA_ABERTURA" = true ] && verificar_ambiente_termux
    # Garante uma transição limpa mesmo se o assistente ou o apt tiverem
    # alterado cursor, rolagem, quebra de linha ou tela alternativa.
    restaurar_terminal_manager
    menu_principal
}

