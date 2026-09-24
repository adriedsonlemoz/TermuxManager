# Módulo: settings_shortcuts.sh
# Atalhos globais do Manager. Carregado por settings.sh.

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

