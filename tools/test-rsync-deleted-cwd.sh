#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/source" "$TMP/dest" "$TMP/deleted"
printf 'ok\n' > "$TMP/source/file.txt"

# Simula exatamente a condição observada: processo permanece em uma pasta
# cujo nome é removido por outro processo antes do rsync iniciar.
(
  cd "$TMP/deleted"
  rmdir "$TMP/deleted"
  HOME="$TMP/home"
  (
    cd "${HOME:-/data/data/com.termux/files/home}" 2>/dev/null || cd / || exit 70
    rsync -a "$TMP/source/" "$TMP/dest/"
  )
)

test "$(cat "$TMP/dest/file.txt")" = "ok"
echo "PASS: rsync não depende de PWD removido"
