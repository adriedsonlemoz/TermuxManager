#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"
PAINEL_DIR="$HOME/Painel"
PROJETOS_DIR="$PAINEL_DIR/projetos"
mkdir -p "$PAINEL_DIR" "$PROJETOS_DIR" "$TMP/case1/projeto-x/backend" "$TMP/case1/projeto-x/frontend"
touch "$TMP/case1/projeto-x/package.json"
source "$ROOT_DIR/modules/import.sh"

wizard_resetar_importacao
WIZ_ZIP_NOME="projeto-x-1.0.0"
wizard_preparar_zip_extraido "$TMP/case1"
[ "$WIZ_ORIGEM" = "$TMP/case1/projeto-x" ]
[ "$WIZ_ACHATAR" = true ]
[ -z "$WIZ_DESTINO" ]
[ "$WIZ_NOME_PROJETO" = "projeto-x" ]

wizard_definir_destino painel
[ "$WIZ_DESTINO" = "$PAINEL_DIR" ]
[ "$WIZ_DESTINO_PROJETO" = false ]

wizard_definir_destino projetos
[ "$WIZ_DESTINO" = "$PROJETOS_DIR/projeto-x" ]
[ "$WIZ_DESTINO_PROJETO" = true ]

printf 'OK: importação genérica Painel/Projetos validada\n'
