#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/Painel/.tmp" "$HOME/.termux-manager/dependencies"
export SESSION_TMP_DIR="$HOME/Painel/.tmp"
export LOG_FILE="$HOME/manager.log"
export DEPENDENCY_STATE_DIR="$HOME/.termux-manager/dependencies"
export UI_LIVE_BOX_ACTIVE=false

# shellcheck disable=SC1090
source "$ROOT/modules/core.sh"
# shellcheck disable=SC1090
source "$ROOT/modules/config.sh"
# shellcheck disable=SC1090
source "$ROOT/modules/ui.sh"
# shellcheck disable=SC1090
source "$ROOT/modules/runtime.sh"

proj="$TMP/app"
mkdir -p "$proj/node_modules/foo"
cat > "$proj/package.json" <<'JSON'
{"name":"demo","version":"1.0.0","dependencies":{"foo":"1.0.0"}}
JSON
cat > "$proj/node_modules/foo/package.json" <<'JSON'
{"name":"foo","version":"1.0.0","main":"index.js"}
JSON
cat > "$proj/node_modules/foo/index.js" <<'JS'
module.exports = require('./util')
JS

# A árvore existe e o pacote direto está instalado, mas o arquivo interno falta.
if verificar_integridade_node_modules "$proj"; then
  echo "Integridade aceitou pacote internamente corrompido" >&2
  exit 1
fi

echo "module.exports = 123" > "$proj/node_modules/foo/util.js"
verificar_integridade_node_modules "$proj" || {
  echo "Integridade rejeitou instalação válida" >&2
  exit 1
}

logf="$TMP/backend.log"
printf '%s\n' "Error: Cannot find module './util'" "code: 'MODULE_NOT_FOUND'" > "$logf"
log_indica_dependencia_corrompida "$logf" || {
  echo "MODULE_NOT_FOUND não foi classificado como falha de dependência" >&2
  exit 1
}

echo "OK: integridade de dependências detecta corrupção interna e MODULE_NOT_FOUND"
