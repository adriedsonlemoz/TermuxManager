#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -nE 's/^MANAGER_VERSION="([^"]+)".*/\1/p' "$ROOT_DIR/manager.sh" | head -n1)"
[ -n "$VERSION" ]

grep -Fq "Versão $VERSION" "$ROOT_DIR/manager.sh"
grep -Fq "**Versão atual:** $VERSION" "$ROOT_DIR/README.md"
grep -Fq "Versão atual de referência: \`$VERSION\`." "$ROOT_DIR/RELEASE_STANDARD.md"
grep -Fq "\"version\": \"$VERSION\"" "$ROOT_DIR/MANIFEST.json"
grep -Fq "\"tag\": \"v$VERSION\"" "$ROOT_DIR/MANIFEST.json"
grep -Fq "\"asset\": \"TermuxManager-v$VERSION.zip\"" "$ROOT_DIR/MANIFEST.json"
grep -Fq "Pacote único: TermuxManager-v$VERSION.zip" "$ROOT_DIR/README.md"
grep -Fq "Pacote único: TermuxManager-v$VERSION.zip" "$ROOT_DIR/RELEASE_STANDARD.md"
grep -Fq 'NAME="TermuxManager-v$VERSION"' "$ROOT_DIR/tools/build-release.sh"
! grep -Fq 'manager-v1.0.70.sha256' "$ROOT_DIR/README.md"
! grep -Fq '"checksum":' "$ROOT_DIR/MANIFEST.json"

echo "OK: versão, documentação, manifesto e pacote único estão sincronizados em $VERSION."
