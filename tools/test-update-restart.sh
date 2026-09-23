#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/manager-update-test.XXXXXX")"
trap 'rm -rf "$TMP_BASE"' EXIT

INSTALL="$TMP_BASE/install"
PKG="$TMP_BASE/pkg"
HOME_TEST="$TMP_BASE/home"
PREFIX_TEST="$TMP_BASE/prefix"
mkdir -p "$INSTALL" "$PKG/modules" "$HOME_TEST/storage/downloads" "$PREFIX_TEST/bin" "$PREFIX_TEST/tmp"
cp -a "$ROOT_DIR/." "$INSTALL/"

cat > "$PKG/manager.sh" <<'SCRIPT'
#!/usr/bin/env bash
MANAGER_VERSION="9.9.9"
printf 'UPDATE_RESTART_VISIBLE version=%s\n' "$MANAGER_VERSION"
SCRIPT

for modulo in core.sh config.sh ui.sh import.sh projects.sh runtime.sh termux.sh updater.sh settings.sh help.sh app.sh; do
    printf ':\n' > "$PKG/modules/$modulo"
done
(
    cd "$PKG"
    zip -qr "$TMP_BASE/manager-v9.9.9.zip" .
)

cat > "$TMP_BASE/harness.sh" <<SCRIPT
#!/usr/bin/env bash
set -uo pipefail
export HOME=$(printf '%q' "$HOME_TEST")
export PREFIX=$(printf '%q' "$PREFIX_TEST")
export TMPDIR=$(printf '%q' "$PREFIX_TEST/tmp")
MANAGER_VERSION="test"
MANAGER_DEVELOPER="test"
MANAGER_REPOSITORY="test"
MANAGER_LICENSE="test"
MANAGER_CHANNEL="test"
FIRST_RUN_FILE="\$HOME/.manager_ready"
BASE_DIR=$(printf '%q' "$INSTALL")
MODULES_DIR="\$BASE_DIR/modules"
SELF_PATH="\$BASE_DIR/manager.sh"
MODULOS_OBRIGATORIOS=(core.sh config.sh ui.sh import.sh projects.sh runtime.sh termux.sh updater.sh settings.sh help.sh app.sh)
for modulo in "\${MODULOS_OBRIGATORIOS[@]}"; do source "\$MODULES_DIR/\$modulo"; done
LARGURA_CAIXA=48
ICONES_ATIVADOS=true
DESCRICOES_ATIVADAS=true
LIMPAR_TEMPORARIOS_AUTO=true
PAUSA_ERRO_SEGUNDOS=0
setup_dirs
adquirir_bloqueio
trap finalizar_manager EXIT
garantir_comando(){ return 0; }
sleep(){ :; }
instalar_pacote_manager $(printf '%q' "$TMP_BASE/manager-v9.9.9.zip") <<< \$'1\\n'
SCRIPT
chmod +x "$TMP_BASE/harness.sh"

bash "$TMP_BASE/harness.sh" > "$TMP_BASE/output.log" 2>&1 || true
if grep -q 'UPDATE_RESTART_VISIBLE version=9.9.9' "$TMP_BASE/output.log"; then
    printf 'OK: a nova versão reiniciou com saída visível.\n'
else
    printf 'FALHA: a saída do processo reiniciado não chegou ao terminal.\n' >&2
    tail -n 80 "$TMP_BASE/output.log" >&2
    exit 1
fi
