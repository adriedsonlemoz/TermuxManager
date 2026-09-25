#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT_DIR/modules/core.sh"
UI="$ROOT_DIR/modules/ui.sh"
TERMUX="$ROOT_DIR/modules/termux.sh"
ACTIONS="$ROOT_DIR/modules/termux_packages_actions.sh"
SETUP="$ROOT_DIR/modules/termux_setup.sh"
PKG_UI="$ROOT_DIR/modules/termux_packages_ui.sh"

bash -n "$ACTIONS" "$SETUP" "$PKG_UI"
grep -Fq 'comando_referencia_pacote() {' "$ACTIONS"
grep -Fq 'pacote_funcional_pos_instalacao() {' "$ACTIONS"
grep -Fq 'copiar_log_setup_downloads() {' "$PKG_UI"
grep -Fq 'Copiar log para Downloads' "$SETUP"
grep -Fq 'Pendentes: $pendentes' "$SETUP"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/home/storage/downloads" "$TMP/base/logs" "$TMP/bin"

# Simula um bootstrap onde os comandos estão funcionais, mas os nomes dos
# pacotes não podem ser consultados no banco dpkg. A pós-checagem deve validar
# a funcionalidade real e não gerar falso negativo para coreutils/findutils/gawk.
cat > "$TMP/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$TMP/bin/dpkg-query"

(
    export HOME="$TMP/home"
    export PATH="$TMP/bin:$PATH"
    export BASE_DIR="$TMP/base"
    source "$CORE"
    source "$UI"
    source "$TERMUX"
    pacote_funcional_pos_instalacao coreutils
    pacote_funcional_pos_instalacao findutils
    pacote_funcional_pos_instalacao gawk
)

echo "OK: pós-checagem valida comandos funcionais sem falso negativo por nome de pacote."

# A opção do wizard deve copiar apenas um log sanitizado para Downloads.
(
    export HOME="$TMP/home"
    export BASE_DIR="$TMP/base"
    source "$CORE"
    source "$UI"
    source "$TERMUX"
    CANDIDATOS_DOWNLOADS=("$TMP/home/storage/downloads")
    TERMUX_SETUP_LOG="$TMP/base/logs/termux-setup.log"
    printf 'TOKEN=segredo123\ninstalação concluída\n' > "$TERMUX_SETUP_LOG"
    copiar_log_setup_downloads
    [ "$TERMUX_SETUP_LOG_EXPORTADO" = "$TMP/home/storage/downloads/termux-setup.log" ]
    [ -f "$TERMUX_SETUP_LOG_EXPORTADO" ]
    grep -Fq 'instalação concluída' "$TERMUX_SETUP_LOG_EXPORTADO"
    ! grep -Fq 'segredo123' "$TERMUX_SETUP_LOG_EXPORTADO"
)

echo "OK: log da configuração pode ser copiado de forma sanitizada para Downloads."
