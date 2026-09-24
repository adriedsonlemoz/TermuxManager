#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERMUX="$ROOT_DIR/modules/termux.sh"
TERMUX_PACKAGES="$ROOT_DIR/modules/termux_packages.sh"
TERMUX_PACKAGES_ACTIONS="$ROOT_DIR/modules/termux_packages_actions.sh"
TERMUX_TOOLS="$ROOT_DIR/modules/termux_tools.sh"
CORE="$ROOT_DIR/modules/core.sh"
README="$ROOT_DIR/README.md"

bash -n "$TERMUX" "$TERMUX_PACKAGES" "$TERMUX_PACKAGES_ACTIONS" "$TERMUX_TOOLS" "$CORE"
grep -Fq 'menu_web_dev()' "$TERMUX_TOOLS"
grep -Fq 'menu_python_dev()' "$TERMUX_TOOLS"
grep -Fq 'menu_bancos_dev()' "$TERMUX_TOOLS"
grep -Fq 'ferramentas_recomendadas_projetos()' "$TERMUX_TOOLS"
grep -Fq 'Ambiente Go' "$TERMUX_TOOLS"
grep -Fq 'Ambiente Rust' "$TERMUX_TOOLS"
grep -Fq 'Ambiente Ruby' "$TERMUX_TOOLS"
grep -Fq 'Instalação em lote' "$TERMUX_PACKAGES_ACTIONS"
grep -Fq 'fallback individual' "$TERMUX_PACKAGES_ACTIONS"
grep -Fq 'TERMUX_INSTALL_NONINTERACTIVE=true instalar_lista_pacotes' "$CORE"
grep -Fq 'package.json' "$TERMUX_TOOLS"
grep -Fq 'Cargo.toml' "$TERMUX_TOOLS"
grep -Fq 'go.mod' "$TERMUX_TOOLS"
grep -Fq 'termux-setup-storage' "$README"
grep -Fq 'Recomendado' "$README"

grep -Fq 'pacote_instalado_ou_funcional()' "$TERMUX_PACKAGES_ACTIONS"
grep -Fq 'mostrar_ferramentas_instaladas()' "$TERMUX_TOOLS"
grep -Fq 'menu_detalhe_ambiente_dev()' "$TERMUX_TOOLS"
grep -Fq 'ambiente_dev_status()' "$TERMUX_TOOLS"
grep -Fq 'Instalar o que falta' "$TERMUX_TOOLS"
grep -Fq 'Todas as ferramentas' "$TERMUX_TOOLS"

# Um comando funcional fornecido por outro pacote/versão deve ser aceito como disponível.
(
    set -u
    TMPROOT="/tmp/painel-test-dev-tools-$$"
    trap 'rm -rf "$TMPROOT"' EXIT
    mkdir -p "$TMPROOT/bin" "$TMPROOT/logs"
    cat > "$TMPROOT/bin/node" <<'EOF'
#!/bin/sh
exit 0
EOF
    cat > "$TMPROOT/bin/npm" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$TMPROOT/bin/node" "$TMPROOT/bin/npm"
    PATH="$TMPROOT/bin:$PATH"
    PAINEL_DIR="$TMPROOT/painel"
    LOG_DIR="$TMPROOT/logs"
    HOME="$TMPROOT/home"
    PREFIX="$TMPROOT/prefix"
    source "$TERMUX"
    pacote_ja_funcional nodejs
    ambiente_dev_contar web
    [ "$AMB_DEV_TOTAL" -ge 1 ]
)

echo "OK: painel de ambientes, versões reais e instalador unificado estão presentes."
