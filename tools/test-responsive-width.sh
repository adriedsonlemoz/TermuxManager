#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/modules/config.sh"

# Mock tput/stty via functions. A terminal com 80 colunas deve produzir caixa 78,
# comprovando que não existe mais o antigo teto de 46.
tput() { [ "${1:-}" = cols ] && printf '80\n'; }
stty() { [ "${1:-}" = size ] && printf '24 80\n' || return 0; }
detectar_terminal || true
[ "$LARGURA_CAIXA" -eq 78 ] || { echo "FAIL: largura esperada 78, obtida $LARGURA_CAIXA"; exit 1; }

# Recalcula para um terminal menor sem ultrapassar o espaço disponível.
tput() { [ "${1:-}" = cols ] && printf '36\n'; }
stty() { [ "${1:-}" = size ] && printf '24 36\n' || return 0; }
detectar_terminal || true
[ "$LARGURA_CAIXA" -eq 34 ] || { echo "FAIL: largura esperada 34, obtida $LARGURA_CAIXA"; exit 1; }

echo "PASS: largura responsiva acompanha o terminal"
