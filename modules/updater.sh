# Módulo: updater.sh
# Atualização completa ou isolada do Manager.sh.

versao_arquivo_manager() {
    local arquivo="$1" versao=""
    versao=$(grep -m1 -E '^MANAGER_VERSION=' "$arquivo" 2>/dev/null | sed -E 's/^MANAGER_VERSION="?([^"[:space:]]+)"?.*/\1/')
    [ -n "$versao" ] || versao="não identificada"
    printf '%s' "$versao"
}

hash_arquivo_manager() {
    local arquivo="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$arquivo" 2>/dev/null | awk '{print $1}'
    else
        cksum "$arquivo" 2>/dev/null | awk '{print $1}'
    fi
}


hash_pacote_manager() {
    local pasta="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        (
            cd "$pasta" || exit 1
            find manager.sh modules -type f -print0 2>/dev/null \
                | sort -z \
                | xargs -0 sha256sum 2>/dev/null \
                | sha256sum \
                | awk '{print $1}'
        )
    else
        (
            cd "$pasta" || exit 1
            find manager.sh modules -type f -print 2>/dev/null \
                | sort \
                | while IFS= read -r arquivo; do cksum "$arquivo"; done \
                | cksum \
                | awk '{print $1}'
        )
    fi
}


versao_nome_pacote() {
    local nome
    nome="$(basename "$1")"
    if [[ "$nome" =~ ^manager-v([0-9]+\.[0-9]+\.[0-9]+)\.zip$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "não padronizado"
    fi
}

data_arquivo_manager() {
    local arquivo="$1"
    date -r "$arquivo" '+%d/%m/%Y %H:%M' 2>/dev/null || echo "não disponível"
}

arquivo_status_atualizacao() {
    printf '%s' "$BASE_DIR/.updates/last-update.conf"
}

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

listar_pacotes_completos() {
    ATUALIZACOES_ENCONTRADAS=()
    local arquivo
    # Aceita qualquer .zip na pasta Download, não só "manager*.zip". O
    # conteúdo é validado depois (precisa ter manager.sh e modules/ dentro),
    # então não há motivo para exigir um nome de arquivo específico — isso
    # só fazia atualizações sumirem da lista quando o navegador salvava com
    # outro nome (ex.: "manager (1).zip", "download.zip").
    while IFS= read -r -d '' arquivo; do
        ATUALIZACOES_ENCONTRADAS+=("$arquivo")
    done < <(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 -type f \
        -iname '*.zip' \
        -print0 2>/dev/null | sort -z)
}

listar_modulos_atualizacao() {
    ATUALIZACOES_ENCONTRADAS=()
    local arquivo nome
    while IFS= read -r -d '' arquivo; do
        nome="$(basename "$arquivo")"
        nome="${nome%.module.sh}.sh"
        if [ "$nome" = "manager.sh" ] || [ -f "$MODULES_DIR/$nome" ]; then
            ATUALIZACOES_ENCONTRADAS+=("$arquivo")
        fi
    done < <(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 -type f \
        \( -iname 'manager.sh' -o -iname '*.module.sh' -o -iname '*.sh' \) \
        -print0 2>/dev/null | sort -z)
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

instalar_pacote_manager() {
    local arquivo="$1"
    garantir_comando unzip unzip
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
    local tamanho_extraido arquivos_pacote espaco_livre tamanho_backup_estimado
    tamanho_extraido="$(du -sb "$pacote" 2>/dev/null | awk '{print $1}')"
    [ -n "$tamanho_extraido" ] || tamanho_extraido=0
    arquivos_pacote="$(find "$pacote" -type f 2>/dev/null | wc -l | tr -d ' ')"
    espaco_livre="$(df -Pk "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $4 * 1024}')"
    [ -n "$espaco_livre" ] || espaco_livre=0
    tamanho_backup_estimado="$(du -sb "$BASE_DIR/manager.sh" "$BASE_DIR/modules" 2>/dev/null | awk '{s+=$1} END {print s+0}')"

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
    tar -czf "$backup" -C "$BASE_DIR" manager.sh modules || { error "Falha ao criar backup."; rm -rf "$tmp"; pause; return; }
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
        rm -rf "$MODULES_DIR"; mv "$antigos_modulos" "$MODULES_DIR" 2>/dev/null || true
        tar -xzf "$backup" -C "$BASE_DIR" 2>/dev/null || true
        error "Atualização falhou; o backup foi restaurado."; rm -rf "$tmp"; pause; return
    fi
    tela_atualizacao_etapa 4 "$total_etapas" "Aplicando a atualização" "Núcleo e módulos substituídos." "concluída"
    sleep 0.35
    tela_atualizacao_etapa 5 "$total_etapas" "Finalizando" "Registrando a atualização e preparando o reinício."
    rm -rf "$tmp"
    cat > "$(arquivo_status_atualizacao)" <<EOF
DATA="$(date '+%d/%m/%Y %H:%M:%S')"
TIPO="completa"
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

instalar_modulo_manager() {
    local arquivo="$1" updates_dir="$BASE_DIR/.updates" stamp nome destino descricao
    stamp="$(date '+%Y%m%d_%H%M%S')"; mkdir -p "$updates_dir"
    bash -n "$arquivo" || { error "O arquivo possui erro de sintaxe."; pause; return; }
    nome="$(basename "$arquivo")"; nome="${nome%.module.sh}.sh"
    if [ "$nome" = "manager.sh" ]; then destino="$SELF_PATH"; descricao="arquivo principal"
    elif [ -f "$MODULES_DIR/$nome" ]; then destino="$MODULES_DIR/$nome"; descricao="módulo $nome"
    else error "O arquivo não corresponde a um módulo instalado."; pause; return; fi

    local hash_atual hash_novo tamanho_atual tamanho_novo linhas_atual linhas_novo
    hash_atual="$(hash_arquivo_manager "$destino")"; hash_novo="$(hash_arquivo_manager "$arquivo")"
    tamanho_atual="$(stat -c%s "$destino" 2>/dev/null || echo 0)"; tamanho_novo="$(stat -c%s "$arquivo" 2>/dev/null || echo 0)"
    linhas_atual="$(wc -l < "$destino")"; linhas_novo="$(wc -l < "$arquivo")"

    cabecalho_tela "🧩 Atualização de módulo" "Somente um arquivo será substituído"
    caixa_simples "Comparação" \
        "Destino: $descricao" \
        "Atual: $(formatar_tamanho "$tamanho_atual") • $linhas_atual linhas" \
        "Novo: $(formatar_tamanho "$tamanho_novo") • $linhas_novo linhas" \
        "Hash atual: ${hash_atual:0:12}…" \
        "Hash novo: ${hash_novo:0:12}…"
    [ "$hash_atual" = "$hash_novo" ] && { ok "Este arquivo já está instalado."; pause; return; }
    confirmar_acao "Substituir somente $descricao?" "n" || return

    local backup="$updates_dir/${nome}.backup_$stamp" temporario="$BASE_DIR/.update_${nome}_$stamp" hash_final hash_esperado
    cp "$destino" "$backup" || { error "Falha ao criar backup."; pause; return; }
    tr -d '\r' < "$arquivo" > "$temporario" || { error "Falha ao copiar o arquivo."; rm -f "$temporario"; pause; return; }
    bash -n "$temporario" || { error "A cópia temporária é inválida."; rm -f "$temporario"; pause; return; }
    # Calculado a partir do arquivo JÁ limpo (pós tr -d '\r'), não do original
    # em "$arquivo". Antes disso comparava com o hash do arquivo original,
    # que quase sempre é diferente quando o arquivo baixado tem quebras de
    # linha estilo Windows (\r\n) — fazendo a verificação abaixo falhar e
    # desfazer a atualização mesmo quando ela tinha dado certo.
    hash_esperado="$(hash_arquivo_manager "$temporario")"
    [ "$nome" = manager.sh ] && chmod 700 "$temporario" || chmod 600 "$temporario"
    mv -f "$temporario" "$destino" || { cp "$backup" "$destino"; error "Falha ao substituir o arquivo."; pause; return; }
    hash_final="$(hash_arquivo_manager "$destino")"
    if [ "$hash_final" != "$hash_esperado" ] || ! bash -n "$destino"; then
        cp "$backup" "$destino"; error "A verificação falhou; o backup foi restaurado."; pause; return
    fi
    cat > "$(arquivo_status_atualizacao)" <<EOF
DATA="$(date '+%d/%m/%Y %H:%M:%S')"
TIPO="módulo"
ARQUIVO="$(basename "$arquivo")"
DESTINO="$nome"
VERSAO_ANTERIOR="$MANAGER_VERSION"
VERSAO_NOVA="$MANAGER_VERSION"
STATUS="confirmada"
EOF
    ok "$descricao atualizado com sucesso."
    info "O Manager será fechado para recarregar os módulos."
    sleep 2; exit 0
}

atualizar_manager_local() {
    if ! check_storage_access; then
        pause
        return
    fi
    while true; do
        menu_unificado "🔄 Atualizar Manager" "Escolha exatamente o que deseja atualizar" \
            "[0] Voltar  •  [1–3] Selecionar" \
            "1|📦|Atualização completa|Usar manager.zip e substituir todo o Manager" \
            "2|🧩|Atualizar um módulo|Substituir somente um arquivo .sh" \
            "3|🕘|Ver última atualização|Confirmar data, arquivo e status"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1)
                listar_pacotes_completos
                selecionar_atualizacao_lista "📦 Atualização completa" "Qualquer .zip válido do Manager no Download" || continue
                instalar_pacote_manager "$ATUALIZACAO_ESCOLHIDA"
                ;;
            2)
                listar_modulos_atualizacao
                selecionar_atualizacao_lista "🧩 Atualizar um módulo" "Procura manager.sh ou arquivos .sh compatíveis" || continue
                instalar_modulo_manager "$ATUALIZACAO_ESCOLHIDA"
                ;;
            3) mostrar_ultima_atualizacao_manager ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
