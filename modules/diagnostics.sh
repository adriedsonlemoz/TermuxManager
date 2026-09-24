# Módulo: diagnostics.sh
# Carregador da Central de Diagnóstico.
#
# Responsabilidades separadas para reduzir acoplamento e facilitar testes:
#   diagnostics_core.sh    -> captura de falhas, sanitização e utilitários
#   diagnostics_project.sh -> relatório de falha dos testes de projetos
#   diagnostics_reports.sh -> exportações consolidadas e pacote de suporte
#   diagnostics_android.sh -> coleta Android via Shizuku e teste de I/O
#   diagnostics_ui.sh      -> menus e navegação da Central de Diagnóstico

DIAGNOSTICS_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _diagnostics_submodule in \
    diagnostics_core.sh \
    diagnostics_project.sh \
    diagnostics_reports.sh \
    diagnostics_android.sh \
    diagnostics_ui.sh; do
    if [ ! -r "$DIAGNOSTICS_MODULE_DIR/$_diagnostics_submodule" ]; then
        printf 'Erro: submódulo de diagnóstico ausente ou ilegível: %s\n' \
            "$DIAGNOSTICS_MODULE_DIR/$_diagnostics_submodule" >&2
        return 1 2>/dev/null || exit 1
    fi
    # shellcheck source=/dev/null
    source "$DIAGNOSTICS_MODULE_DIR/$_diagnostics_submodule"
done
unset _diagnostics_submodule
