# Módulo: termux.sh
# Manager.sh — ponto de entrada do subsistema Termux.
#
# As responsabilidades foram separadas para manter este módulo pequeno:
#   termux_packages.sh -> pkg/apt, repositórios, logs e diagnóstico
#   termux_tools.sh    -> ferramentas e ambientes de desenvolvimento
#   termux_setup.sh    -> manutenção e assistente de primeira execução

TERMUX_SETUP_LOG="${BASE_DIR:-$HOME/scripts/manager}/logs/termux-setup.log"
TERMUX_DIAGNOSTIC_LOG="${BASE_DIR:-$HOME/scripts/manager}/logs/ultimo-diagnostico.txt"
LAST_PKG_COMMAND=""
LAST_PKG_EXIT_CODE=""
TERMUX_UI_DRAWN=false
TERMUX_UI_LAST_SIGNATURE=""
WIZARD_MODE=false
PKG_LAST_NONEMPTY_LINES=""
LAST_PKG_LOG_START_OFFSET=0
PKG_ACTIVE_PID=""
PKG_CANCEL_REQUESTED=false
TERMUX_VARIANT_ID=""
TERMUX_VARIANT_LABEL=""
TERMUX_VARIANT_SOURCE=""
TERMUX_REPO_PRIMARY=""
TERMUX_REPO_SUMMARY=""

TERMUX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _termux_submodule in termux_packages.sh termux_tools.sh termux_setup.sh; do
    if [ ! -r "$TERMUX_MODULE_DIR/$_termux_submodule" ]; then
        printf 'Erro: submódulo Termux ausente ou ilegível: %s\n' "$TERMUX_MODULE_DIR/$_termux_submodule" >&2
        return 1 2>/dev/null || exit 1
    fi
    # shellcheck source=/dev/null
    source "$TERMUX_MODULE_DIR/$_termux_submodule"
done
unset _termux_submodule
