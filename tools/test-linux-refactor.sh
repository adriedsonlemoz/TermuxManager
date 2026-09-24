#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX="$ROOT_DIR/modules/linux.sh"
DIAG="$ROOT_DIR/modules/linux_diagnostics.sh"
X11="$ROOT_DIR/modules/linux_x11.sh"

bash -n "$LINUX" "$DIAG" "$X11"
[ -s "$DIAG" ]
[ -s "$X11" ]
grep -Fq 'source "$LINUX_MODULE_DIR/linux_diagnostics.sh"' "$LINUX"
grep -Fq 'source "$LINUX_MODULE_DIR/linux_x11.sh"' "$LINUX"
! grep -Fq 'linux_exibir_diagnostico_distro() {' "$LINUX"
! grep -Fq 'linux_iniciar_desktop() {' "$LINUX"
grep -Fq 'linux_exibir_diagnostico_distro() {' "$DIAG"
grep -Fq 'linux_iniciar_desktop() {' "$X11"
[ "$(wc -l < "$LINUX")" -lt 1600 ]

(
    set -u
    PAINEL_DIR="/tmp/painel-test-linux-refactor"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="/tmp"
    PREFIX="/tmp/prefix"
    source "$LINUX"
    declare -F linux_exibir_diagnostico_distro >/dev/null
    declare -F linux_iniciar_desktop >/dev/null
    declare -F menu_linux_celular >/dev/null
)

echo "OK: linux.sh foi dividido em submódulos de diagnóstico e X11 sem quebrar a API pública."
