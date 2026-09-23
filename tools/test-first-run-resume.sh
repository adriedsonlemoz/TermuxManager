#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMUX="$ROOT_DIR/modules/termux.sh"
APP="$ROOT_DIR/modules/app.sh"
SETTINGS="$ROOT_DIR/modules/settings.sh"
MANAGER="$ROOT_DIR/manager.sh"

bash -n "$TERMUX"
bash -n "$APP"
bash -n "$SETTINGS"

grep -Fq 'FIRST_RUN_STATE_FILE="$HOME/.manager_first_run.state"' "$MANAGER"
grep -Fq 'first_run_mark_stage update' "$TERMUX"
grep -Fq 'first_run_mark_stage tools' "$TERMUX"
grep -Fq 'Ctrl+C abre opções seguras' "$TERMUX"
grep -Fq 'Pacotes já instalados não serão reinstalados.' "$TERMUX"
grep -Fq 'Prosseguindo automaticamente em 3 segundos...' "$TERMUX"
grep -Fq 'A atualização do Termux já terminou.' "$TERMUX"
grep -Fq 'Acquire::http::Timeout=30' "$TERMUX"
grep -Fq 'DPkg::Lock::Timeout=30' "$TERMUX"
grep -Fq 'PKG_CANCEL_REQUESTED=true' "$TERMUX"
grep -Fq 'FIRST_RUN_STATE_FILE' "$SETTINGS"
! grep -Fq 'touch "$FIRST_RUN_FILE" 2>/dev/null || true\n        return 0' "$TERMUX"

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
