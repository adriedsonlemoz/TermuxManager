#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HOME="$(mktemp -d)"
trap 'rm -rf "$HOME"' EXIT
mkdir -p "$HOME/Painel/backend" "$HOME/Painel/projetos/demo/backend" "$HOME/Painel/.logs" "$HOME/Painel/.pids"
LOG_DIR="$HOME/Painel/.logs"; PID_DIR="$HOME/Painel/.pids"; LOG_FILE="$HOME/manager.log"; SESSION_TMP_DIR="$HOME/tmp"
mkdir -p "$SESSION_TMP_DIR"
source "$ROOT/modules/core.sh"
source "$ROOT/modules/runtime.sh"
nome_processo_projeto "$HOME/Painel" backend; a="$NOME_PROCESSO"
nome_processo_projeto "$HOME/Painel/projetos/demo" backend; b="$NOME_PROCESSO"
[ "$a" != "$b" ] || { echo "IDs colidiram: $a"; exit 1; }
[[ "$a" == Painel_*_backend ]] || { echo "ID inesperado: $a"; exit 1; }
[[ "$b" == demo_*_backend ]] || { echo "ID inesperado: $b"; exit 1; }
echo "OK runtime isolation: $a != $b"
