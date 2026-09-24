# Módulo: diagnostics_reports.sh
# Exportação consolidada e pacote de suporte.

copiar_sanitizado() {
    local origem="$1" destino="$2"
    [ -f "$origem" ] || return 0
    mkdir -p "$(dirname "$destino")"
    redigir_segredos < "$origem" > "$destino"
}

exportar_todos_relatorios() {
    resolver_downloads_diagnostico || return 1
    inicializar_diagnosticos
    local carimbo destino f snapshot total=0
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    destino="$DOWNLOADS_DIR/TermuxManager-Relatorios-$carimbo"
    mkdir -p "$destino/manager" "$destino/projetos" "$destino/termux" || return 1

    [ -f "$LOG_FILE" ] && copiar_sanitizado "$LOG_FILE" "$destino/manager/log-principal.txt" && total=$((total+1))
    [ -f "$MANAGER_INCIDENT_INDEX" ] && copiar_sanitizado "$MANAGER_INCIDENT_INDEX" "$destino/manager/indice-incidentes.txt" && total=$((total+1))
    for f in "$MANAGER_INCIDENT_DIR"/erro-*.txt; do
        [ -f "$f" ] || continue
        copiar_sanitizado "$f" "$destino/manager/$(basename "$f")"
        total=$((total+1))
    done
    for f in "$LOG_DIR"/*.log; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = manager.log ] && continue
        copiar_sanitizado "$f" "$destino/projetos/$(basename "$f" .log).txt"
        total=$((total+1))
    done
    [ -f "${TERMUX_SETUP_LOG:-}" ] && copiar_sanitizado "$TERMUX_SETUP_LOG" "$destino/termux/operacoes-pkg.txt" && total=$((total+1))
    [ -f "${TERMUX_DIAGNOSTIC_LOG:-}" ] && copiar_sanitizado "$TERMUX_DIAGNOSTIC_LOG" "$destino/termux/ultimo-diagnostico-pkg.txt" && total=$((total+1))
    snapshot="$(gerar_snapshot_termux)"
    copiar_sanitizado "$snapshot" "$destino/termux/ambiente-atual.txt" && total=$((total+1))

    {
        cabecalho_relatorio_diagnostico "Exportação completa" "Manager + projetos + Termux" "todos"
        printf 'Relatórios exportados: %s\n' "$total"
        printf 'Estrutura: manager/ projetos/ termux/\n'
        printf 'Destino: %s\n' "$(caminho_curto "$destino")"
    } > "$destino/LEIA-ME.txt"

    caixa_simples "📤 Todos os relatórios exportados" \
        "Arquivos: $total" \
        "Pastas: manager, projetos e termux" \
        "Segredos comuns: removidos" \
        "Destino: $(caminho_curto "$destino")"
    pause
}

exportar_pacote_diagnostico_completo() {
    resolver_downloads_diagnostico || return 1
    inicializar_diagnosticos
    local carimbo tmp pacote formato f snapshot
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    tmp="$SESSION_TMP_DIR/diagnostico-$carimbo"
    rm -rf "$tmp" 2>/dev/null || true
    mkdir -p "$tmp/manager" "$tmp/projetos" "$tmp/termux"

    copiar_sanitizado "$LOG_FILE" "$tmp/manager/manager.log"
    copiar_sanitizado "$MANAGER_INCIDENT_INDEX" "$tmp/manager/incidentes.log"
    for f in "$MANAGER_INCIDENT_DIR"/erro-*.txt; do
        [ -f "$f" ] || continue
        copiar_sanitizado "$f" "$tmp/manager/$(basename "$f")"
    done
    for f in "$LOG_DIR"/*.log; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = manager.log ] && continue
        copiar_sanitizado "$f" "$tmp/projetos/$(basename "$f")"
    done
    [ -f "${TERMUX_SETUP_LOG:-}" ] && copiar_sanitizado "$TERMUX_SETUP_LOG" "$tmp/termux/termux-setup.log"
    [ -f "${TERMUX_DIAGNOSTIC_LOG:-}" ] && copiar_sanitizado "$TERMUX_DIAGNOSTIC_LOG" "$tmp/termux/ultimo-diagnostico.txt"
    snapshot="$(gerar_snapshot_termux)"
    copiar_sanitizado "$snapshot" "$tmp/termux/ambiente-atual.txt"

    {
        cabecalho_relatorio_diagnostico "Pacote completo" "Manager + projetos + Termux" "todos"
        printf 'Arquivos do Manager: %s\n' "$(find "$tmp/manager" -type f 2>/dev/null | wc -l | tr -d ' ')"
        printf 'Logs de projetos: %s\n' "$(find "$tmp/projetos" -type f 2>/dev/null | wc -l | tr -d ' ')"
        printf 'Arquivos do Termux: %s\n' "$(find "$tmp/termux" -type f 2>/dev/null | wc -l | tr -d ' ')"
        printf 'Diretório do Manager: %s\n' "${BASE_DIR:-indisponível}"
        printf 'Diretório do Painel: %s\n' "$(caminho_curto "$PAINEL_DIR")"
    } > "$tmp/LEIA-ME.txt"
    [ -f "$BASE_DIR/MANIFEST.json" ] && cp -f "$BASE_DIR/MANIFEST.json" "$tmp/manager/MANIFEST.json"

    if command -v zip >/dev/null 2>&1; then
        pacote="$DOWNLOADS_DIR/termux-manager-diagnostico-$carimbo.zip"
        if ! (cd "$tmp" && zip -qr "$pacote" .); then
            rm -rf "$tmp" 2>/dev/null || true
            return 1
        fi
        formato="ZIP"
    else
        pacote="$DOWNLOADS_DIR/termux-manager-diagnostico-$carimbo.tar.gz"
        if ! tar -czf "$pacote" -C "$tmp" .; then
            rm -rf "$tmp" 2>/dev/null || true
            return 1
        fi
        formato="TAR.GZ"
    fi
    rm -rf "$tmp" 2>/dev/null || true

    caixa_simples "📦 Pacote de diagnóstico criado" \
        "Arquivo: $(basename "$pacote")" \
        "Formato: $formato • Tamanho: $(tamanho_legivel_arquivo "$pacote")" \
        "Categorias: Manager, projetos e Termux" \
        "Segredos comuns: removidos" \
        "Destino: $(caminho_curto "$DOWNLOADS_DIR")"
    pause
}



# Diagnóstico do aparelho Android via Rish/Shizuku.
# Mantém a coleta leve separada dos testes de I/O para evitar relatórios enormes.
