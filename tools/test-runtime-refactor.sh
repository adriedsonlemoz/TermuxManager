#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

for file in runtime.sh runtime_detect.sh runtime_dependencies.sh runtime_processes.sh; do
    [ -r "$ROOT_DIR/modules/$file" ] || { echo "Submódulo ausente: $file" >&2; exit 1; }
done

# runtime.sh deve permanecer apenas como carregador e não voltar a concentrar
# centenas de linhas de implementação.
[ "$(wc -l < "$ROOT_DIR/modules/runtime.sh")" -le 80 ] || {
    echo 'runtime.sh voltou a crescer além do limite do carregador.' >&2
    exit 1
}
grep -Fq 'runtime_detect.sh runtime_dependencies.sh runtime_processes.sh' "$ROOT_DIR/modules/runtime.sh"

source "$ROOT_DIR/modules/core.sh"
info(){ :; }; warn(){ :; }; error(){ :; }; ok(){ :; }; log(){ :; }
source "$ROOT_DIR/modules/runtime.sh"

type detectar_stack >/dev/null 2>&1
type instalar_dependencias >/dev/null 2>&1
type executar_em_background >/dev/null 2>&1

# Regressão: chaves arbitrárias do package.json não podem ser confundidas
# com dependências nem scripts reais.
proj="$TMP/projeto"
mkdir -p "$proj"
cat > "$proj/package.json" <<'JSON'
{
  "name": "runtime-regression",
  "scripts": {"start": "node server.js", "build": "echo ok"},
  "metadata": {"next": "não é dependência", "dev": "não é script"},
  "dependencies": {"express": "^5.0.0"}
}
JSON

detectar_stack "$proj"
[ "$DETECT_FRAMEWORK" = "Express" ] || {
    echo "Framework incorreto: esperado Express, recebido $DETECT_FRAMEWORK" >&2
    exit 1
}
[ "$DETECT_RUN_CMD" = "npm run start" ] || {
    echo "Script incorreto: esperado npm run start, recebido $DETECT_RUN_CMD" >&2
    exit 1
}

# Regressão: instalar_dependencias nunca deve alterar o diretório atual do
# chamador, inclusive em saída de erro.
before="$PWD"
mkdir -p "$SESSION_TMP_DIR"
set +e
instalar_dependencias "$proj" desconhecido >/dev/null 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || { echo 'Gerenciador desconhecido deveria falhar.' >&2; exit 1; }
[ "$PWD" = "$before" ] || {
    echo "Diretório atual vazou da instalação: $before -> $PWD" >&2
    exit 1
}

printf 'OK: runtime modular, detecção JSON e isolamento de CWD validados.\n'
