#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/Painel/.logs" "$HOME/Painel/.import_tmp/session_$$" "$HOME/.termux-manager/dependencies"
source "$ROOT/modules/core.sh"
source "$ROOT/modules/config.sh"
source "$ROOT/modules/ui.sh"
source "$ROOT/modules/import.sh"
source "$ROOT/modules/runtime.sh"
mkdir -p "$SESSION_TMP_DIR" "$LOG_DIR"
: > "$LOG_FILE"

old="$HOME/Painel/projetos/demo"
new="$TMP/new"
mkdir -p "$old/frontend/node_modules/foo" "$new/frontend"
printf '{"name":"demo","dependencies":{"foo":"1.0.0"}}\n' > "$old/frontend/package.json"
printf '{"name":"demo","dependencies":{"foo":"1.0.0"}}\n' > "$new/frontend/package.json"
printf 'preserve-me\n' > "$old/frontend/node_modules/foo/marker"

preservar_dependencias_substituicao "$new" "$old"
[ ! -d "$old/frontend/node_modules" ] || { echo 'node_modules não foi movido para cache' >&2; exit 1; }
rm -rf "$old"
mkdir -p "$old/frontend"
cp "$new/frontend/package.json" "$old/frontend/package.json"
restaurar_dependencias_substituicao "$old"
[ -f "$old/frontend/node_modules/foo/marker" ] || { echo 'node_modules não foi restaurado' >&2; exit 1; }

# Manifesto alterado: não deve preservar dependências antigas.
printf '{"name":"demo","dependencies":{"foo":"2.0.0"}}\n' > "$new/frontend/package.json"
preservar_dependencias_substituicao "$new" "$old"
[ -d "$old/frontend/node_modules" ] || { echo 'node_modules foi preservado com manifesto alterado' >&2; exit 1; }

echo 'OK: reimportação rápida preserva node_modules apenas quando dependências não mudam.'
