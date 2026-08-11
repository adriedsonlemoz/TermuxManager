#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
PAINEL_DIR="$HOME/Painel"
PROJETOS_DIR="$PAINEL_DIR/projetos"
mkdir -p "$PROJETOS_DIR/minha-pasta"
cat > "$PROJETOS_DIR/minha-pasta/package.json" <<'JSON'
{"name":"nome-tecnico-package","dependencies":{"vite":"latest"}}
JSON
comando_existe(){ command -v "$1" >/dev/null 2>&1; }
# shellcheck source=/dev/null
source "$ROOT_DIR/modules/projects.sh"
projeto="$PROJETOS_DIR/minha-pasta"
nome_amigavel_projeto "$projeto"
[ "$NOME_PROJETO" = "minha-pasta" ]
[ "$PROJETO_TEM_APELIDO" = false ]
nome_package_projeto "$projeto"
[ "$NOME_PACKAGE_PROJETO" = "nome-tecnico-package" ]
salvar_apelido_projeto "$projeto" "AL Sistemas"
nome_amigavel_projeto "$projeto"
[ "$NOME_PROJETO" = "AL Sistemas" ]
[ "$PROJETO_TEM_APELIDO" = true ]
[ -d "$HOME/.termux-manager/projects" ]
[ ! -e "$projeto/.manager.json" ]
salvar_apelido_projeto "$projeto" ""
nome_amigavel_projeto "$projeto"
[ "$NOME_PROJETO" = "minha-pasta" ]
echo "PASS: nome da pasta, package separado e apelido externo funcionando."
