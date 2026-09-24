# Módulo: projects_storage.sh
# Informações, backup e exclusão segura de projetos. Carregado por projects.sh.

projeto_caminho_exclusao_seguro() {
    local alvo="${1:-}" real_alvo real_painel
    [ -n "$alvo" ] && [ -e "$alvo" ] || return 1
    real_alvo="$(realpath -m "$alvo" 2>/dev/null || printf '%s' "$alvo")"
    real_painel="$(realpath -m "${PAINEL_DIR:-$HOME/Painel}" 2>/dev/null || printf '%s' "${PAINEL_DIR:-$HOME/Painel}")"
    case "$real_alvo" in
        "$real_painel") return 2 ;;
        "$real_painel"/*) return 0 ;;
        *) return 1 ;;
    esac
}

mostrar_informacoes_projeto() {
    local projeto="$1"
    nome_amigavel_projeto "$projeto"
    nome_package_projeto "$projeto"
    title "Informações: $NOME_PROJETO"

    local tamanho qtd_arquivos qtd_pastas modificado
    tamanho=$(du -sh "$projeto" 2>/dev/null | cut -f1)
    qtd_arquivos=$(find "$projeto" -type f 2>/dev/null | wc -l | tr -d ' ')
    qtd_pastas=$(find "$projeto" -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    modificado=$(date -r "$projeto" '+%d/%m/%Y %H:%M' 2>/dev/null)

    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}$NOME_PROJETO${C_RESET}" true
    caixa_linha_sep
    caixa_linha_texto "🏷️ Exibição: ${NOME_PROJETO}"
    caixa_linha_texto "📂 Pasta: $(basename "$projeto")"
    [ -n "$NOME_PACKAGE_PROJETO" ] && caixa_linha_texto "📦 Package: ${NOME_PACKAGE_PROJETO}"
    caixa_linha_texto "📁 ${projeto}"
    if ! eh_painel_raiz "$projeto"; then
        rotulo_stack_projeto "$projeto"
        caixa_linha_texto "🧩 Tipo: ${ROTULO_STACK}"
    fi
    caixa_linha_texto "📊 Tamanho: ${tamanho:-?}"
    caixa_linha_texto "📄 Arquivos: ${qtd_arquivos}   📂 Pastas: ${qtd_pastas}"
    caixa_linha_texto "🕒 Modificado: ${modificado:-?}"
    caixa_linha_baixo

    pause
}

# Resolve o destino público dos backups de projetos. Os pacotes finais ficam
# visíveis no Android em Download/projetos/backups. BACKUPS_DIR continua sendo
# uma área interna legada do Painel e não é usada como destino final.
resolver_destino_backup_projetos() {
    if ! resolver_downloads_dir >/dev/null 2>&1; then
        error "Não foi possível acessar a pasta Downloads."
        info "Execute termux-setup-storage e conceda acesso ao armazenamento."
        return 1
    fi

    PROJECT_BACKUPS_DIR="$DOWNLOADS_DIR/projetos/backups"
    if ! mkdir -p "$PROJECT_BACKUPS_DIR" 2>>"$LOG_FILE"; then
        error "Não foi possível criar: $PROJECT_BACKUPS_DIR"
        return 1
    fi
    return 0
}

# Cria um TAR.GZ enxuto: dependências baixáveis, repositório Git, caches,
# resultados de build e temporários não entram no pacote. O código-fonte,
# manifests/locks, configurações, assets e demais arquivos do projeto ficam.
compactar_backup_projeto() {
    local origem="$1" destino="$2" nome
    nome="$(basename "$origem")"

    tar -czf "$destino" \
        --exclude='node_modules' --exclude='*/node_modules' \
        --exclude='.git' --exclude='*/.git' \
        --exclude='.next' --exclude='*/.next' \
        --exclude='.nuxt' --exclude='*/.nuxt' \
        --exclude='.svelte-kit' --exclude='*/.svelte-kit' \
        --exclude='.cache' --exclude='*/.cache' \
        --exclude='.parcel-cache' --exclude='*/.parcel-cache' \
        --exclude='.turbo' --exclude='*/.turbo' \
        --exclude='.vite' --exclude='*/.vite' \
        --exclude='coverage' --exclude='*/coverage' \
        --exclude='dist' --exclude='*/dist' \
        --exclude='build' --exclude='*/build' \
        --exclude='target' --exclude='*/target' \
        --exclude='vendor' --exclude='*/vendor' \
        --exclude='.venv' --exclude='*/.venv' \
        --exclude='venv' --exclude='*/venv' \
        --exclude='__pycache__' --exclude='*/__pycache__' \
        --exclude='.pytest_cache' --exclude='*/.pytest_cache' \
        --exclude='.mypy_cache' --exclude='*/.mypy_cache' \
        --exclude='tmp' --exclude='*/tmp' \
        --exclude='temp' --exclude='*/temp' \
        -C "$(dirname "$origem")" "$nome" 2>>"$LOG_FILE"
}

# Cria primeiro em uma área temporária privada, copia para Downloads, verifica
# integridade por SHA-256 e remove imediatamente a cópia temporária do Termux.
# Retorna o caminho público em BACKUP_PROJETO_RESULTADO.
gerar_backup_publico_projeto() {
    local origem="$1" rotulo="${2:-$(basename "$1")}" carimbo arquivo tmp_dir temporario destino hash_tmp hash_dest
    [ -d "$origem" ] || { error "Pasta não encontrada: $(caminho_curto "$origem")"; return 1; }
    resolver_destino_backup_projetos || return 1

    carimbo="$(date '+%Y-%m-%d_%H-%M-%S')"
    arquivo="${rotulo}_${carimbo}.tar.gz"
    tmp_dir="${SESSION_TMP_DIR:-$TMP_ROOT/session_$$}/backup"
    mkdir -p "$tmp_dir" || return 1
    temporario="$tmp_dir/$arquivo"
    destino="$PROJECT_BACKUPS_DIR/$arquivo"

    rm -f "$temporario"
    info "Compactando código e arquivos essenciais..."
    if ! compactar_backup_projeto "$origem" "$temporario"; then
        rm -f "$temporario"
        error "Falha ao criar o pacote de backup."
        return 1
    fi

    info "Copiando para Download/projetos/backups..."
    if ! cp -f "$temporario" "$destino" 2>>"$LOG_FILE"; then
        rm -f "$temporario"
        error "Falha ao copiar o backup para Downloads."
        return 1
    fi

    hash_tmp="$(sha256sum "$temporario" 2>/dev/null | awk '{print $1}')"
    hash_dest="$(sha256sum "$destino" 2>/dev/null | awk '{print $1}')"
    if [ -z "$hash_tmp" ] || [ "$hash_tmp" != "$hash_dest" ]; then
        rm -f "$destino" "$temporario"
        error "A verificação do backup falhou. O arquivo incompleto foi removido."
        return 1
    fi

    rm -f "$temporario"
    BACKUP_PROJETO_RESULTADO="$destino"
    log "INFO" "Backup público verificado: $origem -> $destino"
    return 0
}

criar_backup_projeto() {
    local projeto="$1" sem_pausa="${2:-false}" nome tamanho
    nome="$(basename "$projeto")"
    title "Backup: $nome"

    if gerar_backup_publico_projeto "$projeto" "$nome"; then
        tamanho=$(stat -c%s "$BACKUP_PROJETO_RESULTADO" 2>/dev/null || echo 0)
        ok "Backup criado e verificado."
        info "Destino: $BACKUP_PROJETO_RESULTADO"
        info "Tamanho: $(formatar_tamanho "$tamanho")"
        info "Ignorados: node_modules, .git, caches, builds e dependências regeneráveis."
        [ "$sem_pausa" = true ] || pause
        return 0
    fi

    error "Backup não concluído. Veja $(caminho_curto "$LOG_FILE") para detalhes."
    [ "$sem_pausa" = true ] || pause
    return 1
}


# ============================================================================
# CENTRO DE EXCLUSÃO DO PAINEL
# ============================================================================

quantidade_itens_diretos() {
    local alvo="$1"
    [ -d "$alvo" ] || { printf '0'; return; }
    find "$alvo" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l | tr -d ' '
}

backup_pasta_antes_excluir() {
    local alvo="$1" rotulo="$2"
    [ -d "$alvo" ] || return 0
    info "Criando backup antes da exclusão..."
    if gerar_backup_publico_projeto "$alvo" "$rotulo"; then
        ok "Backup salvo e verificado em Downloads."
        info "Destino: $BACKUP_PROJETO_RESULTADO"
        return 0
    fi
    error "Não foi possível criar um backup seguro. Exclusão cancelada."
    return 1
}

confirmar_exclusao_nivel() {
    local palavra="$1" descricao="$2"
    warn "$descricao"
    read -rp "Digite $palavra para confirmar: " resposta
    [ "$resposta" = "$palavra" ] || { info "Cancelado. Nada foi apagado."; pause; return 1; }
    return 0
}

selecionar_projeto_para_excluir() {
    descobrir_entradas
    if [ ${#PROJETOS_ENCONTRADOS[@]} -eq 0 ]; then
        warn "Nenhum projeto foi detectado."
        pause
        return
    fi
    cabecalho_tela "🗑️ Excluir um projeto" "Selecione exatamente o projeto a remover"
    caixa_linha_topo
    local i=1 entrada caminho origem
    for entrada in "${PROJETOS_ENCONTRADOS[@]}"; do
        caminho="${entrada%%|*}"; origem="${entrada##*|}"
        nome_amigavel_projeto "$caminho"
        menu_opcao "$i" "📦" "$NOME_PROJETO" "$origem"
        i=$((i+1))
    done
    caixa_linha_baixo
    rodape_atalhos "[0] Cancelar  •  [número] Selecionar"
    ler_opcao
    [ "$RESPOSTA_MENU" = 0 ] && return
    if [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] && [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#PROJETOS_ENCONTRADOS[@]} ]; then
        entrada="${PROJETOS_ENCONTRADOS[$((RESPOSTA_MENU-1))]}"
        excluir_projeto "${entrada%%|*}"
    else
        warn "Opção inválida."
        pause
    fi
}

limpar_conteudo_pasta_projetos() {
    local qtd tamanho fazer_backup
    qtd="$(quantidade_itens_diretos "$PROJETOS_DIR")"
    tamanho="$(du -sh "$PROJETOS_DIR" 2>/dev/null | cut -f1)"
    cabecalho_tela "🧹 Limpar projetos" "A pasta ~/Painel/projetos será preservada"
    caixa_simples "Resumo" "Itens diretos: ${qtd:-0}" "Tamanho: ${tamanho:-0}" \
        "Preserva: backups, arquivos da raiz do Painel e configurações"
    [ "${qtd:-0}" -gt 0 ] || { info "A pasta projetos já está vazia."; pause; return; }
    read -rp "Criar backup da pasta projetos antes de limpar? (S/n): " fazer_backup
    if [[ ! "$fazer_backup" =~ ^[nN]$ ]]; then
        backup_pasta_antes_excluir "$PROJETOS_DIR" "projetos_completo" || { pause; return; }
    fi
    confirmar_exclusao_nivel "LIMPAR" "Todos os itens dentro de $PROJETOS_DIR serão removidos." || return
    garantir_cwd_fora_do_alvo "$PROJETOS_DIR" || { error "Não foi possível mover o terminal para um diretório seguro."; pause; return 1; }
    find "$PROJETOS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    log "INFO" "Conteúdo de $PROJETOS_DIR removido; pasta preservada."
    ok "Todos os projetos foram removidos. A pasta projetos foi preservada."
    pause
}

excluir_pasta_projetos_completa() {
    local qtd tamanho fazer_backup
    qtd="$(quantidade_itens_diretos "$PROJETOS_DIR")"
    tamanho="$(du -sh "$PROJETOS_DIR" 2>/dev/null | cut -f1)"
    cabecalho_tela "🗑️ Excluir pasta projetos" "Remove a pasta e todo o seu conteúdo"
    caixa_simples "Resumo" "Itens diretos: ${qtd:-0}" "Tamanho: ${tamanho:-0}" \
        "O Manager recriará uma pasta projetos vazia para continuar funcionando"
    read -rp "Criar backup antes de excluir? (S/n): " fazer_backup
    if [[ -d "$PROJETOS_DIR" && ! "$fazer_backup" =~ ^[nN]$ ]]; then
        backup_pasta_antes_excluir "$PROJETOS_DIR" "pasta_projetos" || { pause; return; }
    fi
    confirmar_exclusao_nivel "PROJETOS" "A pasta $PROJETOS_DIR inteira será removida." || return
    garantir_cwd_fora_do_alvo "$PROJETOS_DIR" || { error "Não foi possível mover o terminal para um diretório seguro."; pause; return 1; }
    rm -rf -- "${PROJETOS_DIR:?}"
    mkdir -p "$PROJETOS_DIR"
    log "INFO" "Pasta projetos excluída e recriada vazia."
    ok "Pasta projetos removida e recriada vazia."
    pause
}

menu_exclusao_painel() {
    while true; do
        local qtd tamanho_painel tamanho_projetos
        qtd="$(quantidade_itens_diretos "$PROJETOS_DIR")"
        tamanho_painel="$(du -sh "$PAINEL_DIR" 2>/dev/null | cut -f1)"
        tamanho_projetos="$(du -sh "$PROJETOS_DIR" 2>/dev/null | cut -f1)"
        menu_unificado "🧹 Limpeza do Painel" "Escolha exatamente o nível de exclusão" \
            "[0] Voltar  •  Ações destrutivas exigem confirmação" \
            "1|📦|Excluir um projeto|Selecionar somente um projeto" \
            "2|🧹|Limpar conteúdo de projetos|Remove ${qtd:-0} item(ns), mantém a pasta • ${tamanho_projetos:-0}" \
            "3|🗑️|Excluir pasta projetos|Remove e recria ~/Painel/projetos vazia" \
            "4|⚠️|Excluir todo o Painel|Projetos, backups, arquivos e configurações • ${tamanho_painel:-0}"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) selecionar_projeto_para_excluir ;;
            2) limpar_conteudo_pasta_projetos ;;
            3) excluir_pasta_projetos_completa ;;
            4) excluir_painel_inteiro ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

excluir_projeto() {
    local projeto="$1" fazer_backup conf seguranca_rc=0
    projeto_caminho_exclusao_seguro "$projeto" || seguranca_rc=$?
    if [ "$seguranca_rc" -eq 2 ]; then
        cabecalho_tela "🛑 Exclusão bloqueada" "Proteção da raiz do Painel"
        caixa_simples_wrap "Projeto na raiz"             "Este projeto representa a própria raiz de ~/Painel."             "Ele não pode ser removido pela ação Excluir projeto."             "Use Configurações → Limpeza do Painel para uma exclusão completa e confirmada."
        pause
        return 1
    elif [ "$seguranca_rc" -ne 0 ]; then
        error "Exclusão bloqueada: caminho fora de ~/Painel."
        pause
        return 1
    fi
    title "Excluir Projeto"
    warn "Isso removerá permanentemente: $projeto"
    read -rp "Deseja fazer um backup antes de excluir? (s/N): " fazer_backup
    if [[ "$fazer_backup" =~ ^[sS]$ ]]; then
        if ! criar_backup_projeto "$projeto" true; then
            error "O projeto NÃO foi excluído porque o backup não foi concluído."
            pause
            return 1
        fi
    fi
    read -rp "Confirma exclusão? (s/N): " conf
    if [[ "$conf" =~ ^[sS]$ ]]; then
        garantir_cwd_fora_do_alvo "$projeto" || { error "Não foi possível mover o terminal para um diretório seguro."; pause; return 1; }
        rm -rf -- "$projeto"
        ok "Projeto removido."
        if [[ "$fazer_backup" =~ ^[sS]$ ]]; then
            info "Backup preservado em: $BACKUP_PROJETO_RESULTADO"
        fi
        log "INFO" "Projeto excluído: $projeto"
        pause
        return 0
    else
        info "Exclusão cancelada."
        pause
        return 1
    fi
}
