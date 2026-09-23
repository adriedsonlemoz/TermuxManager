#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
source "$ROOT_DIR/modules/core.sh"
info(){ :; }; warn(){ :; }; error(){ echo "$*" >&2; }; ok(){ :; }; log(){ :; }
source "$ROOT_DIR/modules/runtime.sh"
mkdir -p "$SESSION_TMP_DIR"
proj="$HOME/Painel/frontend"
mkdir -p "$proj/node_modules"
printf '{"name":"cache-test","version":"1.0.0","dependencies":{}}\n' > "$proj/package.json"
# Primeira execução: node_modules já existe; deve verificar e registrar sem instalar.
executar_com_progresso(){ echo 'ERRO: instalação não deveria ser executada' >&2; return 99; }
instalar_dependencias "$proj" npm
stamp="$(dependency_stamp_path "$proj")"
[ -f "$stamp" ] || { echo 'Cache externo não foi criado' >&2; exit 1; }
[ ! -f "$proj/.manager-deps.hash" ] || { echo 'Cache legado ficou dentro do projeto' >&2; exit 1; }
# Simula atualização/substituição dos arquivos mantendo o mesmo manifesto.
rm -f "$proj/arquivo-antigo" 2>/dev/null || true
touch "$proj/arquivo-novo"
dependencias_atualizadas "$proj" npm || { echo 'Cache não sobreviveu à atualização do projeto' >&2; exit 1; }
echo 'OK: dependências existentes são reutilizadas e cache fica fora do projeto.'
