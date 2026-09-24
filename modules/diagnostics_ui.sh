# Módulo: diagnostics_ui.sh
# Menus e apresentação da Central de Diagnóstico.

selecionar_erro_arquivo() {
    local categoria="$1" arquivo="$2" nome_exibido="$3" nome_saida="$4"
    local -a linhas=() textos=()
    local registro numero conteudo i escolha

    while IFS= read -r registro; do
        [ -n "$registro" ] || continue
        numero="${registro%%:*}"
        conteudo="${registro#*:}"
        linhas+=("$numero")
        textos+=("$conteudo")
    done < <(listar_correspondencias_erro "$arquivo" 25)

    while true; do
        detectar_terminal
        cabecalho_tela "🧩 Erros detectados" "$nome_exibido"
        if [ "${#linhas[@]}" -eq 0 ]; then
            caixa_simples "Nenhum padrão de erro reconhecido" \
                "O log existe, mas não contém palavras de erro conhecidas." \
                "Você ainda pode exportar o arquivo completo." \
                "Tamanho: $(tamanho_legivel_arquivo "$arquivo")"
        else
            caixa_diagnostico_inicio "Selecione um registro"
            for ((i=0; i<${#linhas[@]}; i++)); do
                linha_diagnostico "$((i+1))) Linha ${linhas[$i]} — $(truncar_visivel "${textos[$i]}" $((LARGURA_CAIXA - 18)))"
            done
            caixa_diagnostico_fim
        fi
        caixa_simples "Ações" \
            "[A] Exportar o log completo" \
            "[0] Voltar" \
            "Os relatórios são copiados para Downloads."
        rodape_atalhos "[número] Exportar erro  •  [A] Log completo  •  [0] Voltar"
        ui_buffer_flush
        read -r escolha
        case "${escolha,,}" in
            0) return ;;
            a) exportar_trecho_diagnostico "$categoria" "$arquivo" 0 "$nome_saida" ;;
            *)
                if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le "${#linhas[@]}" ]; then
                    exportar_trecho_diagnostico "$categoria" "$arquivo" "${linhas[$((escolha-1))]}" "$nome_saida"
                else
                    feedback_curto "Opção inválida."
                fi
                ;;
        esac
    done
}

menu_erros_manager() {
    local -a arquivos=() nomes=()
    local f escolha i erros
    while true; do
        arquivos=(); nomes=()
        [ -s "$MANAGER_INCIDENT_INDEX" ] && arquivos+=("$MANAGER_INCIDENT_INDEX") && nomes+=("Índice de falhas técnicas")
        [ -s "$LOG_FILE" ] && arquivos+=("$LOG_FILE") && nomes+=("Log principal do Manager")
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            arquivos+=("$f")
            nomes+=("Incidente $(basename "$f" .txt | sed 's/^erro-//')")
        done < <(find "$MANAGER_INCIDENT_DIR" -maxdepth 1 -type f -name 'erro-*.txt' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 20 | cut -d' ' -f2-)

        cabecalho_tela "🧠 Erros do Manager" "Falhas internas e mensagens registradas"
        if [ "${#arquivos[@]}" -eq 0 ]; then
            caixa_simples "Nenhum registro disponível" "O Manager ainda não registrou erros técnicos."
        else
            caixa_diagnostico_inicio "Registros disponíveis"
            for ((i=0; i<${#arquivos[@]}; i++)); do
                erros="$(contar_erros_arquivo "${arquivos[$i]}")"
                linha_diagnostico "$((i+1))) ${nomes[$i]}"
                linha_diagnostico "   ${erros} ocorrência(s) • $(tamanho_legivel_arquivo "${arquivos[$i]}") • $(data_arquivo_curta "${arquivos[$i]}")" "$C_DIM"
            done
            caixa_diagnostico_fim
        fi
        rodape_atalhos "[número] Abrir  •  [0] Voltar"
        ui_buffer_flush
        read -r escolha
        [ "$escolha" = 0 ] && return
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le "${#arquivos[@]}" ]; then
            i=$((escolha-1))
            selecionar_erro_arquivo "Manager" "${arquivos[$i]}" "${nomes[$i]}" "manager-${nomes[$i]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}

menu_logs_projetos() {
    local -a arquivos=() nomes=()
    local f escolha i erros
    while true; do
        arquivos=(); nomes=()
        while IFS= read -r f; do
            [ -f "$f" ] || continue
            arquivos+=("$f")
            nomes+=("$(basename "$f" .log)")
        done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' ! -name 'manager.log' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

        cabecalho_tela "🚀 Logs de projetos" "Frontend, backend e processos executados"
        if [ "${#arquivos[@]}" -eq 0 ]; then
            caixa_simples "Nenhum log de projeto" \
                "Execute um projeto pelo Manager para gerar registros." \
                "Somente logs existentes aparecem nesta lista."
        else
            caixa_diagnostico_inicio "Projetos registrados"
            for ((i=0; i<${#arquivos[@]}; i++)); do
                erros="$(contar_erros_arquivo "${arquivos[$i]}")"
                linha_diagnostico "$((i+1))) ${nomes[$i]}"
                linha_diagnostico "   ${erros} erro(s) reconhecido(s) • $(tamanho_legivel_arquivo "${arquivos[$i]}") • $(data_arquivo_curta "${arquivos[$i]}")" "$C_DIM"
            done
            caixa_diagnostico_fim
        fi
        rodape_atalhos "[número] Abrir  •  [0] Voltar"
        ui_buffer_flush
        read -r escolha
        [ "$escolha" = 0 ] && return
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le "${#arquivos[@]}" ]; then
            i=$((escolha-1))
            selecionar_erro_arquivo "Projeto" "${arquivos[$i]}" "${nomes[$i]}" "projeto-${nomes[$i]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}

menu_logs_termux() {
    local -a arquivos=() nomes=()
    local snapshot escolha i erros
    while true; do
        arquivos=(); nomes=()
        snapshot="$(gerar_snapshot_termux)"
        arquivos+=("$snapshot"); nomes+=("Diagnóstico atual do Termux")
        [ -s "${TERMUX_SETUP_LOG:-}" ] && arquivos+=("$TERMUX_SETUP_LOG") && nomes+=("Instalações e atualizações do pkg")
        [ -s "${TERMUX_DIAGNOSTIC_LOG:-}" ] && arquivos+=("$TERMUX_DIAGNOSTIC_LOG") && nomes+=("Último diagnóstico de falha do pkg")

        cabecalho_tela "📱 Diagnóstico do Termux" "Pacotes, ambiente e falhas do sistema"
        caixa_diagnostico_inicio "Fontes disponíveis"
        for ((i=0; i<${#arquivos[@]}; i++)); do
            erros="$(contar_erros_arquivo "${arquivos[$i]}")"
            linha_diagnostico "$((i+1))) ${nomes[$i]}"
            linha_diagnostico "   ${erros} ocorrência(s) • $(tamanho_legivel_arquivo "${arquivos[$i]}") • $(data_arquivo_curta "${arquivos[$i]}")" "$C_DIM"
        done
        caixa_diagnostico_fim
        caixa_simples "Limite" \
            "Esta área cobre o ambiente do Termux e o sistema de pacotes." \
            "Logs internos do Android (logcat) exigem permissões externas."
        rodape_atalhos "[número] Abrir  •  [0] Voltar"
        ui_buffer_flush
        read -r escolha
        [ "$escolha" = 0 ] && return
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le "${#arquivos[@]}" ]; then
            i=$((escolha-1))
            selecionar_erro_arquivo "Termux" "${arquivos[$i]}" "${nomes[$i]}" "termux-${nomes[$i]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}


status_central_diagnosticos() {
    local incidentes projetos tamanho
    incidentes=$(find "$MANAGER_INCIDENT_DIR" -maxdepth 1 -type f -name 'erro-*.txt' 2>/dev/null | wc -l | tr -d ' ')
    projetos=$(find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' ! -name manager.log 2>/dev/null | wc -l | tr -d ' ')
    tamanho=$(du -sh "$LOG_DIR" "${BASE_DIR:-$HOME/scripts/manager}/logs" 2>/dev/null | awk '{s=s " " $1} END {gsub(/^ /, "", s); print s}')
    caixa_simples "Resumo atual" \
        "Incidentes internos: ${incidentes:-0}" \
        "Logs de projetos: ${projetos:-0}" \
        "Log do Termux: $([ -s "${TERMUX_SETUP_LOG:-}" ] && printf 'disponível' || printf 'vazio')" \
        "Espaço usado: ${tamanho:-0 B}"
}

limpar_registros_diagnosticos() {
    cabecalho_tela "🧹 Limpar diagnósticos" "Projetos e configurações serão preservados"
    caixa_simples "Será removido" \
        "• Incidentes técnicos capturados" \
        "• Logs de projetos em ~/Painel/.logs" \
        "• Logs de operações do pkg" \
        "• Diagnósticos temporários" \
        "Não remove projetos, pacotes ou configurações."
    confirmar_acao "Deseja apagar todos os registros de diagnóstico?" || return
    find "$LOG_DIR" -maxdepth 1 -type f -name '*.log*' -delete 2>/dev/null || true
    rm -rf "$DIAGNOSTICS_DIR" 2>/dev/null || true
    rm -f "${TERMUX_SETUP_LOG:-}" "${TERMUX_DIAGNOSTIC_LOG:-}" 2>/dev/null || true
    setup_dirs
    inicializar_diagnosticos
    ok "Registros de diagnóstico removidos."
    pause
}

menu_central_diagnosticos() {
    inicializar_diagnosticos
    while true; do
        menu_unificado "🩺 Central de Diagnóstico" "Erros separados por origem e exportação para Downloads" "[0] Voltar  •  [1–9] Selecionar" \
            "1|🧠|Erros do Manager|Falhas internas, comandos e mensagens registradas" \
            "2|🚀|Erros dos projetos|Frontend, backend e demais processos" \
            "3|📱|Erros do Termux|pkg, dpkg, ambiente e armazenamento" \
            "4|📤|Exportar todos os relatórios|Arquivos separados em manager, projetos e termux" \
            "5|📦|Pacote completo de suporte|Todos os relatórios compactados em um arquivo" \
            "6|📊|Resumo dos registros|Quantidade, disponibilidade e espaço usado" \
            "7|🧹|Limpar diagnósticos|Preserva projetos, pacotes e configurações" \
            "8|📱|Diagnóstico do Android|CPU, RAM, térmica, bateria e processos via Shizuku" \
            "9|💾|Teste de armazenamento|Velocidade de escrita e cópia em relatório separado"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) menu_erros_manager ;;
            2) menu_logs_projetos ;;
            3) menu_logs_termux ;;
            4) exportar_todos_relatorios ;;
            5) exportar_pacote_diagnostico_completo ;;
            6) cabecalho_tela "📊 Resumo dos diagnósticos" "Estado atual"; status_central_diagnosticos; pause ;;
            7) limpar_registros_diagnosticos ;;
            8) coletar_android_shizuku ;;
            9) teste_armazenamento_android ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
