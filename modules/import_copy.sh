# Módulo: import_copy.sh
# Motor de cópia, progresso, rsync e utilitários de transferência.

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

