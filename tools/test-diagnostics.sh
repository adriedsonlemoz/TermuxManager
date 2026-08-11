#!/usr/bin/env bash
set -Euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export PREFIX="${PREFIX:-/usr}"
export TERM="${TERM:-xterm}"
mkdir -p "$HOME/storage/downloads"

BASE_DIR="$ROOT_DIR"
MODULES_DIR="$ROOT_DIR/modules"
SELF_PATH="$ROOT_DIR/manager.sh"
MANAGER_VERSION="1.0.48"
MANAGER_DEVELOPER="Teste"
MANAGER_REPOSITORY="teste"
MANAGER_LICENSE="teste"
MANAGER_CHANNEL="Estável"
FIRST_RUN_FILE="$HOME/.manager_ready"

for modulo in core.sh config.sh ui.sh import.sh projects.sh runtime.sh termux.sh diagnostics.sh; do
    # shellcheck source=/dev/null
    source "$MODULES_DIR/$modulo"
done

TERMUX_SETUP_LOG="$HOME/termux-setup.log"
TERMUX_DIAGNOSTIC_LOG="$HOME/termux-diagnostico.txt"
setup_dirs
inicializar_diagnosticos
ativar_captura_diagnosticos

# return 1 usado como controle de fluxo não deve virar incidente.
set +e
controle_normal() { return 1; }
controle_normal
set -e
[ "$(find "$MANAGER_INCIDENT_DIR" -type f -name 'erro-*.txt' | wc -l | tr -d ' ')" -eq 0 ] || { printf 'Falha: return normal virou incidente.\n'; exit 1; }

printf '[teste] [ERROR] JWT_SECRET=segredo-manager falha interna\n' > "$LOG_FILE"
printf 'npm ERR! TypeError: falhou PASSWORD=segredo-projeto\n' > "$LOG_DIR/demo_frontend.log"
printf 'E: dpkg error TOKEN=segredo-termux\n' > "$TERMUX_SETUP_LOG"

falha_controlada() { comando_inexistente_diagnostico_148; }
set +e
falha_controlada 2>/dev/null
set -e

incidentes=$(find "$MANAGER_INCIDENT_DIR" -type f -name 'erro-*.txt' | wc -l | tr -d ' ')
[ "$incidentes" -eq 1 ] || { printf 'Esperado 1 incidente, encontrado %s\n' "$incidentes"; exit 1; }

pause() { :; }
exportar_todos_relatorios >/dev/null
pasta_relatorios=$(find "$DOWNLOADS_DIR" -maxdepth 1 -type d -name 'TermuxManager-Relatorios-*' | head -n 1)
[ -d "$pasta_relatorios/manager" ] && [ -d "$pasta_relatorios/projetos" ] && [ -d "$pasta_relatorios/termux" ] || { printf 'Exportação completa por pastas falhou.\n'; exit 1; }

exportar_pacote_diagnostico_completo </dev/null >/dev/null || true
pacote=$(find "$DOWNLOADS_DIR" -maxdepth 1 -type f -name 'termux-manager-diagnostico-*' | head -n 1)
[ -f "$pacote" ] || { printf 'Pacote de diagnóstico não foi criado.\n'; exit 1; }

extraido="$TMP/extraido"
mkdir -p "$extraido"
case "$pacote" in
    *.zip) unzip -q "$pacote" -d "$extraido" ;;
    *.tar.gz) tar -xzf "$pacote" -C "$extraido" ;;
esac

if grep -RqsE 'segredo-manager|segredo-projeto|segredo-termux' "$extraido" "$MANAGER_INCIDENT_DIR"; then
    printf 'Falha: um segredo de teste permaneceu no relatório.\n'
    exit 1
fi

grep -Rqs '\[REMOVIDO\]' "$extraido" || { printf 'Falha: sanitização não foi comprovada.\n'; exit 1; }
[ -d "$extraido/manager" ] && [ -d "$extraido/projetos" ] && [ -d "$extraido/termux" ] || {
    printf 'Falha: categorias esperadas não foram criadas.\n'
    exit 1
}

printf 'Teste da Central de Diagnóstico concluído com sucesso.\n'
