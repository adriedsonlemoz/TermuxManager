#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(grep -m1 '^MANAGER_VERSION=' "$ROOT_DIR/manager.sh" | sed -E 's/.*"([^"]+)".*/\1/')"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Versão inválida: $VERSION"; exit 1; }
DIST="$ROOT_DIR/dist"
NAME="TermuxManager-v$VERSION"
rm -rf "$DIST/$NAME" "$DIST/$NAME.zip"
mkdir -p "$DIST/$NAME"
find "$ROOT_DIR" -mindepth 1 -maxdepth 1 \
  ! -name .git ! -name dist ! -name backups ! -name logs ! -name cache ! -name tmp ! -name .updates \
  -exec cp -a {} "$DIST/$NAME/" \
  \;
mkdir -p "$DIST/$NAME/.updates"
touch "$DIST/$NAME/.updates/.gitkeep"
(
  cd "$DIST/$NAME"
  zip -qr "../$NAME.zip" .
)
echo "Release criada (pacote único):"
echo "  $DIST/$NAME.zip"
printf 'SHA-256: '
sha256sum "$DIST/$NAME.zip" | awk '{print $1}' 
