#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/modules/config.sh"
source "$ROOT_DIR/modules/ui.sh"

C_RESET=''; C_CYAN=''; C_BOLD=''; C_WHITE=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''
ICONES_ATIVADOS=true
DESCRICOES_ATIVADAS=true

# Emojis presentes na UI que antes não faziam parte da tabela de largura.
# Cada um ocupa duas colunas no Termux/Android e não pode deslocar a borda.
for icone in 🚪 🌍 🆕 🛠 📱 🔒; do
    [ "$(largura_visivel "$icone")" -eq 2 ] || {
        printf 'FAIL: largura visível incorreta para %s: %s\n' "$icone" "$(largura_visivel "$icone")" >&2
        exit 1
    }
done

# Simula um menu sendo aberto depois de a largura disponível ter mudado.
# menu_unificado precisa recalcular a largura ANTES de montar seu buffer.
LARGURA_CAIXA=70
tput() { [ "${1:-}" = cols ] && printf '42\n'; }
stty() { [ "${1:-}" = size ] && printf '24 42\n' || return 0; }
tela_limpar() { detectar_terminal; }
ui_buffer_flush() { :; }

out="$(menu_unificado \
    'Aplicar alterações' \
    'Reinício do shell recomendado' \
    '[1] Reiniciar  •  [2] Continuar  •  [0] Sair' \
    '1|↩|Reiniciar o shell agora|Aplicar todas as alterações' \
    '2|▶️|Continuar para o Manager|Aplicar depois' \
    '0|🚪|Sair sem reiniciar|Voltar ao terminal atual')"

while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
        ╭*|╰*|│*)
            vis="$(largura_visivel "$line")"
            [ "$vis" -eq 40 ] || {
                printf 'FAIL: linha de caixa com %s colunas; esperado 40: %s\n' "$vis" "$line" >&2
                exit 1
            }
            ;;
    esac
done <<< "$out"

# Mensagens informativas da atualização devem ficar dentro das caixas, e não
# ser impressas como texto solto abaixo delas.
! grep -Fq "printf '\\nLog completo:" "$ROOT_DIR/modules/termux_packages_actions.sh"
! grep -Fq "printf '\\nProsseguindo automaticamente" "$ROOT_DIR/modules/termux_packages_actions.sh"
grep -Fq '"Log completo: $(caminho_curto "$TERMUX_SETUP_LOG")"' "$ROOT_DIR/modules/termux_packages_actions.sh"
grep -Fq '"Prosseguindo automaticamente em 3 segundos..."' "$ROOT_DIR/modules/termux_packages_actions.sh"

echo 'PASS: textos, emojis e bordas permanecem contidos nas caixas.'
