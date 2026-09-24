# Módulo: diagnostics_android.sh
# Diagnóstico Android via Rish/Shizuku e teste de armazenamento.

localizar_rish_diagnostico() {
    local candidato
    for candidato in "$HOME/rish/rish" "$HOME/rish" "$HOME/bin/rish"; do
        [ -f "$candidato" ] && { printf '%s' "$candidato"; return 0; }
    done
    return 1
}

executar_rish_diagnostico() {
    local comando="$1" rish
    rish="$(localizar_rish_diagnostico)" || return 2
    sh "$rish" -c "$comando" 2>&1
}

verificar_shizuku_diagnostico() {
    local saida
    saida="$(executar_rish_diagnostico 'id' 2>/dev/null)" || return 1
    printf '%s' "$saida" | grep -q 'uid=2000(shell)'
}

coletar_android_shizuku() {
    resolver_downloads_diagnostico || return 1
    cabecalho_tela "📱 Diagnóstico Android" "CPU, memória, térmica, bateria e processos"

    if ! localizar_rish_diagnostico >/dev/null; then
        caixa_simples "Rish não encontrado" \
            "Esperado em: ~/rish/rish" \
            "Configure o Rish do Shizuku e tente novamente."
        pause; return 1
    fi
    if ! verificar_shizuku_diagnostico; then
        caixa_simples "Shizuku não está ativo" \
            "Abra o Shizuku e inicie o serviço." \
            "Depois volte ao Manager e execute a coleta novamente." \
            "O app não precisa permanecer na tela; o serviço precisa continuar ativo."
        pause; return 1
    fi

    local carimbo destino cmd
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    destino="$DOWNLOADS_DIR/android-diagnostico-$carimbo.txt"
    cmd='echo "=== IDENTIDADE ==="; id; echo; echo "=== BUILD ==="; getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.product.device; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.build.fingerprint; echo; echo "=== CPU ==="; cat /proc/cpuinfo; echo; for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_{cur,min,max}_freq; do [ -r "$f" ] && echo "$f=$(cat "$f")"; done; echo; echo "=== MEMORIA ==="; cat /proc/meminfo; echo; dumpsys meminfo | grep -A 18 "Total RAM"; echo; echo "=== PROCESSOS RSS ==="; dumpsys meminfo | head -80; echo; echo "=== OOM ==="; dumpsys activity oom | head -180; echo; echo "=== ARMAZENAMENTO ==="; df -h /data /sdcard 2>/dev/null; echo; cat /proc/diskstats; echo; echo "=== BATERIA ==="; dumpsys battery; echo; echo "=== TERMICA ==="; dumpsys thermalservice; echo; echo "=== POWER ==="; dumpsys power | head -180; echo; echo "=== ZRAM ==="; cat /proc/swaps; echo; echo "=== FIM ==="'

    {
        cabecalho_relatorio_diagnostico "Android via Shizuku" "Rish (uid 2000/shell)" "coleta compacta"
        printf 'Observação: teste de velocidade de armazenamento não está incluído nesta coleta.\n\n'
        executar_rish_diagnostico "$cmd"
    } | redigir_segredos > "$destino"

    caixa_simples "📥 Diagnóstico Android criado" \
        "Arquivo: $(basename "$destino")" \
        "Tamanho: $(tamanho_legivel_arquivo "$destino")" \
        "Destino: $(caminho_curto "$DOWNLOADS_DIR")" \
        "Teste de armazenamento: separado"
    pause
}

teste_armazenamento_android() {
    resolver_downloads_diagnostico || return 1
    cabecalho_tela "💾 Teste de armazenamento" "Escrita e cópia separados do diagnóstico"
    local carimbo destino teste copia tamanho_mb=128 inicio fim ms bytes mib_s
    carimbo="$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date +%s)"
    destino="$DOWNLOADS_DIR/android-storage-test-$carimbo.txt"
    teste="$DOWNLOADS_DIR/.manager-io-test-$carimbo.bin"
    copia="$DOWNLOADS_DIR/.manager-io-copy-$carimbo.bin"

    caixa_simples "Teste temporário" \
        "Arquivo de teste: ${tamanho_mb} MiB" \
        "Mede escrita sequencial e cópia local." \
        "Os arquivos temporários serão apagados ao final."

    medir() {
        local rotulo="$1"; shift
        inicio="$(date +%s%3N 2>/dev/null || date +%s000)"
        "$@" >/dev/null 2>&1
        local rc=$?
        fim="$(date +%s%3N 2>/dev/null || date +%s000)"
        ms=$((fim-inicio)); [ "$ms" -lt 1 ] && ms=1
        bytes=$((tamanho_mb*1024*1024))
        mib_s=$((bytes*1000/ms/1024/1024))
        printf '%s: %s MiB/s (%s ms)\n' "$rotulo" "$mib_s" "$ms" >> "$destino"
        return $rc
    }

    {
        cabecalho_relatorio_diagnostico "Teste de armazenamento" "Downloads" "${tamanho_mb} MiB"
        printf 'Aviso: resultado é indicativo e varia com cache, temperatura e carga do sistema.\n\n'
    } > "$destino"
    local falhas=0
    if ! medir "Escrita sequencial" dd if=/dev/zero of="$teste" bs=1M count="$tamanho_mb" conv=fsync; then
        printf 'Falha: não foi possível concluir a escrita sequencial.\n' >> "$destino"
        falhas=$((falhas+1))
    fi
    if [ -f "$teste" ]; then
        if ! medir "Cópia local" cp "$teste" "$copia"; then
            printf 'Falha: não foi possível concluir a cópia local.\n' >> "$destino"
            falhas=$((falhas+1))
        fi
    else
        printf 'Cópia local: não executada porque o arquivo de escrita não foi criado.\n' >> "$destino"
        falhas=$((falhas+1))
    fi
    rm -f "$teste" "$copia" 2>/dev/null || true
    sync 2>/dev/null || true

    if [ "$falhas" -gt 0 ]; then
        caixa_simples "⚠️ Teste incompleto" \
            "Relatório: $(basename "$destino")" \
            "Falhas detectadas: $falhas" \
            "Arquivos temporários: removidos"
        pause
        return 1
    fi

    caixa_simples "💾 Teste concluído" \
        "Relatório: $(basename "$destino")" \
        "$(tail -n 2 "$destino" | tr '\n' ' ')" \
        "Arquivos temporários: removidos"
    pause
}

