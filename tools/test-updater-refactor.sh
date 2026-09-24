#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$ROOT_DIR/modules/updater.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/manager-updater-refactor.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

bash -n "$UPDATER"
for modulo in updater_core.sh updater_github.sh updater_local.sh updater_install.sh updater_ui.sh; do
    test -f "$ROOT_DIR/modules/$modulo"
    bash -n "$ROOT_DIR/modules/$modulo"
    grep -Fq "$modulo" "$UPDATER"
done

error(){ LAST_ERROR="$*"; }
source "$UPDATER"
for funcao in \
    consultar_atualizacao_github validar_manifesto_pacote_manager verificar_atualizacao_github \
    listar_pacotes_completos listar_modulos_atualizacao instalar_pacote_manager \
    instalar_modulo_manager atualizar_manager_local; do
    declare -F "$funcao" >/dev/null
 done

PKG="$TMP/pkg"
mkdir -p "$PKG/modules"
printf '#!/usr/bin/env bash\nMANAGER_VERSION="9.9.9"\n' > "$PKG/manager.sh"
printf ':\n' > "$PKG/modules/core.sh"
printf ':\n' > "$PKG/modules/app.sh"

manifesto_valido(){
    local manager_hash core_hash app_hash
    manager_hash="$(sha256sum "$PKG/manager.sh" | awk '{print $1}')"
    core_hash="$(sha256sum "$PKG/modules/core.sh" | awk '{print $1}')"
    app_hash="$(sha256sum "$PKG/modules/app.sh" | awk '{print $1}')"
    cat > "$PKG/MANIFEST.json" <<JSON
{
  "version": "9.9.9",
  "files": {
    "manager.sh": "$manager_hash",
    "modules/app.sh": "$app_hash",
    "modules/core.sh": "$core_hash"
  }
}
JSON
}

manifesto_valido
LAST_ERROR=""
validar_manifesto_pacote_manager "$PKG"

manager_hash="$(sha256sum "$PKG/manager.sh" | awk '{print $1}')"
cat > "$PKG/MANIFEST.json" <<JSON
{
  "version": "9.9.9",
  "files": {
    "manager.sh": "$manager_hash"
  }
}
JSON
LAST_ERROR=""
if validar_manifesto_pacote_manager "$PKG"; then
    echo "FALHA: manifesto parcial foi aceito." >&2
    exit 1
fi
printf '%s' "$LAST_ERROR" | grep -Fq 'script sem hash declarado'

manifesto_valido
sed -i 's/"version": "9.9.9"/"version": "9.9.8"/' "$PKG/MANIFEST.json"
LAST_ERROR=""
if validar_manifesto_pacote_manager "$PKG"; then
    echo "FALHA: versão divergente entre manifesto e manager.sh foi aceita." >&2
    exit 1
fi
printf '%s' "$LAST_ERROR" | grep -Fq 'não corresponde ao manager.sh'

mkdir -p "$TMP/zip-src/sub"
printf 'fora\n' > "$TMP/zip-src/escape.sh"
(
    cd "$TMP/zip-src/sub"
    zip -q "$TMP/inseguro.zip" ../escape.sh
)
LAST_ERROR=""
if validar_zip_manager_seguro "$TMP/inseguro.zip"; then
    echo "FALHA: ZIP com travessia de diretório foi aceito." >&2
    exit 1
fi
printf '%s' "$LAST_ERROR" | grep -Fq 'caminho inseguro'

BASE_DIR="$TMP/install"
mkdir -p "$BASE_DIR/tools" "$TMP/new/tools"
printf 'antigo\n' > "$BASE_DIR/tools/obsoleto.sh"
printf 'novo\n' > "$TMP/new/tools/atual.sh"
updater_sincronizar_auxiliares "$TMP/new"
test -f "$BASE_DIR/tools/atual.sh"
test ! -e "$BASE_DIR/tools/obsoleto.sh"

echo "OK: updater modular, manifesto completo, ZIP seguro e sincronização sem arquivos obsoletos."
