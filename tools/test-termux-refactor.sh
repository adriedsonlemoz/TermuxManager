#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMUX="$ROOT_DIR/modules/termux.sh"
PACKAGES="$ROOT_DIR/modules/termux_packages.sh"
PACKAGES_CORE="$ROOT_DIR/modules/termux_packages_core.sh"
PACKAGES_UI="$ROOT_DIR/modules/termux_packages_ui.sh"
PACKAGES_MONITOR="$ROOT_DIR/modules/termux_packages_monitor.sh"
PACKAGES_ACTIONS="$ROOT_DIR/modules/termux_packages_actions.sh"
TOOLS="$ROOT_DIR/modules/termux_tools.sh"
SETUP="$ROOT_DIR/modules/termux_setup.sh"

bash -n "$TERMUX" "$PACKAGES" "$PACKAGES_CORE" "$PACKAGES_UI" "$PACKAGES_MONITOR" "$PACKAGES_ACTIONS" "$TOOLS" "$SETUP"
for arquivo in "$PACKAGES_CORE" "$PACKAGES_UI" "$PACKAGES_MONITOR" "$PACKAGES_ACTIONS" "$TOOLS" "$SETUP"; do
    [ -s "$arquivo" ]
done

# termux_packages.sh agora também é um carregador pequeno.
[ "$(wc -l < "$PACKAGES")" -lt 50 ]
grep -Fq 'termux_packages_core.sh' "$PACKAGES"
grep -Fq 'termux_packages_ui.sh' "$PACKAGES"
grep -Fq 'termux_packages_monitor.sh' "$PACKAGES"
grep -Fq 'termux_packages_actions.sh' "$PACKAGES"
grep -Fq 'executar_pkg_monitorado() {' "$PACKAGES_MONITOR"
grep -Fq 'instalar_lista_pacotes() {' "$PACKAGES_ACTIONS"
grep -Fq 'menu_instalar_ferramentas() {' "$TOOLS"
grep -Fq 'assistente_primeira_execucao() {' "$SETUP"
! grep -Fq 'executar_pkg_monitorado() {' "$PACKAGES"
! grep -Fq 'instalar_lista_pacotes() {' "$PACKAGES"

# A API pública precisa continuar disponível somente ao carregar termux.sh.
(
    set -u
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    export HOME="$TMP/home"
    BASE_DIR="$TMP/base"
    PAINEL_DIR="$HOME/Painel"
    LOG_DIR="$PAINEL_DIR/.logs"
    PREFIX="$TMP/prefix"
    mkdir -p "$HOME" "$BASE_DIR/logs" "$LOG_DIR" "$PREFIX"
    source "$TERMUX"
    declare -F detectar_variante_termux >/dev/null
    declare -F gerar_diagnostico_pkg >/dev/null
    declare -F executar_pkg_monitorado >/dev/null
    declare -F instalar_lista_pacotes >/dev/null
    declare -F menu_instalar_ferramentas >/dev/null
    declare -F assistente_primeira_execucao >/dev/null
)

# Diagnósticos e logs exportados devem passar pela sanitização inclusive
# quando diagnostics.sh ainda não foi carregado.
grep -Fq 'sanitizar_saida_termux() {' "$PACKAGES_UI"
grep -Fq 'sanitizar_saida_termux < "$origem" > "$destino"' "$PACKAGES_UI"
grep -Fq '| sanitizar_saida_termux > "$TERMUX_DIAGNOSTIC_LOG"' "$PACKAGES_UI"

# Quando o pkg exige interação, a retomada usa os argumentos originais.
grep -Fq 'executar_pkg_interativo "$titulo" "${args[@]}"' "$PACKAGES_MONITOR"

echo "OK: termux_packages.sh foi dividido em quatro submódulos; API pública preservada."

# Regressão de segurança: o diagnóstico gerado não pode manter segredos crus.
(
    set -u
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    export HOME="$TMP/home"
    BASE_DIR="$TMP/base"
    PAINEL_DIR="$TMP/painel"
    LOG_DIR="$TMP/logs"
    PREFIX="$TMP/prefix"
    mkdir -p "$BASE_DIR/logs" "$HOME" "$PREFIX"
    source "$TERMUX"
    TERMUX_SETUP_LOG="$TMP/pkg.log"
    TERMUX_DIAGNOSTIC_LOG="$TMP/diag.txt"
    MANAGER_VERSION='teste'
    LAST_PKG_COMMAND='pkg install demo TOKEN=segredo123'
    LAST_PKG_EXIT_CODE=1
    caminho_curto(){ printf '%s' "$1"; }
    printf 'falha TOKEN=segredo456 https://usuario:senha@repo.example/arquivo\n' > "$TERMUX_SETUP_LOG"
    gerar_diagnostico_pkg 'teste de sanitização'
    ! grep -Fq 'segredo123' "$TERMUX_DIAGNOSTIC_LOG"
    ! grep -Fq 'segredo456' "$TERMUX_DIAGNOSTIC_LOG"
    ! grep -Fq 'usuario:senha' "$TERMUX_DIAGNOSTIC_LOG"
    grep -Fq '[REMOVIDO]' "$TERMUX_DIAGNOSTIC_LOG"
)

echo "OK: diagnóstico do pkg remove segredos antes de exibir/exportar."

# Integração: um prompt detectado durante o modo monitorado migra para a
# execução interativa usando os argumentos originais do pkg.
(
    set -u
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    mkdir -p "$TMP/bin" "$TMP/base/logs" "$TMP/home"
    cat > "$TMP/bin/apt-get" <<'SH'
#!/usr/bin/env bash
sleep 20
SH
    chmod +x "$TMP/bin/apt-get"
    export HOME="$TMP/home"
    PATH="$TMP/bin:$PATH"
    BASE_DIR="$TMP/base"
    PAINEL_DIR="$TMP/painel"
    LOG_DIR="$TMP/logs"
    PREFIX="$TMP/prefix"
    source "$TERMUX"
    TERMUX_SETUP_LOG="$TMP/pkg.log"
    C_CYAN= C_BOLD= C_DIM= C_RESET= C_GREEN= C_YELLOW=
    log(){ :; }
    tela_operacao_termux(){ :; }
    encerrar_ui_termux(){ TERMUX_UI_DRAWN=false; }
    pids_gerenciador_pacotes_ativos(){ :; }
    log_pkg_exige_interacao(){ return 0; }
    pid_ou_filho_parado(){ return 1; }
    executar_pkg_interativo(){ local _titulo="$1"; shift; printf '%s\n' "$*" > "$TMP/interativo.args"; return 0; }
    executar_pkg_monitorado "Teste interativo" 0 10 "Pacote" "Detalhe" -- install -y git
    grep -Fxq 'install -y git' "$TMP/interativo.args"
)

echo "OK: prompt do pkg migra para sessão interativa com os argumentos originais."
