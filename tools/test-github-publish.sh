#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Carrega somente definições; as funções testadas não exigem o restante do Manager.
source "$ROOT/modules/projects.sh"

[ "$(normalizar_nome_repo_github 'Meu Projeto 2.0')" = "meu-projeto-2.0" ]
[ "$(normalizar_nome_repo_github '  API @ Principal  ')" = "api-principal" ]

PAINEL_DIR="$TMP/Painel"
mkdir -p "$PAINEL_DIR"
garantir_gitignore_seguro "$PAINEL_DIR"

grep -Fxq 'node_modules/' "$PAINEL_DIR/.gitignore"
grep -Fxq '.env' "$PAINEL_DIR/.gitignore"
grep -Fxq '.npmrc' "$PAINEL_DIR/.gitignore"
grep -Fxq '.logs/' "$PAINEL_DIR/.gitignore"
grep -Fxq 'projetos/' "$PAINEL_DIR/.gitignore"

# A seção gerenciada não pode ser duplicada em chamadas posteriores.
garantir_gitignore_seguro "$PAINEL_DIR"
[ "$(grep -Fc '# >>> Termux Manager: proteção de publicação >>>' "$PAINEL_DIR/.gitignore")" -eq 1 ]

# O menu e o despachante precisam expor a ação GitHub.
grep -Fq '|⬆️|Enviar para GitHub|' "$ROOT/modules/projects_git.sh"
grep -Fq 'enviar_projeto_github "$projeto"' "$ROOT/modules/projects_git.sh"


# Regressões da 1.0.60: log dedicado e identidade fora da preparação local.
grep -Fq 'GITHUB_LOG_FILE="$GITHUB_LOG_DIR/github.log"' "$ROOT/modules/projects_github_core.sh"
grep -Fq 'github_mostrar_falha' "$ROOT/modules/projects_github_core.sh"
prep=$(sed -n '/^preparar_repo_git_local()/,/^}/p' "$ROOT/modules/projects_github_project.sh")
if printf '%s\n' "$prep" | grep -Fq 'configurar_identidade_git_github'; then
    echo 'ERRO: identidade Git voltou a bloquear preparar_repo_git_local.' >&2
    exit 1
fi
grep -Fq 'configurar_identidade_git_github "$projeto"' "$ROOT/modules/projects_github_project.sh"

printf 'OK: fluxo básico de publicação GitHub validado.\n'
