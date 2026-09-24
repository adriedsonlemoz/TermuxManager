# Módulo: linux_backup.sh
# Backup, restauração e encerramento de sessões das distribuições Linux.

linux_backup_distro() {
    local alias="${1:-}" modo="${2:-interativo}" destino pasta stamp rc=0
    [ -n "$alias" ] || return 1
    LINUX_BACKUP_RESULT_FILE=""
    resolver_downloads_dir >/dev/null 2>&1 || true
    pasta="${DOWNLOADS_DIR:-$HOME/storage/downloads}"
    [ -d "$pasta" ] || mkdir -p "$pasta" 2>/dev/null || true
    if [ ! -d "$pasta" ]; then
        if [ "$modo" = "interativo" ]; then
            cabecalho_tela "💾 Backup Linux" "$alias"
            caixa_simples_wrap "Downloads indisponível" \
                "Não foi possível acessar Downloads para salvar o backup."
            pause
        fi
        return 1
    fi
    stamp="$(date '+%Y%m%d-%H%M%S')"
    destino="$pasta/TermuxManager-${alias}-${stamp}.tar.xz"
    linux_coletar_info_distro "$alias" false
    if [ "$modo" = "interativo" ]; then
        cabecalho_tela "💾 Criar backup" "$LINUX_INFO_NAME"
        caixa_simples_wrap "Arquivo de backup" \
            "Tamanho atual: $LINUX_INFO_SIZE" \
            "Destino: $(caminho_curto "$destino")" \
            "A compactação pode demorar em distros grandes."
        confirmar_acao "Criar backup agora?" "s" || return 0
        ui_buffer_flush 2>/dev/null || true
    fi
    proot-distro backup --output "$destino" "$alias" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    if [ "$rc" -eq 0 ] && [ -f "$destino" ]; then
        LINUX_BACKUP_RESULT_FILE="$destino"
        linux_log "backup criado: $alias -> $destino"
        if [ "$modo" = "interativo" ]; then
            ok "Backup criado em Downloads."
            printf 'Arquivo: %s\n' "$(caminho_curto "$destino")"
            pause
        fi
        return 0
    fi
    rm -f "$destino" 2>/dev/null || true
    [ "$modo" = "interativo" ] && { error "Não foi possível criar o backup."; pause; }
    return 1
}

linux_backup_alias_arquivo() {
    local arquivo="${1:-}" base alias conteudo=""
    [ -f "$arquivo" ] && [ -s "$arquivo" ] || return 1
    base="$(basename "$arquivo")"

    # Se tar estiver disponível, não confie apenas no nome: um arquivo vazio ou
    # corrompido com o padrão do Manager não deve aparecer como backup restaurável.
    if command -v tar >/dev/null 2>&1; then
        conteudo="$(tar -tf "$arquivo" 2>/dev/null)" || return 1
        [ -n "$conteudo" ] || return 1
        alias="$(printf '%s\n' "$conteudo" | awk -F/ 'NF && $1!="" && $1!="." && ($2=="rootfs" || $2=="manifest.json") {print $1; exit}')"
        if [[ "$alias" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
            printf '%s\n' "$alias"
            return 0
        fi
    fi

    if [[ "$base" =~ ^TermuxManager-([A-Za-z0-9][A-Za-z0-9._-]{0,63})-[0-9]{8}-[0-9]{6}\.tar(\.xz|\.gz|\.bz2|\.lzma|\.zst)?$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

linux_coletar_backups_downloads() {
    local pasta arquivo
    LINUX_BACKUP_FILES=()
    resolver_downloads_dir >/dev/null 2>&1 || true
    pasta="${DOWNLOADS_DIR:-$HOME/storage/downloads}"
    [ -d "$pasta" ] || return 1
    shopt -s nullglob
    for arquivo in \
        "$pasta"/*.tar "$pasta"/*.tar.gz "$pasta"/*.tgz \
        "$pasta"/*.tar.bz2 "$pasta"/*.tbz2 \
        "$pasta"/*.tar.xz "$pasta"/*.txz \
        "$pasta"/*.tar.lzma "$pasta"/*.tlzma \
        "$pasta"/*.tar.zst "$pasta"/*.tzst; do
        if [ -f "$arquivo" ] && linux_backup_alias_arquivo "$arquivo" >/dev/null 2>&1; then
            LINUX_BACKUP_FILES+=("$arquivo")
        fi
    done
    shopt -u nullglob
    [ ${#LINUX_BACKUP_FILES[@]} -gt 0 ]
}

linux_backup_arquivo_resumo() {
    local arquivo="${1:-}" kb data alias
    [ -f "$arquivo" ] || return 1
    kb="$(du -k "$arquivo" 2>/dev/null | awk 'NR==1{print $1+0}')"
    data="$(date -r "$arquivo" '+%d/%m/%Y %H:%M' 2>/dev/null || printf 'data desconhecida')"
    alias="$(linux_backup_alias_arquivo "$arquivo" 2>/dev/null || true)"
    printf '%s • %s • %s\n' "${alias:-distro?}" "$(linux_formatar_tamanho_kb "${kb:-0}")" "$data"
}

linux_restaurar_backup() {
    local escolha arquivo alias="" i resumo kb data existente=false rc=0 criar_seg=false
    linux_garantir_proot_distro || { pause; return 1; }
    if ! linux_coletar_backups_downloads; then
        cabecalho_tela "♻️ Restaurar backup" "Backups em Downloads"
        caixa_simples_wrap "Nenhum backup encontrado" \
            "Não encontrei arquivos TAR compatíveis na pasta Downloads." \
            "Crie um backup pelo painel de uma distro ou copie um backup para Downloads."
        pause
        return 0
    fi

    local -a opcoes=()
    for ((i=0; i<${#LINUX_BACKUP_FILES[@]}; i++)); do
        arquivo="${LINUX_BACKUP_FILES[$i]}"
        resumo="$(linux_backup_arquivo_resumo "$arquivo")"
        opcoes+=("$((i+1))|💾|$(basename "$arquivo")|$resumo")
    done
    menu_unificado "♻️ Restaurar backup" "Arquivos encontrados em Downloads" \
        "[0] Voltar  •  [1–${#LINUX_BACKUP_FILES[@]}] Selecionar" "${opcoes[@]}"
    ler_opcao
    escolha="$RESPOSTA_MENU"
    [ "$escolha" = "0" ] && return 0
    if ! [[ "$escolha" =~ ^[0-9]+$ ]] || [ "$escolha" -lt 1 ] || [ "$escolha" -gt ${#LINUX_BACKUP_FILES[@]} ]; then
        feedback_curto "Opção inválida."
        return 1
    fi

    arquivo="${LINUX_BACKUP_FILES[$((escolha-1))]}"
    alias="$(linux_backup_alias_arquivo "$arquivo" 2>/dev/null || true)"
    kb="$(du -k "$arquivo" 2>/dev/null | awk 'NR==1{print $1+0}')"
    data="$(date -r "$arquivo" '+%d/%m/%Y %H:%M' 2>/dev/null || printf 'desconhecida')"

    if [ -n "$alias" ]; then
        linux_coletar_instaladas || true
        printf '%s\n' "${LINUX_INSTALLED_DISTROS[@]}" | grep -Fxq "$alias" && existente=true || true
    fi

    cabecalho_tela "♻️ Restaurar backup" "$(basename "$arquivo")"
    caixa_simples_wrap "Antes de restaurar" \
        "Distro no backup: ${alias:-não identificada}" \
        "Tamanho: $(linux_formatar_tamanho_kb "${kb:-0}")" \
        "Data: $data" \
        "$([ "$existente" = true ] && printf 'Já instalada: SIM — os dados atuais serão substituídos.' || printf 'Já instalada: não detectada.')" \
        "O arquivo de backup em Downloads não será apagado."

    if [ "$existente" = true ]; then
        if confirmar_acao "Criar um backup de segurança da instalação atual antes?" "s"; then
            ui_buffer_flush 2>/dev/null || true
            printf '⏳ Criando backup de segurança de %s...\n' "$alias"
            if linux_backup_distro "$alias" automatico; then
                printf '✅ Backup de segurança: %s\n' "$(caminho_curto "$LINUX_BACKUP_RESULT_FILE")"
                criar_seg=true
            else
                error "O backup de segurança falhou. A restauração foi cancelada."
                pause
                return 1
            fi
        fi
    fi

    confirmar_acao "Restaurar este backup agora?" "n" || return 0
    ui_buffer_flush 2>/dev/null || true
    printf '⏳ Restaurando backup... não feche o Termux.\n'
    proot-distro restore "$arquivo" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    if [ "$rc" -ne 0 ]; then
        error "A restauração terminou com erro."
        [ "$criar_seg" = true ] && info "O backup de segurança foi mantido em Downloads."
        pause
        return 1
    fi

    linux_log "backup restaurado: ${alias:-desconhecida} <- $arquivo"
    [ -n "$alias" ] && linux_invalidar_cache_distro "$alias"
    cabecalho_tela "✅ Backup restaurado" "${alias:-Distribuição Linux}"
    if [ -n "$alias" ]; then
        linux_coletar_info_distro "$alias" true
        caixa_simples_wrap "Resultado" \
            "Distribuição: $LINUX_INFO_NAME" \
            "Saúde: ${LINUX_INFO_HEALTH_ICON} ${LINUX_INFO_HEALTH_LABEL}" \
            "Tamanho atual: $LINUX_INFO_SIZE" \
            "$([ "$criar_seg" = true ] && printf 'Backup anterior: %s' "$(basename "$LINUX_BACKUP_RESULT_FILE")" || printf 'Arquivo restaurado: %s' "$(basename "$arquivo")")"
    else
        caixa_simples_wrap "Resultado" \
            "Restauração concluída pelo proot-distro." \
            "Abra Meus Linux para conferir a distribuição restaurada."
    fi
    pause
}

linux_encerrar_sessoes_distro() {
    local alias="${1:-}" sessoes
    [ -n "$alias" ] || return 1
    sessoes="$(linux_distro_sessoes_ativas "$alias")"
    if [ "$sessoes" -le 0 ] 2>/dev/null; then
        cabecalho_tela "⏹️ Sessões Linux" "$alias"
        caixa_simples "Nenhuma sessão ativa" "Não há processos do proot-distro registrados para esta distribuição."
        pause
        return 0
    fi
    cabecalho_tela "⏹️ Encerrar sessões" "$alias"
    caixa_simples "Sessões ativas: $sessoes" \
        "O proot-distro encerrará a árvore de processos desta distribuição." \
        "Salve seu trabalho dentro do Linux antes de continuar."
    confirmar_acao "Encerrar as sessões de '$alias'?" "n" || return 0
    if proot-distro kill "$alias" >>"$LINUX_LOG" 2>&1; then
        ok "Sessões encerradas."
    else
        error "Não foi possível encerrar as sessões."
    fi
    pause
}
