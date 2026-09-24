#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMUX="$ROOT_DIR/modules/termux.sh"
TERMUX_PACKAGES="$ROOT_DIR/modules/termux_packages.sh"
TERMUX_PACKAGES_MONITOR="$ROOT_DIR/modules/termux_packages_monitor.sh"
TERMUX_PACKAGES_ACTIONS="$ROOT_DIR/modules/termux_packages_actions.sh"
TERMUX_SETUP="$ROOT_DIR/modules/termux_setup.sh"
APP="$ROOT_DIR/modules/app.sh"
SETTINGS="$ROOT_DIR/modules/settings.sh"
SETTINGS_MAINT="$ROOT_DIR/modules/settings_maintenance.sh"
MANAGER="$ROOT_DIR/manager.sh"

bash -n "$TERMUX" "$TERMUX_PACKAGES" "$TERMUX_PACKAGES_MONITOR" "$TERMUX_PACKAGES_ACTIONS" "$TERMUX_SETUP"
bash -n "$APP"
bash -n "$SETTINGS" "$SETTINGS_MAINT"

grep -Fq 'FIRST_RUN_STATE_FILE="$HOME/.manager_first_run.state"' "$MANAGER"
grep -Fq 'first_run_mark_stage update' "$TERMUX_SETUP"
grep -Fq 'first_run_mark_stage tools' "$TERMUX_SETUP"
grep -Fq 'Ctrl+C abre opções seguras' "$TERMUX_PACKAGES_MONITOR"
grep -Fq 'Pacotes já instalados não serão reinstalados.' "$TERMUX_SETUP"
grep -Fq 'Prosseguindo automaticamente em 3 segundos...' "$TERMUX_PACKAGES_ACTIONS"
grep -Fq 'A atualização do Termux já terminou.' "$TERMUX_PACKAGES_ACTIONS"
grep -Fq 'Acquire::http::Timeout=30' "$TERMUX_PACKAGES_MONITOR"
grep -Fq 'DPkg::Lock::Timeout=30' "$TERMUX_PACKAGES_MONITOR"
grep -Fq 'PKG_CANCEL_REQUESTED=true' "$TERMUX_PACKAGES_MONITOR"
grep -Fq 'FIRST_RUN_STATE_FILE' "$SETTINGS_MAINT"
! grep -Fq 'touch "$FIRST_RUN_FILE" 2>/dev/null || true\n        return 0' "$TERMUX_SETUP"

echo "OK: primeira configuração possui retomada, atividade visível e Ctrl+C seguro."

# Integração: Ctrl+C durante apt-get monitorado deve retornar 130 sem acionar
# o trap global do Manager; depois o trap anterior precisa estar restaurado.
TMP="$(mktemp -d)"
cleanup_test_first_run() { rm -rf "$TMP"; }
trap cleanup_test_first_run EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
chmod +x "$TMP/bin/apt-get"

(
    set -u
    PATH="$TMP/bin:$PATH"
    # shellcheck source=/dev/null
    source "$TERMUX"
    TERMUX_SETUP_LOG="$TMP/pkg.log"
    C_CYAN= C_BOLD= C_DIM= C_RESET= C_GREEN= C_YELLOW=
    TERMUX_UI_DRAWN=false
    TERMUX_UI_LAST_SIGNATURE=""
    log(){ :; }
    caminho_curto(){ printf '%s' "$1"; }
    tela_operacao_termux(){ :; }
    encerrar_ui_termux(){ TERMUX_UI_DRAWN=false; }
    pids_gerenciador_pacotes_ativos(){ :; }
    log_pkg_exige_interacao(){ return 1; }
    pid_ou_filho_parado(){ return 1; }
    ultimas_linhas_pkg(){ printf 'sem saída'; }

    GLOBAL_HIT=0
    trap 'GLOBAL_HIT=1' INT
    TARGET_PID=$BASHPID
    (sleep 1; kill -INT "$TARGET_PID") &
    if executar_pkg_monitorado "Teste" 0 10 "Pacote" "Detalhe" -- install -y git; then
        rc=0
    else
        rc=$?
    fi
    [ "$rc" -eq 130 ]
    [ "$GLOBAL_HIT" -eq 0 ]
    kill -INT "$BASHPID"
    sleep 0.1
    [ "$GLOBAL_HIT" -eq 1 ]
)

echo "OK: Ctrl+C monitorado retorna ao fluxo e restaura o trap anterior."
