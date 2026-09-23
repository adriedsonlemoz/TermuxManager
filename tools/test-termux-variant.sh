#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMUX_MOD="$ROOT_DIR/modules/termux.sh"
bash -n "$TERMUX_MOD"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

grep -Fq 'Google Play' "$TERMUX_MOD"
grep -Fq 'GitHub/F-Droid' "$TERMUX_MOD"
grep -Fq 'pacote_disponivel_termux' "$TERMUX_MOD"

(
    PREFIX="$TMP/gplay"
    mkdir -p "$PREFIX/etc/apt"
    printf 'deb https://termux.net stable main
' > "$PREFIX/etc/apt/sources.list"
    TERMUX_VERSION='googleplay.2026.06.21'
    # shellcheck source=/dev/null
    source "$TERMUX_MOD"
    detectar_variante_termux
    [ "$TERMUX_VARIANT_ID" = 'google-play' ]
    [ "$TERMUX_VARIANT_LABEL" = 'Google Play' ]
)

(
    PREFIX="$TMP/github"
    mkdir -p "$PREFIX/etc/apt"
    printf 'deb https://packages.termux.dev/apt/termux-main stable main
' > "$PREFIX/etc/apt/sources.list"
    TERMUX_VERSION='0.119.0'
    # shellcheck source=/dev/null
    source "$TERMUX_MOD"
    detectar_variante_termux
    [ "$TERMUX_VARIANT_ID" = 'github-fdroid' ]
    [ "$TERMUX_VARIANT_LABEL" = 'GitHub/F-Droid' ]
)

echo "OK: variante do Termux detectada corretamente para Google Play e GitHub/F-Droid."
