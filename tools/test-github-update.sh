#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$ROOT_DIR/modules/updater.sh"
UPDATER_CORE="$ROOT_DIR/modules/updater_core.sh"
UPDATER_GITHUB="$ROOT_DIR/modules/updater_github.sh"
UPDATER_INSTALL="$ROOT_DIR/modules/updater_install.sh"
UPDATER_UI="$ROOT_DIR/modules/updater_ui.sh"
bash -n "$UPDATER" "$UPDATER_CORE" "$UPDATER_GITHUB" "$UPDATER_INSTALL" "$UPDATER_UI"

grep -Fq 'MANAGER_GITHUB_BRANCH="${TERMUX_MANAGER_GITHUB_BRANCH:-main}"' "$UPDATER_CORE"
grep -Fq 'Verificar no GitHub' "$UPDATER_UI"
grep -Fq 'MANAGER_GITHUB_ARCHIVE_URL' "$UPDATER_CORE"
grep -Fq 'validar_manifesto_pacote_manager' "$UPDATER_CORE"
grep -Fq 'GITHUB_REMOTE_CHANGELOG' "$UPDATER_CORE"
grep -Fq 'TIPO="${ATUALIZACAO_TIPO:-completa}"' "$UPDATER_INSTALL"
grep -Fq 'README.md CHANGELOG.md RELEASE_STANDARD.md MANIFEST.json' "$UPDATER_INSTALL"
grep -Fq 'github_fetch_to_file()' "$UPDATER_GITHUB"
grep -Fq 'Conectando ao GitHub...' "$UPDATER_GITHUB"
grep -Fq 'Carregando informações...' "$UPDATER_GITHUB"
grep -Fq 'Baixado:' "$UPDATER_GITHUB"
grep -Fq 'Isso não é travamento.' "$UPDATER_GITHUB"
grep -Fq 'sleep 0.20' "$UPDATER_GITHUB"
grep -Fq 'Abrindo conexão...' "$UPDATER_UI"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/MANIFEST.json" <<EOF
{
  "version": "9.9.9",
  "files": {}
}
EOF
cat > "$TMP/CHANGELOG.md" <<'EOF'
# Changelog

## [9.9.9] - 2099-01-01
- atualização de teste

## [1.0.0] - 2020-01-01
- antiga
EOF

(
    set -u
    MANAGER_VERSION="1.0.79"
    TERMUX_MANAGER_GITHUB_MANIFEST_URL="file://$TMP/MANIFEST.json"
    TERMUX_MANAGER_GITHUB_CHANGELOG_URL="file://$TMP/CHANGELOG.md"
    source "$UPDATER"
    consultar_atualizacao_github
    [ "$GITHUB_REMOTE_VERSION" = "9.9.9" ]
    [ "$GITHUB_UPDATE_STATE" = "new" ]
    printf '%s' "$GITHUB_REMOTE_CHANGELOG" | grep -Fq 'atualização de teste'
)

echo "OK: atualização pela main consulta versão e changelog corretamente."
