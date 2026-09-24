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
# SUBMÓDULOS DE CONFIGURAÇÕES
# ============================================================================

SETTINGS_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _settings_submodule in settings_fish.sh settings_shortcuts.sh settings_maintenance.sh; do
    # shellcheck source=/dev/null
    source "$SETTINGS_MODULE_DIR/$_settings_submodule"
done
unset _settings_submodule SETTINGS_MODULE_DIR
