#!/usr/bin/env bash
set -Euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'for pf in "$PID_DIR"/*.pid; do [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null || true; done; rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
source "$ROOT_DIR/modules/core.sh"
comando_existe(){ command -v "$1" >/dev/null 2>&1; }
info(){ :; }; warn(){ :; }; error(){ :; }; ok(){ :; }; log(){ :; }
MOSTRAR_LOG_FALHA=false; ABRIR_NAVEGADOR_AUTO=false; TEMPO_DETECTAR_PORTA=4
source "$ROOT_DIR/modules/runtime.sh"
mkdir -p "$LOG_DIR" "$PID_DIR" "$SESSION_TMP_DIR"

porta=$((20000 + RANDOM % 10000))
app="$HOME/healthy"; mkdir -p "$app"; printf 'PORT=%s\n' "$porta" > "$app/.env"
executar_em_background "$app" "python3 -m http.server $porta --bind 127.0.0.1" healthy_backend "$app" backend
for _ in {1..20}; do
    estado_servidor_processo healthy_backend >/dev/null 2>&1 || true
    [ "${ESTADO_PROCESSO:-}" = "servidor disponível" ] && break
    sleep 0.2
done
[ "${ESTADO_PROCESSO:-}" = "servidor disponível" ] && [ "${ICONE_PROCESSO:-}" = "🟢" ] && [ "${PORTA_PROCESSO:-}" = "$porta" ] || { echo 'Falha no estado saudável.'; exit 1; }
parar_processo healthy_backend >/dev/null 2>&1 || true

deadport=$((31000 + RANDOM % 10000)); app="$HOME/degraded"; mkdir -p "$app"; printf 'PORT=%s\n' "$deadport" > "$app/.env"
executar_em_background "$app" "bash -c 'echo \"Failed running src/server.js\"; while true; do sleep 60; done'" degraded_backend "$app" backend
for _ in {1..20}; do
    estado_servidor_processo degraded_backend >/dev/null 2>&1 || true
    [ "${ESTADO_PROCESSO:-}" = "processo ativo • servidor falhou" ] && break
    sleep 0.2
done
[ "${ESTADO_PROCESSO:-}" = "processo ativo • servidor falhou" ] && [ "${ICONE_PROCESSO:-}" = "🟡" ] || { echo 'Falha no estado degradado.'; exit 1; }
parar_processo degraded_backend >/dev/null 2>&1 || true

echo 'Teste de saúde de runtime concluído com sucesso.'
