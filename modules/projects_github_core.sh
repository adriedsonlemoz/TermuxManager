# Módulo: projects_github_core.sh
# Infraestrutura, autenticação, metadados e Central GitHub global.

GITHUB_LOG_DIR="$HOME/.termux-manager/logs"
GITHUB_LOG_FILE="$GITHUB_LOG_DIR/github.log"
GITHUB_LAST_ERROR=""

normalizar_nome_repo_github() {
    local nome="${1:-projeto}"
    nome=$(printf '%s' "$nome" | tr '[:upper:]' '[:lower:]' | \
        sed -E 's/[[:space:]]+/-/g; s/[^a-z0-9._-]+/-/g; s/-+/-/g; s/^[._-]+//; s/[._-]+$//')
    [ -n "$nome" ] || nome="projeto"
    printf '%s' "$nome"
}

github_caminho_curto() {
    local caminho="${1:-}"
    if declare -F caminho_curto >/dev/null 2>&1; then
        caminho_curto "$caminho"
    elif [ -n "${HOME:-}" ] && [[ "$caminho" == "$HOME"* ]]; then
        printf '~%s' "${caminho#"$HOME"}"
    else
        printf '%s' "$caminho"
    fi
}

github_log_init() {
    mkdir -p "$GITHUB_LOG_DIR" 2>/dev/null || true
    touch "$GITHUB_LOG_FILE" 2>/dev/null || true
    {
        printf '\n============================================================\n'
        printf '[%s] Nova operação GitHub — Manager %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${MANAGER_VERSION:-?}"
    } >> "$GITHUB_LOG_FILE" 2>/dev/null || true
}

github_redigir_stream() {
    if declare -F redigir_segredos >/dev/null 2>&1; then
        redigir_segredos
    else
        cat
    fi
}

github_redigir_texto() {
    printf '%s' "${1:-}" | github_redigir_stream | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

github_log() {
    local nivel="$1" etapa="$2" mensagem="${3:-}"
    mkdir -p "$GITHUB_LOG_DIR" 2>/dev/null || true
    mensagem="$(github_redigir_texto "$mensagem")"
    printf '[%s] [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$nivel" "$etapa" "$mensagem" >> "$GITHUB_LOG_FILE" 2>/dev/null || true
}

# Executa um comando preservando stderr/stdout no log específico e devolve o
# erro real em GITHUB_LAST_ERROR. Não registra tokens nem variáveis de ambiente.
github_run() {
    local etapa="$1"; shift
    local tmp rc cmd
    mkdir -p "$GITHUB_LOG_DIR" 2>/dev/null || true
    tmp=$(mktemp "${TMPDIR:-/tmp}/termux-manager-gh.XXXXXX" 2>/dev/null || printf '%s' "$GITHUB_LOG_DIR/.gh-$$.tmp")
    cmd=$(printf '%q ' "$@")
    github_log INFO "$etapa" "Comando: ${cmd% }"
    "$@" >"$tmp" 2>&1
    rc=$?
    if [ -s "$tmp" ]; then
        github_redigir_stream < "$tmp" | sed 's/^/    /' >> "$GITHUB_LOG_FILE" 2>/dev/null || true
    fi
    if [ "$rc" -eq 0 ]; then
        github_log OK "$etapa" "Concluído"
        GITHUB_LAST_ERROR=""
    else
        GITHUB_LAST_ERROR=$(tail -n 8 "$tmp" 2>/dev/null | github_redigir_stream | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
        [ -n "$GITHUB_LAST_ERROR" ] || GITHUB_LAST_ERROR="Comando terminou com código $rc."
        github_log ERROR "$etapa" "Código $rc — $GITHUB_LAST_ERROR"
    fi
    rm -f "$tmp" 2>/dev/null || true
    return "$rc"
}

github_mostrar_falha() {
    local titulo="$1" etapa="$2" detalhe="${3:-$GITHUB_LAST_ERROR}"
    cabecalho_tela "❌ $titulo" "Falha detectada durante a integração com GitHub"
    caixa_simples "Etapa" "$etapa" \
        "Detalhe: ${detalhe:-erro não informado pela ferramenta}" \
        "Log: $(github_caminho_curto "$GITHUB_LOG_FILE")"
    github_log ERROR "$etapa" "Exibido ao usuário: ${detalhe:-sem detalhe}"
}

garantir_ferramentas_github() {
    local faltando=()
    comando_existe git || faltando+=(git)
    comando_existe gh || faltando+=(gh)
    [ ${#faltando[@]} -eq 0 ] && { github_log OK ferramentas "git e gh disponíveis"; return 0; }

    cabecalho_tela "🐙 Preparando GitHub" "Instalação automática das ferramentas necessárias"
    caixa_simples "Ferramentas ausentes" "${faltando[*]}" \
        "O Manager pode instalar automaticamente pelo pkg do Termux."
    read -rp "Instalar agora? [S/n]: " resposta
    case "${resposta,,}" in n|nao|não) github_log INFO ferramentas "Instalação cancelada pelo usuário"; return 1;; esac
    instalar_pkg_termux "${faltando[@]}" || { github_log ERROR ferramentas "pkg não conseguiu instalar: ${faltando[*]}"; return 1; }
    if comando_existe git && comando_existe gh; then
        github_log OK ferramentas "Ferramentas instaladas"
        return 0
    fi
    github_log ERROR ferramentas "Ferramentas continuam indisponíveis após instalação"
    return 1
}

autenticar_github_manager() {
    if github_run "autenticação/status" gh auth status --hostname github.com; then
        github_run "autenticação/setup-git" gh auth setup-git || true
        return 0
    fi

    cabecalho_tela "🔐 Conectar ao GitHub" "Login necessário somente na primeira vez"
    caixa_simples "Login assistido" \
        "O GitHub CLI abrirá o fluxo oficial de autenticação." \
        "Use HTTPS; sua senha do GitHub não é armazenada pelo Manager."
    echo
    github_log INFO autenticação "Iniciando gh auth login"
    if ! gh auth login --hostname github.com --git-protocol https --web 2>&1 | tee -a "$GITHUB_LOG_FILE"; then
        GITHUB_LAST_ERROR="O GitHub CLI não concluiu o login."
        github_log ERROR autenticação "$GITHUB_LAST_ERROR"
        github_mostrar_falha "Não foi possível concluir o login" "Autenticação no GitHub" "$GITHUB_LAST_ERROR"
        return 1
    fi
    github_run "autenticação/setup-git" gh auth setup-git || true
    if ! github_run "autenticação/confirmação" gh auth status --hostname github.com; then
        github_mostrar_falha "Login não confirmado" "Verificação da autenticação"
        return 1
    fi
    return 0
}


# ---------------------------------------------------------------------------
# GitHub global + vínculo seguro por projeto
# ---------------------------------------------------------------------------
GITHUB_META_DIR="${PAINEL_DIR:-$HOME/Painel}/.github-projects"
GITHUB_META_REPO=""
GITHUB_META_REMOTE=""
GITHUB_META_BRANCH=""
GITHUB_ACCOUNT=""

validar_branch_git() {
    [[ "${1:-}" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "${1:-}" != -* ]] && [[ "${1:-}" != */ ]] && [[ "${1:-}" != /* ]]
}

github_repo_slug_de_url() {
    local url="${1:-}" slug
    url="${url%.git}"
    case "$url" in
        git@github.com:*) slug="${url#git@github.com:}" ;;
        ssh://git@github.com/*) slug="${url#ssh://git@github.com/}" ;;
        https://github.com/*) slug="${url#https://github.com/}" ;;
        http://github.com/*) slug="${url#http://github.com/}" ;;
        *) return 1 ;;
    esac
    slug="${slug#/}"
    [[ "$slug" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || return 1
    printf '%s' "$slug"
}

github_projeto_chave() {
    local projeto="$1" caminho
    caminho="$(realpath -m "$projeto" 2>/dev/null || printf '%s' "$projeto")"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$caminho" | sha256sum | awk '{print substr($1,1,20)}'
    else
        printf '%s' "$caminho" | cksum | awk '{print $1}'
    fi
}

github_meta_arquivo() {
    mkdir -p "$GITHUB_META_DIR" 2>/dev/null || true
    printf '%s/%s.conf' "$GITHUB_META_DIR" "$(github_projeto_chave "$1")"
}

github_meta_carregar() {
    local projeto="$1" arquivo linha chave valor
    GITHUB_META_REPO=""; GITHUB_META_REMOTE=""; GITHUB_META_BRANCH=""
    arquivo="$(github_meta_arquivo "$projeto")"
    [ -f "$arquivo" ] || return 1
    while IFS= read -r linha || [ -n "$linha" ]; do
        chave="${linha%%=*}"; valor="${linha#*=}"
        case "$chave" in
            REPO) GITHUB_META_REPO="$valor" ;;
            REMOTE) GITHUB_META_REMOTE="$valor" ;;
            BRANCH) GITHUB_META_BRANCH="$valor" ;;
        esac
    done < "$arquivo"
    return 0
}

github_meta_salvar() {
    local projeto="$1" repo="$2" remote="${3:-origin}" branch="${4:-${GITHUB_BRANCH_PADRAO:-main}}" arquivo
    mkdir -p "$GITHUB_META_DIR" 2>/dev/null || true
    arquivo="$(github_meta_arquivo "$projeto")"
    {
        printf 'REPO=%s\n' "$repo"
        printf 'REMOTE=%s\n' "$remote"
        printf 'BRANCH=%s\n' "$branch"
    } > "$arquivo"
}

github_meta_remover() {
    rm -f -- "$(github_meta_arquivo "$1")" 2>/dev/null || true
}

github_sincronizar_vinculo_do_git() {
    local projeto="$1" remote="${2:-}" url repo branch
    [ -d "$projeto/.git" ] || return 1
    if [ -z "$remote" ]; then
        if declare -F github_encontrar_remote_projeto >/dev/null 2>&1 && github_encontrar_remote_projeto "$projeto"; then
            remote="$GITHUB_REMOTE"
        else
            remote="origin"
            git -C "$projeto" remote get-url "$remote" >/dev/null 2>&1 || remote="$(git -C "$projeto" remote 2>/dev/null | head -n1 || true)"
        fi
    fi
    [ -n "$remote" ] || return 1
    url="$(git -C "$projeto" remote get-url "$remote" 2>/dev/null || true)"
    repo="$(github_repo_slug_de_url "$url" 2>/dev/null || true)"
    [ -n "$repo" ] || return 1
    branch="$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || true)"
    github_meta_salvar "$projeto" "$repo" "$remote" "${branch:-${GITHUB_BRANCH_PADRAO:-main}}"
    return 0
}

github_validar_vinculo_push() {
    local projeto="$1" remote="${2:-origin}" url repo
    url="$(git -C "$projeto" remote get-url "$remote" 2>/dev/null || true)"
    repo="$(github_repo_slug_de_url "$url" 2>/dev/null || true)"
    if [ -z "$repo" ]; then
        GITHUB_LAST_ERROR="O remoto '$remote' não aponta para um repositório GitHub reconhecido."
        return 1
    fi
    if github_meta_carregar "$projeto"; then
        if [ -n "$GITHUB_META_REPO" ] && [ "$GITHUB_META_REPO" != "$repo" ]; then
            GITHUB_LAST_ERROR="Proteção ativada: o projeto está registrado como '$GITHUB_META_REPO', mas o remoto atual aponta para '$repo'."
            return 1
        fi
    else
        github_meta_salvar "$projeto" "$repo" "$remote" "$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || printf '%s' "${GITHUB_BRANCH_PADRAO:-main}")"
    fi
    return 0
}

# Resolve o remoto GitHub correto de um projeto. O vínculo salvo pelo Manager
# tem prioridade sobre "origin", porque origin pode apontar para outro provedor.
github_encontrar_remote_projeto() {
    local projeto="$1" remoto url repo meta_repo="" meta_remote=""
    GITHUB_REMOTE=""; GITHUB_REMOTE_URL=""; GITHUB_REMOTE_REPO=""
    [ -d "$projeto/.git" ] || return 1

    if github_meta_carregar "$projeto"; then
        meta_repo="$GITHUB_META_REPO"
        meta_remote="$GITHUB_META_REMOTE"
    fi

    if [ -n "$meta_remote" ]; then
        url="$(git -C "$projeto" remote get-url "$meta_remote" 2>/dev/null || true)"
        repo="$(github_repo_slug_de_url "$url" 2>/dev/null || true)"
        if [ -n "$repo" ] && { [ -z "$meta_repo" ] || [ "$repo" = "$meta_repo" ]; }; then
            GITHUB_REMOTE="$meta_remote"; GITHUB_REMOTE_URL="$url"; GITHUB_REMOTE_REPO="$repo"
            return 0
        fi
    fi

    if [ -n "$meta_repo" ]; then
        while IFS= read -r remoto; do
            [ -n "$remoto" ] || continue
            url="$(git -C "$projeto" remote get-url "$remoto" 2>/dev/null || true)"
            repo="$(github_repo_slug_de_url "$url" 2>/dev/null || true)"
            if [ "$repo" = "$meta_repo" ]; then
                GITHUB_REMOTE="$remoto"; GITHUB_REMOTE_URL="$url"; GITHUB_REMOTE_REPO="$repo"
                return 0
            fi
        done < <(git -C "$projeto" remote 2>/dev/null || true)
    fi

    url="$(git -C "$projeto" remote get-url origin 2>/dev/null || true)"
    repo="$(github_repo_slug_de_url "$url" 2>/dev/null || true)"
    if [ -n "$repo" ]; then
        GITHUB_REMOTE="origin"; GITHUB_REMOTE_URL="$url"; GITHUB_REMOTE_REPO="$repo"
        return 0
    fi

    while IFS= read -r remoto; do
        [ -n "$remoto" ] || continue
        url="$(git -C "$projeto" remote get-url "$remoto" 2>/dev/null || true)"
        repo="$(github_repo_slug_de_url "$url" 2>/dev/null || true)"
        if [ -n "$repo" ]; then
            GITHUB_REMOTE="$remoto"; GITHUB_REMOTE_URL="$url"; GITHUB_REMOTE_REPO="$repo"
            return 0
        fi
    done < <(git -C "$projeto" remote 2>/dev/null || true)
    return 1
}

github_status_conta() {
    GITHUB_ACCOUNT=""
    command -v gh >/dev/null 2>&1 || { printf 'gh não instalado'; return; }
    if gh auth status --hostname github.com >/dev/null 2>&1; then
        GITHUB_ACCOUNT="$(gh api user --jq '.login' 2>/dev/null || true)"
        printf 'Conectado%s' "$([ -n "$GITHUB_ACCOUNT" ] && printf ': %s' "$GITHUB_ACCOUNT")"
    else
        printf 'Não conectado'
    fi
}

github_configurar_identidade_global() {
    local atual_nome atual_email login id sugestao_nome sugestao_email nome email
    garantir_ferramentas_github || { pause; return 1; }
    atual_nome="$(git config --global user.name 2>/dev/null || true)"
    atual_email="$(git config --global user.email 2>/dev/null || true)"
    login="$(gh api user --jq '.login' 2>/dev/null || true)"
    id="$(gh api user --jq '.id' 2>/dev/null || true)"
    sugestao_nome="$(gh api user --jq '.name // .login' 2>/dev/null || true)"
    [ -n "$sugestao_nome" ] || sugestao_nome="${login:-$atual_nome}"
    if [[ "$id" =~ ^[0-9]+$ ]] && [ -n "$login" ]; then
        sugestao_email="${id}+${login}@users.noreply.github.com"
    elif [ -n "$login" ]; then
        sugestao_email="${login}@users.noreply.github.com"
    else
        sugestao_email="$atual_email"
    fi
    cabecalho_tela "✍️ Identidade Git" "Usada por padrão em todos os projetos"
    caixa_simples_wrap "Atual" \
        "Nome: ${atual_nome:-não configurado}" \
        "E-mail: ${atual_email:-não configurado}"
    read -rp "Nome [${sugestao_nome:-$atual_nome}]: " nome
    nome="${nome:-${sugestao_nome:-$atual_nome}}"
    read -rp "E-mail [${sugestao_email:-$atual_email}]: " email
    email="${email:-${sugestao_email:-$atual_email}}"
    [ -n "$nome" ] && git config --global user.name "$nome"
    [ -n "$email" ] && git config --global user.email "$email"
    ok "Identidade Git global atualizada."
    pause
}

github_definir_branch_padrao() {
    local atual="${GITHUB_BRANCH_PADRAO:-main}" branch
    cabecalho_tela "🌿 Branch padrão" "Usada ao preparar novos projetos"
    caixa_simples "Configuração atual" "Branch padrão: $atual"
    read -rp "Nova branch [$atual]: " branch
    branch="${branch:-$atual}"
    if ! validar_branch_git "$branch"; then
        error "Nome de branch inválido."
        pause
        return 1
    fi
    GITHUB_BRANCH_PADRAO="$branch"
    salvar_config
    ok "Branch padrão definida como '$branch'."
    pause
}

github_testar_conexao() {
    garantir_ferramentas_github || { pause; return 1; }
    cabecalho_tela "🧪 Testar GitHub" "Conta, API e autenticação Git"
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        caixa_simples "❌ Não conectado" "Use Conectar conta antes de testar."
        pause
        return 1
    fi
    local login api="falhou" git_auth="não configurado"
    login="$(gh api user --jq '.login' 2>/dev/null || true)"
    gh api rate_limit >/dev/null 2>&1 && api="OK"
    gh auth setup-git >/dev/null 2>&1 && git_auth="OK"
    caixa_simples "Resultado" \
        "Conta: ${login:-não identificada}" \
        "API GitHub: $api" \
        "Autenticação Git: $git_auth" \
        "Branch padrão: ${GITHUB_BRANCH_PADRAO:-main}"
    pause
}

github_conta_atual_tela() {
    local status nome email login
    status="$(github_status_conta)"
    nome="$(git config --global user.name 2>/dev/null || true)"
    email="$(git config --global user.email 2>/dev/null || true)"
    login="$(gh api user --jq '.login' 2>/dev/null || true)"
    cabecalho_tela "👤 Conta GitHub" "Configuração global do Manager"
    caixa_simples_wrap "Estado" \
        "GitHub CLI: $status" \
        "Usuário: ${login:-não identificado}" \
        "Git nome: ${nome:-não configurado}" \
        "Git e-mail: ${email:-não configurado}" \
        "Branch padrão: ${GITHUB_BRANCH_PADRAO:-main}"
    pause
}

github_desconectar_conta() {
    command -v gh >/dev/null 2>&1 || { warn "GitHub CLI não está instalado."; pause; return; }
    gh auth status --hostname github.com >/dev/null 2>&1 || { info "Nenhuma conta GitHub conectada."; pause; return; }
    confirmar_acao "Desconectar a conta GitHub deste Termux?" "n" || return 0
    if gh auth logout --hostname github.com </dev/null >>"$GITHUB_LOG_FILE" 2>&1; then
        ok "Conta GitHub desconectada."
    else
        error "Não foi possível desconectar automaticamente."
    fi
    pause
}

github_meus_repositorios() {
    local entrada projeto i=1 repo estado branch
    local -a itens=() projetos=()
    descobrir_entradas
    for entrada in "${PROJETOS_ENCONTRADOS[@]}"; do
        projeto="${entrada%%|*}"
        projetos+=("$projeto")
        projeto_git_status_resumido "$projeto"
        repo=""
        [ -n "${PROJ_GIT_REMOTE:-}" ] && repo="$(github_repo_slug_de_url "$PROJ_GIT_REMOTE" 2>/dev/null || true)"
        if [ "$PROJ_GIT_REPO" != true ]; then
            estado="Git não iniciado"
        elif [ -z "$repo" ]; then
            estado="GitHub não vinculado"
        elif [ "${PROJ_GIT_CHANGES:-0}" -gt 0 ] 2>/dev/null; then
            estado="$repo • ${PROJ_GIT_CHANGES} alt."
        else
            estado="$repo • árvore local limpa"
        fi
        nome_amigavel_projeto "$projeto"
        itens+=("$i|📦|$NOME_PROJETO|$estado")
        i=$((i+1))
    done
    if [ ${#itens[@]} -eq 0 ]; then
        cabecalho_tela "🌐 Meus repositórios" "Projetos do Manager"
        caixa_simples "Lista vazia" "Nenhum projeto foi encontrado no Painel."
        pause
        return 0
    fi
    menu_unificado "🌐 MEUS REPOSITÓRIOS" "${#itens[@]} projeto(s)" \
        "[0] Voltar  •  [número] Abrir Git/GitHub" "${itens[@]}"
    ler_opcao
    if [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] && [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#projetos[@]} ]; then
        menu_git_projeto "${projetos[$((RESPOSTA_MENU-1))]}"
    fi
}

menu_github_global() {
    local status
    github_log_init
    while true; do
        status="$(github_status_conta)"
        menu_unificado "🐙 GITHUB" "$status" "[0] Voltar  •  [1–8] Selecionar" \
            "1|🔐|Conectar conta|Login oficial pelo GitHub CLI" \
            "2|👤|Conta atual|Usuário e identidade Git" \
            "3|✍️|Nome e e-mail|Identidade global dos commits" \
            "4|✅|Verificar autenticação|Confirmar sessão do GitHub" \
            "5|🌿|Branch padrão|Atual: ${GITHUB_BRANCH_PADRAO:-main}" \
            "6|🧪|Testar conexão|API e autenticação Git" \
            "7|🌐|Meus repositórios|Projetos e vínculos GitHub" \
            "8|🚪|Desconectar|Remover login deste Termux"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) garantir_ferramentas_github && autenticar_github_manager; pause ;;
            2) github_conta_atual_tela ;;
            3) github_configurar_identidade_global ;;
            4) autenticar_github_manager; pause ;;
            5) github_definir_branch_padrao ;;
            6) github_testar_conexao ;;
            7) github_meus_repositorios ;;
            8) github_desconectar_conta ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
