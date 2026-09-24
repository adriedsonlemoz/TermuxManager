# Módulo: linux.sh
# Linux no celular — carregador do subsistema PRoot + Termux:X11.

LINUX_STATE_DIR="$PAINEL_DIR/linux"
LINUX_LOG="$LOG_DIR/linux.log"
LINUX_ARCH_CACHE_TTL=21600
LINUX_INFO_CACHE_TTL=300

LINUX_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ordem intencional: núcleo primeiro; diagnóstico e X11 fornecem funções usadas
# pelos módulos de distribuições/UI em tempo de execução.
for _linux_submodule in \
    linux_core.sh \
    linux_diagnostics.sh \
    linux_distros.sh \
    linux_backup.sh \
    linux_x11.sh \
    linux_ui.sh; do
    # shellcheck source=/dev/null
    source "$LINUX_MODULE_DIR/$_linux_submodule"
done
unset _linux_submodule
