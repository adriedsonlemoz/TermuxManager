#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT/modules/settings.sh"
FISH="$ROOT/modules/settings_fish.sh"
SHORTCUTS="$ROOT/modules/settings_shortcuts.sh"
MAINT="$ROOT/modules/settings_maintenance.sh"

bash -n "$CORE" "$FISH" "$SHORTCUTS" "$MAINT"
for file in "$FISH" "$SHORTCUTS" "$MAINT"; do [ -s "$file" ]; done
[ "$(wc -l < "$CORE")" -lt 180 ]
grep -Fq 'settings_fish.sh settings_shortcuts.sh settings_maintenance.sh' "$CORE"
grep -Fq 'menu_config_fish() {' "$FISH"
grep -Fq 'menu_atalhos_manager() {' "$SHORTCUTS"
grep -Fq 'menu_configuracoes() {' "$MAINT"
! grep -Fq 'menu_config_fish() {' "$CORE"
! grep -Fq 'menu_atalhos_manager() {' "$CORE"

# A API pública continua disponível apenas carregando settings.sh.
(
    set -u
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    export HOME="$TMP/home"
    mkdir -p "$HOME"
    PAINEL_DIR="$HOME/Painel"; PROJETOS_DIR="$PAINEL_DIR/projetos"; BACKUPS_DIR="$PAINEL_DIR/backups"
    LOG_DIR="$PAINEL_DIR/.logs"; LOG_FILE="$LOG_DIR/manager.log"; PID_DIR="$PAINEL_DIR/.pids"
    TMP_ROOT="$PAINEL_DIR/.tmp"; SESSION_TMP_DIR="$TMP_ROOT/session_$$"
    BASE_DIR="$TMP/manager"; PREFIX="$TMP/prefix"; CONFIG_FILE="$TMP/config"; FIRST_RUN_FILE="$TMP/ready"; FIRST_RUN_STATE_FILE="$TMP/state"
    mkdir -p "$BASE_DIR" "$PREFIX/bin" "$PROJETOS_DIR" "$BACKUPS_DIR" "$LOG_DIR" "$PID_DIR" "$SESSION_TMP_DIR"
    source "$CORE"
    declare -F menu_configuracoes >/dev/null
    declare -F menu_config_fish >/dev/null
    declare -F menu_atalhos_manager >/dev/null
    declare -F excluir_painel_inteiro >/dev/null
)

# Regressão: Fish deve usar o instalador robusto central quando disponível,
# em vez de abrir um caminho paralelo de pkg/apt.
(
    set -u
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    export HOME="$TMP/home"
    mkdir -p "$HOME" "$TMP/bin"
    PATH="$TMP/bin:$PATH"
    PAINEL_DIR="$HOME/Painel"; PROJETOS_DIR="$PAINEL_DIR/projetos"; BACKUPS_DIR="$PAINEL_DIR/backups"
    LOG_DIR="$PAINEL_DIR/.logs"; LOG_FILE="$LOG_DIR/manager.log"; PID_DIR="$PAINEL_DIR/.pids"
    TMP_ROOT="$PAINEL_DIR/.tmp"; SESSION_TMP_DIR="$TMP_ROOT/session_$$"
    BASE_DIR="$TMP/manager"; PREFIX="$TMP/prefix"; CONFIG_FILE="$TMP/config"; FIRST_RUN_FILE="$TMP/ready"; FIRST_RUN_STATE_FILE="$TMP/state"
    mkdir -p "$BASE_DIR" "$PREFIX/bin" "$PROJETOS_DIR" "$BACKUPS_DIR" "$LOG_DIR" "$PID_DIR" "$SESSION_TMP_DIR"
    source "$CORE"
    cabecalho_tela(){ :; }; ok(){ :; }; error(){ :; }; info(){ :; }
    instalar_lista_pacotes(){
        printf '%s|%s\n' "$1" "$2" > "$TMP/installer.called"
        cat > "$TMP/bin/fish" <<'SH'
#!/usr/bin/env bash
exit 0
SH
        chmod +x "$TMP/bin/fish"
        return 0
    }
    instalar_fish_shell
    grep -Fxq 'Fish Shell|fish' "$TMP/installer.called"
)

# Proteção destrutiva: o Painel não pode ser apagado quando contém a própria
# instalação do Manager.
(
    set -u
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    export HOME="$TMP/home"
    PAINEL_DIR="$HOME/Painel"; PROJETOS_DIR="$PAINEL_DIR/projetos"; BACKUPS_DIR="$PAINEL_DIR/backups"
    LOG_DIR="$PAINEL_DIR/.logs"; LOG_FILE="$LOG_DIR/manager.log"; PID_DIR="$PAINEL_DIR/.pids"
    TMP_ROOT="$PAINEL_DIR/.tmp"; SESSION_TMP_DIR="$TMP_ROOT/session_$$"
    BASE_DIR="$PAINEL_DIR/manager"; PREFIX="$TMP/prefix"; CONFIG_FILE="$TMP/config"; FIRST_RUN_FILE="$TMP/ready"; FIRST_RUN_STATE_FILE="$TMP/state"
    mkdir -p "$BASE_DIR" "$PROJETOS_DIR" "$BACKUPS_DIR" "$LOG_DIR" "$PID_DIR" "$SESSION_TMP_DIR"
    touch "$BASE_DIR/protegido"
    source "$CORE"
    title(){ :; }; error(){ :; }; info(){ :; }; pause(){ :; }
    rc=0; excluir_painel_inteiro >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 1 ]
    [ -f "$BASE_DIR/protegido" ]
)

# O helper de desinstalação deve usar o bash detectado no ambiente atual.
grep -Fq 'bash_bin="$(command -v bash' "$MAINT"
grep -Fq '#!$bash_bin' "$MAINT"

echo "OK: settings.sh modular, Fish unificado e ações destrutivas protegidas."
