#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
HOME="$TMP/home"
PAINEL_DIR="$HOME/Painel"
PROJETOS_DIR="$PAINEL_DIR/projetos"
mkdir -p "$PAINEL_DIR" "$PROJETOS_DIR"
source "$ROOT_DIR/modules/import.sh"

# ZIP com uma pasta externa versionada: a camada não deve ser duplicada.
mkdir -p "$TMP/zip1/projeto-x-1.2.3/backend" "$TMP/zip1/projeto-x-1.2.3/frontend"
touch "$TMP/zip1/projeto-x-1.2.3/package.json"
wizard_resetar_importacao
WIZ_ZIP_NOME="projeto-x-1.2.3"
wizard_preparar_zip_extraido "$TMP/zip1"
[ "$WIZ_ORIGEM" = "$TMP/zip1/projeto-x-1.2.3" ]
[ "$WIZ_NOME_PROJETO" = "projeto-x" ]
[ "$WIZ_CAMADA_EXTERNA" = "projeto-x-1.2.3" ]

wizard_definir_destino painel
[ "$WIZ_DESTINO" = "$PAINEL_DIR" ]
[ "$WIZ_DESTINO_PROJETO" = false ]
[ "$WIZ_ACHATAR" = true ]

wizard_definir_destino projetos
[ "$WIZ_DESTINO" = "$PROJETOS_DIR/projeto-x" ]
[ "$WIZ_DESTINO_PROJETO" = true ]
[ "$WIZ_ACHATAR" = true ]

# ZIP sem pasta externa também deve criar pasta própria em Projetos.
mkdir -p "$TMP/zip2/backend" "$TMP/zip2/frontend"
touch "$TMP/zip2/package.json"
wizard_resetar_importacao
WIZ_ZIP_NOME="outro-projeto-v2.4.1"
wizard_preparar_zip_extraido "$TMP/zip2"
[ "$WIZ_NOME_PROJETO" = "outro-projeto" ]
wizard_definir_destino projetos
[ "$WIZ_DESTINO" = "$PROJETOS_DIR/outro-projeto" ]

# Nomes que não são semver não podem ser mutilados.
[ "$(nome_projeto_sem_versao 'api-v2')" = "api-v2" ]
[ "$(nome_projeto_sem_versao 'projeto-2026')" = "projeto-2026" ]

printf 'OK: destinos Painel/Projetos e nome do projeto validados\n'
