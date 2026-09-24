#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/modules/projects.sh"
GITHUB="$ROOT/modules/projects_github.sh"
GITHUB_PROJECT="$ROOT/modules/projects_github_project.sh"
STORAGE="$ROOT/modules/projects_storage.sh"

bash -n "$CORE" "$GITHUB" "$GITHUB_PROJECT" "$STORAGE"
[ -s "$GITHUB" ]
[ -s "$STORAGE" ]
grep -Fq 'source "$PROJECTS_MODULE_DIR/projects_github.sh"' "$CORE"
grep -Fq 'source "$PROJECTS_MODULE_DIR/projects_storage.sh"' "$CORE"
! grep -Fq 'enviar_projeto_github() {' "$CORE"
! grep -Fq 'criar_backup_projeto() {' "$CORE"
grep -Fq 'enviar_projeto_github() {' "$GITHUB_PROJECT"
grep -Fq 'criar_backup_projeto() {' "$STORAGE"
[ "$(wc -l < "$CORE")" -lt 700 ]

(
    set -u
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    export HOME="$TMP/home"
    PAINEL_DIR="$HOME/Painel"
    PROJETOS_DIR="$PAINEL_DIR/projetos"
    BACKUPS_DIR="$PAINEL_DIR/backups"
    LOG_DIR="$PAINEL_DIR/.logs"
    LOG_FILE="$LOG_DIR/manager.log"
    PID_DIR="$PAINEL_DIR/.pids"
    mkdir -p "$PROJETOS_DIR/demo" "$BACKUPS_DIR" "$LOG_DIR" "$PID_DIR"
    source "$CORE"
    declare -F enviar_projeto_github >/dev/null
    declare -F criar_backup_projeto >/dev/null
    declare -F projeto_caminho_exclusao_seguro >/dev/null
    projeto_caminho_exclusao_seguro "$PROJETOS_DIR/demo"
    rc=0; projeto_caminho_exclusao_seguro "$PAINEL_DIR" || rc=$?
    [ "$rc" -eq 2 ]
    rc=0; projeto_caminho_exclusao_seguro "$TMP/fora" || rc=$?
    [ "$rc" -eq 1 ]
)

# Uma falha ao instalar dependências não pode terminar com sucesso falso e
# o diretório atual deve ser restaurado mesmo quando instalar_dependencias usa cd.
(
    set -u
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    export HOME="$TMP/home"
    PAINEL_DIR="$HOME/Painel"; PROJETOS_DIR="$PAINEL_DIR/projetos"; BACKUPS_DIR="$PAINEL_DIR/backups"
    LOG_DIR="$PAINEL_DIR/.logs"; LOG_FILE="$LOG_DIR/manager.log"; PID_DIR="$PAINEL_DIR/.pids"
    mkdir -p "$PROJETOS_DIR/demo/front" "$LOG_DIR" "$PID_DIR" "$BACKUPS_DIR"
    source "$CORE"
    title(){ :; }; info(){ :; }; ok(){ :; }; error(){ :; }; pause(){ :; }
    detectar_estrutura_projeto(){ PROJ_MODO=simple; FRONT_DIR="$PROJETOS_DIR/demo/front"; FRONT_FRAMEWORK=Teste; FRONT_GERENCIADOR=npm; BACK_DIR=""; BACK_FRAMEWORK=""; BACK_GERENCIADOR=""; }
    instalar_dependencias(){ cd "$1"; return 1; }
    verificar_instalacao(){ return 0; }
    inicio="$(pwd -P)"
    if atualizar_dependencias_projeto "$PROJETOS_DIR/demo"; then
        echo 'ERRO: falha de dependências foi reportada como sucesso.' >&2
        exit 1
    fi
    [ "$(pwd -P)" = "$inicio" ]
)

echo "OK: projects.sh foi dividido em GitHub e armazenamento; exclusão e atualização de dependências ficaram protegidas."
