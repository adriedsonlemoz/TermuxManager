#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$ROOT/modules/import.sh"
COPY="$ROOT/modules/import_copy.sh"
WIZARD="$ROOT/modules/import_wizard.sh"

[ -f "$COPY" ] && [ -f "$WIZARD" ]
grep -Fq 'import_copy.sh import_wizard.sh' "$WRAPPER"
grep -q '^motor_copia()' "$COPY"
grep -q '^wizard_executar_importacao()' "$WIZARD"
grep -q '^validar_zip_importacao()' "$WIZARD"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
source "$WRAPPER"

# O carregador precisa preservar a API pública.
declare -F importar_projeto >/dev/null
declare -F motor_copia >/dev/null
declare -F wizard_preparar_zip_extraido >/dev/null

# Um ZIP com caminho de travessia nunca pode chegar à extração.
touch "$TMP/pacote.zip"
error(){ :; }
unzip(){
    if [ "${1:-}" = "-Z1" ]; then
        printf '%s\n' '../escape.txt' 'projeto/package.json'
        return 0
    fi
    return 0
}
if validar_zip_importacao "$TMP/pacote.zip"; then
    echo 'FAIL: ZIP com ../ foi aceito' >&2
    exit 1
fi
unzip(){
    if [ "${1:-}" = "-Z1" ]; then
        printf '%s\n' 'projeto/package.json' 'projeto/src/main.js'
        return 0
    fi
    return 0
}
validar_zip_importacao "$TMP/pacote.zip"

# Falha ao copiar um item avulso não pode mais ser marcada como sucesso.
WIZ_SOBRESCREVER=false
WIZ_DESTINO_PROJETO=false
WIZ_DESTINO="$TMP/destino"
WIZ_ITENS=("$TMP/arquivo-inexistente.txt")
ULTIMA_COPIA_OK=true
cabecalho_tela(){ :; }
caminho_curto(){ printf '%s' "$1"; }
warn(){ :; }
ok(){ :; }
mkdir -p "$WIZ_DESTINO"
if wizard_executar_importacao; then
    echo 'FAIL: importação parcial retornou sucesso' >&2
    exit 1
fi
[ "$ULTIMA_COPIA_OK" = false ]

echo 'OK: refatoração da importação, ZIP seguro e falha parcial validados.'
