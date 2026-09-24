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
grep -Fq 'Perfil estimado' "$LINUX"
grep -Fq 'pode apresentar travamentos' "$LINUX"
grep -Fq 'linux_docker_arquitetura_dispositivo' "$LINUX"
grep -Fq 'linux_verificar_compatibilidade_imagem' "$LINUX"
grep -Fq 'Compatibilidade: ${LINUX_ARCH_STATUS_LABEL}' "$LINUX"
grep -Fq 'Download evitado' "$LINUX"
grep -Fq 'linux_detectar_gerenciador_distro' "$LINUX"
grep -Fq 'linux_xfce_instalado' "$LINUX"
grep -Fq 'dnf -y install @xfce-desktop-environment' "$LINUX"
grep -Fq 'zypper --non-interactive install -t pattern xfce' "$LINUX"
grep -Fq 'XFCE já instalado' "$LINUX"
grep -Fq 'Instalar XFCE agora?' "$LINUX"
grep -Fq 'APT, Pacman, APK, DNF e Zypper são reconhecidos.' "$LINUX"

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

# Simula detecção do gerenciador da distro e presença/ausência do XFCE.
(
    set -u
    PAINEL_DIR="/tmp/painel-test-linux-xfce"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="/tmp"
    PREFIX="/tmp/prefix"
    source "$LINUX"

    SIM_XFCE="no"
    proot-distro() {
        local script="${!#}"
        if [[ "$script" == *'command -v apt-get'* ]]; then
            printf 'dnf\n'
            return 0
        fi
        if [[ "$script" == *'command -v xfce4-session'* ]]; then
            [ "$SIM_XFCE" = "yes" ]
            return
        fi
        return 0
    }

    [ "$(linux_detectar_gerenciador_distro teste)" = "dnf" ]
    [ "$(linux_descrever_gerenciador_distro dnf)" = "DNF (Fedora/Rocky)" ]
    ! linux_xfce_instalado teste
    SIM_XFCE="yes"
    linux_xfce_instalado teste
)

echo "OK: Linux no celular integra PRoot, Termux:X11, XFCE inteligente, diagnóstico, arquitetura e confirmações de segurança."
