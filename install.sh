#!/data/data/com.termux/files/usr/bin/bash
# Instalador oficial do Termux Manager.
# Uso recomendado:
#   pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/adriedsonlemoz/TermuxManager/main/install.sh | bash

set -Euo pipefail

REPOSITORY="adriedsonlemoz/TermuxManager"
API_URL="https://api.github.com/repos/${REPOSITORY}/releases/latest"
INSTALL_DIR="${HOME}/scripts/manager"
BACKUP_ROOT="${HOME}/.termux-manager/backups"
TMP_BASE="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
TMP_DIR=""

info() { printf '\n▶ %s\n' "$*"; }
ok()   { printf '✅ %s\n' "$*"; }
fail() { printf '❌ %s\n' "$*" >&2; exit 1; }

cleanup() {
    [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ] && rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT INT TERM

command -v pkg >/dev/null 2>&1 || fail "Este instalador deve ser executado dentro do Termux."
command -v curl >/dev/null 2>&1 || fail "curl não foi encontrado. Execute: pkg install -y curl"

necessarios=()
command -v unzip >/dev/null 2>&1 || necessarios+=(unzip)
command -v sha256sum >/dev/null 2>&1 || necessarios+=(coreutils)
if [ ${#necessarios[@]} -gt 0 ]; then
    info "Preparando ferramentas necessárias"
    pkg install -y "${necessarios[@]}" || fail "Não foi possível instalar as ferramentas necessárias."
fi

mkdir -p "$TMP_BASE"
TMP_DIR="$(mktemp -d "$TMP_BASE/termux-manager-install.XXXXXX")" || fail "Não foi possível criar a pasta temporária."

info "Consultando a versão mais recente"
release_json="$(curl -fsSL --retry 3 --connect-timeout 20 "$API_URL")" || fail "Não foi possível consultar as releases no GitHub."
zip_url="$(printf '%s\n' "$release_json" | grep -oE 'https://[^" ]+/manager-v[0-9]+\.[0-9]+\.[0-9]+\.zip' | head -n 1 || true)"
[ -n "$zip_url" ] || fail "A release mais recente não contém manager-vX.Y.Z.zip."

zip_name="${zip_url##*/}"
sha_name="${zip_name%.zip}.sha256"
sha_url="${zip_url%.zip}.sha256"
zip_path="$TMP_DIR/$zip_name"
sha_path="$TMP_DIR/$sha_name"
stage_dir="$TMP_DIR/stage"

info "Baixando $zip_name"
curl -fL --retry 3 --connect-timeout 20 -o "$zip_path" "$zip_url" || fail "Falha ao baixar o pacote da release."
curl -fL --retry 3 --connect-timeout 20 -o "$sha_path" "$sha_url" || fail "Falha ao baixar o checksum da release."

info "Verificando integridade"
expected="$(awk 'NR==1 {print $1}' "$sha_path")"
actual="$(sha256sum "$zip_path" | awk '{print $1}')"
[[ "$expected" =~ ^[0-9A-Fa-f]{64}$ ]] || fail "Checksum publicado em formato inválido."
[ "${expected,,}" = "${actual,,}" ] || fail "O SHA-256 do pacote não confere. Instalação cancelada."
ok "SHA-256 confirmado"

mkdir -p "$stage_dir"
unzip -q "$zip_path" -d "$stage_dir" || fail "Não foi possível extrair o pacote."
[ -f "$stage_dir/manager.sh" ] || fail "Pacote inválido: manager.sh não encontrado."
[ -d "$stage_dir/modules" ] || fail "Pacote inválido: pasta modules não encontrada."

bash -n "$stage_dir/manager.sh" || fail "manager.sh contém erro de sintaxe."
for module in "$stage_dir"/modules/*.sh; do
    [ -f "$module" ] || continue
    bash -n "$module" || fail "Erro de sintaxe em ${module##*/}."
done

package_version="${zip_name#manager-v}"
package_version="${package_version%.zip}"
internal_version="$(sed -nE 's/^MANAGER_VERSION="([^"]+)".*/\1/p' "$stage_dir/manager.sh" | head -n 1)"
[ -n "$internal_version" ] || fail "Não foi possível identificar a versão interna."
[ "$package_version" = "$internal_version" ] || fail "Versão do pacote ($package_version) difere da versão interna ($internal_version)."

info "Instalando Termux Manager $internal_version"
mkdir -p "$(dirname "$INSTALL_DIR")"
new_dir="${INSTALL_DIR}.new.$$"
old_dir="${INSTALL_DIR}.old.$$"
rm -rf -- "$new_dir" "$old_dir"
cp -a "$stage_dir" "$new_dir" || fail "Não foi possível preparar a nova instalação."

backup_dir=""
if [ -e "$INSTALL_DIR" ]; then
    mkdir -p "$BACKUP_ROOT"
    backup_dir="$BACKUP_ROOT/installer-$(date +%Y%m%d-%H%M%S)"
    cp -a "$INSTALL_DIR" "$backup_dir" || fail "Não foi possível criar o backup da instalação atual."
    mv "$INSTALL_DIR" "$old_dir" || fail "Não foi possível preparar a substituição da instalação atual."
fi

if ! mv "$new_dir" "$INSTALL_DIR"; then
    [ -e "$old_dir" ] && mv "$old_dir" "$INSTALL_DIR" 2>/dev/null || true
    fail "Não foi possível concluir a instalação. A instalação anterior foi preservada quando possível."
fi
rm -rf -- "$old_dir"

ok "Termux Manager $internal_version instalado em ~/scripts/manager"
[ -n "$backup_dir" ] && printf 'Backup anterior: %s\n' "$backup_dir"

info "Abrindo o Termux Manager"
if [ -r /dev/tty ]; then
    exec bash "$INSTALL_DIR/manager.sh" </dev/tty
else
    exec bash "$INSTALL_DIR/manager.sh"
fi
