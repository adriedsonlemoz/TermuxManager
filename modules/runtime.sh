# Módulo: runtime.sh
# Manager.sh — ponto de entrada do subsistema de runtime.
#
# Responsabilidades separadas:
#   runtime_detect.sh       -> detecção de stack e estrutura do projeto
#   runtime_dependencies.sh -> .env, dependências, instalação e testes
#   runtime_processes.sh    -> processos, portas, execução e saúde

RUNTIME_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _runtime_submodule in runtime_detect.sh runtime_dependencies.sh runtime_processes.sh; do
    if [ ! -r "$RUNTIME_MODULE_DIR/$_runtime_submodule" ]; then
        printf 'Erro: submódulo de runtime ausente ou ilegível: %s\n' "$RUNTIME_MODULE_DIR/$_runtime_submodule" >&2
        return 1 2>/dev/null || exit 1
    fi
    # shellcheck source=/dev/null
    source "$RUNTIME_MODULE_DIR/$_runtime_submodule"
done
unset _runtime_submodule
