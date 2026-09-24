#!/data/data/com.termux/files/usr/bin/bash
###############################################################################
# manager.sh — Gerenciador de Projetos para Termux — Versão 1.0.85
#
# Gerencia importação, listagem, teste (detecção de stack + instalação
# automática de dependências) e execução de projetos frontend/backend
# diretamente no Termux (Android).
#
# Desenvolvedor: Adriedson Aparecido Lemos
###############################################################################

set -Euo pipefail

# Se o Manager for iniciado a partir de uma pasta que foi removida em outra
# operação/sessão, o shell pode ficar com um CWD inválido e emitir repetidamente
# "getcwd(): No such file or directory". Recupera somente nesse caso, sem
# alterar o diretório normal do usuário quando ele ainda existe.
if ! pwd -P >/dev/null 2>&1; then
    cd "${HOME:-/}" 2>/dev/null || cd /
fi

MANAGER_VERSION="1.0.85"
MANAGER_DEVELOPER="Adriedson Aparecido Lemos"
MANAGER_REPOSITORY="https://github.com/adriedsonlemoz/TermuxManager"
MANAGER_LICENSE="Uso livre conforme o repositório"
MANAGER_CHANNEL="Estável"
FIRST_RUN_FILE="$HOME/.manager_ready"
FIRST_RUN_STATE_FILE="$HOME/.manager_first_run.state"

# Garante um locale UTF-8, se disponível — necessário para que ${#string}
# conte caracteres (não bytes) e para que os cálculos de largura das caixas
# funcionem corretamente com emojis/acentos. Em ambientes sem locale UTF-8,
# o script continua funcionando, só com alinhamento levemente menos preciso.
if command -v locale >/dev/null 2>&1; then
    if locale -a 2>/dev/null | grep -qi '^C\.utf8$\|^C\.UTF-8$'; then
        export LC_ALL=C.UTF-8
    elif locale -a 2>/dev/null | grep -qi '^en_US\.utf8$\|^en_US\.UTF-8$'; then
        export LC_ALL=en_US.UTF-8
    fi
fi


BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$BASE_DIR/modules"
SELF_PATH="$BASE_DIR/manager.sh"

MODULOS_OBRIGATORIOS=(
    core.sh config.sh ui.sh import.sh projects.sh runtime.sh
    termux.sh linux.sh diagnostics.sh updater.sh settings.sh help.sh app.sh
)

carregar_modulos() {
    local modulo caminho
    for modulo in "${MODULOS_OBRIGATORIOS[@]}"; do
        caminho="$MODULES_DIR/$modulo"
        if [ ! -r "$caminho" ]; then
            printf 'Erro: módulo obrigatório ausente ou ilegível: %s\n' "$caminho" >&2
            exit 1
        fi
        # shellcheck source=/dev/null
        source "$caminho"
    done
}

carregar_modulos
main "$@"
