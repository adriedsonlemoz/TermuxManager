# Módulo: import.sh
# Manager.sh — módulo

# ============================================================================
# IMPORTAR PROJETO
# ============================================================================

# Estado do assistente de importação. Mantido em variáveis globais para permitir
# navegar entre etapas sem perder escolhas.
WIZ_ORIGEM_BASE=""; WIZ_ORIGEM=""; WIZ_TIPO=""; WIZ_MODO=""
WIZ_DESTINO=""; WIZ_ACHATAR=false; WIZ_SOBRESCREVER=false
WIZ_DESTINO_FIXO=false; WIZ_ZIP_NOME=""; WIZ_ORIGEM_ORIGINAL=""
WIZ_NOME_PROJETO=""; WIZ_DESTINO_PROJETO=false; WIZ_CAMADA_EXTERNA=""
WIZ_ITENS=()
WIZ_DEPS_PRESERVADAS=()
ULTIMO_PROJETO_IMPORTADO=""
ULTIMA_COPIA_OK=false

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
    local item alvo origem_pacote=""
    if [ "$WIZ_SOBRESCREVER" = true ] && [ "$WIZ_DESTINO_PROJETO" = true ]; then
        alvo="$WIZ_DESTINO"
        garantir_cwd_fora_do_alvo "$alvo" || { error "Não foi possível mover o terminal para um diretório seguro."; pause; return 1; }
        if [ ${#WIZ_ITENS[@]} -eq 1 ] && [ -d "${WIZ_ITENS[0]}" ]; then
            origem_pacote="${WIZ_ITENS[0]}"
            preservar_dependencias_substituicao "$origem_pacote" "$alvo"
        fi
        rm -rf "$alvo"
    fi

    if [ ${#WIZ_ITENS[@]} -eq 1 ] && [ -d "${WIZ_ITENS[0]}" ]; then
        # WIZ_DESTINO já é o destino FINAL. Para Painel, recebe os itens soltos;
        # para Projetos, aponta para ~/Painel/projetos/<nome> e recebe o mesmo
        # conteúdo, sem criar uma segunda camada com o nome da pasta origem.
        motor_copia "${WIZ_ITENS[0]}" "$WIZ_DESTINO" true false || return 1
    else
        cabecalho_tela "📥 Importando arquivos" "Cópia segura para $(caminho_curto "$WIZ_DESTINO")"
        mkdir -p "$WIZ_DESTINO"
        for item in "${WIZ_ITENS[@]}"; do
            if [ -e "$WIZ_DESTINO/$(basename "$item")" ]; then warn "Já existe: $(basename "$item"). Item pulado."; continue; fi
            cp -a "$item" "$WIZ_DESTINO/" && ok "Copiado: $(basename "$item")"
        done
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
formatar_tamanho() {
    local bytes="$1"
    if [ "$bytes" -ge 1073741824 ]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f GB", b/1073741824 }'
    elif [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f MB", b/1048576 }'
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f KB", b/1024 }'
    else
        echo "${bytes} B"
    fi
}

# Formata segundos para MM:SS
formatar_tempo() {
    local total="$1"
    printf "%02d:%02d" $((total / 60)) $((total % 60))
}

# Trunca um caminho relativo para caber na caixa, mantendo o final (mais útil)
truncar_caminho() {
    local caminho="$1" max="$2"
    local len=${#caminho}
    if [ "$len" -le "$max" ]; then
        echo "$caminho"
    else
        echo "…${caminho: -$((max-1))}"
    fi
}

ALTURA_CAIXA_PROGRESSO=8
_PROGRESSO_INICIADO=false
_PROGRESSO_ULTIMO_RENDER_MS=0

agora_milisegundos() {
    date +%s%3N 2>/dev/null || echo "$(( $(date +%s) * 1000 ))"
}

# Renderização específica da fase de análise. A descoberta inicial não conhece
# o total de arquivos; por isso não exibe uma porcentagem falsa de 100% em cada
# atualização. A porcentagem só aparece na segunda etapa, quando o total já é
# conhecido e estamos calculando o tamanho real do conteúdo.
progresso_analise_render() {
    local titulo="$1" etapa="$2" indice="$3" total="$4" arq_rel="$5" inicio="$6"
    local agora decorrido arq_mostrar largura_barra pct preenchido vazio barra
    agora=$(date +%s); decorrido=$((agora - inicio)); [ "$decorrido" -lt 0 ] && decorrido=0
    arq_mostrar="$(truncar_caminho "$arq_rel" $((LARGURA_CAIXA - 18)))"

    if [ "$_PROGRESSO_INICIADO" == true ]; then
        printf "\033[%dA" "$ALTURA_CAIXA_PROGRESSO"
    fi
    _PROGRESSO_INICIADO=true

    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}📦 Analisando ${titulo}${C_RESET}" true
    caixa_linha_sep
    if [ "$etapa" = descoberta ]; then
        caixa_linha_texto "Etapa 1/2 • Descobrindo arquivos"
        caixa_linha_texto "➜ ${indice} arquivo(s) encontrado(s)"
        caixa_linha_texto "➜ Verificando: ${C_DIM}${arq_mostrar}${C_RESET}"
        caixa_linha_texto "⏳ $(formatar_tempo "$decorrido") decorridos • total ainda sendo calculado"
    else
        pct=$((total > 0 ? indice * 100 / total : 0)); [ "$pct" -gt 100 ] && pct=100
        largura_barra=$((LARGURA_CAIXA - 12)); [ "$largura_barra" -lt 10 ] && largura_barra=10
        preenchido=$((largura_barra * pct / 100)); vazio=$((largura_barra - preenchido))
        barra="$(repetir_char '█' "$preenchido")$(repetir_char '░' "$vazio")"
        caixa_linha_texto "Etapa 2/2 • Calculando tamanho"
        caixa_linha_texto "${C_GREEN}${barra}${C_RESET} ${pct}%"
        caixa_linha_texto "${indice}/${total} arquivos • ➜ ${C_DIM}${arq_mostrar}${C_RESET}"
        caixa_linha_texto "⏳ $(formatar_tempo "$decorrido") decorridos"
    fi
    caixa_linha_baixo
}

# progresso_render <titulo> <indice> <total_arq> <bytes_copiados> <bytes_total> <arquivo_rel> <inicio_epoch> [forcar]
progresso_render() {
    local titulo="$1" indice="$2" total_arq="$3" bytes_cop="$4" bytes_tot="$5" arq_rel="$6" inicio="$7" forcar="${8:-false}"
    local agora_ms
    agora_ms="$(agora_milisegundos)"

    # Evita redesenhar a tela a cada arquivo. No Termux, isso pode ser mais caro
    # que a própria cópia quando há centenas de arquivos pequenos.
    if [ "$forcar" != true ] && [ $((agora_ms - _PROGRESSO_ULTIMO_RENDER_MS)) -lt 500 ]; then
        return 0
    fi
    _PROGRESSO_ULTIMO_RENDER_MS="$agora_ms"

    local agora pct_bytes pct_arquivos largura_barra preenchido vazio barra velocidade eta
    agora=$(date +%s)
    local decorrido=$((agora - inicio))
    [ "$decorrido" -lt 1 ] && decorrido=1

    if [ "$bytes_tot" -gt 0 ]; then
        pct_bytes=$((bytes_cop * 100 / bytes_tot))
    else
        pct_bytes=$((total_arq > 0 ? indice * 100 / total_arq : 0))
    fi
    pct_arquivos=$((total_arq > 0 ? indice * 100 / total_arq : 0))
    [ "$pct_bytes" -gt 100 ] && pct_bytes=100
    [ "$pct_arquivos" -gt 100 ] && pct_arquivos=100

    largura_barra=$((LARGURA_CAIXA - 12))
    [ "$largura_barra" -lt 10 ] && largura_barra=10
    preenchido=$((largura_barra * pct_bytes / 100))
    vazio=$((largura_barra - preenchido))
    barra="$(repetir_char '█' "$preenchido")$(repetir_char '░' "$vazio")"

    # Na renderização final, nunca deixe os indicadores como "calculando...".
    # Projetos pequenos podem terminar antes de 3 segundos, então calculamos a
    # média com pelo menos 1 segundo e mostramos o tempo total concluído.
    local concluido=false
    if [ "$indice" -ge "$total_arq" ] && { [ "$bytes_tot" -le 0 ] || [ "$bytes_cop" -ge "$bytes_tot" ]; }; then
        concluido=true
    fi

    if [ "$concluido" = true ]; then
        local vel_final=$((bytes_cop / decorrido))
        if [ "$vel_final" -gt 0 ]; then
            velocidade="$(formatar_tamanho "$vel_final")/s"
        else
            velocidade="Concluído"
        fi
        eta="$(formatar_tempo "$((agora - inicio))") total"
    elif [ "$decorrido" -lt 3 ] || [ "$bytes_cop" -le 0 ]; then
        velocidade="calculando..."
        eta="calculando..."
    else
        local vel_bytes=$((bytes_cop / decorrido))
        velocidade="$(formatar_tamanho "$vel_bytes")/s"
        if [ "$vel_bytes" -gt 0 ] && [ "$bytes_tot" -gt "$bytes_cop" ]; then
            eta=$(( (bytes_tot - bytes_cop) / vel_bytes ))
            eta="$(formatar_tempo "$eta") restantes"
        else
            eta="finalizando..."
        fi
    fi

    local arq_mostrar
    arq_mostrar="$(truncar_caminho "$arq_rel" $((LARGURA_CAIXA - 10)))"

    if [ "$_PROGRESSO_INICIADO" == true ]; then
        printf "\033[%dA" "$ALTURA_CAIXA_PROGRESSO"
    fi
    _PROGRESSO_INICIADO=true

    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}📦 ${titulo}${C_RESET}" true
    caixa_linha_sep
    caixa_linha_texto "${C_GREEN}${barra}${C_RESET} ${pct_bytes}%"
    caixa_linha_texto "${indice}/${total_arq} arquivos (${pct_arquivos}%)"
    caixa_linha_texto "📁 ${C_DIM}${arq_mostrar}${C_RESET}"
    caixa_linha_texto "⚡ ${velocidade}   ⏳ ${eta}"
    caixa_linha_baixo
}

progresso_resetar() {
    _PROGRESSO_INICIADO=false
    _PROGRESSO_ULTIMO_RENDER_MS=0
}

copiar_com_rsync() {
    local origem="$1" destino="$2" modo="$3" total_arquivos="$4" total_bytes="$5" inicio="$6"
    shift 6
    local -a excluir_padroes=("$@")
    local -a args=(-a --human-readable --info=progress2 --no-inc-recursive --out-format='MANAGER_FILE:%n')
    [ "$modo" = 2 ] && args+=(--ignore-existing)
    local pad
    for pad in "${excluir_padroes[@]}"; do
        [ -n "$pad" ] && args+=(--exclude="$pad")
    done

    local saida="$SESSION_TMP_DIR/rsync_progress_$$.log"
    : > "$saida"

    # O shell pode continuar apontando para uma pasta que foi removida ou
    # substituída durante uma importação anterior. Nessa situação, programas
    # como rsync abortam com getcwd(): No such file or directory, mesmo quando
    # origem e destino são caminhos absolutos. Execute o rsync a partir de um
    # diretório estável e existente para tornar a cópia independente do PWD.
    (
        cd "${HOME:-/data/data/com.termux/files/home}" 2>/dev/null || cd / || exit 70
        exec rsync "${args[@]}" "$origem/" "$destino/"
    ) >"$saida" 2>>"$LOG_FILE" &
    local pid=$! ultimo="Preparando arquivos..." pct=0 bytes=0 copiados=0

    while kill -0 "$pid" 2>/dev/null; do
        local linha
        linha="$(tr '\r' '\n' < "$saida" | grep -E '[0-9]+%' | tail -n 1)"
        if [ -n "$linha" ]; then
            pct="$(printf '%s' "$linha" | grep -oE '[0-9]+%' | tail -n1 | tr -d '%' || echo 0)"
            bytes=$(( total_bytes * pct / 100 ))
        fi
        # Conta arquivos realmente informados pelo rsync. Assim o painel avança
        # em números concretos (10/254, 20/254...) em vez de só aparecer no fim.
        copiados="$(grep -c '^MANAGER_FILE:' "$saida" 2>/dev/null || true)"
        [ "$copiados" -gt "$total_arquivos" ] && copiados="$total_arquivos"
        local ultimo_arquivo
        ultimo_arquivo="$(grep '^MANAGER_FILE:' "$saida" 2>/dev/null | tail -n 1 | sed 's/^MANAGER_FILE://' || true)"
        [ -n "$ultimo_arquivo" ] && ultimo="$ultimo_arquivo"
        # Em alguns aparelhos a saída por arquivo pode ser bufferizada. Nesse
        # caso, usa a porcentagem global como avanço mínimo aproximado.
        local estimado=$((total_arquivos * pct / 100))
        [ "$estimado" -gt "$copiados" ] && copiados="$estimado"
        progresso_render "$(basename "$origem")" "$copiados" "$total_arquivos" "$bytes" "$total_bytes" "$ultimo" "$inicio"
        sleep 0.5
    done
    wait "$pid"
    local rc=$?
    progresso_render "$(basename "$origem")" "$total_arquivos" "$total_arquivos" "$total_bytes" "$total_bytes" "Cópia concluída" "$inicio" true
    rm -f "$saida"
    return "$rc"
}

# ----------------------------------------------------------------------------
# motor_copia <origem> <destino_base> <achatar:true|false> [pausar_final:true|false]
# ----------------------------------------------------------------------------
motor_copia() {
    local origem="$1" destino_base="$2" achatar="$3" pausar_final="${4:-true}"
    local destino="$destino_base"
    [ "$achatar" != true ] && destino="$destino_base/$(basename "$origem")"

    mkdir -p "$destino_base"

    echo
    caixa_simples "🧹 Limpeza da Cópia" "Exclusões padrão: $EXCLUSOES_PADRAO" "ENTER = usar padrão | - = não excluir"
    read -rp "Nomes a excluir: " -a excl_input
    local -a excluir_padroes=()
    if [ ${#excl_input[@]} -eq 0 ]; then
        # shellcheck disable=SC2206
        excluir_padroes=($EXCLUSOES_PADRAO)
    elif [ "${excl_input[0]}" != "-" ]; then
        excluir_padroes=("${excl_input[@]}")
    fi

    local -a find_expr=()
    if [ ${#excluir_padroes[@]} -gt 0 ]; then
        find_expr+=("(")
        local primeiro=true pad
        for pad in "${excluir_padroes[@]}"; do
            [ -z "$pad" ] && continue
            if [ "$primeiro" == true ]; then primeiro=false; else find_expr+=("-o"); fi
            find_expr+=("-name" "$pad")
        done
        find_expr+=(")" "-prune" "-o")
    fi

    local modo_conflito=""
    case "$CONFLITO_PADRAO" in
        substituir) modo_conflito=1 ;;
        pular) modo_conflito=2 ;;
        renomear) modo_conflito=3 ;;
        perguntar|"")
            echo
            caixa_simples "⚠ Arquivos Existentes" "1) 🔄 Substituir" "2) ⏭ Pular" "3) 📝 Renomear automaticamente" "4) ❓ Perguntar em cada conflito"
            read -rp "Escolha: " modo_conflito
            ;;
    esac
    case "$modo_conflito" in 1|2|3|4) ;; *) warn "Opção inválida."; pause; return ;; esac

    clear
    progresso_resetar
    local -a arquivos_origem=() pastas_origem=()
    local f d rel alvo tam encontrados=0
    local inicio_analise
    inicio_analise=$(date +%s)

    # A descoberta também dá feedback. Como o total ainda não é conhecido,
    # mostramos quantos arquivos já foram encontrados e o nome atual.
    while IFS= read -r -d '' f; do
        arquivos_origem+=("$f")
        encontrados=$((encontrados + 1))
        rel="${f#"$origem"/}"
        if [ $((encontrados % 10)) -eq 0 ]; then
            progresso_analise_render "$(basename "$origem")" descoberta "$encontrados" 0 "$rel" "$inicio_analise"
        fi
    done < <(find "$origem" "${find_expr[@]}" -type f -print0 2>/dev/null)

    while IFS= read -r -d '' d; do pastas_origem+=("$d"); done \
        < <(find "$origem" "${find_expr[@]}" -mindepth 1 -type d -print0 2>/dev/null)

    if [ ${#arquivos_origem[@]} -eq 0 ]; then
        warn "Nenhum arquivo encontrado para copiar."
        pause
        return 1
    fi

    local total_arquivos=${#arquivos_origem[@]} total_bytes=0 analise_indice=0
    progresso_resetar
    for f in "${arquivos_origem[@]}"; do
        analise_indice=$((analise_indice + 1))
        tam=$(stat -c%s "$f" 2>/dev/null || echo 0)
        total_bytes=$((total_bytes + tam))
        rel="${f#"$origem"/}"
        # Atualiza a cada 10 arquivos e força o último quadro.
        if [ $((analise_indice % 10)) -eq 0 ] || [ "$analise_indice" -eq "$total_arquivos" ]; then
            progresso_analise_render "$(basename "$origem")" tamanho "$analise_indice" "$total_arquivos" "$rel" "$inicio_analise"
        fi
    done

    mkdir -p "$destino"
    local pastas_copiadas=0
    for d in "${pastas_origem[@]}"; do
        rel="${d#"$origem"/}"
        alvo="$destino/$rel"
        [ -d "$alvo" ] || { mkdir -p "$alvo"; pastas_copiadas=$((pastas_copiadas + 1)); }
    done

    clear
    progresso_resetar
    local inicio=$(date +%s)
    local arquivos_copiados=0 arquivos_pulados=0 indice=0 bytes_copiados=0

    # rsync reduz drasticamente a sobrecarga para centenas de arquivos pequenos.
    # Os modos renomear/perguntar continuam no motor individual por exigirem
    # decisão específica para cada conflito.
    if { [ "$modo_conflito" = 1 ] || [ "$modo_conflito" = 2 ]; } && ! command -v rsync >/dev/null 2>&1; then
        caixa_simples "⚡ Cópia otimizada" \
            "O pacote rsync melhora projetos com muitos arquivos." \
            "Sem ele, será usado o modo compatível."
        if confirmar_acao "Instalar rsync agora?" "s"; then
            instalar_pkg_termux rsync || warn "Não foi possível instalar rsync; usando modo compatível."
        fi
        clear
        progresso_resetar
        inicio=$(date +%s)
    fi

    if command -v rsync >/dev/null 2>&1 && { [ "$modo_conflito" = 1 ] || [ "$modo_conflito" = 2 ]; }; then
        if copiar_com_rsync "$origem" "$destino" "$modo_conflito" "$total_arquivos" "$total_bytes" "$inicio" "${excluir_padroes[@]}"; then
            arquivos_copiados="$total_arquivos"
        else
            error "A cópia com rsync falhou. Consulte o log."
            pause
            return 1
        fi
    else
        local destino_arquivo acao
        for f in "${arquivos_origem[@]}"; do
            indice=$((indice + 1))
            rel="${f#"$origem"/}"
            destino_arquivo="$destino/$rel"
            mkdir -p "$(dirname "$destino_arquivo")"

            if [ -e "$destino_arquivo" ]; then
                acao="$modo_conflito"
                if [ "$modo_conflito" == 4 ]; then
                    printf "\033[%dA\033[J" "$ALTURA_CAIXA_PROGRESSO" 2>/dev/null || true
                    progresso_resetar
                    warn "Conflito: '$rel' já existe."
                    echo "  1) Substituir  2) Pular  3) Renomear automaticamente"
                    read -rp "  Escolha: " acao
                fi
                case "$acao" in
                    2) arquivos_pulados=$((arquivos_pulados + 1)); continue ;;
                    3)
                        local base_nome="${destino_arquivo%.*}" ext="${destino_arquivo##*.}"
                        [ "$base_nome" == "$destino_arquivo" ] && ext=""
                        local n=1 novo="$destino_arquivo"
                        while [ -e "$novo" ]; do
                            if [ -n "$ext" ]; then novo="${base_nome}_${n}.${ext}"; else novo="${destino_arquivo}_${n}"; fi
                            n=$((n + 1))
                        done
                        destino_arquivo="$novo"
                        ;;
                esac
            fi

            tam=$(stat -c%s "$f" 2>/dev/null || echo 0)
            if cp -a "$f" "$destino_arquivo"; then
                bytes_copiados=$((bytes_copiados + tam))
                arquivos_copiados=$((arquivos_copiados + 1))
            else
                warn "Falha ao copiar: $rel"
            fi
            progresso_render "$(basename "$origem")" "$indice" "$total_arquivos" "$bytes_copiados" "$total_bytes" "$rel" "$inicio"
        done
        progresso_render "$(basename "$origem")" "$total_arquivos" "$total_arquivos" "$bytes_copiados" "$total_bytes" "Cópia concluída" "$inicio" true
    fi

    local fim duracao
    fim=$(date +%s)
    duracao=$((fim - inicio))
    echo
    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}${C_GREEN}✅ Projeto importado com sucesso${C_RESET}" true
    caixa_linha_sep
    caixa_linha_texto "${arquivos_copiados} arquivos copiados"
    [ "$arquivos_pulados" -gt 0 ] && caixa_linha_texto "${arquivos_pulados} arquivos pulados"
    caixa_linha_texto "${pastas_copiadas} pastas criadas"
    caixa_linha_texto "Tempo: $(formatar_tempo "$duracao")"
    caixa_linha_baixo
    log "INFO" "motor_copia: $arquivos_copiados arquivos, $pastas_copiadas pastas, ${total_bytes}B, ${duracao}s (origem=$origem destino=$destino)"

    ULTIMO_PROJETO_IMPORTADO="$destino"
    ULTIMA_COPIA_OK=true
    ok "Cópia concluída."
    [ "$pausar_final" = true ] && pause
    return 0
}

