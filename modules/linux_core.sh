# Módulo: linux_core.sh
# Núcleo Linux: arquitetura, perfil do aparelho, PRoot e caminhos de containers.

linux_docker_arquitetura_dispositivo() {
    local arch="${1:-$(linux_arquitetura)}"
    case "$arch" in
        aarch64|arm64) printf 'arm64' ;;
        arm|armhf|armeabi-v7a) printf 'arm' ;;
        x86_64|amd64) printf 'amd64' ;;
        i386|i486|i586|i686|x86) printf '386' ;;
        riscv64) printf 'riscv64' ;;
        *) return 1 ;;
    esac
}

linux_dockerhub_ref_partes() {
    local ref="${1:-}" nome tag primeiro namespace repositorio ultimo
    linux_imagem_referencia_valida "$ref" || return 1
    [[ "$ref" == *@* ]] && return 1
    nome="$ref"
    primeiro="${nome%%/*}"
    if [[ "$nome" == */* ]] && { [[ "$primeiro" == *.* ]] || [[ "$primeiro" == *:* ]] || [ "$primeiro" = "localhost" ]; }; then
        return 1
    fi
    tag="latest"
    ultimo="${nome##*/}"
    if [[ "$ultimo" == *:* ]]; then
        tag="${ultimo##*:}"
        nome="${nome%:*}"
    fi
    if [[ "$nome" == */* ]]; then
        namespace="${nome%%/*}"
        repositorio="${nome#*/}"
    else
        namespace="library"
        repositorio="$nome"
    fi
    [ -n "$namespace" ] && [ -n "$repositorio" ] && [ -n "$tag" ] || return 1
    printf '%s|%s|%s\n' "$namespace" "$repositorio" "$tag"
}

linux_arch_cache_arquivo() {
    local ref="${1:-}" seguro fingerprint
    seguro="$(printf '%s' "$ref" | tr '/:@+' '_____' | tr -cd 'A-Za-z0-9._-' | cut -c1-48)"
    [ -n "$seguro" ] || seguro="imagem"
    if command -v sha256sum >/dev/null 2>&1; then
        fingerprint="$(printf '%s' "$ref" | sha256sum | awk '{print substr($1,1,16)}')"
    else
        fingerprint="$(printf '%s' "$ref" | cksum 2>/dev/null | awk '{print $1}' | head -n1)"
    fi
    [ -n "$fingerprint" ] || fingerprint="semhash"
    printf '%s/arch-cache/%s-%s.cache\n' "$LINUX_STATE_DIR" "$seguro" "$fingerprint"
}

linux_consultar_arquiteturas_dockerhub() {
    local ref="${1:-}" partes namespace repositorio tag cache agora salvo_ts salvo_archs json archs url
    partes="$(linux_dockerhub_ref_partes "$ref")" || return 1
    IFS='|' read -r namespace repositorio tag <<< "$partes"
    cache="$(linux_arch_cache_arquivo "$ref")"
    agora="$(date +%s 2>/dev/null || printf '0')"

    if [ -f "$cache" ]; then
        IFS='|' read -r salvo_ts salvo_archs < "$cache" || true
        if [[ "$agora" =~ ^[0-9]+$ ]] && [[ "${salvo_ts:-}" =~ ^[0-9]+$ ]] && \
           [ $((agora - salvo_ts)) -ge 0 ] && [ $((agora - salvo_ts)) -lt "$LINUX_ARCH_CACHE_TTL" ] && [ -n "${salvo_archs:-}" ]; then
            LINUX_IMAGE_ARCHS="$salvo_archs"
            return 0
        fi
    fi

    command -v curl >/dev/null 2>&1 || return 1
    url="https://hub.docker.com/v2/repositories/${namespace}/${repositorio}/tags/${tag}"
    json="$(curl -fsSL --connect-timeout 6 --max-time 15 "$url" 2>>"$LINUX_LOG")" || return 1
    archs="$(printf '%s' "$json" \
        | grep -oE '"architecture"[[:space:]]*:[[:space:]]*"[^"]+"' \
        | sed -E 's/.*"architecture"[[:space:]]*:[[:space:]]*"([^"]+)"/\1/' \
        | grep -Ev '^(unknown|)$' \
        | sort -u \
        | paste -sd ',' -)"
    [ -n "$archs" ] || return 1
    LINUX_IMAGE_ARCHS="$archs"
    mkdir -p "$(dirname "$cache")" 2>/dev/null || true
    printf '%s|%s\n' "$agora" "$archs" > "$cache" 2>/dev/null || true
    return 0
}

linux_verificar_compatibilidade_imagem() {
    local ref="${1:-}" device_arch docker_arch lista item
    device_arch="$(linux_arquitetura)"
    docker_arch="$(linux_docker_arquitetura_dispositivo "$device_arch" 2>/dev/null || true)"
    LINUX_DEVICE_ARCH="$device_arch"
    LINUX_DEVICE_DOCKER_ARCH="$docker_arch"
    LINUX_IMAGE_ARCHS=""
    LINUX_ARCH_STATUS="unknown"
    LINUX_ARCH_STATUS_ICON="⚪"
    LINUX_ARCH_STATUS_LABEL="Não confirmado"
    LINUX_ARCH_STATUS_MSG="Não foi possível confirmar a arquitetura antes do download. O proot-distro fará a validação durante a instalação."

    if [ -z "$docker_arch" ]; then
        LINUX_ARCH_STATUS_MSG="A arquitetura '$device_arch' não possui mapeamento OCI conhecido pelo Manager."
        return 0
    fi

    if ! linux_consultar_arquiteturas_dockerhub "$ref"; then
        if ! linux_dockerhub_ref_partes "$ref" >/dev/null 2>&1; then
            LINUX_ARCH_STATUS_MSG="A referência não é do Docker Hub ou usa um formato que não permite pré-consulta. O proot-distro fará a validação durante a instalação."
        fi
        return 0
    fi

    lista=",${LINUX_IMAGE_ARCHS},"
    if [[ "$lista" == *",${docker_arch},"* ]]; then
        LINUX_ARCH_STATUS="compatible"
        LINUX_ARCH_STATUS_ICON="✅"
        LINUX_ARCH_STATUS_LABEL="Compatível"
        LINUX_ARCH_STATUS_MSG="A imagem publica uma variante nativa para a arquitetura deste aparelho."
    else
        LINUX_ARCH_STATUS="incompatible"
        LINUX_ARCH_STATUS_ICON="⛔"
        LINUX_ARCH_STATUS_LABEL="Incompatível nativamente"
        LINUX_ARCH_STATUS_MSG="A imagem consultada não publica uma variante para a arquitetura deste aparelho."
    fi
}

linux_mostrar_compatibilidade_imagem() {
    local ref="$1" nome_amigavel="${2:-$1}"
    linux_coletar_contexto_arquitetura
    cabecalho_tela "🔎 Compatibilidade da distribuição" "$nome_amigavel"
    caixa_simples_wrap "Aparelho" \
        "CPU: ${LINUX_ARCH_CPU_GEN:-?} • Termux: ${LINUX_ARCH_TERMUX:-?} (${LINUX_ARCH_BITS:-?} bits)" \
        "Android ABI: ${LINUX_ARCH_ANDROID_ABI:-não informada}" \
        "OCI usada: $(linux_docker_arquitetura_dispositivo "$LINUX_ARCH_TERMUX" 2>/dev/null || echo não mapeada)" \
        "Imagem: $ref" \
        "$LINUX_ARCH_INTERPRETATION"
    printf '\n⏳ Consultando arquiteturas publicadas antes do download...\n'
    ui_buffer_flush 2>/dev/null || true
    linux_verificar_compatibilidade_imagem "$ref"
    cabecalho_tela "${LINUX_ARCH_STATUS_ICON} Compatibilidade: ${LINUX_ARCH_STATUS_LABEL}" "$nome_amigavel"
    local -a detalhes=(
        "Aparelho: ${LINUX_DEVICE_ARCH}${LINUX_DEVICE_DOCKER_ARCH:+ • OCI ${LINUX_DEVICE_DOCKER_ARCH}}"
        "Imagem: $ref"
        "$LINUX_ARCH_STATUS_MSG"
    )
    [ -n "$LINUX_IMAGE_ARCHS" ] && detalhes+=("Arquiteturas publicadas: ${LINUX_IMAGE_ARCHS//,/ • }")
    caixa_simples "Resultado" "${detalhes[@]}"

    if [ "$LINUX_ARCH_STATUS" = "incompatible" ]; then
        caixa_simples "Download evitado" \
            "O Manager não iniciou o download porque a imagem não oferece suporte nativo para este aparelho." \
            "Isso evita gastar dados móveis e armazenamento em uma instalação que provavelmente falharia." \
            "Instalações por emulação/QEMU não são configuradas automaticamente nesta versão."
        linux_log "imagem bloqueada por arquitetura: $ref host=$LINUX_DEVICE_ARCH oci=$LINUX_DEVICE_DOCKER_ARCH disponíveis=$LINUX_IMAGE_ARCHS"
        pause
        return 1
    fi
    return 0
}

linux_log() {
    mkdir -p "$LINUX_STATE_DIR" "$(dirname "$LINUX_LOG")" 2>/dev/null || true
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LINUX_LOG"
}

linux_mem_total_kb() {
    awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0'
}

linux_mem_disponivel_kb() {
    awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0'
}

linux_espaco_livre_kb() {
    df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4; exit}' || printf '0'
}

linux_formatar_gb_kb() {
    local kb="${1:-0}"
    awk -v kb="$kb" 'BEGIN { printf "%.1f GB", kb/1024/1024 }'
}

linux_cpu_nucleos() {
    if command -v nproc >/dev/null 2>&1; then
        nproc 2>/dev/null || printf '1'
    else
        grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf '1'
    fi
}

linux_arquitetura() {
    if command -v dpkg >/dev/null 2>&1; then
        dpkg --print-architecture 2>/dev/null || uname -m
    else
        uname -m
    fi
}

linux_bits_processo() {
    local bits=""
    if command -v getconf >/dev/null 2>&1; then
        bits="$(getconf LONG_BIT 2>/dev/null || true)"
    fi
    if [[ "$bits" =~ ^(32|64)$ ]]; then
        printf '%s\n' "$bits"
        return 0
    fi
    case "$(linux_arquitetura)" in
        aarch64|arm64|x86_64|amd64|riscv64) printf '64\n' ;;
        arm|armhf|armeabi-v7a|i386|i486|i586|i686|x86) printf '32\n' ;;
        *) printf 'desconhecido\n' ;;
    esac
}

linux_android_prop() {
    local chave="${1:-}"
    [ -n "$chave" ] || return 1
    command -v getprop >/dev/null 2>&1 || return 1
    getprop "$chave" 2>/dev/null | head -n1
}

linux_cpu_arm_geracao() {
    local geracao linha
    geracao="$(awk -F: '/^[[:space:]]*CPU architecture[[:space:]]*:/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
    if [[ "$geracao" =~ ^[0-9]+$ ]]; then
        printf 'ARMv%s\n' "$geracao"
        return 0
    fi
    linha="$(grep -m1 -E 'ARMv[0-9]+|AArch64' /proc/cpuinfo 2>/dev/null || true)"
    if [[ "$linha" =~ ARMv([0-9]+) ]]; then
        printf 'ARMv%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    case "$(uname -m 2>/dev/null || true)" in
        aarch64|arm64) printf 'ARMv8+\n' ;;
        armv8*) printf 'ARMv8\n' ;;
        armv7*) printf 'ARMv7\n' ;;
        *) printf 'não identificada\n' ;;
    esac
}

linux_coletar_contexto_arquitetura() {
    LINUX_ARCH_TERMUX="$(linux_arquitetura)"
    LINUX_ARCH_BITS="$(linux_bits_processo)"
    LINUX_ARCH_KERNEL="$(uname -m 2>/dev/null || printf 'desconhecido')"
    LINUX_ARCH_ANDROID_ABI="$(linux_android_prop ro.product.cpu.abi 2>/dev/null || true)"
    LINUX_ARCH_ANDROID_ABILIST="$(linux_android_prop ro.product.cpu.abilist 2>/dev/null || true)"
    LINUX_ARCH_ANDROID_ABILIST32="$(linux_android_prop ro.product.cpu.abilist32 2>/dev/null || true)"
    LINUX_ARCH_ANDROID_ABILIST64="$(linux_android_prop ro.product.cpu.abilist64 2>/dev/null || true)"
    LINUX_ARCH_CPU_GEN="$(linux_cpu_arm_geracao)"
    LINUX_ARCH_INTERPRETATION=""

    case "$LINUX_ARCH_TERMUX" in
        arm|armhf|armeabi-v7a)
            if [[ "$LINUX_ARCH_ANDROID_ABILIST64" == *arm64-v8a* ]] || [[ "$LINUX_ARCH_ANDROID_ABILIST" == *arm64-v8a* ]] ||                [[ "$LINUX_ARCH_KERNEL" == aarch64* ]] || [[ "$LINUX_ARCH_CPU_GEN" =~ ARMv([89]|[1-9][0-9]) ]]; then
                LINUX_ARCH_INTERPRETATION="CPU/Android com recursos ARMv8+, mas o Termux atual executa em 32 bits (arm)."
            else
                LINUX_ARCH_INTERPRETATION="O Termux atual executa ARM em 32 bits. A geração física da CPU não muda a ABI usada pelas distros."
            fi
            ;;
        aarch64|arm64)
            LINUX_ARCH_INTERPRETATION="Termux e distros nativas usam ARM de 64 bits (AArch64/arm64)."
            ;;
        x86_64|amd64)
            LINUX_ARCH_INTERPRETATION="Termux executa em x86_64 de 64 bits."
            ;;
        i386|i486|i586|i686|x86)
            LINUX_ARCH_INTERPRETATION="Termux executa em x86 de 32 bits."
            ;;
        *)
            LINUX_ARCH_INTERPRETATION="Arquitetura do Termux: $LINUX_ARCH_TERMUX; processo: ${LINUX_ARCH_BITS} bits."
            ;;
    esac
}

linux_android_versao() {
    if command -v getprop >/dev/null 2>&1; then
        getprop ro.build.version.release 2>/dev/null | head -1
    else
        printf 'desconhecida'
    fi
}

linux_avaliar_aparelho() {
    local ram_kb livre_kb cores
    ram_kb="$(linux_mem_total_kb)"
    livre_kb="$(linux_espaco_livre_kb)"
    cores="$(linux_cpu_nucleos)"
    [[ "$ram_kb" =~ ^[0-9]+$ ]] || ram_kb=0
    [[ "$livre_kb" =~ ^[0-9]+$ ]] || livre_kb=0
    [[ "$cores" =~ ^[0-9]+$ ]] || cores=1

    LINUX_RAM_KB="$ram_kb"
    LINUX_FREE_KB="$livre_kb"
    LINUX_CPU_CORES="$cores"
    LINUX_PROFILE="DESKTOP"
    LINUX_PROFILE_ICON="🟢"
    LINUX_PROFILE_MSG="Boa margem para uma distribuição Linux e interface gráfica leve."
    LINUX_PROFILE_RECOMMEND="XFCE, LXQt ou MATE são boas opções. KDE pode ser testado se houver RAM livre suficiente."

    # Heurística conservadora. Não tenta inferir potência real da CPU apenas por núcleos.
    if [ "$ram_kb" -lt $((3 * 1024 * 1024)) ] || [ "$livre_kb" -lt $((5 * 1024 * 1024)) ]; then
        LINUX_PROFILE="BÁSICO"
        LINUX_PROFILE_ICON="🔴"
        LINUX_PROFILE_MSG="O aparelho tem pouca margem para um desktop Linux completo."
        LINUX_PROFILE_RECOMMEND="Prefira terminal, LXDE, Openbox ou i3. Desktops pesados podem apresentar travamentos e falta de memória."
    elif [ "$ram_kb" -lt $((6 * 1024 * 1024)) ] || [ "$livre_kb" -lt $((10 * 1024 * 1024)) ] || [ "$cores" -le 4 ]; then
        LINUX_PROFILE="INTERMEDIÁRIO"
        LINUX_PROFILE_ICON="🟡"
        LINUX_PROFILE_MSG="Linux deve funcionar bem, mas o desktop precisa ser leve."
        LINUX_PROFILE_RECOMMEND="XFCE ou LXQt são indicados. MATE também pode funcionar; evite KDE/GNOME com muitas aplicações abertas."
    fi
}

linux_mostrar_perfil() {
    detectar_variante_termux 2>/dev/null || true
    linux_avaliar_aparelho
    linux_coletar_contexto_arquitetura
    cabecalho_tela "📱 Capacidade para Linux" "Estimativa local antes da instalação"
    caixa_simples_wrap "Hardware detectado" \
        "RAM total: $(linux_formatar_gb_kb "$LINUX_RAM_KB")" \
        "RAM disponível: $(linux_formatar_gb_kb "$(linux_mem_disponivel_kb)")" \
        "CPU: ${LINUX_CPU_CORES} núcleo(s) • ${LINUX_ARCH_CPU_GEN}" \
        "Termux: ${LINUX_ARCH_TERMUX} • ${LINUX_ARCH_BITS} bits" \
        "Android ABI: ${LINUX_ARCH_ANDROID_ABI:-não informada}" \
        "Kernel: ${LINUX_ARCH_KERNEL}" \
        "Espaço livre: $(linux_formatar_gb_kb "$LINUX_FREE_KB")" \
        "Android: $(linux_android_versao)"
    caixa_simples_wrap "Arquitetura interpretada" \
        "$LINUX_ARCH_INTERPRETATION" \
        "As distros nativas seguem a arquitetura do Termux, não apenas a geração da CPU."
    caixa_simples_wrap "${LINUX_PROFILE_ICON} Perfil: ${LINUX_PROFILE}" \
        "$LINUX_PROFILE_MSG" \
        "$LINUX_PROFILE_RECOMMEND"
    pause
}

linux_garantir_proot_distro() {
    command -v proot-distro >/dev/null 2>&1 && return 0

    if declare -F pacote_disponivel_termux >/dev/null 2>&1 && ! pacote_disponivel_termux proot-distro; then
        cabecalho_tela "🐧 Preparar Linux" "Compatibilidade do Termux"
        caixa_simples "⚠ proot-distro indisponível" \
            "O pacote proot-distro não aparece nos repositórios configurados nesta edição do Termux." \
            "Atualize os repositórios ou use uma edição do Termux que ofereça esse pacote."
        return 1
    fi

    cabecalho_tela "🐧 Preparar Linux" "Instalar gerenciador de distribuições"
    caixa_simples "proot-distro não encontrado" \
        "O Manager usa o proot-distro oficial para instalar Linux sem root." \
        "Ele será instalado pelo gerenciador de pacotes do Termux."
    confirmar_acao "Instalar proot-distro agora?" "s" || return 1

    if executar_pkg_monitorado "Instalando proot-distro" 15 92 \
        "Preparando suporte a distribuições Linux..." \
        "A instalação pode levar alguns minutos." -- install -y proot-distro; then
        ok "proot-distro instalado."
        linux_log "proot-distro instalado"
        return 0
    fi

    mostrar_erro_pkg "Não foi possível instalar proot-distro."
    return 1
}

linux_coletar_instaladas() {
    LINUX_INSTALLED_DISTROS=()
    command -v proot-distro >/dev/null 2>&1 || return 1
    local saida rc=0 linha
    saida="$(proot-distro list -q 2>/dev/null)" || rc=$?
    if [ "$rc" -ne 0 ]; then
        saida="$(proot-distro list --quiet 2>/dev/null)" || return 1
    fi
    while IFS= read -r linha; do
        linha="${linha//$'\r'/}"
        linha="${linha#${linha%%[![:space:]]*}}"
        linha="${linha%${linha##*[![:space:]]}}"
        [ -n "$linha" ] || continue
        [[ "$linha" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || continue
        LINUX_INSTALLED_DISTROS+=("$linha")
    done <<< "$saida"
    return 0
}

linux_proot_arquitetura_dispositivo() {
    local arch="${1:-$(linux_arquitetura)}"
    case "$arch" in
        aarch64|arm64) printf 'aarch64' ;;
        arm|armhf|armeabi-v7a) printf 'arm' ;;
        x86_64|amd64) printf 'x86_64' ;;
        i386|i486|i586|i686|x86) printf 'i686' ;;
        riscv64) printf 'riscv64' ;;
        *) return 1 ;;
    esac
}

linux_container_dir() {
    local alias="${1:-}" base="${PREFIX:-}/var/lib/proot-distro"
    [ -n "$alias" ] || return 1
    if [ -d "$base/containers/$alias" ]; then
        printf '%s\n' "$base/containers/$alias"
    elif [ -d "$base/installed-rootfs/$alias" ]; then
        printf '%s\n' "$base/installed-rootfs/$alias"
    else
        return 1
    fi
}

linux_container_rootfs() {
    local alias="${1:-}" dir
    dir="$(linux_container_dir "$alias" 2>/dev/null || true)"
    [ -n "$dir" ] || return 1
    if [ -d "$dir/rootfs" ]; then
        printf '%s\n' "$dir/rootfs"
    else
        printf '%s\n' "$dir"
    fi
}

linux_container_manifest() {
    local alias="${1:-}" dir
    dir="$(linux_container_dir "$alias" 2>/dev/null || true)"
    [ -n "$dir" ] && [ -f "$dir/manifest.json" ] || return 1
    printf '%s\n' "$dir/manifest.json"
}

linux_manifest_campo() {
    local alias="${1:-}" campo="${2:-}" manifest valor
    manifest="$(linux_container_manifest "$alias" 2>/dev/null || true)"
    [ -n "$manifest" ] || return 1
    valor="$(sed -nE 's/^[[:space:]]*"'"$campo"'"[[:space:]]*:[[:space:]]*"([^"\\]*)".*/\1/p' "$manifest" 2>/dev/null | head -n1)"
    [ -n "$valor" ] || return 1
    printf '%s\n' "$valor"
}

linux_os_release_campo() {
    local alias="${1:-}" campo="${2:-}" root valor
    root="$(linux_container_rootfs "$alias" 2>/dev/null || true)"
    [ -n "$root" ] && [ -f "$root/etc/os-release" ] || return 1
    valor="$(sed -nE 's/^'"$campo"'=(.*)$/\1/p' "$root/etc/os-release" 2>/dev/null | head -n1)"
    valor="${valor#\"}"; valor="${valor%\"}"
    valor="${valor#\'}"; valor="${valor%\'}"
    [ -n "$valor" ] || return 1
    printf '%s\n' "$valor"
}

linux_formatar_tamanho_kb() {
    local kb="${1:-0}"
    [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
    awk -v kb="$kb" 'BEGIN {
        if (kb >= 1048576) printf "%.1f GB", kb/1048576;
        else if (kb >= 1024) printf "%.0f MB", kb/1024;
        else printf "%d KB", kb;
    }'
}

linux_cache_info_arquivo() {
    local alias="${1:-linux}" seguro
    seguro="$(printf '%s' "$alias" | tr -cd 'A-Za-z0-9._-')"
    [ -n "$seguro" ] || seguro="linux"
    printf '%s/info-cache/%s.health\n' "$LINUX_STATE_DIR" "$seguro"
}

linux_cache_tamanho_arquivo() {
    local alias="${1:-linux}" seguro
    seguro="$(printf '%s' "$alias" | tr -cd 'A-Za-z0-9._-')"
    [ -n "$seguro" ] || seguro="linux"
    printf '%s/info-cache/%s.size\n' "$LINUX_STATE_DIR" "$seguro"
}

linux_invalidar_cache_distro() {
    local alias="${1:-}" cache
    [ -n "$alias" ] || return 0
    cache="$(linux_cache_info_arquivo "$alias")"
    rm -f "$cache" "$(linux_cache_tamanho_arquivo "$alias")" 2>/dev/null || true
}

