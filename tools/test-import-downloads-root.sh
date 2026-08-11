#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
DOWNLOADS_DIR="$HOME/storage/downloads"
mkdir -p "$DOWNLOADS_DIR/projetos"
touch "$DOWNLOADS_DIR/projeto-novo.zip"
check_storage_access(){ return 0; }
source "$ROOT_DIR/modules/import.sh"
wizard_resetar_importacao
wizard_localizar_origem
[ "$WIZ_ORIGEM_BASE" = "$DOWNLOADS_DIR" ] || { echo "Origem não ficou na raiz de Downloads" >&2; exit 1; }
echo 'OK: importação inicia sempre na raiz de Downloads.'
