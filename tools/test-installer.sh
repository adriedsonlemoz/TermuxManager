#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/install.sh"
README="$ROOT_DIR/README.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash -n "$INSTALLER"
grep -Fq 'archive/refs/heads/${BRANCH}.zip' "$INSTALLER"
! grep -Fq 'releases/latest' "$INSTALLER"
grep -Fq 'MANIFEST.json' "$INSTALLER"
grep -Fq 'Manifesto validado' "$INSTALLER"
grep -Fq 'curl -fsSL https://raw.githubusercontent.com/adriedsonlemoz/TermuxManager/main/install.sh | bash' "$README"
! grep -Fq 'pkg install -y curl && curl -fsSL' "$README"
grep -Fq 'aguardar_pkg_livre' "$INSTALLER"
grep -Fq 'pids_pkg_ativos' "$INSTALLER"

mkdir -p "$TMP/fixture/TermuxManager-main" "$TMP/fakebin" "$TMP/home" "$TMP/prefix" "$TMP/tmp"
cp -a "$ROOT_DIR"/. "$TMP/fixture/TermuxManager-main/"
(
    cd "$TMP/fixture"
    zip -qr "$TMP/source.zip" TermuxManager-main
)
cat > "$TMP/fakebin/pkg" <<'PKG'
#!/usr/bin/env bash
exit 0
PKG
chmod +x "$TMP/fakebin/pkg"

PATH="$TMP/fakebin:$PATH" \
HOME="$TMP/home" \
PREFIX="$TMP/prefix" \
TMPDIR="$TMP/tmp" \
TERMUX_MANAGER_SOURCE_URL="file://$TMP/source.zip" \
TERMUX_MANAGER_INSTALL_DIR="$TMP/home/scripts/manager" \
TERMUX_MANAGER_BACKUP_ROOT="$TMP/home/backups" \
TERMUX_MANAGER_SKIP_LAUNCH=1 \
bash "$INSTALLER" >/dev/null

[ -f "$TMP/home/scripts/manager/manager.sh" ]
[ -f "$TMP/home/scripts/manager/MANIFEST.json" ]
grep -Fq 'MANAGER_VERSION="1.0.71"' "$TMP/home/scripts/manager/manager.sh"

echo "OK: instalador baixa a branch main, valida o manifesto e instala sem depender de GitHub Releases."
