#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX="$ROOT_DIR/modules/linux.sh"
APP="$ROOT_DIR/modules/app.sh"
MANAGER="$ROOT_DIR/manager.sh"

bash -n "$LINUX" "$APP" "$MANAGER"

grep -Fq 'linux.sh diagnostics.sh' "$MANAGER"
grep -Fq '4|🐧|Linux no celular|Distros, PRoot e Termux:X11' "$APP"
grep -Fq '4) menu_linux_celular ;;' "$APP"
grep -Fq 'menu_linux_celular()' "$LINUX"
grep -Fq 'proot-distro install "$imagem"' "$LINUX"
grep -Fq 'proot-distro login "$LINUX_DISTRO_ALIAS"' "$LINUX"
grep -Fq 'proot-distro remove "$LINUX_DISTRO_ALIAS"' "$LINUX"
grep -Fq 'proot-distro reset "$LINUX_DISTRO_ALIAS"' "$LINUX"
grep -Fq 'proot-distro list -q' "$LINUX"
grep -Fq 'ubuntu:24.04' "$LINUX"
grep -Fq 'debian:12' "$LINUX"
grep -Fq 'linux_selecionar_instalada' "$LINUX"
grep -Fq 'Você não precisa digitar alias manualmente.' "$LINUX"
grep -Fq 'proot-distro search -q -l 8' "$LINUX"
grep -Fq 'termux-x11-nightly' "$LINUX"
grep -Fq 'termux-x11-universal-debug.apk' "$LINUX"
grep -Fq -- '--shared-tmp' "$LINUX"
grep -Fq 'xfce4-session' "$LINUX"
grep -Fq 'startlxqt' "$LINUX"
grep -Fq 'startlxde' "$LINUX"
grep -Fq 'mate-session' "$LINUX"
grep -Fq 'openbox-session' "$LINUX"
grep -Fq 'startplasma-x11' "$LINUX"
grep -Fq 'gnome-session' "$LINUX"
grep -Fq 'Você pode instalar mais de um ambiente na mesma distribuição.' "$LINUX"
grep -Fq 'Perfil:' "$LINUX"
grep -Fq 'podem apresentar travamentos' "$LINUX"
grep -Fq 'linux_docker_arquitetura_dispositivo' "$LINUX"
grep -Fq 'linux_verificar_compatibilidade_imagem' "$LINUX"
grep -Fq 'Compatibilidade: ${LINUX_ARCH_STATUS_LABEL}' "$LINUX"
grep -Fq 'Download evitado' "$LINUX"
grep -Fq 'linux_detectar_gerenciador_distro' "$LINUX"
grep -Fq 'linux_xfce_instalado' "$LINUX"
grep -Fq 'dnf -y install @xfce-desktop-environment' "$LINUX"
grep -Fq 'zypper --non-interactive install -t pattern xfce' "$LINUX"
grep -Fq 'linux_desktop_instalado' "$LINUX"
grep -Fq 'Escolher e instalar um ambiente agora?' "$LINUX"
grep -Fq 'linux_instalar_ambiente_grafico' "$LINUX"

grep -Fq 'linux_meus_linux()' "$LINUX"
grep -Fq 'menu_linux_distro()' "$LINUX"
grep -Fq 'linux_atualizar_distro()' "$LINUX"
grep -Fq 'linux_backup_distro()' "$LINUX"
grep -Fq 'linux_restaurar_backup()' "$LINUX"
grep -Fq 'proot-distro restore "$arquivo"' "$LINUX"
grep -Fq 'Restaurar backup|Buscar em Downloads' "$LINUX"
grep -Fq 'linux_exibir_info_distro()' "$LINUX"
grep -Fq 'linux_distro_tamanho_kb()' "$LINUX"
grep -Fq 'linux_testar_saude_distro()' "$LINUX"
grep -Fq -- '--architecture "$arch_proot"' "$LINUX"
grep -Fq 'Teste pós-instalação' "$LINUX"
grep -Fq 'Exec format error' "$LINUX"
grep -Fq 'Meus Linux' "$LINUX"
grep -Fq 'Atualizar sistema' "$LINUX"
grep -Fq 'Criar backup' "$LINUX"
grep -Fq 'linux_exibir_diagnostico_distro()' "$LINUX"
grep -Fq 'ARCH_MISMATCH' "$LINUX"
grep -Fq 'QEMU_REQUIRED' "$LINUX"
grep -Fq 'LOADER_MISSING' "$LINUX"
grep -Fq 'linux_rotulo_curto_saude()' "$LINUX"
grep -Fq 'Testar novamente' "$LINUX"
grep -Fq 'linux_diagnosticar_ambiente_proot()' "$LINUX"
grep -Fq 'linux_reparar_ambiente_proot()' "$LINUX"
grep -Fq 'menu_ambiente_proot()' "$LINUX"
grep -Fq 'Ambiente PRoot|Diagnosticar e reparar' "$LINUX"
grep -Fq 'install -y --reinstall proot proot-distro' "$LINUX"
grep -Fq 'host_shell="${PREFIX:-}/bin/sh"' "$LINUX"
grep -Fq 'linux_traduzir_erro_proot()' "$LINUX"
grep -Fq 'linux_coletar_contexto_arquitetura()' "$LINUX"
grep -Fq 'PROOT_ENV_FAILURE' "$LINUX"
grep -Fq 'Erro original do PRoot — preservado' "$LINUX"

# Referências OCI atuais podem conter tag (:) e caminho (/).
(
    set -u
    PAINEL_DIR="/tmp/painel-test-linux-ref"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="/tmp"
    PREFIX="/tmp/prefix"
    source "$LINUX"
    linux_imagem_referencia_valida "ubuntu:24.04"
    linux_imagem_referencia_valida "opensuse/leap:15"
    ! linux_imagem_referencia_valida "imagem com espaço"
)

# Simula a classificação de um aparelho básico sem depender de Android/Termux real.
(
    set -u
    PAINEL_DIR="/tmp/painel-test-linux"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="/tmp"
    PREFIX="/tmp/prefix"
    source "$LINUX"
    linux_mem_total_kb() { printf '%s\n' $((2 * 1024 * 1024)); }
    linux_espaco_livre_kb() { printf '%s\n' $((4 * 1024 * 1024)); }
    linux_cpu_nucleos() { printf '8\n'; }
    linux_avaliar_aparelho
    [ "$LINUX_PROFILE" = "BÁSICO" ]
)

# Valida mapeamento da arquitetura e decisão de compatibilidade sem rede real.
(
    set -u
    PAINEL_DIR="/tmp/painel-test-linux-arch"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="/tmp"
    PREFIX="/tmp/prefix"
    source "$LINUX"

    [ "$(linux_docker_arquitetura_dispositivo aarch64)" = "arm64" ]
    [ "$(linux_docker_arquitetura_dispositivo arm)" = "arm" ]
    [ "$(linux_docker_arquitetura_dispositivo x86_64)" = "amd64" ]
    [ "$(linux_docker_arquitetura_dispositivo i686)" = "386" ]
    [ "$(linux_docker_arquitetura_dispositivo riscv64)" = "riscv64" ]
    [ "$(linux_dockerhub_ref_partes ubuntu:24.04)" = "library|ubuntu|24.04" ]
    [ "$(linux_dockerhub_ref_partes opensuse/leap:15)" = "opensuse|leap|15" ]

    linux_arquitetura() { printf 'aarch64\n'; }
    linux_consultar_arquiteturas_dockerhub() { LINUX_IMAGE_ARCHS="amd64,arm64"; return 0; }
    linux_verificar_compatibilidade_imagem "ubuntu:24.04"
    [ "$LINUX_ARCH_STATUS" = "compatible" ]
    [ "$LINUX_DEVICE_DOCKER_ARCH" = "arm64" ]

    linux_consultar_arquiteturas_dockerhub() { LINUX_IMAGE_ARCHS="amd64"; return 0; }
    linux_verificar_compatibilidade_imagem "ubuntu:24.04"
    [ "$LINUX_ARCH_STATUS" = "incompatible" ]

    linux_consultar_arquiteturas_dockerhub() { return 1; }
    linux_verificar_compatibilidade_imagem "ubuntu:24.04"
    [ "$LINUX_ARCH_STATUS" = "unknown" ]
)

# Simula detecção do gerenciador e múltiplos ambientes gráficos.
(
    set -u
    PAINEL_DIR="/tmp/painel-test-linux-desktops"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="/tmp"
    PREFIX="/tmp/prefix"
    source "$LINUX"

    SIM_COMMANDS="xfce4-session,startlxqt"
    proot-distro() {
        local script="${!#}"
        if [[ "$script" == *'command -v apt-get'* ]]; then
            printf 'dnf\n'
            return 0
        fi
        if [[ "$script" == *"command -v 'xfce4-session'"* ]]; then
            [[ ",$SIM_COMMANDS," == *",xfce4-session,"* ]]
            return
        fi
        if [[ "$script" == *"command -v 'startlxqt'"* ]]; then
            [[ ",$SIM_COMMANDS," == *",startlxqt,"* ]]
            return
        fi
        if [[ "$script" == *"command -v 'startlxde'"* ]] || \
           [[ "$script" == *"command -v 'mate-session'"* ]] || \
           [[ "$script" == *"command -v 'openbox-session'"* ]] || \
           [[ "$script" == *"command -v 'i3'"* ]] || \
           [[ "$script" == *"command -v 'startplasma-x11'"* ]] || \
           [[ "$script" == *"command -v 'gnome-session'"* ]]; then
            return 1
        fi
        return 0
    }

    [ "$(linux_detectar_gerenciador_distro teste)" = "dnf" ]
    [ "$(linux_descrever_gerenciador_distro dnf)" = "DNF (Fedora/Rocky)" ]
    [ "$(linux_desktop_launcher xfce)" = "xfce4-session" ]
    [ "$(linux_desktop_launcher lxqt)" = "startlxqt" ]
    [ "$(linux_desktop_launcher kde)" = "startplasma-x11" ]
    linux_desktop_instalado teste xfce
    linux_desktop_instalado teste lxqt
    ! linux_desktop_instalado teste mate
    [ "$(linux_desktops_instalados_resumo teste)" = "XFCE, LXQt" ]

    linux_mem_total_kb() { printf '%s\n' $((8 * 1024 * 1024)); }
    linux_espaco_livre_kb() { printf '%s\n' $((20 * 1024 * 1024)); }
    linux_cpu_nucleos() { printf '8\n'; }
    linux_avaliar_aparelho
    [ "$LINUX_PROFILE" = "DESKTOP" ]
    linux_desktop_recomendado_perfil xfce
    linux_desktop_recomendado_perfil mate
    ! linux_desktop_recomendado_perfil gnome

    script="$(linux_desktop_guest_script lxqt)"
    [[ "$script" == *'lxqt'* ]]
    [[ "$script" == *'qterminal'* ]]
)


# Simula uma distro instalada para validar identificação, tamanho, arquitetura,
# desktop, gerenciador, sessões e teste de saúde sem depender do Termux real.
(
    set -u
    TMPROOT="/tmp/painel-test-linux-distro-$$"
    trap 'rm -rf "$TMPROOT"' EXIT
    PAINEL_DIR="$TMPROOT/painel"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="$TMPROOT/home"
    PREFIX="$TMPROOT/prefix"
    TMPDIR="$TMPROOT/tmp"
    mkdir -p "$PREFIX/var/lib/proot-distro/containers/debian/rootfs/etc" \
             "$PREFIX/var/lib/proot-distro/containers/debian/rootfs/usr/bin" \
             "$TMPDIR"
    cat > "$PREFIX/var/lib/proot-distro/containers/debian/rootfs/etc/os-release" <<'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
VERSION_ID="12"
EOF
    cat > "$PREFIX/var/lib/proot-distro/containers/debian/manifest.json" <<'EOF'
{
  "image_ref": "debian:12",
  "arch": "arm"
}
EOF
    touch "$PREFIX/var/lib/proot-distro/containers/debian/rootfs/usr/bin/apt-get"
    touch "$PREFIX/var/lib/proot-distro/containers/debian/rootfs/usr/bin/xfce4-session"
    dd if=/dev/zero of="$PREFIX/var/lib/proot-distro/containers/debian/rootfs/sample.bin" bs=1024 count=4 status=none

    source "$LINUX"
    proot-distro() {
        case "${1:-}" in
            ps)
                printf 'PID CONTAINER TYPE USER UPTIME COMMAND\n'
                printf '123 debian login root 1m /bin/sh\n'
                ;;
            login)
                printf '__TM_HEALTH_OK__'
                ;;
            *) return 0 ;;
        esac
    }
    linux_coletar_info_distro debian true
    [ "$LINUX_INFO_NAME" = "Debian GNU/Linux 12 (bookworm)" ]
    [ "$LINUX_INFO_VERSION" = "12" ]
    [ "$LINUX_INFO_ARCH" = "arm" ]
    [ "$LINUX_INFO_IMAGE" = "debian:12" ]
    [ "$LINUX_INFO_PM" = "apt" ]
    [ "$LINUX_INFO_DESKTOPS" = "XFCE" ]
    [ "$LINUX_INFO_SESSIONS" = "1" ]
    [ "$LINUX_INFO_HEALTH" = "ok" ]
    [ "$LINUX_INFO_SIZE_KB" -gt 0 ]
)


# Simula uma falha Exec format para confirmar que a causa fica explicada.
(
    set -u
    TMPROOT="/tmp/painel-test-linux-diag-$$"
    trap 'rm -rf "$TMPROOT"' EXIT
    PAINEL_DIR="$TMPROOT/painel"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="$TMPROOT/home"
    PREFIX="$TMPROOT/prefix"
    TMPDIR="$TMPROOT/tmp"
    root="$PREFIX/var/lib/proot-distro/containers/alpine/rootfs"
    mkdir -p "$root/bin" "$TMPDIR"
    printf '#!/bin/sh\n' > "$root/bin/sh"
    chmod +x "$root/bin/sh"
    cat > "$PREFIX/var/lib/proot-distro/containers/alpine/manifest.json" <<'EOF'
{
  "image_ref": "alpine:3.23",
  "arch": "arm"
}
EOF
    source "$LINUX"
    linux_arquitetura() { printf 'arm\n'; }
    linux_arquitetura_binario() { printf 'arm\n'; }
    linux_loader_binario() { return 1; }
    proot-distro() {
        if [ "${1:-}" = login ]; then
            printf 'proot error: execve("/bin/sh"): Exec format error\n' >&2
            printf 'proot info: the program is a foreign binary but qemu was not specified\n' >&2
            return 1
        fi
        return 0
    }
    linux_testar_saude_distro alpine true
    [ "$LINUX_INFO_HEALTH" = problem ]
    [ "$LINUX_DIAG_CODE" = PROOT_ENV_FAILURE ]
    [ "$LINUX_DIAG_REASON" = 'Falha do ambiente PRoot' ]
)

# Distingue geração da CPU de ABI/bitness do Termux e traduz erros conhecidos.
(
    set -u
    PAINEL_DIR="/tmp/painel-test-linux-arch-context"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="/tmp"
    PREFIX="/tmp/prefix"
    source "$LINUX"
    linux_arquitetura() { printf 'arm\n'; }
    linux_bits_processo() { printf '32\n'; }
    linux_cpu_arm_geracao() { printf 'ARMv8\n'; }
    uname() { printf 'armv8l\n'; }
    getprop() {
        case "${1:-}" in
            ro.product.cpu.abi) printf 'armeabi-v7a\n' ;;
            ro.product.cpu.abilist) printf 'arm64-v8a,armeabi-v7a\n' ;;
            ro.product.cpu.abilist32) printf 'armeabi-v7a\n' ;;
            ro.product.cpu.abilist64) printf 'arm64-v8a\n' ;;
        esac
    }
    linux_coletar_contexto_arquitetura
    [ "$LINUX_ARCH_TERMUX" = arm ]
    [ "$LINUX_ARCH_BITS" = 32 ]
    [ "$LINUX_ARCH_CPU_GEN" = ARMv8 ]
    [ "$LINUX_ARCH_ANDROID_ABI" = armeabi-v7a ]
    [[ "$LINUX_ARCH_INTERPRETATION" == *'Termux atual executa em 32 bits'* ]]

    traduzido="$(linux_traduzir_erro_proot 'proot error: Exec format error; the program is a foreign binary but qemu was not specified; the loader was not found or does not work.')"
    [[ "$traduzido" == *'recusou o formato'* ]]
    [[ "$traduzido" == *'QEMU'* ]]
    [[ "$traduzido" == *'loader do sistema'* ]]
)

# Simula o diagnóstico do motor PRoot sem tocar em distribuições reais.
(
    set -u
    TMPROOT="/tmp/painel-test-proot-env-$$"
    trap 'rm -rf "$TMPROOT"' EXIT
    PAINEL_DIR="$TMPROOT/painel"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="$TMPROOT/home"
    PREFIX="$TMPROOT/prefix"
    TMPDIR="$PREFIX/tmp"
    mkdir -p "$PREFIX/bin" "$TMPDIR" "$LOG_DIR"
    printf '#!/bin/sh\nexit 0\n' > "$PREFIX/bin/sh"
    chmod +x "$PREFIX/bin/sh"
    source "$LINUX"
    dpkg-query() {
        case "${*: -1}" in
            proot) printf '5.1-test' ;;
            proot-distro) printf '4.0-test' ;;
            *) return 1 ;;
        esac
    }
    proot() {
        printf '__TM_PROOT_HOST_OK__'
    }
    proot-distro() { return 0; }
    timeout() { shift; "$@"; }
    linux_diagnosticar_ambiente_proot
    [ "$LINUX_PROOT_ENV_STATUS" = OK ]
    [ "$LINUX_PROOT_ENV_TMP_STATUS" = OK ]
    [ "$LINUX_PROOT_ENV_HOST_STATUS" = OK ]
    [ "$LINUX_PROOT_ENV_PROOT_VERSION" = '5.1-test' ]
)


# Valida descoberta de backups criados pelo Manager e leitura do alias.
(
    set -u
    TMPROOT="/tmp/painel-test-linux-restore-$$"
    trap 'rm -rf "$TMPROOT"' EXIT
    PAINEL_DIR="$TMPROOT/painel"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="$TMPROOT/home"
    PREFIX="$TMPROOT/prefix"
    DOWNLOADS_DIR="$TMPROOT/Downloads"
    mkdir -p "$DOWNLOADS_DIR" "$LOG_DIR"
    touch "$DOWNLOADS_DIR/TermuxManager-debian-20260924-120000.tar.xz"
    touch "$DOWNLOADS_DIR/arquivo-qualquer.tar"
    source "$LINUX"
    resolver_downloads_dir() { return 0; }
    [ "$(linux_backup_alias_arquivo "$DOWNLOADS_DIR/TermuxManager-debian-20260924-120000.tar.xz")" = debian ]
    linux_coletar_backups_downloads
    [ "${#LINUX_BACKUP_FILES[@]}" -eq 1 ]
    [ "${LINUX_BACKUP_FILES[0]}" = "$DOWNLOADS_DIR/TermuxManager-debian-20260924-120000.tar.xz" ]
)

echo "OK: Linux no celular integra diagnóstico explicativo, reparo do ambiente PRoot, restauração de backup, Meus Linux, tamanho, atualização, X11 e múltiplos desktops."
