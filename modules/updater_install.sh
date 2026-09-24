# Submódulo: updater_install.sh
# Instalação transacional de pacotes completos.

updater_restaurar_backup() {
    local backup="$1" item
    [ -f "$backup" ] || return 1
    rm -rf -- "$BASE_DIR/manager.sh" "$BASE_DIR/modules"
    for item in install.sh README.md CHANGELOG.md RELEASE_STANDARD.md MANIFEST.json tools resources config; do
        rm -rf -- "$BASE_DIR/$item"
    done
    tar -xzf "$backup" -C "$BASE_DIR"
}

updater_sincronizar_auxiliares() {
    local pacote="$1" auxiliar
    for auxiliar in install.sh README.md CHANGELOG.md RELEASE_STANDARD.md MANIFEST.json; do
        if [ -f "$pacote/$auxiliar" ]; then
            cp -f "$pacote/$auxiliar" "$BASE_DIR/$auxiliar" || return 1
        fi
    done
    for auxiliar in tools resources config; do
        if [ -d "$pacote/$auxiliar" ]; then
            rm -rf -- "$BASE_DIR/$auxiliar" || return 1
            cp -a "$pacote/$auxiliar" "$BASE_DIR/$auxiliar" || return 1
        fi
    done
    [ ! -f "$BASE_DIR/install.sh" ] || chmod 700 "$BASE_DIR/install.sh" 2>/dev/null || true
    return 0
}

instalar_pacote_manager() {
    local arquivo="$1"
    if ! garantir_comando unzip unzip || ! command -v unzip >/dev/null 2>&1; then
        error "Não foi possível disponibilizar o comando unzip."
        pause
        return 1
    fi
    if ! validar_zip_manager_seguro "$arquivo"; then
        pause
        return 1
    fi
    local updates_dir="$BASE_DIR/.updates" stamp tmp pacote modulo faltando=false
    stamp="$(date '+%Y%m%d_%H%M%S')"
    tmp="$updates_dir/extract_$stamp"
    mkdir -p "$updates_dir"; rm -rf "$tmp"; mkdir -p "$tmp"

    unzip -q "$arquivo" -d "$tmp" || { error "Falha ao extrair o pacote."; rm -rf "$tmp"; pause; return; }
    pacote="$tmp"
    if [ ! -f "$pacote/manager.sh" ]; then
        local raiz=(); shopt -s nullglob dotglob; raiz=("$tmp"/*); shopt -u nullglob dotglob
        [ ${#raiz[@]} -eq 1 ] && [ -d "${raiz[0]}" ] && pacote="${raiz[0]}"
    fi
    [ -f "$pacote/manager.sh" ] && [ -d "$pacote/modules" ] || { error "Pacote inválido: manager.sh ou modules/ ausente."; rm -rf "$tmp"; pause; return; }
    if find "$pacote" -type l -print -quit 2>/dev/null | grep -q .; then
        error "Pacote inválido: links simbólicos não são permitidos em uma atualização."
        rm -rf "$tmp"
        pause
        return 1
    fi
    if ! validar_manifesto_pacote_manager "$pacote"; then
        rm -rf "$tmp"
        pause
        return 1
    fi

    for modulo in "${MODULOS_OBRIGATORIOS[@]}"; do
        [ -f "$pacote/modules/$modulo" ] || { error "Módulo ausente: $modulo"; faltando=true; }
    done
    [ "$faltando" = false ] || { rm -rf "$tmp"; pause; return; }

    local shfile
    while IFS= read -r -d '' shfile; do
        bash -n "$shfile" || { error "Erro de sintaxe em $(basename "$shfile")"; rm -rf "$tmp"; pause; return; }
    done < <(find "$pacote" -type f -name '*.sh' -print0)

    local nova_versao hash_atual hash_novo hash_principal_atual hash_principal_novo tamanho_novo linhas_novas
    nova_versao="$(versao_arquivo_manager "$pacote/manager.sh")"
    if ! versao_semver_valida "$nova_versao"; then
        error "Pacote inválido: versão interna não reconhecida."
        rm -rf "$tmp"
        pause
        return 1
    fi
    hash_atual="$(hash_pacote_manager "$BASE_DIR")"
    hash_novo="$(hash_pacote_manager "$pacote")"
    hash_principal_atual="$(hash_arquivo_manager "$SELF_PATH")"
    hash_principal_novo="$(hash_arquivo_manager "$pacote/manager.sh")"
    tamanho_novo="$(stat -c%s "$arquivo" 2>/dev/null || echo 0)"
    linhas_novas="$(find "$pacote" -type f -name '*.sh' -exec cat {} + | wc -l)"

    cabecalho_tela "🔼 Atualização completa" "Substitui manager.sh e todos os módulos"
    caixa_simples "Instalação atual" \
        "Versão: $MANAGER_VERSION" \
        "Pasta: $(caminho_curto "$BASE_DIR")" \
        "Hash do pacote: ${hash_atual:0:12}…" \
        "Hash principal: ${hash_principal_atual:0:12}…"
    caixa_simples "Pacote selecionado" \
        "Arquivo: $(basename "$arquivo")" \
        "Padrão GitHub: $(versao_nome_pacote "$arquivo")" \
        "Versão interna: $nova_versao" \
        "Data: $(data_arquivo_manager "$arquivo")" \
        "Tamanho: $(formatar_tamanho "$tamanho_novo")" \
        "Linhas Bash: $linhas_novas" \
        "Hash do pacote: ${hash_novo:0:12}…" \
        "Hash principal: ${hash_principal_novo:0:12}…"
    if [ -n "$hash_atual" ] && [ "$hash_atual" = "$hash_novo" ]; then
        ok "Este pacote completo já está instalado."
        rm -rf "$tmp"
        pause
        return
    fi
    confirmar_atualizacao_visual() {
        local escolha
        while true; do
            cabecalho_tela "📦 Atualização completa" "Revise as informações antes de continuar"
            caixa_linha_topo
            caixa_linha_texto "${C_BOLD}Resumo da atualização${C_RESET}" true
            caixa_linha_sep
            caixa_linha_texto "Versão atual: $MANAGER_VERSION"
            caixa_linha_texto "Nova versão: $nova_versao"
            caixa_linha_texto "Pacote: $(basename "$arquivo")"
            caixa_linha_texto "Tamanho: $(formatar_tamanho "$tamanho_novo")"
            caixa_linha_texto "Backup automático: ativado"
            caixa_linha_texto "Reinício automático: ativado"
            caixa_linha_sep
            menu_opcao "1" "⬆" "Atualizar agora" "Criar backup e instalar a nova versão"
            menu_opcao "2" "📋" "Ver detalhes técnicos" "Hashes, data, linhas e diretório de destino"
            menu_opcao "0" "↩" "Cancelar" "Voltar sem modificar a instalação"
            caixa_linha_baixo
            rodape_atalhos "[1] Atualizar  •  [2] Detalhes  •  [0] Cancelar"
            ler_opcao "Escolha uma opção: "
            escolha="$RESPOSTA_MENU"
            case "$escolha" in
                1) return 0 ;;
                2)
                    cabecalho_tela "📋 Detalhes da atualização" "Informações técnicas do pacote selecionado"
                    caixa_simples "Comparação"                         "Instalação: $(caminho_curto "$BASE_DIR")"                         "Versão atual: $MANAGER_VERSION"                         "Nova versão: $nova_versao"                         "Data do arquivo: $(data_arquivo_manager "$arquivo")"                         "Tamanho do ZIP: $(formatar_tamanho "$tamanho_novo")"                         "Linhas Bash: $linhas_novas"                         "Hash atual: ${hash_atual:0:16}…"                         "Hash novo: ${hash_novo:0:16}…"
                    pause
                    ;;
                0) return 1 ;;
                *) feedback_curto "Opção inválida." ;;
            esac
        done
    }

    confirmar_atualizacao_visual || { rm -rf "$tmp"; return; }

    # A tela é desenhada uma única vez. Nas etapas seguintes somente o bloco
    # de status é reescrito no mesmo lugar, evitando o efeito de recarregar a
    # página inteira a cada fase.
    local tamanho_extraido arquivos_pacote espaco_livre tamanho_backup_estimado=0 tamanho_item
    local -a itens_backup=(manager.sh modules)
    local item_backup
    for item_backup in install.sh README.md CHANGELOG.md RELEASE_STANDARD.md MANIFEST.json tools resources config; do
        [ -e "$BASE_DIR/$item_backup" ] && itens_backup+=("$item_backup")
    done

    tamanho_extraido="$(du -sb "$pacote" 2>/dev/null | awk '{print $1}')"
    [ -n "$tamanho_extraido" ] || tamanho_extraido=0
    arquivos_pacote="$(find "$pacote" -type f 2>/dev/null | wc -l | tr -d ' ')"
    espaco_livre="$(df -Pk "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $4 * 1024}')"
    [ -n "$espaco_livre" ] || espaco_livre=0
    for item_backup in "${itens_backup[@]}"; do
        tamanho_item="$(du -sb "$BASE_DIR/$item_backup" 2>/dev/null | awk '{print $1}')"
        [[ "$tamanho_item" =~ ^[0-9]+$ ]] || tamanho_item=0
        tamanho_backup_estimado=$((tamanho_backup_estimado + tamanho_item))
    done

    # Margem conservadora: pacote extraído + backup + uma segunda cópia dos
    # módulos durante a troca, acrescida de 20%.
    local espaco_necessario
    espaco_necessario=$(( (tamanho_extraido * 2 + tamanho_backup_estimado) * 120 / 100 ))
    if [ "$espaco_livre" -gt 0 ] && [ "$espaco_livre" -lt "$espaco_necessario" ]; then
        cabecalho_tela "⚠ Espaço insuficiente" "A atualização não foi iniciada"
        caixa_simples "Armazenamento"             "Disponível: $(formatar_tamanho "$espaco_livre")"             "Necessário: aproximadamente $(formatar_tamanho "$espaco_necessario")"             "Libere espaço e tente novamente."
        rm -rf "$tmp"
        pause
        return
    fi

    tela_atualizacao_iniciar() {
        # A atualização precisa escrever diretamente no terminal. Usar
        # cabecalho_tela aqui ativava o buffer global e fazia o novo Manager
        # herdar stdout apontando para um arquivo temporário após o exec.
        ui_buffer_flush 2>/dev/null || true
        tela_limpar
        local tela
        tela="$(
            caixa_linha_topo
            caixa_linha_texto "${C_BOLD}${C_WHITE}🔄 Atualizando Manager${C_RESET}" true
            caixa_linha_texto "${C_DIM}Versão $MANAGER_VERSION → $nova_versao${C_RESET}" true
            caixa_linha_baixo
            echo
            caixa_simples "Resumo da instalação"                 "Pacote: $(basename "$arquivo")"                 "Download: $(formatar_tamanho "$tamanho_novo") • Extraído: $(formatar_tamanho "$tamanho_extraido")"                 "Arquivos: $arquivos_pacote • Backup estimado: $(formatar_tamanho "$tamanho_backup_estimado")"                 "Espaço livre: $(formatar_tamanho "$espaco_livre")"
        )"
        printf '%s\n\n' "$tela"
        # Marca o início da área dinâmica. Cada atualização volta exatamente
        # para esta posição e substitui somente as linhas do progresso.
        printf '\033[s'
    }

    tela_atualizacao_etapa() {
        local etapa="$1" total="$2" titulo="$3" detalhe="$4" estado="${5:-em andamento}"
        local percentual=$(( etapa * 100 / total )) preenchido vazio barra=""
        ui_buffer_flush 2>/dev/null || true
        preenchido=$(( percentual / 5 )); vazio=$((20 - preenchido))
        barra="$(repetir_char '█' "$preenchido")$(repetir_char '░' "$vazio")"
        printf '\033[u\033[J'
        local bloco
        bloco="$(
            caixa_linha_topo
            caixa_linha_texto "${C_BOLD}Etapa $etapa de $total • $percentual%${C_RESET}" true
            caixa_linha_sep
            caixa_linha_texto "$barra"
            caixa_linha_texto "${C_BOLD}$titulo${C_RESET}"
            caixa_linha_texto "$detalhe"
            caixa_linha_texto "Status: $estado"
            caixa_linha_baixo
        )"
        printf '%s\n' "$bloco"
    }

    tela_atualizacao_iniciar

    local total_etapas=5
    tela_atualizacao_etapa 1 "$total_etapas" "Validando o pacote" "Estrutura e sintaxe verificadas." "concluída"
    sleep 0.35

    local backup="$updates_dir/manager_backup_$stamp.tar.gz"
    tela_atualizacao_etapa 2 "$total_etapas" "Criando backup de segurança" "Destino: $(basename "$backup")"
    tar -czf "$backup" -C "$BASE_DIR" "${itens_backup[@]}" || { error "Falha ao criar backup."; rm -rf "$tmp"; pause; return; }
    tela_atualizacao_etapa 2 "$total_etapas" "Criando backup de segurança" "Destino: $(basename "$backup")" "concluída"
    sleep 0.35
    local novo_manager="$BASE_DIR/.manager_new_$stamp.sh" novos_modulos="$BASE_DIR/.modules_new_$stamp" antigos_modulos="$BASE_DIR/.modules_old_$stamp"
    tela_atualizacao_etapa 3 "$total_etapas" "Preparando a nova versão" "Normalizando e organizando os arquivos."
    # tr -d '\r' normaliza quebras de linha estilo Windows (\r\n), que podem
    # vir do arquivo baixado (edição no PC, apps de transferência, etc.) e
    # causar comportamento estranho em scripts Bash.
    tr -d '\r' < "$pacote/manager.sh" > "$novo_manager" || { error "Falha ao preparar manager.sh."; rm -rf "$tmp"; pause; return; }
    cp -R "$pacote/modules" "$novos_modulos" || { error "Falha ao preparar módulos."; rm -rf "$tmp" "$novo_manager"; pause; return; }
    local modfile
    while IFS= read -r -d '' modfile; do
        tr -d '\r' < "$modfile" > "$modfile.tmp" && mv -f "$modfile.tmp" "$modfile"
    done < <(find "$novos_modulos" -type f -name '*.sh' -print0)
    bash -n "$novo_manager" || { error "manager.sh ficou inválido após normalizar quebras de linha."; rm -rf "$tmp" "$novo_manager" "$novos_modulos"; pause; return; }
    chmod 700 "$novo_manager"; find "$novos_modulos" -type f -name '*.sh' -exec chmod 600 {} \;
    tela_atualizacao_etapa 3 "$total_etapas" "Preparando a nova versão" "Arquivos prontos para instalação." "concluída"
    sleep 0.35
    tela_atualizacao_etapa 4 "$total_etapas" "Aplicando a atualização" "Substituindo o núcleo e os módulos."
    mv "$MODULES_DIR" "$antigos_modulos" || { error "Falha ao preparar substituição."; rm -rf "$tmp" "$novo_manager" "$novos_modulos"; pause; return; }
    if mv "$novos_modulos" "$MODULES_DIR" && mv -f "$novo_manager" "$SELF_PATH"; then
        rm -rf "$antigos_modulos"
    else
        rm -rf "$MODULES_DIR" "$novo_manager" "$novos_modulos" "$antigos_modulos"
        updater_restaurar_backup "$backup" 2>/dev/null || true
        error "Atualização falhou; o backup foi restaurado."; rm -rf "$tmp"; pause; return
    fi

    if ! updater_sincronizar_auxiliares "$pacote"; then
        updater_restaurar_backup "$backup" 2>/dev/null || true
        error "Falha ao sincronizar arquivos auxiliares; o backup foi restaurado."
        rm -rf "$tmp"
        pause
        return 1
    fi
    tela_atualizacao_etapa 4 "$total_etapas" "Aplicando a atualização" "Código, documentação e ferramentas sincronizados." "concluída"
    sleep 0.35
    tela_atualizacao_etapa 5 "$total_etapas" "Finalizando" "Registrando a atualização e preparando o reinício."
    rm -rf "$tmp"
    if [ "${ATUALIZACAO_LIMPAR_ARQUIVO:-false}" = true ]; then
        local pasta_download_remota
        pasta_download_remota="$(dirname "$arquivo")"
        rm -f -- "$arquivo" 2>/dev/null || true
        rmdir "$pasta_download_remota" 2>/dev/null || true
    fi
    cat > "$(arquivo_status_atualizacao)" <<EOF
DATA="$(date '+%d/%m/%Y %H:%M:%S')"
TIPO="${ATUALIZACAO_TIPO:-completa}"
ARQUIVO="$(basename "$arquivo")"
VERSAO_ANTERIOR="$MANAGER_VERSION"
VERSAO_NOVA="$nova_versao"
BACKUP="$(basename "$backup")"
STATUS="confirmada"
EOF
    # O atalho aponta para um caminho estável ($BASE_DIR/manager.sh), portanto
    # não precisa ser recriado em toda atualização. Além de redundante, essa
    # operação disparava helpers de UI antigos já carregados em memória.
    tela_atualizacao_etapa 5 "$total_etapas" "Finalizando" "Registro salvo e reinício preparado." "concluída"
    sleep 0.45

    # Garante que nenhuma saída permaneça presa no buffer antes de mostrar a
    # conclusão e, principalmente, antes de substituir o processo com exec.
    ui_buffer_flush 2>/dev/null || true
    tela_limpar
    local tela_final
    tela_final="$(
        caixa_linha_topo
        caixa_linha_texto "${C_BOLD}${C_WHITE}✅ Atualização concluída${C_RESET}" true
        caixa_linha_texto "${C_DIM}O Manager foi atualizado com segurança${C_RESET}" true
        caixa_linha_sep
        caixa_linha_texto "Versão anterior: $MANAGER_VERSION"
        caixa_linha_texto "Versão instalada: $nova_versao"
        caixa_linha_texto "Backup: $(basename "$backup")"
        caixa_linha_texto "Status: arquivos verificados e registro salvo"
        caixa_linha_sep
        caixa_linha_texto "O Manager será reiniciado automaticamente."
        caixa_linha_baixo
    )"
    printf '%s\n\n' "$tela_final"

    local contagem
    for contagem in 3 2 1; do
        printf "\r${C_CYAN}➜${C_RESET} Reiniciando em %s... " "$contagem"
        sleep 1
    done
    printf "\r${C_GREEN}✔${C_RESET} Carregando a versão %s...      \n" "$nova_versao"
    sleep 0.3

    # Última barreira de segurança: restaura stdout, cursor, sinais e lock.
    # Sem isso, o novo processo pode iniciar invisível em um arquivo temporário.
    ui_buffer_flush 2>/dev/null || true
    printf '\033[0m\033[?25h\033[r\033[?7h'
    stty sane 2>/dev/null || true
    liberar_bloqueio 2>/dev/null || true
    trap - EXIT INT TERM
    exec bash "$SELF_PATH"
}

