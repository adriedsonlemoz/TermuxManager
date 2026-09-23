#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/Painel/frontend" "$HOME/Painel/backend" "$HOME/Painel/projetos/outro"
printf '{"scripts":{"dev":"vite"},"dependencies":{"vite":"latest"}}\n' > "$HOME/Painel/frontend/package.json"
printf '{"scripts":{"start":"node server.js"},"dependencies":{"express":"latest"}}\n' > "$HOME/Painel/backend/package.json"
printf '{"scripts":{"start":"node index.js"},"dependencies":{"express":"latest"}}\n' > "$HOME/Painel/projetos/outro/package.json"
# Carrega somente os módulos necessários à descoberta, sem iniciar a UI.
# shellcheck disable=SC1090
source "$ROOT_DIR/modules/core.sh"
# shellcheck disable=SC1090
source "$ROOT_DIR/modules/runtime.sh"
# shellcheck disable=SC1090
source "$ROOT_DIR/modules/projects.sh"
descobrir_entradas
[[ ${#PROJETOS_ENCONTRADOS[@]} -eq 2 ]] || {
  printf 'Esperados 2 projetos, encontrados %s:\n' "${#PROJETOS_ENCONTRADOS[@]}" >&2
  printf '  %s\n' "${PROJETOS_ENCONTRADOS[@]}" >&2
  exit 1
}
[[ "${PROJETOS_ENCONTRADOS[0]}" == "$HOME/Painel|~/Painel (monorepo)" ]] || { printf 'Painel monorepo não foi a primeira entrada\n' >&2; exit 1; }
printf '%s\n' "${PROJETOS_ENCONTRADOS[@]}" | grep -q "$HOME/Painel/projetos/outro|~/Painel/projetos"
if printf '%s\n' "${PROJETOS_ENCONTRADOS[@]}" | grep -Eq "$HOME/Painel/(frontend|backend)\\|"; then
  printf 'frontend/backend foram listados separadamente\n' >&2
  exit 1
fi
echo 'OK: monorepo do Painel aparece uma única vez e projetos em projetos/ continuam separados.'
