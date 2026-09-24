# Módulo: updater.sh
# Carregador do subsistema de atualização do Termux Manager.
#
# Responsabilidades separadas:
#   updater_core.sh    -> estado, versões, hashes e integridade
#   updater_github.sh  -> consulta/download pelo GitHub
#   updater_local.sh   -> arquivos locais e atualização isolada
#   updater_install.sh -> instalação completa e rollback
#   updater_ui.sh      -> histórico, seleção e navegação

UPDATER_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _updater_submodule in \
    updater_core.sh \
    updater_github.sh \
    updater_local.sh \
    updater_install.sh \
    updater_ui.sh; do
    if [ ! -r "$UPDATER_MODULE_DIR/$_updater_submodule" ]; then
        printf 'Erro: submódulo de atualização ausente ou ilegível: %s\n' \
            "$UPDATER_MODULE_DIR/$_updater_submodule" >&2
        return 1 2>/dev/null || exit 1
    fi
    # shellcheck source=/dev/null
    source "$UPDATER_MODULE_DIR/$_updater_submodule"
done
unset _updater_submodule
