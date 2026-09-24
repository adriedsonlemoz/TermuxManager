#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
PAINEL_DIR="$HOME/Painel"
PROJETOS_DIR="$PAINEL_DIR/projetos"
LOG_DIR="$PAINEL_DIR/.logs"
PID_DIR="$PAINEL_DIR/.pids"
BACKUPS_DIR="$PAINEL_DIR/backups"
LOG_FILE="$LOG_DIR/manager.log"
mkdir -p "$PROJETOS_DIR/demo" "$LOG_DIR" "$PID_DIR" "$BACKUPS_DIR"
printf '{"scripts":{"dev":"vite"},"dependencies":{"vite":"latest"}}\n' > "$PROJETOS_DIR/demo/package.json"

# shellcheck source=/dev/null
source "$ROOT_DIR/modules/core.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/modules/runtime.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/modules/projects.sh"

comando_existe git || { echo 'SKIP: git ausente'; exit 0; }
git -C "$PROJETOS_DIR/demo" init -q
git -C "$PROJETOS_DIR/demo" config user.name Teste
git -C "$PROJETOS_DIR/demo" config user.email teste@example.com
git -C "$PROJETOS_DIR/demo" add package.json
git -C "$PROJETOS_DIR/demo" commit -qm inicial
branch="$(git -C "$PROJETOS_DIR/demo" symbolic-ref --short HEAD)"
projeto_git_status_resumido "$PROJETOS_DIR/demo"
[ "$PROJ_GIT_REPO" = true ]
[ "$PROJ_GIT_BRANCH" = "$branch" ]
[ "$PROJ_GIT_CHANGES" = 0 ]
[[ "$PROJ_GIT_LABEL" == *limpo* ]]
printf 'alterado\n' > "$PROJETOS_DIR/demo/novo.txt"
projeto_git_status_resumido "$PROJETOS_DIR/demo"
[ "$PROJ_GIT_CHANGES" -eq 1 ]
[[ "$PROJ_GIT_LABEL" == *'1 alt.'* ]]

grep -Fq 'menu_git_projeto()' "$ROOT_DIR/modules/projects.sh"
grep -Fq 'Atualizar do remoto' "$ROOT_DIR/modules/projects.sh"
grep -Fq 'merge --ff-only' "$ROOT_DIR/modules/projects.sh"
grep -Fq 'projeto_componentes_ativos()' "$ROOT_DIR/modules/projects.sh"
grep -Fq 'projeto_tamanho_resumido()' "$ROOT_DIR/modules/projects.sh"

echo 'OK: painel de projetos mostra Git, alterações, execução e atualização remota segura.'
