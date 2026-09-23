#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export HOME="$(mktemp -d)"
trap 'rm -rf "$HOME"' EXIT
source "$ROOT/modules/core.sh"
source "$ROOT/modules/runtime.sh"
LOG_DIR="$HOME/logs"; PID_DIR="$HOME/pids"; LOG_FILE="$HOME/manager.log"; SESSION_TMP_DIR="$HOME/tmp"
mkdir -p "$LOG_DIR" "$PID_DIR" "$SESSION_TMP_DIR"
printf 'ERRO ANTIGO\n' > "$LOG_DIR/a_backend.log"
printf 'FRONT ANTIGO\n' > "$LOG_DIR/a_frontend.log"
preparar_logs_nova_execucao_teste a_frontend a_backend
[ ! -s "$LOG_DIR/a_backend.log" ]
[ ! -s "$LOG_DIR/a_frontend.log" ]
find "$LOG_DIR" -type f ! -name 'a_backend.log' ! -name 'a_frontend.log' | grep -q .
echo "OK test log rotation"
