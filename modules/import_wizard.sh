# Módulo: import_wizard.sh
# Assistente de importação: origem, ZIP, destino, conflitos e pós-importação.

wizard_resetar_importacao() {
    WIZ_ORIGEM_BASE=""; WIZ_ORIGEM=""; WIZ_TIPO=""; WIZ_MODO=""
    WIZ_DESTINO=""; WIZ_ACHATAR=false; WIZ_SOBRESCREVER=false
    WIZ_DESTINO_FIXO=false; WIZ_ZIP_NOME=""; WIZ_ORIGEM_ORIGINAL=""
    WIZ_NOME_PROJETO=""; WIZ_DESTINO_PROJETO=false; WIZ_CAMADA_EXTERNA=""
    WIZ_ITENS=()
    WIZ_DEPS_PRESERVADAS=()
}

wizard_localizar_origem() {
    check_storage_access || return 1
    # A origem padrão é sempre a raiz de Downloads. Não entra automaticamente
    # em Downloads/projetos: arquivos recém-baixados devem aparecer no assistente
    # sem exigir que o usuário mova o pacote antes de importar.
    WIZ_ORIGEM_BASE="$DOWNLOADS_DIR"
}

wizard_etapa_item() {
    local entradas=() caminhos=() f i=1
    while IFS= read -r -d '' f; do
        caminhos+=("$f")
        icone_tipo_item "$f"
        entradas+=("$i|$ICON_ITEM|$(basename "$f")|$TIPO_ITEM")
        i=$((i+1))
    done < <(find "$WIZ_ORIGEM_BASE" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z)
    [ ${#caminhos[@]} -gt 0 ] || { warn "Nenhum item encontrado em $WIZ_ORIGEM_BASE."; pause; return 1; }

    wizard_cabecalho 1 5 "Importar projeto" "Escolha uma pasta, arquivo ou ZIP."
    caixa_simples "📂 Origem" "$(caminho_curto "$WIZ_ORIGEM_BASE")"
    echo
    caixa_linha_topo
    local item
    for item in "${entradas[@]}"; do
        IFS='|' read -r n ic nome desc <<< "$item"
        menu_opcao "$n" "$ic" "$nome" "$desc"
    done
    caixa_linha_baixo
    rodape_atalhos "[0] Cancelar  •  [número] Selecionar"
    ler_opcao
    [ "$RESPOSTA_MENU" = 0 ] && return 1
    [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] || return 2
    [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#caminhos[@]} ] || return 2
    WIZ_ORIGEM="${caminhos[$((RESPOSTA_MENU-1))]}"
    WIZ_ORIGEM_ORIGINAL="$WIZ_ORIGEM"
    icone_tipo_item "$WIZ_ORIGEM"; WIZ_TIPO="$TIPO_ITEM"
    return 0
}


nome_projeto_sem_versao() {
    local nome="$1"
    nome="${nome%.zip}"
    # Remove apenas sufixos de versão semântica claros. Não altera nomes como
    # api-v2, projeto-2026 ou outros números que façam parte do nome real.
    printf '%s\n' "$nome" | sed -E 's/[-_.]?v?[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$//'
}


validar_zip_importacao() {
    local arquivo="$1" entrada
    [ -f "$arquivo" ] || return 1
    command -v unzip >/dev/null 2>&1 || return 1

    while IFS= read -r entrada; do
        [ -z "$entrada" ] && continue
        entrada="${entrada//\\//}"
        case "$entrada" in
            /*|[A-Za-z]:/*)
                error "ZIP recusado: caminho absoluto encontrado ($entrada)."
                return 1
                ;;
        esac
        if [[ "/$entrada/" == *"/../"* ]]; then
            error "ZIP recusado: caminho que tenta sair da pasta de extração ($entrada)."
            return 1
        fi
    done < <(unzip -Z1 "$arquivo" 2>/dev/null)
    return 0
}

wizard_preparar_zip_extraido() {
    local tmp="$1"
    shopt -s nullglob dotglob
    local raiz=("$tmp"/*)
    shopt -u nullglob dotglob

    WIZ_CAMADA_EXTERNA=""
    if [ ${#raiz[@]} -eq 1 ] && [ -d "${raiz[0]}" ]; then
        # A pasta única do topo é tratada como embalagem do pacote. Guardamos
        # seu nome para criar a pasta do projeto quando o destino for Projetos,
        # mas copiamos o CONTEÚDO dela para evitar projeto/projeto/...
        WIZ_ORIGEM="${raiz[0]}"
        WIZ_CAMADA_EXTERNA="$(basename "${raiz[0]}")"
        WIZ_NOME_PROJETO="$(nome_projeto_sem_versao "$WIZ_CAMADA_EXTERNA")"
        WIZ_MODO="ZIP extraído • pasta externa detectada"
    else
        WIZ_ORIGEM="$tmp"
        WIZ_NOME_PROJETO="$(nome_projeto_sem_versao "$WIZ_ZIP_NOME")"
        WIZ_MODO="ZIP extraído • arquivos na raiz"
    fi
    [ -n "$WIZ_NOME_PROJETO" ] || WIZ_NOME_PROJETO="projeto"
    WIZ_ITENS=("$WIZ_ORIGEM")
    # A organização final é definida somente depois que o usuário escolher o
    # destino: Painel = solto; Projetos = pasta própria obrigatória.
    WIZ_ACHATAR=true
    WIZ_DESTINO=""
    WIZ_DESTINO_FIXO=false
    WIZ_DESTINO_PROJETO=false
}

wizard_etapa_modo() {
    # Reentrar nesta etapa deve descartar apenas escolhas posteriores.
    # A origem selecionada na etapa 1 é restaurada para que um ZIP continue
    # sendo tratado como ZIP mesmo após o usuário voltar da etapa 3.
    [ -n "$WIZ_ORIGEM_ORIGINAL" ] && WIZ_ORIGEM="$WIZ_ORIGEM_ORIGINAL"
    WIZ_ITENS=(); WIZ_ACHATAR=false; WIZ_DESTINO_FIXO=false; WIZ_DESTINO=""; WIZ_DESTINO_PROJETO=false; WIZ_CAMADA_EXTERNA=""
    if [ -d "$WIZ_ORIGEM" ]; then
        menu_unificado "🧭 Importar projeto" "Etapa 2 de 5 — Como importar" \
            "[0] Voltar  •  [1–2] Selecionar" \
            "1|📦|Projeto completo|Importa o conteúdo da pasta selecionada" \
            "2|📄|Arquivos da raiz|Escolha somente arquivos soltos da pasta"
        ler_opcao
        case "$RESPOSTA_MENU" in
            0) return 10 ;;
            1)
                WIZ_MODO="Projeto completo"
                WIZ_ITENS=("$WIZ_ORIGEM")
                WIZ_NOME_PROJETO="$(nome_projeto_sem_versao "$(basename "$WIZ_ORIGEM")")"
                WIZ_ACHATAR=true
                ;;
            2)
                local arquivos=() f i=1
                while IFS= read -r -d '' f; do arquivos+=("$f"); done \
                    < <(find "$WIZ_ORIGEM" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)
                [ ${#arquivos[@]} -gt 0 ] || { warn "A pasta não possui arquivos na raiz."; pause; return 2; }
                wizard_cabecalho 2 5 "Selecionar arquivos" "Informe os números separados por espaço."
                caixa_linha_topo
                for f in "${arquivos[@]}"; do menu_opcao "$i" "📄" "$(basename "$f")" "Arquivo da raiz"; i=$((i+1)); done
                caixa_linha_baixo
                rodape_atalhos "[0] Voltar  •  Exemplo: 1 3 4"
                read -rp "Arquivos: " -a indices
                [ "${indices[0]:-}" = 0 ] && return 10
                local idx
                for idx in "${indices[@]}"; do
                    [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le ${#arquivos[@]} ] && WIZ_ITENS+=("${arquivos[$((idx-1))]}")
                done
                [ ${#WIZ_ITENS[@]} -gt 0 ] || { warn "Nenhum arquivo válido selecionado."; pause; return 2; }
                WIZ_MODO="Arquivos selecionados"
                WIZ_NOME_PROJETO="$(nome_projeto_sem_versao "$(basename "$WIZ_ORIGEM")")"
                ;;
            *) return 2 ;;
        esac
    elif [[ "${WIZ_ORIGEM,,}" == *.zip ]]; then
        WIZ_ZIP_NOME="$(basename "${WIZ_ORIGEM%.zip}")"
        menu_unificado "🧭 Importar projeto" "Etapa 2 de 5 — Pacote ZIP" \
            "[0] Voltar  •  [1–2] Selecionar" \
            "1|📦|Extrair e importar|Descompactar e analisar" \
            "2|📦|Copiar o ZIP|Manter o arquivo compactado"
        ler_opcao
        case "$RESPOSTA_MENU" in
            0) return 10 ;;
            1)
                garantir_comando unzip unzip
                if ! validar_zip_importacao "$WIZ_ORIGEM"; then
                    warn "A importação foi cancelada antes da extração por segurança."
                    pause
                    return 2
                fi
                local tmp="$SESSION_TMP_DIR/${WIZ_ZIP_NOME}_extraido"
                rm -rf "$tmp"; mkdir -p "$tmp"
                info "Extraindo $(basename "$WIZ_ORIGEM")..."
                if ! unzip -q "$WIZ_ORIGEM" -d "$tmp"; then error "Não foi possível extrair o ZIP."; pause; return 2; fi
                wizard_preparar_zip_extraido "$tmp"
                ;;
            2) WIZ_ITENS=("$WIZ_ORIGEM"); WIZ_MODO="Arquivo ZIP" ;;
            *) return 2 ;;
        esac
    else
        WIZ_ITENS=("$WIZ_ORIGEM"); WIZ_MODO="Arquivo único"
    fi
    return 0
}

wizard_definir_destino() {
    local escolha="$1"
    case "$escolha" in
        painel)
            WIZ_DESTINO="$PAINEL_DIR"
            WIZ_DESTINO_PROJETO=false
            WIZ_ACHATAR=true
            ;;
        projetos)
            [ -n "$WIZ_NOME_PROJETO" ] || return 1
            WIZ_DESTINO="$PROJETOS_DIR/$WIZ_NOME_PROJETO"
            WIZ_DESTINO_PROJETO=true
            WIZ_ACHATAR=true
            ;;
        *) return 1 ;;
    esac
}

wizard_etapa_destino() {
    local permite_projetos=true
    case "$WIZ_MODO" in
        "Arquivo único"|"Arquivo ZIP") permite_projetos=false ;;
    esac

    wizard_cabecalho 3 5 "Escolher destino" "Defina como o conteúdo será organizado."
    caixa_linha_topo
    menu_opcao 1 "📂" "~/Painel" "Conteúdo solto diretamente no Painel"
    if [ "$permite_projetos" = true ]; then
        local nome_exib="${WIZ_NOME_PROJETO:-projeto}"
        menu_opcao 2 "📁" "~/Painel/projetos/$nome_exib" "Cria a pasta do projeto automaticamente"
    else
        menu_opcao 2 "🚫" "~/Painel/projetos" "Arquivos avulsos não podem ficar soltos em projetos"
    fi
    caixa_linha_baixo
    rodape_atalhos "[0] Voltar  •  [1–2] Selecionar"
    ler_opcao
    case "$RESPOSTA_MENU" in
        0) return 10 ;;
        1) wizard_definir_destino painel || return 2 ;;
        2)
            [ "$permite_projetos" = true ] || return 2
            wizard_definir_destino projetos || { warn "Não foi possível determinar o nome do projeto."; pause; return 2; }
            ;;
        *) return 2 ;;
    esac
}

wizard_etapa_conflitos() {
    local alvo="$WIZ_DESTINO"
    WIZ_SOBRESCREVER=false

    # Em ~/Painel o conteúdo é deliberadamente solto; conflitos continuam
    # sendo tratados arquivo por arquivo pelo motor de cópia. Em Projetos, o
    # destino é uma pasta exclusiva e pode ser mesclado ou substituído inteiro.
    if [ "$WIZ_DESTINO_PROJETO" = true ] && [ -e "$alvo" ]; then
        menu_unificado "🧭 Importar projeto" "Etapa 4 de 5 — Conflitos" \
            "[0] Voltar  •  [1–2] Selecionar" \
            "1|🔄|Mesclar com segurança|Mantém a pasta e trata conflitos arquivo por arquivo" \
            "2|🧹|Substituir projeto|Remove a pasta atual antes da importação"
        ler_opcao
        case "$RESPOSTA_MENU" in 0) return 10;; 1) WIZ_SOBRESCREVER=false;; 2) WIZ_SOBRESCREVER=true;; *) return 2;; esac
    else
        wizard_cabecalho 4 5 "Verificar conflitos" "Destino preparado para a importação."
        if [ "$WIZ_DESTINO_PROJETO" = true ]; then
            caixa_simples "✅ Pasta do projeto" "$(caminho_curto "$alvo")" "Será criada automaticamente."
        else
            caixa_simples "📂 Conteúdo solto" "$(caminho_curto "$alvo")" "Conflitos serão tratados arquivo por arquivo."
        fi
        rodape_atalhos "[0] Voltar  •  [Enter] Continuar"
        ui_buffer_flush
        read -r RESPOSTA_MENU
        [ "$RESPOSTA_MENU" = 0 ] && return 10
        [ -z "$RESPOSTA_MENU" ] && return 0
        return 2
    fi
    return 0
}

wizard_etapa_revisao() {
    [ "$CONFIRMAR_COPIA" = true ] || return 0
    wizard_cabecalho 5 5 "Revisar importação" "Confira antes de copiar."
    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}📦 Item:${C_RESET} $(basename "$WIZ_ORIGEM")"
    caixa_linha_texto "🏷  Tipo: $WIZ_TIPO"
    caixa_linha_texto "🧭 Modo: $WIZ_MODO"
    caixa_linha_texto "📍 Destino: $(caminho_curto "$WIZ_DESTINO")"
    if [ "$WIZ_DESTINO_PROJETO" = true ]; then
        caixa_linha_texto "📁 Organização: pasta própria do projeto"
    else
        caixa_linha_texto "📂 Organização: conteúdo solto no Painel"
    fi
    if [ "$WIZ_ACHATAR" = true ] && [ -d "$WIZ_ORIGEM" ]; then
        [ -n "$WIZ_CAMADA_EXTERNA" ] && caixa_linha_texto "📦 Camada do ZIP: $WIZ_CAMADA_EXTERNA (não duplicada)"
        local previa="" nome count=0 child
        shopt -s nullglob dotglob
        for child in "$WIZ_ORIGEM"/*; do
            nome="$(basename "$child")"
            [ -z "$previa" ] && previa="$nome" || previa="$previa, $nome"
            count=$((count+1)); [ "$count" -ge 3 ] && break
        done
        shopt -u nullglob dotglob
        [ -n "$previa" ] && caixa_linha_texto "↳ Conteúdo: $(truncar_caminho "$previa" $((LARGURA_CAIXA-15)))"
    fi
    caixa_linha_texto "📚 Itens: ${#WIZ_ITENS[@]}"
    caixa_linha_texto "🧹 Substituir pasta: $(valor_legivel_bool "$WIZ_SOBRESCREVER")"
    caixa_linha_baixo
    rodape_atalhos "[0] Voltar  •  [Enter/1] Confirmar"
    ler_opcao
    case "$RESPOSTA_MENU" in
        ""|1) return 0 ;;
        0) return 10 ;;
        2) return 20 ;;
        *) return 2 ;;
    esac
}

hash_manifesto_portavel() {
    local dir="$1" arquivo saida=""
    for arquivo in package.json package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock; do
        [ -f "$dir/$arquivo" ] || continue
        if command -v sha256sum >/dev/null 2>&1; then
            saida+="${arquivo}:$(sha256sum "$dir/$arquivo" 2>/dev/null | awk '{print $1}')\n"
        elif command -v shasum >/dev/null 2>&1; then
            saida+="${arquivo}:$(shasum -a 256 "$dir/$arquivo" 2>/dev/null | awk '{print $1}')\n"
        else
            saida+="${arquivo}:$(wc -c < "$dir/$arquivo" 2>/dev/null)\n"
        fi
    done
    printf '%b' "$saida" | { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else cksum | awk '{print $1}'; fi; }
}

preservar_dependencias_substituicao() {
    # Mantém node_modules entre pacotes completos quando package.json/lockfiles
    # não mudaram. O move ocorre dentro do armazenamento privado do Termux e é
    # praticamente instantâneo, evitando reinstalar centenas de pacotes.
    local origem="$1" destino="$2" pkg rel src_dir dst_dir h_old h_new cache chave
    WIZ_DEPS_PRESERVADAS=()
    [ -d "$origem" ] && [ -d "$destino" ] || return 0
    declare -F hash_dependencias >/dev/null 2>&1 || return 0

    mkdir -p "$SESSION_TMP_DIR/preserved_deps"
    while IFS= read -r -d '' pkg; do
        dst_dir="$(dirname "$pkg")"
        rel="${dst_dir#"$destino"}"
        rel="${rel#/}"
        [ -n "$rel" ] || rel="."
        src_dir="$origem"
        [ "$rel" != "." ] && src_dir="$origem/$rel"
        [ -f "$src_dir/package.json" ] || continue
        [ -d "$dst_dir/node_modules" ] || continue

        h_old="$(hash_manifesto_portavel "$dst_dir" 2>/dev/null || true)"
        h_new="$(hash_manifesto_portavel "$src_dir" 2>/dev/null || true)"
        [ -n "$h_old" ] && [ "$h_old" = "$h_new" ] || continue

        chave="$(printf '%s' "$rel" | sed 's#[^A-Za-z0-9._-]#_#g')"
        cache="$SESSION_TMP_DIR/preserved_deps/${chave}_node_modules"
        rm -rf "$cache" 2>/dev/null || true
        if mv "$dst_dir/node_modules" "$cache" 2>/dev/null; then
            WIZ_DEPS_PRESERVADAS+=("$rel|$cache")
            log "INFO" "Dependências preservadas para cópia rápida: ${rel}"
        fi
    done < <(find "$destino" -maxdepth 4 -type f -name package.json -not -path '*/node_modules/*' -print0 2>/dev/null)
}

restaurar_dependencias_substituicao() {
    local destino="$1" item rel cache dst_dir
    [ ${#WIZ_DEPS_PRESERVADAS[@]} -gt 0 ] || return 0
    for item in "${WIZ_DEPS_PRESERVADAS[@]}"; do
        rel="${item%%|*}"
        cache="${item#*|}"
        [ -d "$cache" ] || continue
        dst_dir="$destino"
        [ "$rel" != "." ] && dst_dir="$destino/$rel"
        mkdir -p "$dst_dir"
        if [ -d "$dst_dir/node_modules" ]; then
            rm -rf "$cache" 2>/dev/null || true
            continue
        fi
        if mv "$cache" "$dst_dir/node_modules" 2>/dev/null; then
            ok "Dependências reutilizadas: ${rel}"
            log "INFO" "node_modules restaurado sem npm install: ${rel}"
        fi
    done
    WIZ_DEPS_PRESERVADAS=()
}

wizard_executar_importacao() {
    local item alvo origem_pacote="" falhas=0
    ULTIMA_COPIA_OK=false

    if [ "$WIZ_SOBRESCREVER" = true ] && [ "$WIZ_DESTINO_PROJETO" = true ]; then
        alvo="$WIZ_DESTINO"
        garantir_cwd_fora_do_alvo "$alvo" || { error "Não foi possível mover o terminal para um diretório seguro."; pause; return 1; }
        if [ ${#WIZ_ITENS[@]} -eq 1 ] && [ -d "${WIZ_ITENS[0]}" ]; then
            origem_pacote="${WIZ_ITENS[0]}"
            preservar_dependencias_substituicao "$origem_pacote" "$alvo"
        fi
        if ! rm -rf -- "$alvo"; then
            error "Não foi possível remover o projeto atual antes da substituição."
            restaurar_dependencias_substituicao "$alvo"
            return 1
        fi
    fi

    if [ ${#WIZ_ITENS[@]} -eq 1 ] && [ -d "${WIZ_ITENS[0]}" ]; then
        # WIZ_DESTINO já é o destino FINAL. Para Painel, recebe os itens soltos;
        # para Projetos, aponta para ~/Painel/projetos/<nome> e recebe o mesmo
        # conteúdo, sem criar uma segunda camada com o nome da pasta origem.
        if ! motor_copia "${WIZ_ITENS[0]}" "$WIZ_DESTINO" true false; then
            # Se uma substituição preservou node_modules e a cópia falhar,
            # restaura o cache no destino parcial em vez de abandoná-lo no tmp.
            restaurar_dependencias_substituicao "$WIZ_DESTINO"
            return 1
        fi
    else
        cabecalho_tela "📥 Importando arquivos" "Cópia segura para $(caminho_curto "$WIZ_DESTINO")"
        mkdir -p "$WIZ_DESTINO" || { error "Não foi possível criar o destino."; return 1; }
        for item in "${WIZ_ITENS[@]}"; do
            if [ -e "$WIZ_DESTINO/$(basename "$item")" ]; then
                warn "Já existe: $(basename "$item"). Item pulado."
                continue
            fi
            if cp -a -- "$item" "$WIZ_DESTINO/"; then
                ok "Copiado: $(basename "$item")"
            else
                error "Falha ao copiar: $(basename "$item")"
                falhas=$((falhas + 1))
            fi
        done
        if [ "$falhas" -gt 0 ]; then
            warn "Importação incompleta: $falhas item(ns) não puderam ser copiados."
            return 1
        fi
    fi

    restaurar_dependencias_substituicao "$WIZ_DESTINO"

    ULTIMO_PROJETO_IMPORTADO="$WIZ_DESTINO"
    ULTIMA_COPIA_OK=true
    return 0
}

wizard_pos_importacao() {
    local projeto="$1"
    [ -d "$projeto" ] || return 0

    # Só oferece ações de projeto quando o destino realmente contém uma stack
    # reconhecível. Arquivos avulsos continuam retornando ao assistente normal.
    if ! eh_projeto_valido "$projeto"; then
        ok "Importação concluída em $(caminho_curto "$projeto")."
        pause
        return 0
    fi

    while true; do
        detectar_estrutura_projeto "$projeto"
        nome_amigavel_projeto "$projeto"
        rotulo_stack_projeto "$projeto"
        cabecalho_tela "✅ Projeto importado" "$NOME_PROJETO • $ROTULO_STACK"
        caixa_simples "📍 Destino" "$(caminho_curto "$projeto")"
        echo
        caixa_linha_topo
        menu_opcao 1 "🧪" "Testar agora" "Executar o projeto que acabou de ser importado"
        menu_opcao 2 "⚙️" "Abrir menu do projeto" "Ir direto às ações deste projeto"
        menu_opcao 3 "📦" "Importar outro projeto" "Voltar à lista de Downloads"
        menu_opcao 0 "🏠" "Menu principal" "Encerrar o assistente de importação"
        caixa_linha_baixo
        rodape_atalhos "[0–3] Selecionar"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1)
                # O usuário acabou de copiar/importar este projeto. Neste ponto
                # o Manager já conhece a assinatura das dependências; repetir
                # npm ls/varredura de node_modules só atrasa o teste em aparelhos
                # mais modestos. O modo vale apenas para esta execução.
                TESTE_POS_IMPORTACAO_RAPIDO=true
                detectar_estrutura_projeto "$projeto"
                if [ "$PROJ_MODO" = fullstack ]; then
                    testar_componente "$projeto" ambos
                else
                    testar_projeto "$projeto"
                fi
                TESTE_POS_IMPORTACAO_RAPIDO=false
                ;;
            2) tela_projeto "$projeto" ;;
            3) return 30 ;;
            0|"") return 0 ;;
            *) warn "Opção inválida."; pause ;;
        esac
    done
}

importar_projeto() {
    wizard_resetar_importacao
    wizard_localizar_origem || { pause; return; }
    local etapa=1 rc
    while true; do
        case "$etapa" in
            1) wizard_etapa_item; rc=$? ;;
            2) wizard_etapa_modo; rc=$? ;;
            3) wizard_etapa_destino; rc=$? ;;
            4) wizard_etapa_conflitos; rc=$? ;;
            5) wizard_etapa_revisao; rc=$? ;;
        esac
        case "$rc" in
            0)
                if [ "$etapa" -eq 5 ]; then
                    if wizard_executar_importacao; then
                        wizard_pos_importacao "$WIZ_DESTINO"
                        rc=$?
                        if [ "$rc" -eq 30 ]; then
                            wizard_resetar_importacao
                            wizard_localizar_origem || return
                            etapa=1
                            continue
                        fi
                    fi
                    return
                fi
                etapa=$((etapa+1))
                ;;
            10) etapa=$((etapa-1)); [ "$etapa" -lt 1 ] && return ;;
            20) wizard_resetar_importacao; wizard_localizar_origem || return; etapa=1 ;;
            *) warn "Opção inválida."; pause ;;
        esac
    done
}

# ============================================================================
# MOTOR DE CÓPIA COM PROGRESSO
# ============================================================================

# Formata um tamanho em bytes para algo legível (KB/MB/GB)
