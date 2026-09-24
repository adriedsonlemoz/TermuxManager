#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/modules/config.sh"
source "$ROOT_DIR/modules/ui.sh"
C_RESET=''; C_CYAN=''; C_BOLD=''; C_WHITE=''; C_DIM=''
LARGURA_CAIXA=40
texto='Comparar com a branch main e atualizar automaticamente sem interromper o Manager'
curto="$(resumir_descricao_menu "$texto")"
[ "$(largura_visivel "$curto")" -le 32 ]
[[ "$curto" == *'…' ]]
# Não deve terminar com pedaço da palavra longa usada no fim da frase.
[[ "$curto" != *'automaticam…' ]]
out="$(menu_opcao 1 '🌐' 'Verificar no GitHub' "$texto")"
[ -n "$out" ]
echo 'OK: descrições de menu são resumidas em palavra completa e sem cortes estranhos.'
