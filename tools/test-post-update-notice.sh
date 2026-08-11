#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/manager-post-update-test.XXXXXX")"
cleanup(){ rm -rf "$TMP_BASE"; rm -f "$ROOT_DIR/.updates/last-update.conf" "$ROOT_DIR/.updates/last-update-shown"; }
trap cleanup EXIT

export HOME="$TMP_BASE/home"
export PREFIX="$TMP_BASE/prefix"
export TMPDIR="$TMP_BASE/tmp"
mkdir -p "$HOME" "$PREFIX/tmp" "$ROOT_DIR/.updates"

MANAGER_VERSION="$(grep -m1 '^MANAGER_VERSION=' "$ROOT_DIR/manager.sh" | sed -E 's/.*"([^"]+)".*/\1/')"
MANAGER_DEVELOPER="teste"
MANAGER_REPOSITORY="teste"
MANAGER_LICENSE="teste"
MANAGER_CHANNEL="teste"
BASE_DIR="$ROOT_DIR"
MODULES_DIR="$ROOT_DIR/modules"
SELF_PATH="$ROOT_DIR/manager.sh"
FIRST_RUN_FILE="$HOME/.manager_ready"

source "$MODULES_DIR/core.sh"
source "$MODULES_DIR/config.sh"
source "$MODULES_DIR/ui.sh"
source "$MODULES_DIR/import.sh"
source "$MODULES_DIR/updater.sh"
source "$MODULES_DIR/app.sh"

CORES_ATIVADAS=false
aplicar_cores
LARGURA_CAIXA=46
detectar_terminal(){ :; }
mkdir -p "$BASE_DIR/.updates"
cat > "$BASE_DIR/.updates/last-update.conf" <<CONF
DATA="06/08/2026 23:59:00"
TIPO="completa"
ARQUIVO="manager-v${MANAGER_VERSION}.zip"
VERSAO_ANTERIOR="1.0.45"
VERSAO_NOVA="${MANAGER_VERSION}"
BACKUP="manager_backup_teste.tar.gz"
STATUS="confirmada"
CONF
rm -f "$BASE_DIR/.updates/last-update-shown"

mostrar_confirmacao_pos_atualizacao <<< "" > "$TMP_BASE/first.log" 2>&1
grep -q "Manager ${MANAGER_VERSION} ativo" "$TMP_BASE/first.log"
test -s "$BASE_DIR/.updates/last-update-shown"

mostrar_confirmacao_pos_atualizacao > "$TMP_BASE/second.log" 2>&1
if grep -q "Atualização aplicada" "$TMP_BASE/second.log"; then
    echo "FALHA: o aviso foi exibido mais de uma vez." >&2
    exit 1
fi
echo "OK: confirmação pós-atualização exibida uma única vez."
