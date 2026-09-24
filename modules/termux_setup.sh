# Módulo: termux_setup.sh
# Manutenção do Termux e assistente de primeira execução.

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

