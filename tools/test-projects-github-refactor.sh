#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME="$TMP/home"
PAINEL_DIR="$HOME/Painel"
mkdir -p "$PAINEL_DIR"
source "$ROOT/modules/core.sh"
source "$ROOT/modules/projects.sh"
GITHUB_META_DIR="$PAINEL_DIR/.github-projects"
GITHUB_LOG_DIR="$HOME/.termux-manager/logs"
GITHUB_LOG_FILE="$GITHUB_LOG_DIR/github.log"

# O antigo arquivo grande virou apenas carregador dos três blocos coesos.
[ "$(wc -l < "$ROOT/modules/projects_github.sh")" -lt 40 ]
grep -Fq 'projects_github_core.sh' "$ROOT/modules/projects_github.sh"
grep -Fq 'projects_git.sh' "$ROOT/modules/projects_github.sh"
grep -Fq 'projects_github_project.sh' "$ROOT/modules/projects_github.sh"
declare -F menu_git_projeto >/dev/null
declare -F menu_github_global >/dev/null
declare -F enviar_projeto_github >/dev/null

# Regressão: quando origin é de outro provedor e GitHub usa outro remote,
# operações GitHub devem escolher o vínculo salvo, não origin.
PROJ="$TMP/multi-remote"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
git -C "$PROJ" remote add origin https://gitlab.com/exemplo/demo.git
git -C "$PROJ" remote add github https://github.com/exemplo/demo.git
github_meta_salvar "$PROJ" exemplo/demo github main
github_encontrar_remote_projeto "$PROJ"
[ "$GITHUB_REMOTE" = github ]
[ "$GITHUB_REMOTE_REPO" = exemplo/demo ]
[ "$GITHUB_REMOTE_URL" = https://github.com/exemplo/demo.git ]
projeto_git_status_resumido "$PROJ"
[ "$PROJ_GIT_REMOTE" = https://github.com/exemplo/demo.git ]

# Sem metadado, um origin não-GitHub nunca deve ser tratado como vínculo GitHub.
github_meta_remover "$PROJ"
git -C "$PROJ" remote remove github
github_encontrar_remote_projeto "$PROJ" && {
    echo 'ERRO: origin de outro provedor foi tratado como GitHub.' >&2
    exit 1
}

# O log GitHub reaproveita a sanitização global quando ela está disponível.
redigir_segredos() { sed -E 's/token=[^[:space:]]+/token=[REMOVIDO]/g'; }
github_log INFO teste 'token=segredo123 operação'
! grep -Fq 'segredo123' "$GITHUB_LOG_FILE"
grep -Fq 'token=[REMOVIDO]' "$GITHUB_LOG_FILE"

echo 'OK: refatoração Git/GitHub, seleção de remote e sanitização validadas.'
