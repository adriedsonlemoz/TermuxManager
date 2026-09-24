# Submódulo: updater_ui.sh
# Histórico, seleção e menu de atualização.

mostrar_ultima_atualizacao_manager() {
    local historico
    historico="$(arquivo_status_atualizacao)"
    cabecalho_tela "🕘 Última atualização" "Registro local do Manager"
    if [ ! -f "$historico" ]; then
        caixa_simples "Nenhum registro" "Ainda não há atualização confirmada pelo menu."
        pause
        return
    fi
    local data="" tipo="" arquivo="" anterior="" nova="" destino="" status=""
    while IFS='=' read -r chave valor; do
        valor="${valor%\"}"; valor="${valor#\"}"
        case "$chave" in
            DATA) data="$valor" ;;
            TIPO) tipo="$valor" ;;
            ARQUIVO) arquivo="$valor" ;;
            VERSAO_ANTERIOR) anterior="$valor" ;;
            VERSAO_NOVA) nova="$valor" ;;
            DESTINO) destino="$valor" ;;
            STATUS) status="$valor" ;;
        esac
    done < "$historico"
    caixa_simples "✅ Atualização registrada" \
        "Data: ${data:-não registrada}" \
        "Tipo: ${tipo:-não informado}" \
        "Arquivo: ${arquivo:-não informado}" \
        "Destino: ${destino:-pacote completo}" \
        "Versão: ${anterior:-?} → ${nova:-?}" \
        "Status: ${status:-desconhecido}"
    pause
}


selecionar_atualizacao_lista() {
    local titulo="$1" descricao="$2"
    if [ ${#ATUALIZACOES_ENCONTRADAS[@]} -eq 0 ]; then
        cabecalho_tela "$titulo" "$descricao"
        caixa_simples "📭 Nenhum arquivo encontrado" \
            "Coloque o arquivo correto na pasta Download." \
            "Depois volte a esta opção."
        pause
        return 1
    fi
    cabecalho_tela "$titulo" "$descricao"
    caixa_linha_topo
    local i=1 arquivo tipo
    for arquivo in "${ATUALIZACOES_ENCONTRADAS[@]}"; do
        [[ "${arquivo,,}" == *.zip ]] && tipo="Pacote completo" || tipo="Arquivo individual"
        menu_opcao "$i" "📦" "$(basename "$arquivo")" "$tipo • versão $(versao_nome_pacote "$arquivo") • $(data_arquivo_manager "$arquivo")"
        i=$((i+1))
    done
    caixa_linha_baixo
    rodape_atalhos "[0] Voltar  •  [número] Selecionar"
    ler_opcao
    [ "$RESPOSTA_MENU" = 0 ] && return 1
    [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] || { feedback_curto "Opção inválida."; return 1; }
    [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#ATUALIZACOES_ENCONTRADAS[@]} ] || { feedback_curto "Opção inválida."; return 1; }
    ATUALIZACAO_ESCOLHIDA="${ATUALIZACOES_ENCONTRADAS[$((RESPOSTA_MENU-1))]}"
}


atualizar_manager_local() {
    while true; do
        menu_unificado "🔄 Atualizar Manager" "GitHub main ou arquivo local"             "[0] Voltar  •  [1–4] Selecionar"             "1|🌐|Verificar no GitHub|Comparar com a main"             "2|📦|Atualizar por ZIP|Pacote salvo em Downloads"             "3|🧩|Atualizar um módulo|Substituir um arquivo .sh"             "4|🕘|Ver última atualização|Data, arquivo e status"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1)
                GITHUB_UPDATE_INTERACTIVE=true
                github_status_render "🌐 Atualização pelo GitHub" \
                    "Branch: $MANAGER_GITHUB_BRANCH • versão instalada: $MANAGER_VERSION" \
                    "⏳ Abrindo conexão..." "Aguarde: nenhuma alteração será feita sem validação."
                sleep 0.15
                ATUALIZACAO_TIPO="github-main"
                verificar_atualizacao_github
                ATUALIZACAO_TIPO=""
                ;;
            2)
                if ! check_storage_access; then pause; continue; fi
                ATUALIZACAO_TIPO="completa-local"
                listar_pacotes_completos
                selecionar_atualizacao_lista "📦 Atualização completa" "Qualquer .zip válido do Manager no Download" || { ATUALIZACAO_TIPO=""; continue; }
                instalar_pacote_manager "$ATUALIZACAO_ESCOLHIDA"
                ATUALIZACAO_TIPO=""
                ;;
            3)
                if ! check_storage_access; then pause; continue; fi
                listar_modulos_atualizacao
                selecionar_atualizacao_lista "🧩 Atualizar um módulo" "Procura manager.sh ou arquivos .sh compatíveis" || continue
                instalar_modulo_manager "$ATUALIZACAO_ESCOLHIDA"
                ;;
            4) mostrar_ultima_atualizacao_manager ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
