#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT_DIR/install.sh"
README="$ROOT_DIR/README.md"

bash -n "$INSTALLER"
grep -Fq 'api.github.com/repos/${REPOSITORY}/releases/latest' "$INSTALLER"
grep -Fq 'sha256sum' "$INSTALLER"
grep -Fq 'exec bash "$INSTALL_DIR/manager.sh" </dev/tty' "$INSTALLER"
grep -Fq 'raw.githubusercontent.com/adriedsonlemoz/TermuxManager/main/install.sh' "$README"

echo "OK: instalador automático e documentação estão consistentes."
