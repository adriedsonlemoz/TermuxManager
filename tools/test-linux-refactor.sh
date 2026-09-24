#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX="$ROOT_DIR/modules/linux.sh"
CORE="$ROOT_DIR/modules/linux_core.sh"
DISTROS="$ROOT_DIR/modules/linux_distros.sh"
BACKUP="$ROOT_DIR/modules/linux_backup.sh"
DIAG="$ROOT_DIR/modules/linux_diagnostics.sh"
X11="$ROOT_DIR/modules/linux_x11.sh"
UI="$ROOT_DIR/modules/linux_ui.sh"

bash -n "$LINUX" "$CORE" "$DISTROS" "$BACKUP" "$DIAG" "$X11" "$UI"
for f in "$CORE" "$DISTROS" "$BACKUP" "$DIAG" "$X11" "$UI"; do
    [ -s "$f" ]
done

grep -Fq 'linux_core.sh' "$LINUX"
grep -Fq 'linux_diagnostics.sh' "$LINUX"
grep -Fq 'linux_distros.sh' "$LINUX"
grep -Fq 'linux_backup.sh' "$LINUX"
grep -Fq 'linux_x11.sh' "$LINUX"
grep -Fq 'linux_ui.sh' "$LINUX"
! grep -Fq 'linux_exibir_diagnostico_distro() {' "$LINUX"
! grep -Fq 'linux_iniciar_desktop() {' "$LINUX"
! grep -Fq 'linux_instalar_distro() {' "$LINUX"
! grep -Fq 'linux_backup_distro() {' "$LINUX"
! grep -Fq 'menu_linux_celular() {' "$LINUX"
grep -Fq 'linux_exibir_diagnostico_distro() {' "$DIAG"
grep -Fq 'linux_iniciar_desktop() {' "$X11"
grep -Fq 'linux_instalar_distro() {' "$DISTROS"
grep -Fq 'linux_backup_distro() {' "$BACKUP"
grep -Fq 'menu_linux_celular() {' "$UI"
[ "$(wc -l < "$LINUX")" -lt 80 ]

(
    set -u
    PAINEL_DIR="/tmp/painel-test-linux-refactor"
    LOG_DIR="$PAINEL_DIR/.logs"
    HOME="/tmp"
    PREFIX="/tmp/prefix"
    source "$LINUX"
    declare -F linux_exibir_diagnostico_distro >/dev/null
    declare -F linux_iniciar_desktop >/dev/null
    declare -F linux_instalar_distro >/dev/null
    declare -F linux_backup_distro >/dev/null
    declare -F menu_linux_celular >/dev/null
)

echo "OK: linux.sh concluiu a refatoração em seis submódulos sem quebrar a API pública."
