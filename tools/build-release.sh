#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(grep -m1 '^MANAGER_VERSION=' "$ROOT_DIR/manager.sh" | sed -E 's/.*"([^"]+)".*/\1/')"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Versão inválida: $VERSION"; exit 1; }
DIST="$ROOT_DIR/dist"
NAME="manager-v$VERSION"
rm -rf "$DIST/$NAME" "$DIST/$NAME.zip" "$DIST/$NAME.sha256"
mkdir -p "$DIST/$NAME"
find "$ROOT_DIR" -mindepth 1 -maxdepth 1 \
  ! -name .git ! -name dist ! -name backups ! -name logs ! -name cache ! -name tmp \
  -exec cp -a {} "$DIST/$NAME/" \;
(
  cd "$DIST/$NAME"
  zip -qr "../$NAME.zip" .
)
(
  cd "$DIST"
  sha256sum "$NAME.zip" > "$NAME.sha256"
)
echo "Release criada:"
echo "  $DIST/$NAME.zip"
echo "  $DIST/$NAME.sha256"
