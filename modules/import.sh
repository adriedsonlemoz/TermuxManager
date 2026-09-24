# Módulo: import.sh
# Manager.sh — ponto de entrada do subsistema de importação.
#
# Responsabilidades separadas:
#   import_copy.sh   -> cópia, rsync, progresso e utilitários de transferência
#   import_wizard.sh -> assistente de importação, ZIP, destinos e pós-importação

# Estado compartilhado do assistente.
WIZ_ORIGEM_BASE=""; WIZ_ORIGEM=""; WIZ_TIPO=""; WIZ_MODO=""
WIZ_DESTINO=""; WIZ_ACHATAR=false; WIZ_SOBRESCREVER=false
WIZ_DESTINO_FIXO=false; WIZ_ZIP_NOME=""; WIZ_ORIGEM_ORIGINAL=""
WIZ_NOME_PROJETO=""; WIZ_DESTINO_PROJETO=false; WIZ_CAMADA_EXTERNA=""
WIZ_ITENS=()
WIZ_DEPS_PRESERVADAS=()
ULTIMO_PROJETO_IMPORTADO=""
ULTIMA_COPIA_OK=false

IMPORT_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _import_submodule in import_copy.sh import_wizard.sh; do
    if [ ! -r "$IMPORT_MODULE_DIR/$_import_submodule" ]; then
        printf 'Erro: submódulo de importação ausente ou ilegível: %s\n' "$IMPORT_MODULE_DIR/$_import_submodule" >&2
        return 1 2>/dev/null || exit 1
    fi
    # shellcheck source=/dev/null
    source "$IMPORT_MODULE_DIR/$_import_submodule"
done
unset _import_submodule
