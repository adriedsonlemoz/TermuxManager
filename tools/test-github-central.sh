#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PAINEL_DIR="$TMP/Painel"
HOME="$TMP/home"
mkdir -p "$PAINEL_DIR" "$HOME"
source "$ROOT/modules/projects.sh"
GITHUB_META_DIR="$PAINEL_DIR/.github-projects"
GITHUB_BRANCH_PADRAO="main"

[ "$(github_repo_slug_de_url 'https://github.com/exemplo/demo.git')" = 'exemplo/demo' ]
[ "$(github_repo_slug_de_url 'git@github.com:exemplo/demo.git')" = 'exemplo/demo' ]
[ "$(github_repo_slug_de_url 'ssh://git@github.com/exemplo/demo.git')" = 'exemplo/demo' ]

PROJ="$TMP/projeto"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
git -C "$PROJ" remote add origin https://github.com/exemplo/demo.git
github_meta_salvar "$PROJ" 'exemplo/demo' origin main
github_meta_carregar "$PROJ"
[ "$GITHUB_META_REPO" = 'exemplo/demo' ]
[ "$GITHUB_META_REMOTE" = origin ]
[ "$GITHUB_META_BRANCH" = main ]
github_validar_vinculo_push "$PROJ" origin

git -C "$PROJ" remote set-url origin https://github.com/outro/repositorio.git
if github_validar_vinculo_push "$PROJ" origin; then
    echo 'ERRO: vínculo divergente não foi bloqueado.' >&2
    exit 1
fi
[[ "$GITHUB_LAST_ERROR" == *"Proteção ativada"* ]]

grep -Fq 'menu_github_global()' "$ROOT/modules/projects_github_core.sh"
grep -Fq 'github_vincular_repo_existente()' "$ROOT/modules/projects_github_project.sh"
grep -Fq 'github_meus_repositorios()' "$ROOT/modules/projects_github_core.sh"
grep -Fq 'menu_branches_projeto()' "$ROOT/modules/projects_github_project.sh"
grep -Fq 'Configurar projeto' "$ROOT/modules/projects_git.sh"
grep -Fq '13|🐙|GitHub|Conta, identidade e repositórios' "$ROOT/modules/settings_maintenance.sh"
grep -Fq 'GITHUB_BRANCH_PADRAO' "$ROOT/modules/config.sh"

echo 'OK: Central GitHub global e vínculo seguro por projeto validados.'
