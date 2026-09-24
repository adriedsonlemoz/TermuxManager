# Módulo: termux_packages.sh
# Carregador do subsistema de pacotes do Termux.
#
# Responsabilidades separadas para reduzir acoplamento e facilitar testes:
#   termux_packages_core.sh    -> repositórios, variante e estado básico
#   termux_packages_ui.sh      -> UI, diagnóstico, exportação e reparo
#   termux_packages_monitor.sh -> monitoramento de pkg/apt e interação
#   termux_packages_actions.sh -> atualização, ambiente e instalação

TERMUX_PACKAGES_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _termux_packages_submodule in \
    termux_packages_core.sh \
    termux_packages_ui.sh \
    termux_packages_monitor.sh \
    termux_packages_actions.sh; do
    if [ ! -r "$TERMUX_PACKAGES_MODULE_DIR/$_termux_packages_submodule" ]; then
        printf 'Erro: submódulo de pacotes Termux ausente ou ilegível: %s\n' \
            "$TERMUX_PACKAGES_MODULE_DIR/$_termux_packages_submodule" >&2
        return 1 2>/dev/null || exit 1
    fi
    # shellcheck source=/dev/null
    source "$TERMUX_PACKAGES_MODULE_DIR/$_termux_packages_submodule"
done
unset _termux_packages_submodule
