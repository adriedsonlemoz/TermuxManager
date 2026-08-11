#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/modules/config.sh"
source "$ROOT_DIR/modules/ui.sh"
C_RESET=''; C_CYAN=''; C_BOLD=''; C_WHITE=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''
ui_buffer_flush(){ :; }
LARGURA_CAIXA=40
out="$(
  ui_live_box_begin 'Teste' 'largura fixa'
  LARGURA_CAIXA=28
  ui_live_box_message '' '➜' 'curto'
  ui_live_box_message '' '➜' 'uma mensagem um pouco maior que a anterior'
  ui_live_box_end
)"
# Todas as linhas de moldura/conteúdo devem conservar 40 colunas visíveis.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  # remove ANSI, se houver, e conta caracteres; neste teste não há emojis de largura 2 na borda.
  clean="$(strip_ansi "$line")"
  case "$clean" in
    ╭*|├*|╰*|│*)
      vis="$(largura_visivel "$clean")"
      [ "$vis" -eq 40 ] || { printf 'Linha com largura %s, esperado 40: %s\n' "$vis" "$clean" >&2; exit 1; }
      ;;
  esac
done <<< "$out"
echo 'OK: painel vivo mantém largura fixa durante o teste.'
