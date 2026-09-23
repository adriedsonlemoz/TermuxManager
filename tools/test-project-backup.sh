#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export LOG_FILE="$TMP/manager.log"
export TMP_ROOT="$TMP/private"
export SESSION_TMP_DIR="$TMP/private/session_test"
export DOWNLOADS_DIR="$TMP/Download"
mkdir -p "$SESSION_TMP_DIR" "$DOWNLOADS_DIR"

# Stubs mínimos para testar a rotina sem iniciar a interface.
resolver_downloads_dir() { return 0; }
info() { :; }
error() { printf 'ERROR: %s\n' "$*" >&2; }
ok() { :; }
log() { :; }
formatar_tamanho() { printf '%s B' "$1"; }
pause() { :; }
title() { :; }

# shellcheck source=/dev/null
source "$ROOT_DIR/modules/projects.sh"

PROJ="$TMP/origem/meu-projeto"
mkdir -p "$PROJ/src" "$PROJ/node_modules/pkg" "$PROJ/.git/objects" "$PROJ/dist" "$PROJ/.cache" "$PROJ/backend/vendor/lib"
printf 'console.log("ok")\n' > "$PROJ/src/app.js"
printf '{"name":"meu-projeto"}\n' > "$PROJ/package.json"
printf 'lock\n' > "$PROJ/package-lock.json"
printf 'dep\n' > "$PROJ/node_modules/pkg/index.js"
printf 'git\n' > "$PROJ/.git/HEAD"
printf 'build\n' > "$PROJ/dist/app.js"
printf 'cache\n' > "$PROJ/.cache/x"
printf 'vendor\n' > "$PROJ/backend/vendor/lib/x.php"

gerar_backup_publico_projeto "$PROJ" "meu-projeto"
BACKUP="$BACKUP_PROJETO_RESULTADO"
[ -f "$BACKUP" ] || { echo 'backup público ausente'; exit 1; }
case "$BACKUP" in "$DOWNLOADS_DIR/projetos/backups/"*) ;; *) echo "destino incorreto: $BACKUP"; exit 1;; esac

LISTA="$TMP/lista.txt"
tar -tzf "$BACKUP" > "$LISTA"
grep -q 'meu-projeto/src/app.js' "$LISTA"
grep -q 'meu-projeto/package.json' "$LISTA"
grep -q 'meu-projeto/package-lock.json' "$LISTA"
! grep -q '/node_modules/' "$LISTA"
! grep -q '/.git/' "$LISTA"
! grep -q '/dist/' "$LISTA"
! grep -q '/.cache/' "$LISTA"
! grep -q '/vendor/' "$LISTA"

# A cópia temporária deve ter sido removida após a verificação.
if find "$SESSION_TMP_DIR" -type f -name 'meu-projeto_*.tar.gz' | grep -q .; then
    echo 'backup temporário não foi removido'
    exit 1
fi

echo 'project-backup-ok'
