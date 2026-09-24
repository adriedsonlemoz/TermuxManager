#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX="$ROOT_DIR/modules/linux.sh"
APP="$ROOT_DIR/modules/app.sh"
MANAGER="$ROOT_DIR/manager.sh"

bash -n "$LINUX" "$APP" "$MANAGER"

grep -Fq 'linux.sh diagnostics.sh' "$MANAGER"
grep -Fq '3|🐧|Linux no celular|Distribuições, PRoot e Termux:X11' "$APP"
grep -Fq '3) menu_linux_celular ;;' "$APP"
grep -Fq 'menu_linux_celular()' "$LINUX"
grep -Fq 'proot-distro install "$LINUX_DISTRO_ALIAS"' "$LINUX"
grep -Fq 'proot-distro login "$LINUX_DISTRO_ALIAS"' "$LINUX"
grep -Fq 'proot-distro remove "$LINUX_DISTRO_ALIAS"' "$LINUX"
grep -Fq 'proot-distro reset "$LINUX_DISTRO_ALIAS"' "$LINUX"
grep -Fq 'termux-x11-nightly' "$LINUX"
grep -Fq 'termux-x11-universal-debug.apk' "$LINUX"
grep -Fq -- '--shared-tmp' "$LINUX"
grep -Fq 'xfce4-session' "$LINUX"
grep -Fq 'Perfil estimado' "$LINUX"
grep -Fq 'pode apresentar travamentos' "$LINUX"
grep -Fq "Digite o alias '%s' novamente para confirmar" "$LINUX"

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

echo "OK: Linux no celular integra PRoot, Termux:X11, XFCE, diagnóstico e confirmações de segurança."
