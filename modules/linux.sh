# Módulo: linux.sh
# Linux no celular — proot-distro + Termux:X11

LINUX_STATE_DIR="$PAINEL_DIR/linux"
LINUX_LOG="$LOG_DIR/linux.log"
TERMUX_X11_APK_URL="https://github.com/termux/termux-x11/releases/download/nightly/termux-x11-universal-debug.apk"
TERMUX_X11_APK_NAME="termux-x11-universal-debug.apk"

LINUX_ARCH_CACHE_TTL=21600
LINUX_INFO_CACHE_TTL=300

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
    local ref="${1:-}" seguro
    seguro="$(printf '%s' "$ref" | tr '/:@+' '_____' | tr -cd 'A-Za-z0-9._-')"
    [ -n "$seguro" ] || seguro="imagem"
    printf '%s/arch-cache/%s.cache\n' "$LINUX_STATE_DIR" "$seguro"
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
        printf '%s
' "$bits"
        return 0
    fi
    case "$(linux_arquitetura)" in
        aarch64|arm64|x86_64|amd64|riscv64) printf '64
' ;;
        arm|armhf|armeabi-v7a|i386|i486|i586|i686|x86) printf '32
' ;;
        *) printf 'desconhecido
' ;;
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
        printf 'ARMv%s
' "$geracao"
        return 0
    fi
    linha="$(grep -m1 -E 'ARMv[0-9]+|AArch64' /proc/cpuinfo 2>/dev/null || true)"
    if [[ "$linha" =~ ARMv([0-9]+) ]]; then
        printf 'ARMv%s
' "${BASH_REMATCH[1]}"
        return 0
    fi
    case "$(uname -m 2>/dev/null || true)" in
        aarch64|arm64) printf 'ARMv8+
' ;;
        armv8*) printf 'ARMv8
' ;;
        armv7*) printf 'ARMv7
' ;;
        *) printf 'não identificada
' ;;
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

linux_diag_linha_unica() {
    printf '%s' "${1:-}" | tr '\r\n|' '   ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

linux_resolver_bin_sh() {
    local alias="${1:-}" root caminho alvo n=0
    LINUX_DIAG_ROOTFS=""
    LINUX_DIAG_SHELL_PATH=""
    LINUX_DIAG_SHELL_TARGET=""
    root="$(linux_container_rootfs "$alias" 2>/dev/null || true)"
    LINUX_DIAG_ROOTFS="$root"
    [ -n "$root" ] || return 1
    caminho="$root/bin/sh"
    LINUX_DIAG_SHELL_PATH="$caminho"
    [ -e "$caminho" ] || [ -L "$caminho" ] || return 2
    while [ -L "$caminho" ] && [ "$n" -lt 8 ]; do
        alvo="$(readlink "$caminho" 2>/dev/null || true)"
        [ -n "$alvo" ] || break
        if [[ "$alvo" = /* ]]; then
            caminho="$root$alvo"
        else
            caminho="$(dirname "$caminho")/$alvo"
        fi
        n=$((n + 1))
    done
    LINUX_DIAG_SHELL_TARGET="$caminho"
    [ -e "$caminho" ] || return 3
    return 0
}

linux_arquitetura_binario() {
    local arquivo="${1:-}" desc endian bytes b1 b2 machine
    [ -f "$arquivo" ] || return 1
    if command -v file >/dev/null 2>&1; then
        desc="$(file -Lb "$arquivo" 2>/dev/null || true)"
        case "$desc" in
            *aarch64*|*AArch64*|*ARM64*) printf 'aarch64\n'; return 0 ;;
            *x86-64*|*x86_64*) printf 'x86_64\n'; return 0 ;;
            *80386*|*i386*) printf 'i686\n'; return 0 ;;
            *RISC-V*|*riscv64*) printf 'riscv64\n'; return 0 ;;
            *ARM*) printf 'arm\n'; return 0 ;;
            *script*|*text*) printf 'script\n'; return 0 ;;
        esac
    fi
    # Fallback mínimo: lê e_machine diretamente do cabeçalho ELF.
    bytes="$(dd if="$arquivo" bs=1 skip=18 count=2 2>/dev/null | od -An -t u1 2>/dev/null || true)"
    read -r b1 b2 <<< "$bytes"
    [[ "${b1:-}" =~ ^[0-9]+$ ]] && [[ "${b2:-}" =~ ^[0-9]+$ ]] || return 1
    endian="$(dd if="$arquivo" bs=1 skip=5 count=1 2>/dev/null | od -An -t u1 2>/dev/null | tr -d ' ')"
    if [ "$endian" = "2" ]; then machine=$((b1 * 256 + b2)); else machine=$((b1 + b2 * 256)); fi
    case "$machine" in
        183) printf 'aarch64\n' ;;
        40) printf 'arm\n' ;;
        62) printf 'x86_64\n' ;;
        3) printf 'i686\n' ;;
        243) printf 'riscv64\n' ;;
        *) printf 'desconhecida\n' ;;
    esac
}

linux_loader_binario() {
    local arquivo="${1:-}" desc loader
    [ -f "$arquivo" ] || return 1
    command -v file >/dev/null 2>&1 || return 1
    desc="$(file -Lb "$arquivo" 2>/dev/null || true)"
    loader="$(printf '%s\n' "$desc" | sed -nE 's/.*interpreter ([^, ]+).*/\1/p' | head -n1)"
    [ -n "$loader" ] || return 1
    printf '%s\n' "$loader"
}

linux_qemu_disponivel_para() {
    case "${1:-}" in
        aarch64) command -v qemu-aarch64 >/dev/null 2>&1 || command -v qemu-aarch64-static >/dev/null 2>&1 ;;
        arm) command -v qemu-arm >/dev/null 2>&1 || command -v qemu-arm-static >/dev/null 2>&1 ;;
        x86_64) command -v qemu-x86_64 >/dev/null 2>&1 || command -v qemu-x86_64-static >/dev/null 2>&1 ;;
        i686) command -v qemu-i386 >/dev/null 2>&1 || command -v qemu-i386-static >/dev/null 2>&1 ;;
        riscv64) command -v qemu-riscv64 >/dev/null 2>&1 || command -v qemu-riscv64-static >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

linux_preparar_diagnostico_local() {
    local alias="${1:-}" rc=0 loader="" host manifest shell_arch="desconhecida"
    LINUX_DIAG_CODE=""
    LINUX_DIAG_REASON=""
    LINUX_DIAG_DETAIL=""
    LINUX_DIAG_ERROR=""
    LINUX_DIAG_HOST_ARCH="$(linux_proot_arquitetura_dispositivo "$(linux_arquitetura)" 2>/dev/null || linux_arquitetura)"
    LINUX_DIAG_MANIFEST_ARCH="$(linux_manifest_campo "$alias" arch 2>/dev/null || true)"
    LINUX_DIAG_SHELL_ARCH="desconhecida"
    LINUX_DIAG_LOADER=""
    LINUX_DIAG_LOADER_STATUS="não identificado"
    LINUX_DIAG_QEMU="não necessário"

    linux_resolver_bin_sh "$alias" || rc=$?
    case "$rc" in
        1)
            LINUX_DIAG_CODE="ROOTFS_MISSING"
            LINUX_DIAG_REASON="Rootfs ausente"
            LINUX_DIAG_DETAIL="A pasta principal da distribuição não foi encontrada."
            return 1
            ;;
        2)
            LINUX_DIAG_CODE="SHELL_MISSING"
            LINUX_DIAG_REASON="Shell ausente"
            LINUX_DIAG_DETAIL="O arquivo /bin/sh não existe dentro da distribuição."
            return 1
            ;;
        3)
            LINUX_DIAG_CODE="SHELL_TARGET_MISSING"
            LINUX_DIAG_REASON="Shell quebrado"
            LINUX_DIAG_DETAIL="O link /bin/sh aponta para um arquivo que não existe."
            return 1
            ;;
    esac

    shell_arch="$(linux_arquitetura_binario "$LINUX_DIAG_SHELL_TARGET" 2>/dev/null || printf 'desconhecida')"
    LINUX_DIAG_SHELL_ARCH="$shell_arch"
    loader="$(linux_loader_binario "$LINUX_DIAG_SHELL_TARGET" 2>/dev/null || true)"
    LINUX_DIAG_LOADER="$loader"
    if [ -n "$loader" ]; then
        if [ -e "$LINUX_DIAG_ROOTFS$loader" ]; then
            LINUX_DIAG_LOADER_STATUS="presente"
        else
            LINUX_DIAG_LOADER_STATUS="ausente"
            LINUX_DIAG_CODE="LOADER_MISSING"
            LINUX_DIAG_REASON="Loader ausente"
            LINUX_DIAG_DETAIL="O interpretador ELF '$loader' não existe no rootfs."
            return 1
        fi
    fi

    host="$LINUX_DIAG_HOST_ARCH"
    manifest="$LINUX_DIAG_MANIFEST_ARCH"
    if [ -n "$manifest" ] && [ "$shell_arch" != "desconhecida" ] && [ "$shell_arch" != "script" ] && [ "$manifest" != "$shell_arch" ]; then
        LINUX_DIAG_CODE="ARCH_MISMATCH"
        LINUX_DIAG_REASON="Arquitetura divergente"
        LINUX_DIAG_DETAIL="Manifesto: $manifest; /bin/sh: $shell_arch."
        return 1
    fi
    if [ "$shell_arch" != "desconhecida" ] && [ "$shell_arch" != "script" ] && [ -n "$host" ] && [ "$shell_arch" != "$host" ]; then
        if linux_qemu_disponivel_para "$shell_arch"; then
            LINUX_DIAG_QEMU="disponível"
        else
            LINUX_DIAG_QEMU="não detectado"
        fi
    fi
    return 0
}

linux_traduzir_erro_proot() {
    local erro="${1:-}" linha saida=""
    [ -n "$erro" ] || { printf 'Nenhum erro técnico registrado.
'; return 0; }

    [[ "$erro" == *"Exec format error"* ]] && saida+="• O PRoot recusou o formato do executável inicial.\n"
    [[ "$erro" == *"script but its interpreter"* ]] && saida+="• O interpretador necessário ao script não foi encontrado.\n"
    [[ "$erro" == *"ELF but its interpreter"* ]] && saida+="• O loader/interpretador ELF necessário ao binário pode estar ausente.\n"
    [[ "$erro" == *"foreign binary but qemu was not specified"* ]] && saida+="• O PRoot considera possível uma arquitetura estrangeira sem QEMU configurado.\n"
    [[ "$erro" == *"qemu does not work correctly"* ]] && saida+="• Se QEMU estiver sendo usado, ele pode não estar funcionando corretamente.\n"
    [[ "$erro" == *"loader was not found"* ]] && saida+="• O loader do sistema pode estar ausente ou não funcionar dentro do rootfs.\n"
    [[ "$erro" == *"can't chmod"* && "$erro" == *"/tmp/proot-"* ]] && saida+="• O PRoot falhou ao ajustar um arquivo temporário em /tmp.\n"
    [[ "$erro" == *"can't sanitize binding"* && "$erro" == *"/proc/self/fd/"* ]] && saida+="• Há um aviso de redirecionamento de entrada/saída; normalmente ele não é a causa principal.\n"
    [[ "$erro" == *"Permission denied"* ]] && saida+="• Uma permissão necessária foi recusada.\n"
    [[ "$erro" == *"No such file or directory"* ]] && saida+="• Um arquivo ou caminho necessário não foi encontrado.\n"

    if [ -z "$saida" ]; then
        saida="• O PRoot retornou uma falha que ainda não possui tradução específica no Manager.\n"
    fi
    printf '%b' "$saida"
}

linux_orientacao_diagnostico() {
    local codigo="${1:-${LINUX_DIAG_CODE:-UNKNOWN}}"
    case "$codigo" in
        PROOT_ENV_FAILURE)
            printf '%s
' "Atualize proot/proot-distro e teste novamente. Se várias distros falham igual, o problema tende a estar no ambiente PRoot, não em cada Linux."
            ;;
        ARCH_MISMATCH|EXEC_FORMAT)
            printf '%s
' "Confirme a ABI do Termux e reinstale a distro usando essa arquitetura. Não escolha ARM64 apenas porque a CPU é ARMv8."
            ;;
        QEMU_REQUIRED)
            printf '%s
' "Prefira uma imagem nativa da arquitetura do Termux. Emulação exige QEMU configurado corretamente."
            ;;
        LOADER_MISSING|SHELL_MISSING|SHELL_TARGET_MISSING|ROOTFS_MISSING)
            printf '%s
' "O rootfs parece incompleto. Use Reparar/reinstalar e teste a saúde novamente."
            ;;
        PERMISSION)
            printf '%s
' "Revise permissões e armazenamento do Termux, depois execute o teste novamente."
            ;;
        TIMEOUT)
            printf '%s
' "Feche tarefas pesadas, aguarde alguns segundos e repita o teste."
            ;;
        *)
            printf '%s
' "Use Testar novamente e exporte o log se o erro persistir."
            ;;
    esac
}

linux_testar_proot_host() {
    local out rc=0 host_shell
    LINUX_PROOT_HOST_ERROR=""
    command -v proot >/dev/null 2>&1 || { LINUX_PROOT_HOST_ERROR="Comando proot não encontrado."; return 1; }
    # Usa o shell nativo do próprio Termux. /system/bin/sh pode ter ABI diferente
    # em aparelhos cujo hardware é ARM64, mas o Termux está rodando em 32 bits.
    # Nesse caso, testar /system/bin/sh geraria um falso diagnóstico do PRoot.
    host_shell="${PREFIX:-}/bin/sh"
    [ -x "$host_shell" ] || host_shell="$(command -v sh 2>/dev/null || true)"
    [ -n "$host_shell" ] || { LINUX_PROOT_HOST_ERROR="Shell do Termux não encontrado."; return 1; }
    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 8 proot "$host_shell" -c 'printf __TM_PROOT_HOST_OK__' 2>&1)" || rc=$?
    else
        out="$(proot "$host_shell" -c 'printf __TM_PROOT_HOST_OK__' 2>&1)" || rc=$?
    fi
    if [ "$rc" -eq 0 ] && [[ "$out" == *"__TM_PROOT_HOST_OK__"* ]]; then
        return 0
    fi
    LINUX_PROOT_HOST_ERROR="$(printf '%s' "$out" | tr '\r\n' '  ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-600)"
    return 1
}


linux_pacote_versao() {
    local pacote="${1:-}"
    [ -n "$pacote" ] || return 1
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Version}' "$pacote" 2>/dev/null || printf 'não instalado'
    else
        printf 'indisponível'
    fi
}

linux_proot_tmp_dir() {
    if [ -n "${PREFIX:-}" ]; then
        printf '%s/tmp\n' "$PREFIX"
    elif [ -n "${TMPDIR:-}" ]; then
        printf '%s\n' "$TMPDIR"
    else
        printf '/tmp\n'
    fi
}

linux_testar_tmp_proot() {
    local dir arquivo
    LINUX_PROOT_TMP_ERROR=""
    dir="$(linux_proot_tmp_dir)"
    mkdir -p "$dir" 2>/dev/null || {
        LINUX_PROOT_TMP_ERROR="Não foi possível criar $dir."
        return 1
    }
    [ -w "$dir" ] || {
        LINUX_PROOT_TMP_ERROR="$dir não permite gravação."
        return 1
    }
    arquivo="$(mktemp "$dir/manager-proot-test.XXXXXX" 2>/dev/null || true)"
    [ -n "$arquivo" ] && [ -f "$arquivo" ] || {
        LINUX_PROOT_TMP_ERROR="Não foi possível criar arquivo temporário em $dir."
        return 1
    }
    printf '#!/data/data/com.termux/files/usr/bin/sh\nexit 0\n' > "$arquivo" 2>/dev/null || {
        rm -f "$arquivo" 2>/dev/null || true
        LINUX_PROOT_TMP_ERROR="Falha ao gravar arquivo temporário."
        return 1
    }
    chmod 700 "$arquivo" 2>/dev/null || {
        rm -f "$arquivo" 2>/dev/null || true
        LINUX_PROOT_TMP_ERROR="Falha ao aplicar chmod no arquivo temporário."
        return 1
    }
    rm -f "$arquivo" 2>/dev/null || true
    return 0
}

linux_diagnosticar_ambiente_proot() {
    local host_ok="falhou" tmp_ok="falhou" cmd_proot="ausente" cmd_pd="ausente"
    LINUX_PROOT_ENV_PROOT_VERSION="$(linux_pacote_versao proot)"
    LINUX_PROOT_ENV_DISTRO_VERSION="$(linux_pacote_versao proot-distro)"
    LINUX_PROOT_ENV_TMP="$(linux_proot_tmp_dir)"
    LINUX_PROOT_ENV_HOST_ERROR=""
    LINUX_PROOT_ENV_TMP_ERROR=""
    command -v proot >/dev/null 2>&1 && cmd_proot="OK"
    command -v proot-distro >/dev/null 2>&1 && cmd_pd="OK"
    if linux_testar_tmp_proot; then
        tmp_ok="OK"
    else
        LINUX_PROOT_ENV_TMP_ERROR="${LINUX_PROOT_TMP_ERROR:-falha desconhecida}"
    fi
    if linux_testar_proot_host; then
        host_ok="OK"
    else
        LINUX_PROOT_ENV_HOST_ERROR="${LINUX_PROOT_HOST_ERROR:-falha desconhecida}"
    fi
    LINUX_PROOT_ENV_COMMANDS="$cmd_proot / $cmd_pd"
    LINUX_PROOT_ENV_TMP_STATUS="$tmp_ok"
    LINUX_PROOT_ENV_HOST_STATUS="$host_ok"
    if [ "$cmd_proot" = "OK" ] && [ "$cmd_pd" = "OK" ] && [ "$tmp_ok" = "OK" ] && [ "$host_ok" = "OK" ]; then
        LINUX_PROOT_ENV_STATUS="OK"
        return 0
    fi
    LINUX_PROOT_ENV_STATUS="PROBLEMA"
    return 1
}

linux_mostrar_diagnostico_proot() {
    linux_diagnosticar_ambiente_proot || true
    linux_coletar_instaladas >/dev/null 2>&1 || true
    cabecalho_tela "🩺 Ambiente PRoot" "Diagnóstico do motor Linux"
    caixa_simples_wrap "Componentes"         "Comandos proot / proot-distro: ${LINUX_PROOT_ENV_COMMANDS:-?}"         "proot: ${LINUX_PROOT_ENV_PROOT_VERSION:-?}"         "proot-distro: ${LINUX_PROOT_ENV_DISTRO_VERSION:-?}"         "Distros preservadas: ${#LINUX_INSTALLED_DISTROS[@]}"
    caixa_simples_wrap "Testes"         "Temporários: ${LINUX_PROOT_ENV_TMP_STATUS:-?} • $(caminho_curto "${LINUX_PROOT_ENV_TMP:-$(linux_proot_tmp_dir)}")"         "PRoot básico: ${LINUX_PROOT_ENV_HOST_STATUS:-?}"
    if [ -n "${LINUX_PROOT_ENV_TMP_ERROR:-}" ] || [ -n "${LINUX_PROOT_ENV_HOST_ERROR:-}" ]; then
        caixa_simples_wrap "Problema encontrado"             "${LINUX_PROOT_ENV_TMP_ERROR:-}"             "${LINUX_PROOT_ENV_HOST_ERROR:-}"
    else
        caixa_simples "Resultado" "✅ Ambiente PRoot básico funcionando."
    fi
    rodape_atalhos "[0] Voltar  •  [1] Reparar ambiente  •  [2] Testar novamente"
    ui_buffer_flush
}

linux_invalidar_todos_cache_saude() {
    rm -f "$LINUX_STATE_DIR"/info-cache/*.health 2>/dev/null || true
}

linux_reparar_ambiente_proot() {
    local tmpdir antes depois rc=0
    linux_coletar_instaladas >/dev/null 2>&1 || true
    antes=${#LINUX_INSTALLED_DISTROS[@]}
    cabecalho_tela "🛠️ Reparar PRoot" "Sem apagar distribuições"
    caixa_simples_wrap "O que será feito"         "Verificar a pasta temporária do Termux."         "Reinstalar somente proot e proot-distro."         "Limpar o cache de saúde do Manager e testar novamente."         "As $antes distro(s) instalada(s) não serão removidas."
    confirmar_acao "Continuar com o reparo do ambiente PRoot?" "s" || return 0

    tmpdir="$(linux_proot_tmp_dir)"
    mkdir -p "$tmpdir" 2>>"$LINUX_LOG" || rc=1
    chmod u+rwx "$tmpdir" 2>>"$LINUX_LOG" || rc=1
    # Remove apenas temporários criados pelos testes do próprio Manager.
    rm -f "$tmpdir"/manager-proot-test.* "$tmpdir"/tm-linux-health-* 2>/dev/null || true

    if [ "$rc" -ne 0 ]; then
        cabecalho_tela "🛠️ Reparar PRoot" "Falha antes da reinstalação"
        caixa_simples_wrap "Pasta temporária"             "Não foi possível preparar $(caminho_curto "$tmpdir")."             "O Manager não alterou as distribuições instaladas."
        pause
        return 1
    fi

    if declare -F executar_pkg_monitorado >/dev/null 2>&1; then
        if ! executar_pkg_monitorado "Reparando ambiente PRoot" 15 92             "Reinstalando componentes..." "proot e proot-distro" --             install -y --reinstall proot proot-distro; then
            cabecalho_tela "🛠️ Reparar PRoot" "Reinstalação não concluída"
            caixa_simples_wrap "Falha no pkg"                 "Não foi possível reinstalar proot/proot-distro."                 "As distribuições continuam preservadas."
            pause
            return 1
        fi
    else
        if ! pkg install -y --reinstall proot proot-distro >>"$LINUX_LOG" 2>&1; then
            cabecalho_tela "🛠️ Reparar PRoot" "Reinstalação não concluída"
            caixa_simples "Falha no pkg" "As distribuições continuam preservadas."
            pause
            return 1
        fi
    fi

    linux_invalidar_todos_cache_saude
    linux_coletar_instaladas >/dev/null 2>&1 || true
    depois=${#LINUX_INSTALLED_DISTROS[@]}
    linux_diagnosticar_ambiente_proot || true
    linux_log "reparo do ambiente PRoot concluído: status=${LINUX_PROOT_ENV_STATUS:-?} distros=$antes->$depois"
    cabecalho_tela "✅ Reparo do PRoot concluído" "Distribuições preservadas: $depois"
    caixa_simples_wrap "Resultado"         "PRoot básico: ${LINUX_PROOT_ENV_HOST_STATUS:-?}"         "Temporários: ${LINUX_PROOT_ENV_TMP_STATUS:-?}"         "proot: ${LINUX_PROOT_ENV_PROOT_VERSION:-?}"         "proot-distro: ${LINUX_PROOT_ENV_DISTRO_VERSION:-?}"
    if [ "${LINUX_PROOT_ENV_STATUS:-PROBLEMA}" != "OK" ]; then
        caixa_simples_wrap "Ainda há problema"             "O reparo não resolveu o teste básico do PRoot."             "Use o diagnóstico e exporte o log antes de reinstalar distros."
    else
        caixa_simples_wrap "Próximo teste"             "Abra Meus Linux e use Testar novamente na distro com problema."
    fi
    pause
}

menu_ambiente_proot() {
    local escolha
    while true; do
        linux_mostrar_diagnostico_proot
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_reparar_ambiente_proot ;;
            2) : ;;
            0|"") tela_limpar; return 0 ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

linux_classificar_falha_saude() {
    local rc="${1:-1}" erro="${2:-}" host="${LINUX_DIAG_HOST_ARCH:-}" guest="${LINUX_DIAG_SHELL_ARCH:-}"
    # Diagnósticos estruturais encontrados antes da execução têm prioridade.
    if [ -n "${LINUX_DIAG_CODE:-}" ]; then
        return 0
    fi
    if [ "$rc" = "124" ]; then
        LINUX_DIAG_CODE="TIMEOUT"
        LINUX_DIAG_REASON="Inicialização demorou"
        LINUX_DIAG_DETAIL="O teste não respondeu dentro do limite de segurança."
    elif [[ "$erro" == *"Exec format error"* ]]; then
        # A mensagem do PRoot lista QEMU entre causas possíveis mesmo quando
        # ele não é a causa real. Só marcamos QEMU quando há arquitetura
        # estrangeira confirmada; caso contrário usamos o diagnóstico neutro.
        if [ -n "$guest" ] && [ "$guest" != "desconhecida" ] && [ "$guest" != "script" ] && \
           [ -n "$host" ] && [ "$guest" != "$host" ]; then
            LINUX_DIAG_CODE="QEMU_REQUIRED"
            LINUX_DIAG_REASON="Emulação necessária"
            LINUX_DIAG_DETAIL="Host: $host; /bin/sh: $guest; execução nativa incompatível."
        else
            if [ -n "$guest" ] && [ "$guest" != "desconhecida" ] && [ -n "$host" ] && [ "$guest" = "$host" ]; then
                LINUX_DIAG_CODE="PROOT_ENV_FAILURE"
                LINUX_DIAG_REASON="Falha do ambiente PRoot"
                LINUX_DIAG_DETAIL="A arquitetura da distro coincide com o Termux, mas o PRoot não conseguiu executar /bin/sh."
            else
                LINUX_DIAG_CODE="EXEC_FORMAT"
                LINUX_DIAG_REASON="Formato incompatível"
                if [ -n "$guest" ] && [ "$guest" != "desconhecida" ]; then
                    LINUX_DIAG_DETAIL="Host: ${host:-desconhecido}; /bin/sh: $guest."
                else
                    LINUX_DIAG_DETAIL="O Android/PRoot recusou o formato do /bin/sh desta distro."
                fi
            fi
        fi
    elif [[ "$erro" == *"qemu was not specified"* ]] && [ -n "$guest" ] && [ -n "$host" ] && [ "$guest" != "$host" ]; then
        LINUX_DIAG_CODE="QEMU_REQUIRED"
        LINUX_DIAG_REASON="Emulação necessária"
        LINUX_DIAG_DETAIL="A arquitetura da distro é diferente da arquitetura do Termux."
    elif [[ "$erro" == *"Permission denied"* ]]; then
        LINUX_DIAG_CODE="PERMISSION"
        LINUX_DIAG_REASON="Permissão inválida"
        LINUX_DIAG_DETAIL="O /bin/sh existe, mas não pôde ser executado."
    elif [[ "$erro" == *"No such file or directory"* ]] && [[ "$erro" == *"interpreter"* ]]; then
        LINUX_DIAG_CODE="LOADER_MISSING"
        LINUX_DIAG_REASON="Loader ausente"
        LINUX_DIAG_DETAIL="O interpretador dinâmico necessário ao binário não foi encontrado."
    elif [[ "$erro" == *"can't chmod"* && "$erro" == *"/tmp/proot-"* ]]; then
        LINUX_DIAG_CODE="PROOT_ENV_FAILURE"
        LINUX_DIAG_REASON="Falha do ambiente PRoot"
        LINUX_DIAG_DETAIL="O PRoot falhou ao criar ou ajustar arquivos temporários antes de iniciar a distro."
    elif [[ "$erro" == *"No such file or directory"* ]]; then
        LINUX_DIAG_CODE="FILE_MISSING"
        LINUX_DIAG_REASON="Arquivo ausente"
        LINUX_DIAG_DETAIL="Um arquivo necessário para iniciar a distribuição não foi encontrado."
    else
        if ! linux_testar_proot_host; then
            LINUX_DIAG_CODE="PROOT_ENV_FAILURE"
            LINUX_DIAG_REASON="Falha do ambiente PRoot"
            LINUX_DIAG_DETAIL="O teste básico do PRoot também falhou fora da distro; o ambiente do Termux precisa ser verificado."
        else
            LINUX_DIAG_CODE="PROOT_FAILURE"
            LINUX_DIAG_REASON="Falha no PRoot"
            LINUX_DIAG_DETAIL="O PRoot funciona no Termux, mas o proot-distro falhou ao iniciar esta distribuição."
        fi
    fi
}

linux_salvar_cache_saude() {
    local cache="${1:-}" agora="${2:-0}" status="${3:-unknown}"
    mkdir -p "$(dirname "$cache")" 2>/dev/null || true
    {
        printf '%s|%s|%s\n' "$agora" "$status" "$(linux_diag_linha_unica "${LINUX_DIAG_CODE:-}")"
        linux_diag_linha_unica "${LINUX_DIAG_REASON:-}"; printf '\n'
        linux_diag_linha_unica "${LINUX_DIAG_DETAIL:-}"; printf '\n'
        linux_diag_linha_unica "${LINUX_DIAG_ERROR:-}"; printf '\n'
    } > "$cache" 2>/dev/null || true
}

linux_carregar_cache_saude() {
    local cache="${1:-}" agora="${2:-0}" first salvo_ts salvo_status salvo_code
    [ -f "$cache" ] || return 1
    first="$(sed -n '1p' "$cache" 2>/dev/null || true)"
    IFS='|' read -r salvo_ts salvo_status salvo_code <<< "$first"
    if ! [[ "$agora" =~ ^[0-9]+$ ]] || ! [[ "${salvo_ts:-}" =~ ^[0-9]+$ ]] || \
       [ $((agora - salvo_ts)) -lt 0 ] || [ $((agora - salvo_ts)) -ge "$LINUX_INFO_CACHE_TTL" ]; then
        return 1
    fi
    # Caches antigos ou genéricos são refeitos para aproveitar o diagnóstico
    # de ambiente PRoot e a interpretação de arquitetura desta versão.
    if [ "${salvo_status:-}" = "problem" ] && { [ -z "${salvo_code:-}" ] || [ "$salvo_code" = "PROOT_FAILURE" ] || [ "$salvo_code" = "EXEC_FORMAT" ]; }; then
        return 1
    fi
    LINUX_INFO_HEALTH="${salvo_status:-unknown}"
    LINUX_DIAG_CODE="${salvo_code:-}"
    LINUX_DIAG_REASON="$(sed -n '2p' "$cache" 2>/dev/null || true)"
    LINUX_DIAG_DETAIL="$(sed -n '3p' "$cache" 2>/dev/null || true)"
    LINUX_DIAG_ERROR="$(sed -n '4p' "$cache" 2>/dev/null || true)"
    LINUX_INFO_HEALTH_ERROR="$LINUX_DIAG_ERROR"
    return 0
}

linux_testar_saude_distro() {
    local alias="${1:-}" forcar="${2:-false}" cache agora rc=0 saida="" errfile erro=""
    cache="$(linux_cache_info_arquivo "$alias")"
    agora="$(date +%s 2>/dev/null || printf '0')"

    # Coleta metadados locais sempre: é barato e permite explicar o estado mesmo com cache.
    linux_preparar_diagnostico_local "$alias" || true
    if [ "$forcar" != "true" ] && linux_carregar_cache_saude "$cache" "$agora"; then
        return 0
    fi

    errfile="${TMPDIR:-/tmp}/tm-linux-health-$$.log"
    : > "$errfile" 2>/dev/null || true
    if command -v timeout >/dev/null 2>&1 && [ "$(type -t proot-distro 2>/dev/null || true)" = "file" ]; then
        saida="$(timeout 8 proot-distro login "$alias" -- /bin/sh -lc 'printf __TM_HEALTH_OK__' 2>"$errfile")" || rc=$?
    else
        saida="$(proot-distro login "$alias" -- /bin/sh -lc 'printf __TM_HEALTH_OK__' 2>"$errfile")" || rc=$?
    fi
    erro="$(tail -n 14 "$errfile" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-1200)"

    if [ "$rc" -eq 0 ] && [[ "$saida" == *"__TM_HEALTH_OK__"* ]]; then
        LINUX_INFO_HEALTH="ok"
        LINUX_DIAG_CODE="OK"
        LINUX_DIAG_REASON="Inicialização normal"
        LINUX_DIAG_DETAIL="/bin/sh respondeu ao teste do Manager."
        LINUX_DIAG_ERROR=""
        LINUX_INFO_HEALTH_ERROR=""
    else
        LINUX_INFO_HEALTH="problem"
        # Se o preflight encontrou algo estrutural, mantém a causa. Caso contrário classifica stderr/rc.
        linux_classificar_falha_saude "$rc" "$erro"
        LINUX_DIAG_ERROR="$erro"
        LINUX_INFO_HEALTH_ERROR="$erro"
    fi
    linux_salvar_cache_saude "$cache" "$agora" "$LINUX_INFO_HEALTH"
    rm -f "$errfile" 2>/dev/null || true
}

linux_rotulo_curto_saude() {
    case "${LINUX_DIAG_CODE:-}" in
        OK) printf 'OK' ;;
        ARCH_MISMATCH|EXEC_FORMAT) printf 'Arquitetura' ;;
        QEMU_REQUIRED) printf 'QEMU' ;;
        ROOTFS_MISSING) printf 'Rootfs ausente' ;;
        SHELL_MISSING|SHELL_TARGET_MISSING) printf 'Shell ausente' ;;
        LOADER_MISSING) printf 'Loader ausente' ;;
        TIMEOUT) printf 'Timeout' ;;
        PROOT_ENV_FAILURE) printf 'Ambiente PRoot' ;;
        PERMISSION) printf 'Permissão' ;;
        FILE_MISSING) printf 'Arquivo ausente' ;;
        *) printf 'Inicialização' ;;
    esac
}

linux_limpar_ansi_log() {
    sed -E $'s/\x1B\[[0-9;?]*[ -\/]*[@-~]//g'
}

linux_exportar_diagnostico_distro() {
    local alias="${1:-}" pasta carimbo slug destino shell_exib loader_exib erro_pt orientacao proot_status
    [ -n "$alias" ] || return 1
    linux_coletar_info_distro "$alias" false
    linux_coletar_contexto_arquitetura
    erro_pt="$(linux_traduzir_erro_proot "${LINUX_INFO_HEALTH_ERROR:-}")"
    orientacao="$(linux_orientacao_diagnostico "${LINUX_DIAG_CODE:-UNKNOWN}")"
    if linux_testar_proot_host; then
        proot_status="OK"
    else
        proot_status="FALHOU"
    fi

    if ! resolver_downloads_dir >/dev/null 2>&1; then
        cabecalho_tela "📥 Exportar diagnóstico" "$LINUX_INFO_NAME"
        caixa_simples_wrap "Downloads indisponível" \
            "Não foi possível acessar a pasta Downloads." \
            "Execute termux-setup-storage e tente novamente."
        pause
        return 1
    fi
    pasta="${DOWNLOADS_DIR:-$HOME/storage/downloads}"
    mkdir -p "$pasta" 2>/dev/null || true
    [ -d "$pasta" ] || {
        cabecalho_tela "📥 Exportar diagnóstico" "$LINUX_INFO_NAME"
        caixa_simples_wrap "Destino indisponível" "A pasta Downloads não está acessível."
        pause
        return 1
    }

    carimbo="$(date '+%Y%m%d-%H%M%S')"
    if declare -F sanitizar_nome_arquivo >/dev/null 2>&1; then
        slug="$(sanitizar_nome_arquivo "$alias")"
    else
        slug="$(printf '%s' "$alias" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g; s/-+/-/g')"
    fi
    [ -n "$slug" ] || slug="linux"
    destino="$pasta/linux-diagnostico-${slug}-${carimbo}.log"
    shell_exib="${LINUX_DIAG_SHELL_TARGET:-não localizado}"
    [ -n "${LINUX_DIAG_ROOTFS:-}" ] && shell_exib="${shell_exib#"$LINUX_DIAG_ROOTFS"}"
    loader_exib="${LINUX_DIAG_LOADER:-não identificado}"

    {
        printf 'Manager.sh — Diagnóstico Linux\n'
        printf 'Gerado em: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'Distribuição: %s\n' "$LINUX_INFO_NAME"
        printf 'Alias: %s\n\n' "$alias"

        printf '[Resumo em português]\n'
        printf 'Saúde: %s %s\n' "$LINUX_INFO_HEALTH_ICON" "$LINUX_INFO_HEALTH_LABEL"
        printf 'Código: %s\n' "${LINUX_DIAG_CODE:-UNKNOWN}"
        printf 'Motivo: %s\n' "${LINUX_DIAG_REASON:-não identificado}"
        printf 'Detalhe: %s\n' "${LINUX_DIAG_DETAIL:-sem detalhe adicional}"
        printf 'Teste básico do PRoot: %s\n\n' "$proot_status"

        printf '[Interpretação do erro em português]\n%s\n' "$erro_pt"
        printf '[O que fazer]\n%s\n\n' "$orientacao"

        printf '[Arquitetura interpretada]\n'
        printf 'CPU: %s\n' "${LINUX_ARCH_CPU_GEN:-não identificada}"
        printf 'Kernel: %s\n' "${LINUX_ARCH_KERNEL:-desconhecido}"
        printf 'Android ABI principal: %s\n' "${LINUX_ARCH_ANDROID_ABI:-não informada}"
        printf 'Android ABIs: %s\n' "${LINUX_ARCH_ANDROID_ABILIST:-não informadas}"
        printf 'Android ABIs 32-bit: %s\n' "${LINUX_ARCH_ANDROID_ABILIST32:-não informadas}"
        printf 'Android ABIs 64-bit: %s\n' "${LINUX_ARCH_ANDROID_ABILIST64:-não informadas}"
        printf 'Termux: %s (%s bits)\n' "${LINUX_ARCH_TERMUX:-desconhecida}" "${LINUX_ARCH_BITS:-?}"
        printf 'Distro (manifesto): %s\n' "${LINUX_DIAG_MANIFEST_ARCH:-não informado}"
        printf '/bin/sh: %s\n' "${LINUX_DIAG_SHELL_ARCH:-desconhecida}"
        printf 'Interpretação: %s\n' "${LINUX_ARCH_INTERPRETATION:-não disponível}"
        printf 'QEMU: %s\n\n' "${LINUX_DIAG_QEMU:-não verificado}"

        printf '[Arquivos]\n'
        printf 'Shell: %s\n' "$shell_exib"
        printf 'Loader: %s\n' "$loader_exib"
        printf 'Loader no rootfs: %s\n\n' "${LINUX_DIAG_LOADER_STATUS:-não verificado}"

        printf '[Erro original do PRoot — preservado]\n%s\n\n' "${LINUX_INFO_HEALTH_ERROR:-sem registro}"
        [ -n "${LINUX_PROOT_HOST_ERROR:-}" ] && printf '[Erro do teste básico do PRoot]\n%s\n\n' "$LINUX_PROOT_HOST_ERROR"

        printf '[Log recente do Linux]\n'
        if [ -f "$LINUX_LOG" ]; then
            tail -n 160 "$LINUX_LOG" | linux_limpar_ansi_log
        else
            printf 'Arquivo de log não encontrado: %s\n' "$LINUX_LOG"
        fi
    } > "$destino"

    cabecalho_tela "📥 Exportar diagnóstico" "$LINUX_INFO_NAME"
    caixa_simples_wrap "Arquivo salvo" \
        "Diagnóstico em português salvo em Downloads." \
        "O erro técnico original também foi preservado." \
        "Arquivo: $(basename "$destino")"
    pause
}

linux_exibir_diagnostico_distro() {
    local alias="${1:-}" forcar="${2:-false}" shell_exib loader_exib escolha erro_pt orientacao proot_status
    [ -n "$alias" ] || return 1
    while true; do
        linux_coletar_info_distro "$alias" "$forcar"
        forcar=false
        linux_coletar_contexto_arquitetura
        shell_exib="${LINUX_DIAG_SHELL_TARGET:-não localizado}"
        [ -n "${LINUX_DIAG_ROOTFS:-}" ] && shell_exib="${shell_exib#"$LINUX_DIAG_ROOTFS"}"
        loader_exib="${LINUX_DIAG_LOADER:-não identificado}"
        erro_pt="$(linux_traduzir_erro_proot "${LINUX_INFO_HEALTH_ERROR:-}")"
        orientacao="$(linux_orientacao_diagnostico "${LINUX_DIAG_CODE:-UNKNOWN}")"
        if linux_testar_proot_host; then proot_status="OK"; else proot_status="falhou"; fi

        cabecalho_tela "🔎 Diagnóstico Linux" "$LINUX_INFO_NAME"
        caixa_simples_wrap "Resultado" \
            "Saúde: ${LINUX_INFO_HEALTH_ICON} ${LINUX_INFO_HEALTH_LABEL}" \
            "Motivo: ${LINUX_DIAG_REASON:-não identificado}" \
            "Código: ${LINUX_DIAG_CODE:-UNKNOWN}" \
            "PRoot base: $proot_status"

        caixa_simples_wrap "Arquitetura" \
            "CPU: ${LINUX_ARCH_CPU_GEN:-?} • Termux: ${LINUX_ARCH_TERMUX:-?} (${LINUX_ARCH_BITS:-?} bits)" \
            "Android ABI: ${LINUX_ARCH_ANDROID_ABI:-não informada}" \
            "Distro / shell: ${LINUX_DIAG_MANIFEST_ARCH:-?} / ${LINUX_DIAG_SHELL_ARCH:-?}" \
            "${LINUX_ARCH_INTERPRETATION:-}"

        caixa_simples_wrap "Interpretação do erro" "$erro_pt"
        caixa_simples_wrap "O que fazer" "$orientacao"

        caixa_simples_wrap "Arquivos" \
            "Shell: $shell_exib" \
            "Loader: $loader_exib" \
            "Loader no rootfs: ${LINUX_DIAG_LOADER_STATUS:-não verificado}" \
            "Log: $(caminho_curto "$LINUX_LOG")"

        rodape_atalhos "[0] Voltar  •  [1] Exportar log  •  [2] Testar novamente"
        ui_buffer_flush
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_exportar_diagnostico_distro "$alias" ;;
            2) forcar=true ;;
            0|"") tela_limpar; return 0 ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
linux_distro_sessoes_ativas() {
    local alias="${1:-}" saida
    command -v proot-distro >/dev/null 2>&1 || { printf '0\n'; return; }
    saida="$(proot-distro ps 2>/dev/null || true)"
    if [ -z "$saida" ]; then
        printf '0\n'
        return
    fi
    printf '%s\n' "$saida" | awk -v a="$alias" 'NR>1 && $2==a {n++} END{print n+0}'
}

linux_distro_desktops_rootfs() {
    local alias="${1:-}" root id launcher caminho nomes=""
    root="$(linux_container_rootfs "$alias" 2>/dev/null || true)"
    [ -n "$root" ] || { printf 'nenhum\n'; return; }
    for id in xfce lxqt lxde mate openbox i3 kde gnome; do
        launcher="$(linux_desktop_launcher "$id" 2>/dev/null || true)"
        [ -n "$launcher" ] || continue
        caminho=""
        for base in usr/bin usr/local/bin bin; do
            [ -e "$root/$base/$launcher" ] && { caminho="$root/$base/$launcher"; break; }
        done
        if [ -n "$caminho" ]; then
            nomes+="${nomes:+, }$(linux_desktop_nome "$id")"
        fi
    done
    printf '%s\n' "${nomes:-nenhum}"
}

linux_distro_gerenciador_rootfs() {
    local alias="${1:-}" root
    root="$(linux_container_rootfs "$alias" 2>/dev/null || true)"
    [ -n "$root" ] || { printf 'desconhecido\n'; return; }
    [ -e "$root/usr/bin/apt-get" ] && { printf 'apt\n'; return; }
    [ -e "$root/usr/bin/pacman" ] && { printf 'pacman\n'; return; }
    if [ -e "$root/sbin/apk" ] || [ -e "$root/usr/bin/apk" ]; then printf 'apk\n'; return; fi
    [ -e "$root/usr/bin/dnf" ] && { printf 'dnf\n'; return; }
    [ -e "$root/usr/bin/zypper" ] && { printf 'zypper\n'; return; }
    printf 'desconhecido\n'
}

linux_distro_tamanho_kb() {
    local alias="${1:-}" root tamanho cache agora salvo_ts salvo_kb
    root="$(linux_container_rootfs "$alias" 2>/dev/null || true)"
    [ -n "$root" ] || { printf '0\n'; return; }
    cache="$(linux_cache_tamanho_arquivo "$alias")"
    agora="$(date +%s 2>/dev/null || printf '0')"
    if [ -f "$cache" ]; then
        IFS='|' read -r salvo_ts salvo_kb < "$cache" || true
        if [[ "$agora" =~ ^[0-9]+$ ]] && [[ "${salvo_ts:-}" =~ ^[0-9]+$ ]] && [[ "${salvo_kb:-}" =~ ^[0-9]+$ ]] && \
           [ $((agora - salvo_ts)) -ge 0 ] && [ $((agora - salvo_ts)) -lt "$LINUX_INFO_CACHE_TTL" ]; then
            printf '%s\n' "$salvo_kb"
            return
        fi
    fi
    tamanho="$(du -sk "$root" 2>/dev/null | awk 'NR==1{print $1}')"
    [[ "$tamanho" =~ ^[0-9]+$ ]] || tamanho=0
    mkdir -p "$(dirname "$cache")" 2>/dev/null || true
    printf '%s|%s\n' "$agora" "$tamanho" > "$cache" 2>/dev/null || true
    printf '%s\n' "$tamanho"
}

linux_coletar_info_distro() {
    local alias="${1:-}" forcar_saude="${2:-false}" nome versao arch imagem tamanho_kb sessoes desktops gerenciador
    nome="$(linux_os_release_campo "$alias" PRETTY_NAME 2>/dev/null || true)"
    [ -n "$nome" ] || nome="$(linux_os_release_campo "$alias" NAME 2>/dev/null || true)"
    [ -n "$nome" ] || nome="$alias"
    versao="$(linux_os_release_campo "$alias" VERSION_ID 2>/dev/null || true)"
    arch="$(linux_manifest_campo "$alias" arch 2>/dev/null || true)"
    [ -n "$arch" ] || arch="desconhecida"
    imagem="$(linux_manifest_campo "$alias" image_ref 2>/dev/null || true)"
    [ -n "$imagem" ] || imagem="origem não registrada"
    tamanho_kb="$(linux_distro_tamanho_kb "$alias")"
    sessoes="$(linux_distro_sessoes_ativas "$alias")"
    desktops="$(linux_distro_desktops_rootfs "$alias")"
    gerenciador="$(linux_distro_gerenciador_rootfs "$alias")"
    linux_testar_saude_distro "$alias" "$forcar_saude"

    LINUX_INFO_ALIAS="$alias"
    LINUX_INFO_NAME="$nome"
    LINUX_INFO_VERSION="$versao"
    LINUX_INFO_ARCH="$arch"
    LINUX_INFO_IMAGE="$imagem"
    LINUX_INFO_SIZE_KB="$tamanho_kb"
    LINUX_INFO_SIZE="$(linux_formatar_tamanho_kb "$tamanho_kb")"
    LINUX_INFO_SESSIONS="$sessoes"
    LINUX_INFO_DESKTOPS="$desktops"
    LINUX_INFO_PM="$gerenciador"
    if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
        LINUX_INFO_HEALTH_ICON="✅"
        LINUX_INFO_HEALTH_LABEL="OK"
    else
        LINUX_INFO_HEALTH_ICON="⚠️"
        LINUX_INFO_HEALTH_LABEL="$(linux_rotulo_curto_saude)"
    fi
    if [ "$sessoes" -gt 0 ] 2>/dev/null; then
        LINUX_INFO_STATE_ICON="🟢"
        LINUX_INFO_STATE_LABEL="Em execução (${sessoes})"
    else
        LINUX_INFO_STATE_ICON="⚪"
        LINUX_INFO_STATE_LABEL="Parado"
    fi
}

linux_exibir_info_distro() {
    local alias="${1:-}"
    linux_coletar_info_distro "$alias" true
    cabecalho_tela "🐧 $LINUX_INFO_NAME" "Informações da distribuição"
    caixa_simples "Estado" \
        "Alias: $alias" \
        "Estado: ${LINUX_INFO_STATE_ICON} ${LINUX_INFO_STATE_LABEL}" \
        "Saúde: ${LINUX_INFO_HEALTH_ICON} ${LINUX_INFO_HEALTH_LABEL}" \
        "Tamanho atual: $LINUX_INFO_SIZE"
    caixa_simples "Sistema" \
        "Versão: ${LINUX_INFO_VERSION:-não informada}" \
        "Arquitetura: $LINUX_INFO_ARCH" \
        "Imagem de origem: $LINUX_INFO_IMAGE" \
        "Gerenciador: $(linux_descrever_gerenciador_distro "$LINUX_INFO_PM")" \
        "Desktop(s): $LINUX_INFO_DESKTOPS"
    if [ "$LINUX_INFO_HEALTH" != "ok" ]; then
        caixa_simples "⚠ Diagnóstico" \
            "Motivo: ${LINUX_DIAG_REASON:-não identificado}" \
            "Código: ${LINUX_DIAG_CODE:-UNKNOWN}" \
            "Use Diagnóstico para ver os detalhes."
    fi
    pause
}

linux_nome_container_imagem() {
    local ref="${1:-}" nome
    nome="${ref%%@*}"
    nome="${nome##*/}"
    if [[ "$nome" == *:* ]]; then nome="${nome%%:*}"; fi
    nome="$(printf '%s' "$nome" | tr -cd 'A-Za-z0-9._-')"
    [ -n "$nome" ] || nome="linux"
    printf '%s\n' "$nome"
}

linux_imagem_referencia_valida() {
    local ref="${1:-}"
    [ -n "$ref" ] || return 1
    [ ${#ref} -le 255 ] || return 1
    [[ "$ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/:@+-]*$ ]]
}

linux_selecionar_instalada() {
    local titulo="${1:-Selecionar distribuição}" subtitulo="${2:-Distribuições instaladas}" i escolha
    linux_coletar_instaladas || true
    if [ ${#LINUX_INSTALLED_DISTROS[@]} -eq 0 ]; then
        cabecalho_tela "🐧 Nenhuma distribuição instalada" "É preciso instalar uma distribuição antes de continuar"
        caixa_simples "Próximo passo" \
            "Ainda não há nenhum Linux instalado pelo proot-distro." \
            "O Manager pode abrir agora a tela de instalação." \
            "Você não precisa digitar alias manualmente."
        if confirmar_acao "Instalar uma distribuição agora?" "s"; then
            linux_instalar_distro
        fi
        return 1
    fi

    local -a opcoes=()
    for ((i=0; i<${#LINUX_INSTALLED_DISTROS[@]}; i++)); do
        opcoes+=("$((i+1))|🐧|${LINUX_INSTALLED_DISTROS[$i]}|Distribuição instalada")
    done
    while true; do
        menu_unificado "$titulo" "$subtitulo" "[0] Voltar  •  [1–${#LINUX_INSTALLED_DISTROS[@]}] Selecionar" "${opcoes[@]}"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        [ "$escolha" = "0" ] && return 1
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#LINUX_INSTALLED_DISTROS[@]} ]; then
            LINUX_DISTRO_ALIAS="${LINUX_INSTALLED_DISTROS[$((escolha-1))]}"
            return 0
        fi
        feedback_curto "Opção inválida."
    done
}

linux_listar_distros() {
    linux_meus_linux
}

linux_pesquisar_imagem() {
    local termo escolha i saida
    if ! proot-distro help 2>/dev/null | grep -qE '(^|[[:space:]])search([[:space:]]|$)'; then
        cabecalho_tela "🔎 Pesquisar distribuição" "Recurso não disponível nesta versão do proot-distro"
        caixa_simples "Atualização necessária" \
            "Esta instalação do proot-distro não oferece pesquisa no Docker Hub." \
            "Use uma das distribuições recomendadas pelo Manager ou atualize o pacote."
        pause
        return 1
    fi
    ui_preparar_prompt
    printf 'Pesquisar no Docker Hub (ex.: ubuntu, debian, alpine): '
    IFS= read -r termo
    termo="${termo//$'\r'/}"
    termo="${termo#${termo%%[![:space:]]*}}"
    termo="${termo%${termo##*[![:space:]]}}"
    [[ "$termo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { warn "Pesquisa inválida."; sleep 1; return 1; }

    cabecalho_tela "🔎 Pesquisando imagens" "Docker Hub • $termo"
    caixa_simples "Aguarde" "Consultando opções disponíveis..." "Nenhuma instalação será iniciada sem sua confirmação."
    ui_buffer_flush 2>/dev/null || true
    saida="$(proot-distro search -q -l 8 "$termo" 2>>"$LINUX_LOG")" || {
        error "Não foi possível pesquisar imagens agora."
        pause
        return 1
    }
    LINUX_SEARCH_RESULTS=()
    while IFS= read -r linha; do
        linux_imagem_referencia_valida "$linha" && LINUX_SEARCH_RESULTS+=("$linha")
    done <<< "$saida"
    [ ${#LINUX_SEARCH_RESULTS[@]} -gt 0 ] || { warn "Nenhuma imagem encontrada para '$termo'."; pause; return 1; }

    local -a opcoes=()
    for ((i=0; i<${#LINUX_SEARCH_RESULTS[@]}; i++)); do
        opcoes+=("$((i+1))|📦|${LINUX_SEARCH_RESULTS[$i]}|Imagem pública encontrada no Docker Hub")
    done
    while true; do
        menu_unificado "🔎 Resultados" "Selecione uma imagem para instalar" "[0] Voltar  •  [1–${#LINUX_SEARCH_RESULTS[@]}] Selecionar" "${opcoes[@]}"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        [ "$escolha" = "0" ] && return 1
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#LINUX_SEARCH_RESULTS[@]} ]; then
            LINUX_DISTRO_IMAGE="${LINUX_SEARCH_RESULTS[$((escolha-1))]}"
            return 0
        fi
        feedback_curto "Opção inválida."
    done
}

linux_instalar_imagem() {
    local imagem="$1" nome_amigavel="${2:-$1}" arch_proot alias rc=0
    linux_imagem_referencia_valida "$imagem" || { error "Referência de imagem inválida: $imagem"; pause; return 1; }
    LINUX_DISTRO_IMAGE="$imagem"
    linux_mostrar_compatibilidade_imagem "$imagem" "$nome_amigavel" || return 0
    arch_proot="$(linux_proot_arquitetura_dispositivo "$(linux_arquitetura)" 2>/dev/null || true)"
    alias="$(linux_nome_container_imagem "$imagem")"
    cabecalho_tela "⬇️ Instalar distribuição" "$nome_amigavel"
    caixa_simples "Distribuição selecionada" \
        "Imagem: $imagem" \
        "Nome local: $alias" \
        "Arquitetura da instalação: ${arch_proot:-automática}" \
        "Fonte: Docker/OCI via proot-distro" \
        "A instalação pode consumir vários GB após atualizações e programas."
    confirmar_acao "Instalar '$nome_amigavel' agora?" || return 0

    mkdir -p "$(dirname "$LINUX_LOG")"
    cabecalho_tela "⬇️ Instalando $nome_amigavel" "Não feche o Termux durante download e extração"
    caixa_simples "Etapa atual" \
        "Arquitetura: ${arch_proot:-automática}" \
        "Baixando e extraindo a imagem..." \
        "Ao terminar, o Manager fará um teste real de inicialização."
    ui_buffer_flush 2>/dev/null || true

    if [ -n "$arch_proot" ] && proot-distro install --help 2>/dev/null | grep -q -- '--architecture'; then
        proot-distro install "$imagem" --architecture "$arch_proot" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    elif [ -n "$arch_proot" ]; then
        DISTRO_ARCH="$arch_proot" proot-distro install "$imagem" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    else
        proot-distro install "$imagem" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    fi

    if [ "$rc" -ne 0 ]; then
        error "A instalação de '$imagem' falhou."
        printf 'Log: %s\n' "$(caminho_curto "$LINUX_LOG")"
        pause
        return 1
    fi

    linux_log "distribuição instalada: $imagem arch=${arch_proot:-auto}"
    linux_invalidar_cache_distro "$alias"
    cabecalho_tela "🩺 Validando distribuição" "$alias"
    caixa_simples "Teste pós-instalação" \
        "A imagem foi extraída." \
        "Agora o Manager verificará /bin/sh e os dados do sistema." \
        "Uma distro quebrada não será marcada silenciosamente como pronta."
    ui_buffer_flush 2>/dev/null || true
    linux_coletar_info_distro "$alias" true
    if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
        caixa_simples "✅ Instalação validada" \
            "Sistema: $LINUX_INFO_NAME" \
            "Arquitetura: $LINUX_INFO_ARCH" \
            "Tamanho atual: $LINUX_INFO_SIZE" \
            "Saúde: OK" \
            "Abra 'Meus Linux' para iniciar, atualizar ou configurar o desktop."
    else
        caixa_simples "⚠ Instalação precisa de atenção" \
            "A distribuição foi criada, mas /bin/sh não conseguiu iniciar." \
            "Arquitetura solicitada: ${arch_proot:-automática}" \
            "Arquitetura registrada: $LINUX_INFO_ARCH" \
            "Use 'Meus Linux' > '$alias' > Reparar / reinstalar." \
            "O Manager mostrará esta distro como 'Problema'."
        linux_log "saúde pós-instalação falhou: $alias imagem=$imagem arch=$arch_proot"
    fi
    pause
}

linux_instalar_distro() {
    linux_garantir_proot_distro || { pause; return 1; }
    linux_avaliar_aparelho
    local escolha
    while true; do
        menu_unificado "⬇️ INSTALAR DISTRIBUIÇÃO" "${LINUX_PROFILE_ICON} ${LINUX_PROFILE} • CPU $(linux_arquitetura) • $(linux_formatar_gb_kb "$LINUX_FREE_KB") livres" \
            "[0] Voltar  •  [1–7] Selecionar" \
            "1|🐧|Ubuntu 24.04|Boa base para desktops gráficos • imagem ubuntu:24.04" \
            "2|🐧|Debian 12|Estável e versátil para desktop gráfico" \
            "3|🪶|Alpine 3.23|Muito leve • melhor para terminal e servidores" \
            "4|🎩|Fedora 44|Sistema moderno • consumo maior" \
            "5|🦎|openSUSE Leap 15|Alternativa estável" \
            "6|🪨|Rocky Linux 10|Base corporativa • uso principalmente terminal" \
            "7|🔎|Pesquisar outra imagem|Pesquisar no Docker Hub e escolher por número"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_instalar_imagem "ubuntu:24.04" "Ubuntu 24.04"; return ;;
            2) linux_instalar_imagem "debian:12" "Debian 12"; return ;;
            3) linux_instalar_imagem "alpine:3.23" "Alpine 3.23"; return ;;
            4) linux_instalar_imagem "fedora:44" "Fedora 44"; return ;;
            5) linux_instalar_imagem "opensuse/leap:15" "openSUSE Leap 15"; return ;;
            6) linux_instalar_imagem "rockylinux/rockylinux:10" "Rocky Linux 10"; return ;;
            7)
                if linux_pesquisar_imagem; then
                    linux_instalar_imagem "$LINUX_DISTRO_IMAGE" "$LINUX_DISTRO_IMAGE"
                    return
                fi
                ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

linux_abrir_terminal_distro() {
    local alias="${1:-}" escolha
    linux_garantir_proot_distro || { pause; return 1; }
    if [ -n "$alias" ]; then
        LINUX_DISTRO_ALIAS="$alias"
    else
        linux_selecionar_instalada "⌨️ Iniciar Linux" "Escolha uma distribuição" || return 0
    fi

    while true; do
        linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" false
        if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
            break
        fi
        menu_unificado "⚠ Linux com problema" \
            "$LINUX_DISTRO_ALIAS • ${LINUX_DIAG_REASON:-falha ao iniciar}" \
            "[0] Voltar  •  [1–3] Selecionar" \
            "1|🔎|Ver diagnóstico|Causa e detalhes técnicos" \
            "2|🧪|Testar novamente|Refazer o teste sem cache" \
            "3|🩺|Reparar / reinstalar|Recriar esta distribuição"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_exibir_diagnostico_distro "$LINUX_DISTRO_ALIAS" false ;;
            2)
                linux_invalidar_cache_distro "$LINUX_DISTRO_ALIAS"
                linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" true
                if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
                    ok "Teste concluído: distribuição saudável."
                    sleep 1
                    break
                fi
                feedback_curto "Ainda há problema: ${LINUX_DIAG_REASON:-inicialização}."
                ;;
            3) linux_resetar_distro "$LINUX_DISTRO_ALIAS" ;;
            0) return 1 ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done

    cabecalho_tela "⌨️ Iniciar Linux" "Abrindo $LINUX_DISTRO_ALIAS"
    caixa_simples "Sessão Linux" \
        "Distribuição: $LINUX_INFO_NAME" \
        "Alias: $LINUX_DISTRO_ALIAS" \
        "Use exit para voltar ao Manager."
    ui_buffer_flush 2>/dev/null || true
    sleep 0.3
    linux_log "iniciando terminal: $LINUX_DISTRO_ALIAS"
    if ! proot-distro login "$LINUX_DISTRO_ALIAS"; then
        linux_invalidar_cache_distro "$LINUX_DISTRO_ALIAS"
        error "Não foi possível iniciar '$LINUX_DISTRO_ALIAS'."
        pause
    fi
}

linux_remover_distro() {
    local alias="${1:-}"
    linux_garantir_proot_distro || { pause; return 1; }
    if [ -n "$alias" ]; then LINUX_DISTRO_ALIAS="$alias"; else linux_selecionar_instalada "🗑️ Remover distribuição" "Selecione o Linux que será apagado" || return 0; fi
    linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" false
    cabecalho_tela "🗑️ Remover distribuição" "Exclusão permanente"
    caixa_simples "⚠ Atenção" \
        "Distribuição: $LINUX_INFO_NAME ($LINUX_DISTRO_ALIAS)" \
        "Tamanho atual: $LINUX_INFO_SIZE" \
        "Todos os arquivos que existirem somente dentro dela serão apagados." \
        "Use Criar backup antes se houver dados importantes."
    confirmar_acao "Remover '$LINUX_DISTRO_ALIAS' permanentemente?" "n" || return 0
    confirmar_acao "Confirma a exclusão definitiva?" "n" || return 0

    if proot-distro remove "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG"; then
        linux_log "distribuição removida: $LINUX_DISTRO_ALIAS"
        linux_invalidar_cache_distro "$LINUX_DISTRO_ALIAS"
        ok "Distribuição removida."
    else
        error "Falha ao remover a distribuição."
    fi
    pause
}

linux_resetar_distro() {
    local alias="${1:-}" imagem arch rc=0
    linux_garantir_proot_distro || { pause; return 1; }
    if [ -n "$alias" ]; then LINUX_DISTRO_ALIAS="$alias"; else linux_selecionar_instalada "🩺 Reparar / reinstalar" "Escolha a distribuição a ser recriada" || return 0; fi
    imagem="$(linux_manifest_campo "$LINUX_DISTRO_ALIAS" image_ref 2>/dev/null || true)"
    arch="$(linux_proot_arquitetura_dispositivo "$(linux_arquitetura)" 2>/dev/null || true)"
    linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" false
    cabecalho_tela "🩺 Reparar / reinstalar" "Recriar na arquitetura deste Termux"
    caixa_simples "⚠ Reinstalação destrutiva" \
        "Distribuição: $LINUX_INFO_NAME ($LINUX_DISTRO_ALIAS)" \
        "Imagem: ${imagem:-não registrada}" \
        "Arquitetura correta: ${arch:-automática}" \
        "Todos os dados internos da distribuição serão perdidos." \
        "Crie um backup antes se houver arquivos importantes."
    confirmar_acao "Reinstalar '$LINUX_DISTRO_ALIAS'?" "n" || return 0

    if [ -n "$imagem" ] && linux_imagem_referencia_valida "$imagem"; then
        caixa_simples "Correção de arquitetura" \
            "A distro será removida e recriada da imagem original." \
            "A arquitetura será definida explicitamente para evitar Exec format error."
        proot-distro remove "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
        if [ "$rc" -eq 0 ]; then
            if [ -n "$arch" ] && proot-distro install --help 2>/dev/null | grep -q -- '--architecture'; then
                proot-distro install "$imagem" --name "$LINUX_DISTRO_ALIAS" --architecture "$arch" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
            elif [ -n "$arch" ]; then
                DISTRO_ARCH="$arch" proot-distro install --override-alias "$LINUX_DISTRO_ALIAS" "$imagem" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
            else
                proot-distro install "$imagem" --name "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
            fi
        fi
    else
        proot-distro reset "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    fi

    linux_invalidar_cache_distro "$LINUX_DISTRO_ALIAS"
    if [ "$rc" -eq 0 ]; then
        linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" true
        if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
            linux_log "distribuição reparada: $LINUX_DISTRO_ALIAS arch=${arch:-auto}"
            ok "Distribuição reinstalada e validada."
        else
            error "A reinstalação terminou, mas a distro ainda falhou no teste de saúde."
        fi
    else
        error "Falha ao reinstalar a distribuição."
    fi
    pause
}

linux_atualizar_distro() {
    local alias="${1:-}" gerenciador script rc=0
    [ -n "$alias" ] || return 1
    linux_coletar_info_distro "$alias" true
    if [ "$LINUX_INFO_HEALTH" != "ok" ]; then
        cabecalho_tela "⚠ Não é possível atualizar" "$alias"
        caixa_simples "Distribuição com problema" \
            "Motivo: ${LINUX_DIAG_REASON:-falha ao iniciar}" \
            "Código: ${LINUX_DIAG_CODE:-UNKNOWN}" \
            "Use Diagnóstico ou Reparar antes de atualizar."
        pause
        return 1
    fi
    gerenciador="$LINUX_INFO_PM"
    case "$gerenciador" in
        apt) script='export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get -y upgrade' ;;
        pacman) script='pacman -Syu --noconfirm' ;;
        apk) script='apk update && apk upgrade' ;;
        dnf) script='dnf -y upgrade' ;;
        zypper) script='zypper --non-interactive refresh && zypper --non-interactive update' ;;
        *)
            cabecalho_tela "🔄 Atualizar Linux" "$alias"
            caixa_simples "Gerenciador não reconhecido" "Não encontrei um gerenciador de pacotes suportado nesta distribuição."
            pause
            return 1
            ;;
    esac
    cabecalho_tela "🔄 Atualizar Linux" "$LINUX_INFO_NAME"
    caixa_simples "Atualização do sistema" \
        "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
        "Esta operação atualiza os pacotes dentro da distribuição." \
        "Ela não reinstala nem apaga seus arquivos."
    confirmar_acao "Atualizar '$alias' agora?" "s" || return 0
    ui_buffer_flush 2>/dev/null || true
    proot-distro login "$alias" -- /bin/sh -lc "$script" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    linux_invalidar_cache_distro "$alias"
    if [ "$rc" -eq 0 ]; then ok "Sistema atualizado."; else error "A atualização terminou com erro."; fi
    pause
}

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
    local arquivo="${1:-}" base alias
    [ -f "$arquivo" ] || return 1
    base="$(basename "$arquivo")"
    if [[ "$base" =~ ^TermuxManager-(.+)-[0-9]{8}-[0-9]{6}\.tar(\.xz|\.gz|\.bz2|\.lzma|\.zst)?$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi
    if command -v tar >/dev/null 2>&1; then
        alias="$(tar -tf "$arquivo" 2>/dev/null | awk -F/ 'NF && $1!="" && $1!="." && ($2=="rootfs" || $2=="manifest.json") {print $1; exit}')"
        [ -n "$alias" ] && { printf '%s\n' "$alias"; return 0; }
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

menu_linux_distro() {
    local alias="${1:-}" escolha
    [ -n "$alias" ] || return 1
    while true; do
        linux_coletar_info_distro "$alias" false
        menu_unificado "🐧 $LINUX_INFO_NAME" \
            "${LINUX_INFO_STATE_ICON} ${LINUX_INFO_STATE_LABEL} • ${LINUX_INFO_HEALTH_ICON} ${LINUX_INFO_HEALTH_LABEL} • $LINUX_INFO_SIZE" \
            "[0] Voltar  •  [1–9] Selecionar" \
            "1|⌨️|Iniciar terminal|Abrir no terminal" \
            "2|🖥️|Desktop / X11|Ambientes gráficos" \
            "3|🔄|Atualizar sistema|Atualizar pacotes" \
            "4|💾|Criar backup|Salvar em Downloads" \
            "5|🔎|Diagnóstico|Saúde e causa de falhas" \
            "6|ℹ️|Informações|Versão, arquitetura e tamanho" \
            "7|⏹️|Encerrar sessões|Ativas: $LINUX_INFO_SESSIONS" \
            "8|🩺|Reparar / reinstalar|Recriar a distro" \
            "9|🗑️|Remover distribuição|Excluir esta distro"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_abrir_terminal_distro "$alias" ;;
            2) linux_iniciar_desktop "$alias" ;;
            3) linux_atualizar_distro "$alias" ;;
            4) linux_backup_distro "$alias" ;;
            5) linux_exibir_diagnostico_distro "$alias" true ;;
            6) linux_exibir_info_distro "$alias" ;;
            7) linux_encerrar_sessoes_distro "$alias" ;;
            8) linux_resetar_distro "$alias" ;;
            9)
                linux_remover_distro "$alias"
                linux_coletar_instaladas || true
                printf '%s\n' "${LINUX_INSTALLED_DISTROS[@]}" | grep -Fxq "$alias" || return 0
                ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

linux_meus_linux() {
    local i escolha alias resumo estado saude tamanho arch desktops
    linux_garantir_proot_distro || { pause; return 1; }
    while true; do
        linux_coletar_instaladas || true
        if [ ${#LINUX_INSTALLED_DISTROS[@]} -eq 0 ]; then
            cabecalho_tela "🐧 Meus Linux" "Distribuições instaladas"
            caixa_simples "📭 Nenhuma distribuição instalada" \
                "Ainda não existe um Linux instalado neste aparelho." \
                "O Manager pode abrir a instalação agora."
            if confirmar_acao "Instalar uma distribuição agora?" "s"; then linux_instalar_distro; fi
            return 0
        fi

        local -a opcoes=()
        cabecalho_tela "🔎 Analisando distribuições" "Coletando tamanho, arquitetura e estado"
        printf '⏳ Verificando %d instalação(ões)...\n' "${#LINUX_INSTALLED_DISTROS[@]}"
        ui_buffer_flush 2>/dev/null || true
        for ((i=0; i<${#LINUX_INSTALLED_DISTROS[@]}; i++)); do
            alias="${LINUX_INSTALLED_DISTROS[$i]}"
            linux_coletar_info_distro "$alias" false
            resumo="${LINUX_INFO_STATE_ICON} ${LINUX_INFO_STATE_LABEL} • ${LINUX_INFO_HEALTH_ICON} ${LINUX_INFO_HEALTH_LABEL} • ${LINUX_INFO_SIZE} • ${LINUX_INFO_ARCH}"
            [ "$LINUX_INFO_DESKTOPS" != "nenhum" ] && resumo+=" • Desktop: $LINUX_INFO_DESKTOPS"
            opcoes+=("$((i+1))|🐧|$LINUX_INFO_NAME|$resumo")
        done
        menu_unificado "🐧 MEUS LINUX" "Escolha uma distribuição para administrar" \
            "[0] Voltar  •  [1–${#LINUX_INSTALLED_DISTROS[@]}] Abrir" "${opcoes[@]}"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        [ "$escolha" = "0" ] && return 0
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#LINUX_INSTALLED_DISTROS[@]} ]; then
            menu_linux_distro "${LINUX_INSTALLED_DISTROS[$((escolha-1))]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}


linux_x11_android_compativel() {
    local versao major
    versao="$(linux_android_versao)"
    major="${versao%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || return 0
    [ "$major" -ge 8 ]
}

linux_x11_apk_instalado() {
    command -v pm >/dev/null 2>&1 && pm path com.termux.x11 2>/dev/null | grep -q '^package:'
}

linux_x11_companion_instalado() {
    command -v termux-x11 >/dev/null 2>&1
}

linux_instalar_x11_companion() {
    cabecalho_tela "🖥️ Termux:X11" "Instalar componentes no Termux"
    if ! linux_x11_android_compativel; then
        caixa_simples "⚠ Android incompatível" \
            "O Termux:X11 requer Android 8 ou superior." \
            "Android detectado: $(linux_android_versao)"
        pause
        return 1
    fi
    if declare -F pacote_disponivel_termux >/dev/null 2>&1 && ! pacote_disponivel_termux x11-repo; then
        caixa_simples "⚠ x11-repo indisponível" \
            "O repositório gráfico não está disponível nos repositórios atuais do Termux." \
            "O Manager não tentará forçar uma instalação incompatível."
        pause
        return 1
    fi
    caixa_simples "Componentes" \
        "1. Repositório gráfico: x11-repo" \
        "2. Pacote companion: termux-x11-nightly" \
        "O aplicativo Android é instalado em uma etapa separada."
    confirmar_acao "Instalar componentes do Termux:X11?" "s" || return 0

    executar_pkg_monitorado "Preparando Termux:X11" 10 45 \
        "Habilitando repositório gráfico..." "Instalando x11-repo." -- install -y x11-repo || {
            mostrar_erro_pkg "Não foi possível instalar x11-repo."
            pause
            return 1
        }
    executar_pkg_monitorado "Preparando Termux:X11" 50 95 \
        "Instalando o companion do X11..." "Pacote termux-x11-nightly." -- install -y termux-x11-nightly || {
            mostrar_erro_pkg "Não foi possível instalar termux-x11-nightly."
            pause
            return 1
        }
    linux_log "Termux:X11 companion instalado"
    ok "Componentes do Termux:X11 instalados."
    pause
}

linux_baixar_x11_apk() {
    resolver_downloads_dir >/dev/null 2>&1 || true
    cabecalho_tela "📲 Aplicativo Termux:X11" "Baixar APK oficial nightly"
    caixa_simples "Origem" \
        "Projeto oficial: termux/termux-x11" \
        "Arquivo: $TERMUX_X11_APK_NAME" \
        "Destino: $(caminho_curto "$DOWNLOADS_DIR/$TERMUX_X11_APK_NAME")" \
        "O Android pedirá sua confirmação para instalar o APK."
    confirmar_acao "Baixar o APK oficial agora?" "s" || return 0

    if ! command -v curl >/dev/null 2>&1; then
        warn "curl não está instalado."
        confirmar_acao "Instalar curl agora?" "s" || return 1
        executar_pkg_monitorado "Instalando curl" 20 95 "Preparando download..." "Dependência necessária." -- install -y curl || return 1
    fi

    mkdir -p "$DOWNLOADS_DIR"
    local destino="$DOWNLOADS_DIR/$TERMUX_X11_APK_NAME" tmp="${DOWNLOADS_DIR}/.${TERMUX_X11_APK_NAME}.part"
    rm -f "$tmp"
    if curl -fL --retry 3 --connect-timeout 20 --max-time 600 \
        -o "$tmp" "$TERMUX_X11_APK_URL" 2>&1 | tee -a "$LINUX_LOG"; then
        mv -f "$tmp" "$destino"
        linux_log "APK Termux:X11 baixado: $destino"
        ok "APK salvo em $(caminho_curto "$destino")."
        caixa_simples "Instalação no Android" \
            "O Manager pode abrir o instalador, mas não confirma a tela do Android por você." \
            "Se o Android bloquear, permita 'Instalar apps desconhecidos' para o Termux."
        if command -v termux-open >/dev/null 2>&1; then
            confirmar_acao "Abrir o instalador do Android agora?" "s" && \
                termux-open --view --content-type application/vnd.android.package-archive "$destino" >/dev/null 2>&1 || true
        else
            warn "Abra o APK manualmente pelo gerenciador de arquivos em Downloads."
        fi
    else
        rm -f "$tmp"
        error "Falha ao baixar o APK do Termux:X11."
        printf 'Endereço usado: %s\n' "$TERMUX_X11_APK_URL"
    fi
    pause
}

linux_status_x11() {
    detectar_variante_termux 2>/dev/null || true
    cabecalho_tela "🖥️ Status Termux:X11" "Componentes necessários"
    caixa_simples "Termux:X11" \
        "Companion no Termux: $(linux_x11_companion_instalado && echo instalado || echo ausente)" \
        "Aplicativo Android: $(linux_x11_apk_instalado && echo instalado || echo não detectado)" \
        "Origem do Termux: $(termux_origem_resumida)" \
        "Android: $(linux_android_versao)"
    caixa_simples "Observação" \
        "O APK padrão funciona independentemente de sharedUid." \
        "O modo sharedUid só deve ser usado com builds compatíveis e assinaturas correspondentes." \
        "O Manager usa o APK padrão por segurança e compatibilidade."
    pause
}

linux_detectar_gerenciador_distro() {
    local alias="${1:-}"
    [ -n "$alias" ] || return 1
    mkdir -p "$(dirname "$LINUX_LOG")" 2>/dev/null || true
    proot-distro login "$alias" -- /bin/sh -lc '
if command -v apt-get >/dev/null 2>&1; then
  printf "apt\n"
elif command -v pacman >/dev/null 2>&1; then
  printf "pacman\n"
elif command -v apk >/dev/null 2>&1; then
  printf "apk\n"
elif command -v dnf >/dev/null 2>&1; then
  printf "dnf\n"
elif command -v zypper >/dev/null 2>&1; then
  printf "zypper\n"
else
  printf "desconhecido\n"
fi' 2>>"$LINUX_LOG" | tail -n 1
}

linux_descrever_gerenciador_distro() {
    case "${1:-desconhecido}" in
        apt) printf 'APT (Debian/Ubuntu)' ;;
        pacman) printf 'Pacman (Arch)' ;;
        apk) printf 'APK (Alpine)' ;;
        dnf) printf 'DNF (Fedora/Rocky)' ;;
        zypper) printf 'Zypper (openSUSE)' ;;
        *) printf 'Não reconhecido' ;;
    esac
}

linux_desktop_nome() {
    case "${1:-}" in
        xfce) printf 'XFCE' ;;
        lxqt) printf 'LXQt' ;;
        lxde) printf 'LXDE' ;;
        mate) printf 'MATE' ;;
        openbox) printf 'Openbox' ;;
        i3) printf 'i3' ;;
        kde) printf 'KDE Plasma' ;;
        gnome) printf 'GNOME' ;;
        *) printf '%s' "${1:-desconhecido}" ;;
    esac
}

linux_desktop_launcher() {
    case "${1:-}" in
        xfce) printf 'xfce4-session' ;;
        lxqt) printf 'startlxqt' ;;
        lxde) printf 'startlxde' ;;
        mate) printf 'mate-session' ;;
        openbox) printf 'openbox-session' ;;
        i3) printf 'i3' ;;
        kde) printf 'startplasma-x11' ;;
        gnome) printf 'gnome-session' ;;
        *) return 1 ;;
    esac
}

linux_desktop_peso() {
    case "${1:-}" in
        openbox|i3) printf 'muito leve' ;;
        lxde) printf 'muito leve' ;;
        xfce|lxqt) printf 'leve' ;;
        mate) printf 'médio' ;;
        kde) printf 'pesado' ;;
        gnome) printf 'muito pesado' ;;
        *) printf 'desconhecido' ;;
    esac
}

linux_desktop_descricao() {
    case "${1:-}" in
        xfce) printf 'Leve, completo e com ótima compatibilidade' ;;
        lxqt) printf 'Leve e com visual moderno' ;;
        lxde) printf 'Muito leve para aparelhos modestos' ;;
        mate) printf 'Desktop tradicional com consumo médio' ;;
        openbox) printf 'Janela mínima e extremamente leve' ;;
        i3) printf 'Tiling muito leve, focado em teclado' ;;
        kde) printf 'Visual avançado, exige mais RAM e CPU' ;;
        gnome) printf 'Completo, pesado e mais limitado em PRoot' ;;
        *) printf 'Ambiente gráfico' ;;
    esac
}

linux_desktop_recomendado_perfil() {
    local desktop="${1:-}" perfil="${2:-$LINUX_PROFILE}"
    case "$perfil:$desktop" in
        BÁSICO:lxde|BÁSICO:openbox|BÁSICO:i3) return 0 ;;
        INTERMEDIÁRIO:xfce|INTERMEDIÁRIO:lxqt) return 0 ;;
        DESKTOP:xfce|DESKTOP:lxqt|DESKTOP:mate) return 0 ;;
        *) return 1 ;;
    esac
}

linux_desktop_aviso_perfil() {
    local desktop="${1:-}" peso
    peso="$(linux_desktop_peso "$desktop")"
    if [ "$LINUX_PROFILE" = "BÁSICO" ] && [[ "$desktop" =~ ^(mate|kde|gnome)$ ]]; then
        printf '⚠ Muito pesado para o perfil BÁSICO; travamentos e encerramentos são prováveis.'
    elif [ "$LINUX_PROFILE" = "INTERMEDIÁRIO" ] && [[ "$desktop" =~ ^(kde|gnome)$ ]]; then
        printf '⚠ Pode consumir muita RAM/CPU neste aparelho; use apenas para testar.'
    elif [ "$desktop" = "gnome" ]; then
        printf '⚠ GNOME pode ter limitações extras em PRoot por depender de serviços do sistema.'
    elif [ "$desktop" = "kde" ]; then
        printf 'ℹ KDE Plasma é mais pesado que XFCE/LXQt e pode demorar mais para iniciar.'
    else
        printf 'Consumo estimado: %s.' "$peso"
    fi
}

linux_escolher_desktop() {
    local titulo="${1:-🖥️ Escolher ambiente gráfico}" subtitulo="${2:-Selecione o desktop}" rec=""
    linux_avaliar_aparelho
    local -a itens=()
    local id nome desc peso marcador
    for id in xfce lxqt lxde mate openbox i3 kde gnome; do
        nome="$(linux_desktop_nome "$id")"
        desc="$(linux_desktop_descricao "$id")"
        peso="$(linux_desktop_peso "$id")"
        marcador=""
        linux_desktop_recomendado_perfil "$id" && marcador=" • recomendado"
        itens+=("$(( ${#itens[@]} + 1 ))|🖥️|$nome|$desc • $peso$marcador")
    done
    menu_unificado "$titulo" "$subtitulo • perfil ${LINUX_PROFILE}" \
        "[0] Voltar  •  [1–8] Selecionar" "${itens[@]}"
    ler_opcao
    case "$RESPOSTA_MENU" in
        1) LINUX_DESKTOP_ID="xfce" ;;
        2) LINUX_DESKTOP_ID="lxqt" ;;
        3) LINUX_DESKTOP_ID="lxde" ;;
        4) LINUX_DESKTOP_ID="mate" ;;
        5) LINUX_DESKTOP_ID="openbox" ;;
        6) LINUX_DESKTOP_ID="i3" ;;
        7) LINUX_DESKTOP_ID="kde" ;;
        8) LINUX_DESKTOP_ID="gnome" ;;
        0) return 1 ;;
        *) warn "Opção inválida."; sleep 1; return 2 ;;
    esac
    LINUX_DESKTOP_NOME="$(linux_desktop_nome "$LINUX_DESKTOP_ID")"
    LINUX_DESKTOP_LAUNCHER="$(linux_desktop_launcher "$LINUX_DESKTOP_ID")"
    return 0
}

linux_desktop_instalado() {
    local alias="${1:-}" desktop="${2:-}" launcher
    [ -n "$alias" ] && [ -n "$desktop" ] || return 1
    launcher="$(linux_desktop_launcher "$desktop" 2>/dev/null)" || return 1
    mkdir -p "$(dirname "$LINUX_LOG")" 2>/dev/null || true
    proot-distro login "$alias" -- /bin/sh -lc "command -v '$launcher' >/dev/null 2>&1" \
        >>"$LINUX_LOG" 2>&1
}

linux_xfce_instalado() {
    linux_desktop_instalado "${1:-}" xfce
}

linux_desktops_instalados() {
    local alias="${1:-}" id
    [ -n "$alias" ] || return 1
    for id in xfce lxqt lxde mate openbox i3 kde gnome; do
        linux_desktop_instalado "$alias" "$id" && printf '%s\n' "$id"
    done
}

linux_desktops_instalados_resumo() {
    local alias="${1:-}" id nomes=""
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        nomes+="${nomes:+, }$(linux_desktop_nome "$id")"
    done < <(linux_desktops_instalados "$alias" 2>/dev/null || true)
    [ -n "$nomes" ] && printf '%s' "$nomes" || printf 'nenhum'
}

linux_desktop_guest_script() {
    local desktop="${1:-}" launcher
    launcher="$(linux_desktop_launcher "$desktop" 2>/dev/null)" || return 1
    cat <<EOF
set -e
DESKTOP_ID='$desktop'
LAUNCHER='$launcher'
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  case \"\$DESKTOP_ID\" in
    xfce) apt-get install -y xfce4 xfce4-terminal dbus-x11 ;;
    lxqt) apt-get install -y lxqt qterminal dbus-x11 || apt-get install -y lxqt-core qterminal dbus-x11 ;;
    lxde) apt-get install -y lxde-core lxterminal dbus-x11 || apt-get install -y lxde lxterminal dbus-x11 ;;
    mate) apt-get install -y mate-desktop-environment-core mate-terminal dbus-x11 || apt-get install -y mate-desktop-environment mate-terminal dbus-x11 ;;
    openbox) apt-get install -y openbox tint2 lxterminal dbus-x11 ;;
    i3) apt-get install -y i3-wm i3status dmenu xterm dbus-x11 || apt-get install -y i3 xterm dbus-x11 ;;
    kde) apt-get install -y plasma-desktop konsole dbus-x11 || apt-get install -y kde-plasma-desktop konsole dbus-x11 ;;
    gnome) apt-get install -y gnome-session gnome-shell gnome-terminal dbus-x11 ;;
  esac
elif command -v pacman >/dev/null 2>&1; then
  pacman -Sy --noconfirm
  case \"\$DESKTOP_ID\" in
    xfce) pacman -S --needed --noconfirm xfce4 xfce4-goodies dbus ;;
    lxqt) pacman -S --needed --noconfirm lxqt qterminal dbus ;;
    lxde) pacman -S --needed --noconfirm lxde lxterminal dbus ;;
    mate) pacman -S --needed --noconfirm mate mate-extra dbus ;;
    openbox) pacman -S --needed --noconfirm openbox tint2 xterm dbus ;;
    i3) pacman -S --needed --noconfirm i3-wm i3status dmenu xterm dbus ;;
    kde) pacman -S --needed --noconfirm plasma-desktop konsole dbus ;;
    gnome) pacman -S --needed --noconfirm gnome gnome-terminal dbus ;;
  esac
elif command -v apk >/dev/null 2>&1; then
  apk update
  case \"\$DESKTOP_ID\" in
    xfce) apk add xfce4 xfce4-terminal dbus ;;
    lxqt) apk add lxqt-desktop qterminal dbus || apk add lxqt qterminal dbus ;;
    lxde) apk add lxde lxterminal dbus ;;
    mate) apk add mate-desktop-environment mate-terminal dbus || apk add mate-desktop mate-session-manager mate-panel mate-terminal dbus ;;
    openbox) apk add openbox tint2 xterm dbus ;;
    i3) apk add i3wm i3status dmenu xterm dbus ;;
    kde) apk add plasma-desktop konsole dbus ;;
    gnome) apk add gnome-shell gnome-session gnome-terminal dbus ;;
  esac
elif command -v dnf >/dev/null 2>&1; then
  case \"\$DESKTOP_ID\" in
    xfce) dnf -y install @xfce-desktop-environment dbus-x11 || dnf -y group install \"Xfce Desktop\" || dnf -y install xfce4-session xfce4-panel xfce4-settings xfce4-terminal dbus-x11 ;;
    lxqt) dnf -y group install \"LXQt Desktop\" || dnf -y install lxqt-session lxqt-panel pcmanfm-qt qterminal dbus-x11 ;;
    lxde) dnf -y group install \"LXDE Desktop\" || dnf -y install lxde-common lxsession openbox lxterminal dbus-x11 ;;
    mate) dnf -y group install \"MATE Desktop\" || dnf -y install mate-session-manager mate-panel mate-terminal dbus-x11 ;;
    openbox) dnf -y install openbox tint2 xterm dbus-x11 ;;
    i3) dnf -y install i3 i3status dmenu xterm dbus-x11 ;;
    kde) dnf -y group install \"KDE Plasma Workspaces\" || dnf -y install plasma-workspace plasma-desktop konsole dbus-x11 ;;
    gnome) dnf -y group install \"GNOME Desktop Environment\" || dnf -y install gnome-session gnome-shell gnome-terminal dbus-x11 ;;
  esac
elif command -v zypper >/dev/null 2>&1; then
  zypper --non-interactive refresh
  case \"\$DESKTOP_ID\" in
    xfce) zypper --non-interactive install -t pattern xfce || zypper --non-interactive install xfce4-session xfce4-panel xfce4-settings xfce4-terminal dbus-1-x11 ;;
    lxqt) zypper --non-interactive install -t pattern lxqt || zypper --non-interactive install lxqt-session lxqt-panel pcmanfm-qt qterminal dbus-1-x11 ;;
    lxde) zypper --non-interactive install -t pattern lxde || zypper --non-interactive install lxsession openbox lxterminal dbus-1-x11 ;;
    mate) zypper --non-interactive install -t pattern mate || zypper --non-interactive install mate-session-manager mate-panel mate-terminal dbus-1-x11 ;;
    openbox) zypper --non-interactive install openbox tint2 xterm dbus-1-x11 ;;
    i3) zypper --non-interactive install i3 i3status dmenu xterm dbus-1-x11 ;;
    kde) zypper --non-interactive install -t pattern kde_plasma || zypper --non-interactive install plasma5-session plasma5-workspace konsole dbus-1-x11 ;;
    gnome) zypper --non-interactive install -t pattern gnome || zypper --non-interactive install gnome-session gnome-shell gnome-terminal dbus-1-x11 ;;
  esac
else
  echo \"Gerenciador de pacotes não reconhecido para instalação automática.\" >&2
  exit 65
fi
command -v \"\$LAUNCHER\" >/dev/null 2>&1
EOF
}

linux_instalar_desktop_na_distro() {
    local alias="${1:-}" desktop="${2:-}" gerenciador guest_script nome launcher aviso
    [ -n "$alias" ] && [ -n "$desktop" ] || return 1
    nome="$(linux_desktop_nome "$desktop")"
    launcher="$(linux_desktop_launcher "$desktop")"
    gerenciador="$(linux_detectar_gerenciador_distro "$alias" 2>/dev/null || printf 'desconhecido')"
    [ -n "$gerenciador" ] || gerenciador="desconhecido"

    if linux_desktop_instalado "$alias" "$desktop"; then
        cabecalho_tela "✅ $nome já instalado" "$alias"
        caixa_simples "Desktop encontrado" \
            "Distribuição: $alias" \
            "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
            "Inicializador: $launcher" \
            "Nenhuma reinstalação é necessária."
        linux_log "$nome já presente em $alias; reinstalação evitada"
        return 0
    fi

    if [ "$gerenciador" = "desconhecido" ]; then
        cabecalho_tela "⚠ Desktop não automatizado" "$alias"
        caixa_simples "Gerenciador não reconhecido" \
            "O Manager não encontrou apt, pacman, apk, dnf ou zypper nesta distribuição." \
            "A instalação automática foi interrompida para evitar comandos incompatíveis."
        linux_log "gerenciador de pacotes desconhecido em $alias"
        return 65
    fi

    linux_avaliar_aparelho
    aviso="$(linux_desktop_aviso_perfil "$desktop")"
    cabecalho_tela "🪟 Preparando $nome" "$alias"
    caixa_simples "Ambiente gráfico" \
        "Distribuição: $alias" \
        "Desktop: $nome" \
        "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
        "Perfil do aparelho: ${LINUX_PROFILE_ICON} ${LINUX_PROFILE}" \
        "$aviso"
    if [ "$desktop" = "gnome" ]; then
        caixa_simples "⚠ Compatibilidade GNOME" \
            "GNOME foi mantido como opção avançada." \
            "Algumas funções dependem de serviços do sistema que não existem em PRoot." \
            "Se houver problemas, prefira XFCE, LXQt ou MATE."
    fi
    confirmar_acao "Instalar $nome dentro de '$alias'?" || return 2

    guest_script="$(linux_desktop_guest_script "$desktop")" || return 1
    cabecalho_tela "🪟 Instalando $nome" "A instalação dentro do Linux pode ser demorada"
    caixa_simples "Instalação inteligente" \
        "Distribuição: $alias" \
        "Desktop: $nome" \
        "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
        "O Manager validará '$launcher' ao terminar." \
        "Não feche o Termux durante esta etapa."
    if proot-distro login "$alias" -- /bin/sh -lc "$guest_script" 2>&1 | tee -a "$LINUX_LOG"; then
        if linux_desktop_instalado "$alias" "$desktop"; then
            linux_log "$nome instalado e validado em $alias via $gerenciador"
            ok "$nome instalado e validado em '$alias'."
            return 0
        fi
        error "A instalação terminou, mas '$launcher' não foi encontrado."
        linux_log "instalação $nome terminou sem $launcher em $alias via $gerenciador"
        return 1
    fi

    error "Não foi possível instalar $nome automaticamente."
    caixa_simples "Compatibilidade" \
        "Gerenciador detectado: $(linux_descrever_gerenciador_distro "$gerenciador")" \
        "O pacote ou grupo pode ter outro nome nesta versão da distribuição." \
        "Consulte o log para ver qual pacote não foi encontrado." \
        "XFCE e LXQt são as opções com melhor cobertura automática."
    linux_log "falha ao instalar $nome em $alias via $gerenciador"
    return 1
}

linux_instalar_xfce_na_distro() {
    linux_instalar_desktop_na_distro "${1:-}" xfce
}

linux_instalar_ambiente_grafico() {
    linux_garantir_proot_distro || { pause; return 1; }
    linux_avaliar_aparelho
    cabecalho_tela "🪟 Instalar ambiente gráfico" "Escolha o desktop para a distribuição"
    caixa_simples "Perfil do aparelho" \
        "${LINUX_PROFILE_ICON} ${LINUX_PROFILE}" \
        "$LINUX_PROFILE_RECOMMEND" \
        "Você pode instalar mais de um ambiente na mesma distribuição."
    linux_selecionar_instalada "🪟 Instalar ambiente gráfico" "Escolha a distribuição" || return 0
    linux_escolher_desktop "🖥️ Escolher ambiente gráfico" "$LINUX_DISTRO_ALIAS" || return 0
    linux_instalar_desktop_na_distro "$LINUX_DISTRO_ALIAS" "$LINUX_DESKTOP_ID"
    local rc=$?
    [ "$rc" -eq 2 ] || pause
    return 0
}

linux_instalar_desktop_xfce() {
    linux_instalar_ambiente_grafico
}

linux_selecionar_desktop_instalado() {
    local alias="${1:-}" titulo="${2:-🖥️ Ambiente instalado}" id nome indice=0
    local -a ids=() itens=()
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        ids+=("$id")
        indice=$((indice + 1))
        nome="$(linux_desktop_nome "$id")"
        itens+=("$indice|🖥️|$nome|$(linux_desktop_descricao "$id")")
    done < <(linux_desktops_instalados "$alias" 2>/dev/null || true)
    [ ${#ids[@]} -gt 0 ] || return 1
    if [ ${#ids[@]} -eq 1 ]; then
        LINUX_DESKTOP_ID="${ids[0]}"
        LINUX_DESKTOP_NOME="$(linux_desktop_nome "$LINUX_DESKTOP_ID")"
        LINUX_DESKTOP_LAUNCHER="$(linux_desktop_launcher "$LINUX_DESKTOP_ID")"
        return 0
    fi
    menu_unificado "$titulo" "$alias • escolha qual iniciar" \
        "[0] Voltar  •  [1–${#ids[@]}] Selecionar" "${itens[@]}"
    ler_opcao
    [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] || return 2
    [ "$RESPOSTA_MENU" -eq 0 ] && return 2
    [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#ids[@]} ] || return 2
    LINUX_DESKTOP_ID="${ids[$((RESPOSTA_MENU - 1))]}"
    LINUX_DESKTOP_NOME="$(linux_desktop_nome "$LINUX_DESKTOP_ID")"
    LINUX_DESKTOP_LAUNCHER="$(linux_desktop_launcher "$LINUX_DESKTOP_ID")"
    return 0
}

linux_iniciar_desktop() {
    local alias_preselecionado="${1:-}"
    linux_garantir_proot_distro || { pause; return 1; }
    cabecalho_tela "🖥️ Iniciar desktop Linux" "Termux:X11 + ambiente gráfico"
    if ! linux_x11_companion_instalado; then
        warn "O companion termux-x11 não está instalado."
        caixa_simples "Como corrigir" "Abra Termux:X11 > Instalar componentes do X11."
        pause
        return 1
    fi
    if ! linux_x11_apk_instalado; then
        warn "O aplicativo Android Termux:X11 não foi detectado."
        caixa_simples "Como corrigir" "Baixe o APK oficial pelo menu Termux:X11 e conclua a instalação no Android."
        pause
        return 1
    fi

    if [ -n "$alias_preselecionado" ]; then
        LINUX_DISTRO_ALIAS="$alias_preselecionado"
    else
        linux_selecionar_instalada "🖥️ Iniciar desktop Linux" "Escolha a distribuição para o desktop" || return 0
    fi
    linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" false
    if [ "$LINUX_INFO_HEALTH" != "ok" ]; then
        cabecalho_tela "⚠ Desktop indisponível" "$LINUX_DISTRO_ALIAS"
        caixa_simples "Distribuição com problema"             "Motivo: ${LINUX_DIAG_REASON:-falha ao iniciar}"             "Use Diagnóstico ou Reparar antes do desktop."
        pause
        return 1
    fi
    local instalados
    instalados="$(linux_desktops_instalados_resumo "$LINUX_DISTRO_ALIAS")"
    if [ "$instalados" = "nenhum" ]; then
        local gerenciador
        gerenciador="$(linux_detectar_gerenciador_distro "$LINUX_DISTRO_ALIAS" 2>/dev/null || printf 'desconhecido')"
        cabecalho_tela "⚠ Nenhum desktop instalado" "$LINUX_DISTRO_ALIAS"
        caixa_simples "Ambiente gráfico ausente" \
            "Distribuição: $LINUX_DISTRO_ALIAS" \
            "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
            "Você pode escolher XFCE, LXQt, LXDE, MATE, Openbox, i3, KDE ou GNOME."
        if confirmar_acao "Escolher e instalar um ambiente agora?" "s"; then
            linux_escolher_desktop "🖥️ Escolher ambiente gráfico" "$LINUX_DISTRO_ALIAS" || return 0
            linux_instalar_desktop_na_distro "$LINUX_DISTRO_ALIAS" "$LINUX_DESKTOP_ID"
            local rc=$?
            if [ "$rc" -ne 0 ]; then
                [ "$rc" -eq 2 ] || pause
                return 0
            fi
        else
            return 0
        fi
    else
        linux_selecionar_desktop_instalado "$LINUX_DISTRO_ALIAS" "🖥️ Ambientes instalados" || return 0
    fi

    local desktop="$LINUX_DESKTOP_ID" nome="$LINUX_DESKTOP_NOME" launcher="$LINUX_DESKTOP_LAUNCHER"
    cabecalho_tela "🖥️ Iniciar desktop Linux" "Termux:X11 + $nome"
    caixa_simples "Sessão gráfica" \
        "Distribuição: $LINUX_DISTRO_ALIAS" \
        "Desktop: $nome" \
        "Inicializador: $launcher" \
        "Display: :1" \
        "O Manager compartilhará /tmp com a distribuição para o X11." \
        "Feche a sessão gráfica para retornar ao Manager."
    confirmar_acao "Iniciar $nome agora?" "s" || return 0

    pkill -f 'termux-x11 :1' 2>/dev/null || true
    XDG_RUNTIME_DIR="${TMPDIR:-$PREFIX/tmp}" termux-x11 :1 >/dev/null 2>&1 &
    sleep 1
    command -v am >/dev/null 2>&1 && am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
    linux_log "sessão X11 iniciada para $LINUX_DISTRO_ALIAS desktop=$desktop"

    local session_cmd
    session_cmd="export DISPLAY=:1; export XDG_RUNTIME_DIR=/tmp; if command -v dbus-launch >/dev/null 2>&1; then exec dbus-launch --exit-with-session '$launcher'; else exec '$launcher'; fi"
    if ! proot-distro login "$LINUX_DISTRO_ALIAS" --shared-tmp -- /bin/sh -lc "$session_cmd"; then
        error "A sessão gráfica terminou com erro."
        caixa_simples "Dicas" \
            "$nome foi verificado antes da abertura da sessão." \
            "Se aparecer tela preta, consulte Diagnóstico X11." \
            "Ambientes pesados como KDE/GNOME podem exigir mais memória."
        pause
    fi
}

linux_iniciar_xfce() {
    linux_iniciar_desktop
}

linux_parar_x11() {
    cabecalho_tela "⏹️ Parar sessão gráfica" "Encerrar servidor Termux:X11"
    pkill -f 'com.termux.x11' 2>/dev/null || true
    pkill -f 'termux-x11' 2>/dev/null || true
    command -v am >/dev/null 2>&1 && am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 >/dev/null 2>&1 || true
    linux_log "sessão X11 encerrada"
    ok "Solicitação de encerramento enviada ao Termux:X11."
    pause
}

linux_diagnostico_x11() {
    cabecalho_tela "🩺 Diagnóstico X11" "Orientações para problemas comuns"
    caixa_simples "Tela preta ou cursor apenas" \
        "Teste iniciar o servidor com: termux-x11 :1 -legacy-drawing" \
        "Alguns aparelhos precisam desse modo de desenho."
    caixa_simples "Cores trocadas" \
        "Teste: termux-x11 :1 -force-bgra"
    caixa_simples "Desktop lento" \
        "O Android pode limitar CPU quando o Termux fica em segundo plano." \
        "Mantenha o Termux ativo quando possível e use um desktop leve." \
        "O APK sharedUid pode reduzir esse problema, mas só é compatível com builds específicas do Termux."
    caixa_simples "PRoot + X11" \
        "O Manager inicia a distribuição com --shared-tmp." \
        "DISPLAY usado: :1"
    pause
}

menu_termux_x11() {
    while true; do
        local companion="ausente" app="ausente"
        linux_x11_companion_instalado && companion="instalado"
        linux_x11_apk_instalado && app="instalado"
        menu_unificado "🖥️ TERMUX:X11" "Interface gráfica para Linux" \
            "[0] Voltar  •  [1–7] Selecionar" \
            "1|📋|Status|Companion: $companion • App: $app" \
            "2|📦|Instalar componentes|x11-repo + termux-x11-nightly" \
            "3|📲|Baixar aplicativo Android|APK oficial nightly" \
            "4|🪟|Ambientes gráficos|XFCE, LXQt, LXDE, MATE, Openbox, i3, KDE e GNOME" \
            "5|▶️|Iniciar desktop|Escolher um ambiente instalado e abrir no X11" \
            "6|⏹️|Parar sessão gráfica|Encerrar servidor X11" \
            "7|🩺|Diagnóstico X11|Tela preta, cores e lentidão"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) linux_status_x11 ;;
            2) linux_instalar_x11_companion ;;
            3) linux_baixar_x11_apk ;;
            4) linux_instalar_ambiente_grafico ;;
            5) linux_iniciar_desktop ;;
            6) linux_parar_x11 ;;
            7) linux_diagnostico_x11 ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

menu_linux_celular() {
    while true; do
        linux_avaliar_aparelho
        local proot_status="ausente" x11_status="ausente" instaladas=0
        command -v proot-distro >/dev/null 2>&1 && proot_status="pronto"
        linux_x11_companion_instalado && x11_status="pronto"
        if command -v proot-distro >/dev/null 2>&1; then
            linux_coletar_instaladas || true
            instaladas=${#LINUX_INSTALLED_DISTROS[@]}
        fi
        menu_unificado "🐧 LINUX NO CELULAR" "PRoot sem root • perfil ${LINUX_PROFILE}" \
            "[0] Voltar  •  [1–7] Selecionar" \
            "1|🐧|Meus Linux|$instaladas instalada(s) • administrar" \
            "2|⬇️|Instalar novo Linux|Escolher uma distribuição" \
            "3|♻️|Restaurar backup|Buscar em Downloads" \
            "4|🖥️|Termux:X11|Desktops e interface gráfica" \
            "5|📱|Compatibilidade|RAM, CPU e espaço" \
            "6|🩺|Ambiente PRoot|Diagnosticar e reparar" \
            "7|ℹ️|Status do Linux|PRoot: $proot_status • X11: $x11_status"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) linux_meus_linux ;;
            2) linux_instalar_distro ;;
            3) linux_restaurar_backup ;;
            4) menu_termux_x11 ;;
            5) linux_mostrar_perfil ;;
            6) menu_ambiente_proot ;;
            7)
                cabecalho_tela "ℹ️ Linux no celular" "Estado dos componentes"
                caixa_simples "Status" \
                    "Perfil: ${LINUX_PROFILE_ICON} ${LINUX_PROFILE}" \
                    "Distribuições instaladas: $instaladas" \
                    "proot-distro: $proot_status" \
                    "Termux:X11 companion: $x11_status" \
                    "Termux:X11 Android: $(linux_x11_apk_instalado && echo instalado || echo não detectado)" \
                    "Log: $(caminho_curto "$LINUX_LOG")"
                pause
                ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

