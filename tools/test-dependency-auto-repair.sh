#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/Painel/.logs" "$HOME/Painel/.tmp" "$HOME/.termux-manager/dependencies"
# shellcheck disable=SC1090
source "$ROOT/modules/core.sh"
# shellcheck disable=SC1090
source "$ROOT/modules/config.sh"
# shellcheck disable=SC1090
source "$ROOT/modules/ui.sh"
# shellcheck disable=SC1090
source "$ROOT/modules/runtime.sh"
mkdir -p "$LOG_DIR" "$SESSION_TMP_DIR" "$HOME/.termux-manager/dependencies"
: > "$LOG_FILE"
export UI_LIVE_BOX_ACTIVE=false

src="$TMP/foo-src"
proj="$TMP/app"
mkdir -p "$src" "$proj"
cat > "$src/package.json" <<'JSON'
{"name":"foo","version":"1.0.0","main":"index.js"}
JSON
cat > "$src/index.js" <<'JS'
module.exports = require('./util')
JS
cat > "$src/util.js" <<'JS'
module.exports = 42
JS
(cd "$src" && npm pack --silent >/dev/null)
tarball="$src/foo-1.0.0.tgz"
cat > "$proj/package.json" <<JSON
{"name":"demo","version":"1.0.0","dependencies":{"foo":"file:$tarball"}}
JSON
(cd "$proj" && npm install --silent >/dev/null 2>&1)
verificar_integridade_node_modules "$proj"
rm -f "$proj/node_modules/foo/util.js"
if verificar_integridade_node_modules "$proj"; then
  echo "Corrupção não foi detectada antes do reparo" >&2
  exit 1
fi
reparar_dependencias_corrompidas "$proj" npm
[ -f "$proj/node_modules/foo/util.js" ] || { echo "npm ci não restaurou o arquivo" >&2; exit 1; }
verificar_integridade_node_modules "$proj"
echo "OK: reparo automático recria node_modules corrompido usando lockfile"
