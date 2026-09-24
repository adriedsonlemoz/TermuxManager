#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/storage/downloads" "$HOME/Painel/.logs" "$HOME/Painel/.pids" "$HOME/Painel/backend" "$HOME/Painel/frontend"
MANAGER_VERSION="1.0.64"
SHELL="/bin/bash"
LIMPAR_TEMPORARIOS_AUTO=false
PAUSA_ERRO_SEGUNDOS=0
source "$ROOT_DIR/modules/core.sh"
source "$ROOT_DIR/modules/ui.sh"
source "$ROOT_DIR/modules/runtime.sh"
source "$ROOT_DIR/modules/diagnostics.sh"

cat > "$LOG_DIR/demo_backend.log" <<'LOG'
Backend starting
JWT_SECRET=supersecretvalue
Mongo: mongodb://user:pass@localhost:27017/demo
Error: demo failure
LOG
cat > "$LOG_DIR/demo_frontend.log" <<'LOG'
Vite ready
TOKEN=abcdef123456
LOG
cat > "$LOG_FILE" <<'LOG'
[INFO] manager line
PASSWORD=minhasenha
LOG
cat > "$PID_DIR/demo_backend.pid" <<EOF2
12345
EOF2
cat > "$PID_DIR/demo_backend.meta" <<EOF2
COMPONENT=backend
STATE=degraded
CMD=npm run dev
EXPECTED_PORT=3001
EOF2
cat > "$HOME/Painel/backend/.env" <<'EOF2'
JWT_SECRET=segredo-real
MONGO_URI=mongodb://u:p@host/db
SAFE_FLAG=true
EOF2

coletar_logs_teste_projeto "$HOME/Painel" "demo_frontend" "demo_backend" "backend indisponível"
[ -n "$ULTIMO_RELATORIO_TESTE" ]
[ -f "$ULTIMO_RELATORIO_TESTE" ]
grep -q 'LOG BACKEND' "$ULTIMO_RELATORIO_TESTE"
grep -q 'LOG FRONTEND' "$ULTIMO_RELATORIO_TESTE"
grep -q 'LOG DO MANAGER' "$ULTIMO_RELATORIO_TESTE"
grep -q 'Porta esperada: 3001' "$ULTIMO_RELATORIO_TESTE"
grep -q 'JWT_SECRET=\[REMOVIDO\]' "$ULTIMO_RELATORIO_TESTE"
! grep -q 'supersecretvalue\|minhasenha\|segredo-real\|user:pass' "$ULTIMO_RELATORIO_TESTE"
# Regressão visual: falha de servidor deve exibir caminho curto.
grep -q 'Consulte o log: $(caminho_home_relativo "$logf")' "$ROOT_DIR/modules/runtime_processes.sh"
# Toda saída antecipada do fluxo integrado deve passar pelo finalizador.
grep -q 'finalizar_painel_teste_falha' "$ROOT_DIR/modules/runtime_dependencies.sh"
printf 'OK: coleta de logs de teste e correções da tela validadas.\n'
