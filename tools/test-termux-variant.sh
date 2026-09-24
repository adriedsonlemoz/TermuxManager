#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMUX_MOD="$ROOT_DIR/modules/termux.sh"
TERMUX_PACKAGES="$ROOT_DIR/modules/termux_packages.sh"
TERMUX_PACKAGES_CORE="$ROOT_DIR/modules/termux_packages_core.sh"
bash -n "$TERMUX_MOD" "$TERMUX_PACKAGES" "$TERMUX_PACKAGES_CORE"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

grep -Fq 'Google Play' "$TERMUX_PACKAGES_CORE"
grep -Fq 'GitHub/F-Droid' "$TERMUX_PACKAGES_CORE"
grep -Fq 'pacote_disponivel_termux' "$TERMUX_PACKAGES_CORE"

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

# Regressão: opções APT e múltiplos repositórios precisam ser detectados
# sem corromper o repositório primário nem o separador do resumo.
(
    PREFIX="$TMP/multirepo"
    mkdir -p "$PREFIX/etc/apt/sources.list.d"
    printf 'deb [trusted=yes] https://packages.termux.dev/apt/termux-main stable main\n' > "$PREFIX/etc/apt/sources.list"
    printf 'deb https://packages-cf.termux.dev/apt/termux-root root stable\n' > "$PREFIX/etc/apt/sources.list.d/root.list"
    TERMUX_VERSION='0.119.0'
    source "$TERMUX_MOD"
    detectar_variante_termux
    [ "$TERMUX_REPO_PRIMARY" = 'https://packages.termux.dev/apt/termux-main' ]
    [ "$TERMUX_REPO_SUMMARY" = 'https://packages.termux.dev/apt/termux-main, https://packages-cf.termux.dev/apt/termux-root' ]
)

echo "OK: variante do Termux detectada corretamente, inclusive com opções APT e múltiplos repositórios."
