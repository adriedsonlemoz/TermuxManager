# Módulo: settings_maintenance.sh
# Manutenção, restauração e menu principal de configurações. Carregado por settings.sh.

# ============================================================================
# MANUTENÇÃO DO PRÓPRIO MANAGER
# ============================================================================

limpar_estado_interno_manager() {
    # Remove somente dados internos do Manager. Projetos e backups do usuário
    # permanecem intactos em ~/Painel/projetos e ~/Painel/backups.
    rm -f "$CONFIG_FILE" "$FIRST_RUN_FILE" "${FIRST_RUN_STATE_FILE:-}" 2>/dev/null || true
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

    local helper_base helper bash_bin
    helper_base="${TMPDIR:-$HOME/.cache}"
    mkdir -p "$helper_base"
    helper="$helper_base/manager_desinstalar_$$.sh"
    bash_bin="$(command -v bash 2>/dev/null || printf '%s/bin/bash' "${PREFIX:-/data/data/com.termux/files/usr}")"

    cat > "$helper" <<EOF
#!$bash_bin
sleep 1
rm -rf -- $(printf '%q' "$BASE_DIR")
rm -f -- $(printf '%q' "$FIRST_RUN_FILE") $(printf '%q' "${FIRST_RUN_STATE_FILE:-$HOME/.manager_first_run.state}")
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
    GITHUB_BRANCH_PADRAO="main"
    EXCLUSOES_PADRAO="node_modules .git dist build"
    LOG_MAX_BYTES=$((LOG_MAX_MB*1024*1024)); aplicar_cores; salvar_config
    ok "Configurações restauradas."; pause
}

menu_configuracoes() {
    while true; do
        menu_unificado "🧰 Configurações" "Preferências do Manager" "[0] Voltar  •  [1–13] Selecionar" \
            "1|🎨|Aparência|Cores, descrições e ícones" \
            "2|📂|Pastas e caminhos|Painel, projetos e Downloads" \
            "3|📦|Importação|Exclusões, destino e conflitos" \
            "4|🚀|Execução de projetos|Navegador, porta e logs" \
            "5|🧹|Exclusões e limpeza|Temporários e logs" \
            "6|🔔|Comportamento|Inicialização e confirmações" \
            "7|🐟|Fish Shell|Instalar e configurar" \
            "8|🔄|Restaurar padrões|Não apaga projetos" \
            "9|🩺|Central de Diagnóstico|Manager, projetos e Termux" \
            "10|🧹|Limpeza do Painel|Projetos e backups" \
            "11|🛠️|Manutenção do Manager|Restaurar ou desinstalar" \
            "12|⚡|Atalhos do Manager|Comandos manager e mm" \
            "13|🐙|GitHub|Conta, identidade e repositórios"
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
            13) menu_github_global ;;
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
    local qtd_projetos qtd_arquivos qtd_backups tamanho real_painel real_manager

    # Proteção crítica: uma instalação manual pode ter colocado o próprio
    # Manager dentro de ~/Painel. Nesse cenário, apagar o Painel destruiria o
    # processo em execução e deixaria a instalação pela metade.
    real_painel="$(realpath -m -- "$PAINEL_DIR" 2>/dev/null || printf '%s' "$PAINEL_DIR")"
    real_manager="$(realpath -m -- "$BASE_DIR" 2>/dev/null || printf '%s' "$BASE_DIR")"
    case "$real_manager/" in
        "$real_painel/"|"$real_painel/"*)
            error "A pasta do próprio Manager está dentro do Painel e seria apagada."
            info "Mova/reinstale o Manager fora de $PAINEL_DIR antes de usar esta opção."
            pause
            return 1
            ;;
    esac
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
    GITHUB_BRANCH_PADRAO="main"
    aplicar_cores
    salvar_config
    log "INFO" "Pasta Painel inteira excluída e recriada pelo usuário (Configurações)."
    ok "Pasta Painel foi apagada e recriada vazia."
    pause
}

