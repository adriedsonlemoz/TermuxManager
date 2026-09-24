# Módulo: linux.sh
# Linux no celular — proot-distro + Termux:X11

LINUX_STATE_DIR="$PAINEL_DIR/linux"
LINUX_LOG="$LOG_DIR/linux.log"
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

# Diagnósticos Linux/PRoot ficam em módulo separado.
# O source aqui mantém compatibilidade com chamadas que carregam apenas linux.sh.
LINUX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$LINUX_MODULE_DIR/linux_diagnostics.sh"

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


# Termux:X11 e desktops ficam em módulo separado.
# O carregamento aqui mantém compatibilidade com chamadas que usam apenas linux.sh.
# shellcheck source=/dev/null
source "$LINUX_MODULE_DIR/linux_x11.sh"

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

