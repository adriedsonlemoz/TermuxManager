#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMUX="$ROOT_DIR/modules/termux.sh"
CORE="$ROOT_DIR/modules/termux_packages_core.sh"
MONITOR="$ROOT_DIR/modules/termux_packages_monitor.sh"
SETUP="$ROOT_DIR/modules/termux_setup.sh"
APP="$ROOT_DIR/modules/app.sh"
INSTALLER="$ROOT_DIR/install.sh"

bash -n "$CORE" "$MONITOR" "$SETUP" "$APP" "$INSTALLER"
grep -Fq 'indices_apt_inicializados() {' "$CORE"
grep -Fq 'indices_apt_inicializados || return 0' "$CORE"
grep -Fq 'if ! indices_apt_inicializados && command -v pkg' "$MONITOR"
grep -Fq 'local -a pacotes_iniciais=(' "$SETUP"
grep -Fq 'pacotes_pendentes' "$SETUP"
grep -Fq 'if [ -f "$FIRST_RUN_FILE" ]; then' "$APP"
grep -Fq 'executar_pkg_instalador update -y' "$INSTALLER"
grep -Fq 'pkg "$@" </dev/null' "$INSTALLER"

echo "OK: bootstrap de primeira instalação está presente no instalador e no assistente."

TMP="$(mktemp -d)"
cleanup_first_install_test() { rm -rf "$TMP"; }
trap cleanup_first_install_test EXIT
mkdir -p "$TMP/home" "$TMP/base/logs" "$TMP/prefix/var/lib/apt/lists" "$TMP/fakebin"

cat > "$TMP/fakebin/apt-cache" <<'SH'
#!/usr/bin/env bash
# Simula apt-cache sem metadados do pacote.
exit 100
SH
cat > "$TMP/fakebin/pkg" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PKG_CALL_LOG"
exit 0
SH
cat > "$TMP/fakebin/apt-get" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$APT_CALL_LOG"
exit 0
SH
chmod +x "$TMP/fakebin/apt-cache" "$TMP/fakebin/pkg" "$TMP/fakebin/apt-get"

# Cache APT vazio deve ser tratado como "desconhecido/tentar instalar", nunca
# como prova de que o pacote não existe.
(
    set -u
    export HOME="$TMP/home"
    export PREFIX="$TMP/prefix"
    export PATH="$TMP/fakebin:$PATH"
    BASE_DIR="$TMP/base"
    PAINEL_DIR="$TMP/painel"
    LOG_DIR="$TMP/logs"
    source "$TERMUX"
    ! indices_apt_inicializados
    pacote_disponivel_termux pacote-exemplo

    # Depois que há índice real, apt-cache volta a ser autoridade. O fake
    # retorna 100, portanto o pacote passa a ser considerado indisponível.
    printf 'indice\n' > "$PREFIX/var/lib/apt/lists/repo_dists_stable_main_binary-aarch64_Packages"
    indices_apt_inicializados
    if pacote_disponivel_termux pacote-exemplo; then
        echo "FAIL: apt-cache inicializado e negativo foi ignorado" >&2
        exit 1
    fi
)

echo "OK: cache APT vazio não faz pacotes iniciais serem pulados."

# Sem índices, a primeira sincronização monitorada precisa passar pelo wrapper
# pkg do Termux, e não pelo apt-get direto.
(
    set -u
    rm -f "$TMP/prefix/var/lib/apt/lists/"* "$TMP/pkg.calls" "$TMP/apt.calls" 2>/dev/null || true
    export HOME="$TMP/home"
    export PREFIX="$TMP/prefix"
    export PATH="$TMP/fakebin:$PATH"
    export PKG_CALL_LOG="$TMP/pkg.calls"
    export APT_CALL_LOG="$TMP/apt.calls"
    BASE_DIR="$TMP/base"
    PAINEL_DIR="$TMP/painel"
    LOG_DIR="$TMP/logs"
    source "$TERMUX"
    TERMUX_SETUP_LOG="$TMP/setup.log"
    TERMUX_UI_DRAWN=false
    TERMUX_UI_LAST_SIGNATURE=""
    C_CYAN= C_BOLD= C_DIM= C_RESET= C_GREEN= C_YELLOW=
    log(){ :; }
    tela_operacao_termux(){ :; }
    encerrar_ui_termux(){ TERMUX_UI_DRAWN=false; }
    pids_gerenciador_pacotes_ativos(){ :; }
    log_pkg_exige_interacao(){ return 1; }
    pid_ou_filho_parado(){ return 1; }
    ultimas_linhas_pkg(){ printf 'ok'; }

    executar_pkg_monitorado "Bootstrap" 0 10 "Índice" "Primeira sincronização" -- update -y
    grep -Fxq 'update -y' "$TMP/pkg.calls"
    [ ! -s "$TMP/apt.calls" ]
)

echo "OK: primeira sincronização usa o bootstrap oficial do pkg."
