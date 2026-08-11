#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/modules/import.sh"

grep -q '^wizard_pos_importacao()' "$F"
grep -q '"Testar agora"' "$F"
grep -q '"Abrir menu do projeto"' "$F"
grep -q '"Importar outro projeto"' "$F"
grep -q 'testar_componente "$projeto" ambos' "$F"
grep -q 'tela_projeto "$projeto"' "$F"
# A descoberta não pode usar encontrados/encontrados no renderizador percentual.
if grep -q 'progresso_render "Analisando .*" "$encontrados" "$encontrados"' "$F"; then
  echo "FAIL: análise inicial ainda força 100%" >&2
  exit 1
fi
grep -q 'Etapa 1/2 • Descobrindo arquivos' "$F"
grep -q 'Etapa 2/2 • Calculando tamanho' "$F"
grep -q '➜ Verificando:' "$F"
echo "OK: pós-importação e progresso de análise validados"
