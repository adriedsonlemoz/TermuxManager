#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$ROOT_DIR/modules/updater.sh"
bash -n "$UPDATER"

grep -Fq 'MANAGER_GITHUB_BRANCH="${TERMUX_MANAGER_GITHUB_BRANCH:-main}"' "$UPDATER"
grep -Fq 'Verificar no GitHub' "$UPDATER"
grep -Fq 'MANAGER_GITHUB_ARCHIVE_URL' "$UPDATER"
grep -Fq 'validar_manifesto_pacote_manager' "$UPDATER"
grep -Fq 'GITHUB_REMOTE_CHANGELOG' "$UPDATER"
grep -Fq 'TIPO="${ATUALIZACAO_TIPO:-completa}"' "$UPDATER"
grep -Fq 'README.md CHANGELOG.md RELEASE_STANDARD.md MANIFEST.json' "$UPDATER"
grep -Fq 'github_fetch_to_file()' "$UPDATER"
grep -Fq 'Conectando ao GitHub...' "$UPDATER"
grep -Fq 'Carregando informações...' "$UPDATER"
grep -Fq 'Baixado:' "$UPDATER"
grep -Fq 'Isso não é travamento.' "$UPDATER"

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
    MANAGER_VERSION="1.0.78"
    TERMUX_MANAGER_GITHUB_MANIFEST_URL="file://$TMP/MANIFEST.json"
    TERMUX_MANAGER_GITHUB_CHANGELOG_URL="file://$TMP/CHANGELOG.md"
    source "$UPDATER"
    consultar_atualizacao_github
    [ "$GITHUB_REMOTE_VERSION" = "9.9.9" ]
    [ "$GITHUB_UPDATE_STATE" = "new" ]
    printf '%s' "$GITHUB_REMOTE_CHANGELOG" | grep -Fq 'atualização de teste'
)

echo "OK: atualização pela main consulta versão e changelog corretamente."
