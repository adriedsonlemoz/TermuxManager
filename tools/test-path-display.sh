#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
source "$ROOT_DIR/modules/core.sh"
out="$(caminho_home_relativo "$HOME/Painel/.logs/backend.log")"
[ "$out" = "~/Painel/.logs/backend.log" ] || { echo "Falha: $out"; exit 1; }
out2="$(caminho_home_relativo "/tmp/arquivo.log")"
[ "$out2" = "/tmp/arquivo.log" ] || exit 1
printf 'OK: caminhos sob HOME são exibidos com ~\n'
