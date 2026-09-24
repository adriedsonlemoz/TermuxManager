# Módulo: projects_github.sh
# Carregador compatível da integração Git/GitHub.

PROJECTS_GITHUB_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$PROJECTS_GITHUB_MODULE_DIR/projects_github_core.sh"
# shellcheck source=/dev/null
source "$PROJECTS_GITHUB_MODULE_DIR/projects_git.sh"
# shellcheck source=/dev/null
source "$PROJECTS_GITHUB_MODULE_DIR/projects_github_project.sh"
