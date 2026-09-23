#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'cd /; rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/Painel/projetos/demo/sub" "$HOME/Painel/.logs"
export PAINEL_DIR="$HOME/Painel"
export PROJETOS_DIR="$PAINEL_DIR/projetos"
export LOG_DIR="$PAINEL_DIR/.logs"
export LOG_FILE="$LOG_DIR/manager.log"
: > "$LOG_FILE"
log(){ :; }
source "$ROOT/modules/core.sh"

# 1) CWD dentro do alvo precisa ser movido antes da exclusão.
cd "$PROJETOS_DIR/demo/sub"
garantir_cwd_fora_do_alvo "$PROJETOS_DIR/demo"
[ "$(pwd -P)" = "$HOME" ] || { echo "FAIL: CWD não foi movido para HOME"; exit 1; }
rm -rf "$PROJETOS_DIR/demo"
pwd -P >/dev/null

# 2) CWD já órfão deve ser recuperado.
mkdir -p "$TMP/orfao"
cd "$TMP/orfao"
rmdir "$TMP/orfao"
if pwd -P >/dev/null 2>&1; then
  echo "FAIL: teste não criou CWD órfão"; exit 1
fi
garantir_cwd_existente
[ "$(pwd -P)" = "$HOME" ] || { echo "FAIL: CWD órfão não recuperado"; exit 1; }

echo "OK: proteção de CWD passou"
