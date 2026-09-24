# Módulo: projects_github_project.sh
# Vínculo, branches, segurança e publicação GitHub por projeto.

github_vincular_repo_existente() {
    local projeto="$1" repo remote="origin" url branch origin_url
    garantir_ferramentas_github || return 1
    autenticar_github_manager || return 1
    preparar_repo_git_local "$projeto" || return 1
    cabecalho_tela "🔗 Vincular repositório" "Este projeto será ligado a um único repositório"
    read -rp "Repositório (usuario/nome): " repo
    [[ "$repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || { error "Use o formato usuario/repositorio."; pause; return 1; }
    if ! gh repo view "$repo" >/dev/null 2>&1; then
        error "Não encontrei '$repo' com a conta atual."
        pause
        return 1
    fi
    url="https://github.com/$repo.git"

    # Se já existe um vínculo GitHub, altera exatamente esse remote. Caso
    # origin pertença a outro provedor, preserva-o e cria/usa o remote github.
    if github_encontrar_remote_projeto "$projeto"; then
        remote="$GITHUB_REMOTE"
    else
        origin_url="$(git -C "$projeto" remote get-url origin 2>/dev/null || true)"
        if [ -n "$origin_url" ] && ! github_repo_slug_de_url "$origin_url" >/dev/null 2>&1; then
            remote="github"
        fi
    fi

    if git -C "$projeto" remote get-url "$remote" >/dev/null 2>&1; then
        caixa_simples_wrap "Remoto atual" \
            "$remote: $(git -C "$projeto" remote get-url "$remote" 2>/dev/null || true)" \
            "Novo: $repo"
        confirmar_acao "Trocar o repositório vinculado?" "n" || return 0
        git -C "$projeto" remote set-url "$remote" "$url" || return 1
    else
        git -C "$projeto" remote add "$remote" "$url" || return 1
    fi
    branch="$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || printf '%s' "${GITHUB_BRANCH_PADRAO:-main}")"
    github_meta_salvar "$projeto" "$repo" "$remote" "$branch"
    ok "Projeto vinculado a $repo."
    pause
}

github_criar_repo_para_projeto() {
    local projeto="$1"
    garantir_ferramentas_github || return 1
    autenticar_github_manager || return 1
    preparar_repo_git_local "$projeto" || return 1
    if github_remote_existente "$projeto"; then
        caixa_simples "GitHub já vinculado" "Remoto: $GITHUB_REMOTE" \
            "Use Trocar repositório se quiser substituir o vínculo atual."
        pause
        return 0
    fi
    criar_ou_conectar_repo_github "$projeto" || return 1
    github_sincronizar_vinculo_do_git "$projeto" "$GITHUB_REMOTE" || true
    ok "Repositório criado/vinculado."
    pause
}

github_remover_vinculo_projeto() {
    local projeto="$1" remote url
    if ! github_encontrar_remote_projeto "$projeto"; then
        github_meta_remover "$projeto"
        info "Não havia remoto GitHub configurado."
        pause
        return 0
    fi
    remote="$GITHUB_REMOTE"
    url="$GITHUB_REMOTE_URL"
    caixa_simples_wrap "Remover vínculo" \
        "Projeto: $(basename "$projeto")" \
        "Remoto: $remote" \
        "Destino: $url" \
        "O repositório no GitHub NÃO será apagado."
    confirmar_acao "Remover somente o vínculo GitHub local?" "n" || return 0
    git -C "$projeto" remote remove "$remote" || { error "Não foi possível remover o remoto GitHub."; pause; return 1; }
    github_meta_remover "$projeto"
    ok "Vínculo GitHub local removido."
    pause
}

github_definir_branch_projeto() {
    local projeto="$1" atual branch repo remote meta_branch
    atual="$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || true)"
    github_meta_carregar "$projeto" || true
    meta_branch="$GITHUB_META_BRANCH"
    repo="$GITHUB_META_REPO"
    remote="$GITHUB_META_REMOTE"
    read -rp "Branch padrão deste projeto [${meta_branch:-${atual:-${GITHUB_BRANCH_PADRAO:-main}}}]: " branch
    branch="${branch:-${meta_branch:-${atual:-${GITHUB_BRANCH_PADRAO:-main}}}}"
    validar_branch_git "$branch" || { error "Branch inválida."; pause; return 1; }
    if [ -z "$repo" ] && github_encontrar_remote_projeto "$projeto"; then
        repo="$GITHUB_REMOTE_REPO"
        remote="$GITHUB_REMOTE"
    fi
    if [ -n "$repo" ] && [ -n "$remote" ]; then
        github_meta_salvar "$projeto" "$repo" "$remote" "$branch"
        ok "Branch padrão do projeto: $branch."
    else
        error "Vincule primeiro este projeto a um repositório GitHub."
        pause
        return 1
    fi
    pause
}

github_repo_vinculado_tela() {
    local projeto="$1" remote="" url="" repo="" branch meta_branch=""
    projeto_git_status_resumido "$projeto"
    github_meta_carregar "$projeto" || true
    meta_branch="$GITHUB_META_BRANCH"
    if github_encontrar_remote_projeto "$projeto"; then
        remote="$GITHUB_REMOTE"
        url="$GITHUB_REMOTE_URL"
        repo="$GITHUB_REMOTE_REPO"
    fi
    branch="$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || true)"
    cabecalho_tela "🔗 Repositório vinculado" "$(basename "$projeto")"
    caixa_simples_wrap "GitHub" \
        "Repositório: ${repo:-não configurado}" \
        "Remoto: ${remote:-não configurado}" \
        "Branch atual: ${branch:-sem branch}" \
        "Branch padrão: ${meta_branch:-${GITHUB_BRANCH_PADRAO:-main}}" \
        "URL: ${url:-não configurada}"
    pause
}

github_historico_commits() {
    local projeto="$1" linhas
    cabecalho_tela "📝 Histórico de commits" "$(basename "$projeto")"
    if [ ! -d "$projeto/.git" ]; then
        caixa_simples "Sem histórico" "O projeto ainda não possui repositório Git local."
    else
        linhas="$(git -C "$projeto" log -n 12 --date=short --pretty=format:'%h • %ad • %s' 2>/dev/null || true)"
        if [ -n "$linhas" ]; then
            local -a itens=()
            while IFS= read -r linha; do [ -n "$linha" ] && itens+=("$linha"); done <<< "$linhas"
            caixa_simples_wrap "Últimos commits" "${itens[@]}"
        else
            caixa_simples "Sem commits" "Ainda não existem commits neste projeto."
        fi
    fi
    pause
}

github_selecionar_branch_local() {
    local projeto="$1" atual b i=1 escolha
    local -a branches=() opcoes=()
    atual="$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || true)"
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        branches+=("$b")
        opcoes+=("$i|🌿|$b|$([ "$b" = "$atual" ] && printf 'Atual' || printf 'Branch local')")
        i=$((i+1))
    done < <(git -C "$projeto" branch --format='%(refname:short)' 2>/dev/null || true)
    [ ${#branches[@]} -gt 0 ] || return 1
    menu_unificado "🌿 Escolher branch" "Atual: ${atual:-?}" "[0] Voltar" "${opcoes[@]}"
    ler_opcao
    escolha="$RESPOSTA_MENU"
    [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#branches[@]} ] || return 1
    GITHUB_BRANCH_ESCOLHIDA="${branches[$((escolha-1))]}"
}

menu_branches_projeto() {
    local projeto="$1" nova
    while true; do
        local atual="$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || true)"
        menu_unificado "🌿 Branches" "Atual: ${atual:-sem branch}" "[0] Voltar  •  [1–5] Selecionar" \
            "1|📋|Listar branches|Locais e remotas" \
            "2|➕|Criar branch|Nova branch local" \
            "3|↔️|Trocar branch|Selecionar uma branch local" \
            "4|⬇️|Atualizar atual|Fast-forward seguro" \
            "5|⬆️|Publicar atual|Enviar branch ao GitHub"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) listar_branches_projeto "$projeto" ;;
            2)
                read -rp "Nome da nova branch: " nova
                validar_branch_git "$nova" || { feedback_curto "Branch inválida."; continue; }
                if git -C "$projeto" switch -c "$nova" >>"$GITHUB_LOG_FILE" 2>&1; then ok "Branch '$nova' criada e ativada."; else error "Não foi possível criar a branch."; fi
                pause ;;
            3)
                if github_selecionar_branch_local "$projeto"; then
                    if git -C "$projeto" status --porcelain | grep -q .; then
                        caixa_simples "Troca bloqueada" "Existem alterações locais. Faça commit antes de trocar de branch."
                    elif git -C "$projeto" switch "$GITHUB_BRANCH_ESCOLHIDA" >>"$GITHUB_LOG_FILE" 2>&1; then
                        ok "Branch '$GITHUB_BRANCH_ESCOLHIDA' ativada."
                    else error "Não foi possível trocar a branch."; fi
                    pause
                fi ;;
            4) atualizar_projeto_git "$projeto" ;;
            5) enviar_projeto_github "$projeto" ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_config_github_projeto() {
    local projeto="$1"
    while true; do
        github_meta_carregar "$projeto" || true
        menu_unificado "⚙️ GitHub deste projeto" "${GITHUB_META_REPO:-vínculo pelo Git local}" "[0] Voltar  •  [1–5] Selecionar" \
            "1|🔗|Vincular existente|Usar usuario/repositorio" \
            "2|➕|Criar repositório|Criar pela conta conectada" \
            "3|🔁|Trocar repositório|Alterar o remote origin" \
            "4|🌿|Branch padrão|Preferência deste projeto" \
            "5|🚫|Remover vínculo|Mantém o repo no GitHub"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) github_vincular_repo_existente "$projeto" ;;
            2) github_criar_repo_para_projeto "$projeto" ;;
            3) github_vincular_repo_existente "$projeto" ;;
            4) github_definir_branch_projeto "$projeto" ;;
            5) github_remover_vinculo_projeto "$projeto" ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

garantir_gitignore_seguro() {
    local projeto="$1"
    local arquivo="$projeto/.gitignore"
    local inicio='# >>> Termux Manager: proteção de publicação >>>'
    local fim='# <<< Termux Manager: proteção de publicação <<<'
    [ -f "$arquivo" ] && grep -Fq "$inicio" "$arquivo" 2>/dev/null && { github_log OK .gitignore "Seção de proteção já existente"; return 0; }

    if ! {
        [ -s "$arquivo" ] && printf '\n'
        printf '%s\n' "$inicio"
        cat <<'EOF'
# Dependências e builds regeneráveis
node_modules/
dist/
build/
.next/
.nuxt/
.svelte-kit/
coverage/
.cache/
.tmp/
tmp/

# Segredos e credenciais locais
.env
.env.*
!.env.example
!.env.sample
*.pem
*.key
*.p12
*.pfx
.npmrc
credentials.json
service-account*.json

# Arquivos locais do sistema/editor
.DS_Store
Thumbs.db
*.log
EOF
        if [ "$projeto" = "${PAINEL_DIR:-__painel__}" ]; then
            cat <<'EOF'

# Estado interno do Termux Manager (quando o projeto está em ~/Painel)
.manager.conf
.manager.lock/
.logs/
.pids/
.import_tmp/
backups/
projetos/
EOF
        fi
        printf '%s\n' "$fim"
    } >> "$arquivo"; then
        GITHUB_LAST_ERROR="Não foi possível gravar $(github_caminho_curto "$arquivo")."
        github_log ERROR .gitignore "$GITHUB_LAST_ERROR"
        return 1
    fi
    github_log OK .gitignore "Proteções gravadas em $(github_caminho_curto "$arquivo")"
}

verificar_segredos_rastreados_git() {
    local projeto="$1" perigosos=""
    [ -d "$projeto/.git" ] || return 0
    perigosos=$(git -C "$projeto" ls-files 2>>"$GITHUB_LOG_FILE" | grep -E '(^|/)(\.env($|\.)|\.npmrc$|credentials\.json$|service-account[^/]*\.json$)|\.(pem|key|p12|pfx)$' || true)
    [ -z "$perigosos" ] && { github_log OK segurança "Nenhum segredo rastreado detectado"; return 0; }

    github_log ERROR segurança "Arquivos sensíveis rastreados: $(printf '%s' "$perigosos" | tr '\n' ' ')"
    cabecalho_tela "⚠️ Publicação bloqueada" "Arquivos sensíveis já estão sendo rastreados pelo Git"
    caixa_simples "Proteção de credenciais" \
        "O .gitignore não remove arquivos que já foram adicionados anteriormente." \
        "Remova-os do índice antes de enviar ao GitHub." \
        "Detectados: $(printf '%s' "$perigosos" | tr '\n' ' ' | cut -c1-160)"
    info "Exemplo: git rm --cached caminho-do-arquivo"
    pause
    return 1
}

configurar_identidade_git_github() {
    local projeto="$1" login id nome email
    if [ -n "$(git -C "$projeto" config user.name 2>/dev/null || true)" ] && \
       [ -n "$(git -C "$projeto" config user.email 2>/dev/null || true)" ]; then
        github_log OK identidade "Identidade Git local já configurada"
        return 0
    fi

    # A identidade é necessária para commit, não para inicializar o repositório.
    login=$(gh api user --jq '.login' 2>>"$GITHUB_LOG_FILE" || true)
    id=$(gh api user --jq '.id' 2>>"$GITHUB_LOG_FILE" || true)
    nome=$(gh api user --jq '.name // .login' 2>>"$GITHUB_LOG_FILE" || true)
    if [ -z "$login" ]; then
        GITHUB_LAST_ERROR="Não foi possível obter a identidade da conta com 'gh api user'."
        github_log ERROR identidade "$GITHUB_LAST_ERROR"
        return 1
    fi
    [ -n "$nome" ] || nome="$login"
    if [[ "$id" =~ ^[0-9]+$ ]]; then
        email="${id}+${login}@users.noreply.github.com"
    else
        email="${login}@users.noreply.github.com"
    fi
    if ! github_run "identidade/user.name" git -C "$projeto" config user.name "$nome"; then return 1; fi
    if ! github_run "identidade/user.email" git -C "$projeto" config user.email "$email"; then return 1; fi
    return 0
}

github_remote_existente() {
    local projeto="$1"
    if github_encontrar_remote_projeto "$projeto"; then
        github_log OK remoto "GitHub configurado em '$GITHUB_REMOTE' ($GITHUB_REMOTE_REPO)"
        return 0
    fi
    github_log INFO remoto "Nenhum remote GitHub encontrado"
    return 1
}

preparar_repo_git_local() {
    local projeto="$1"
    cabecalho_tela "🐙 Preparando GitHub" "Verificação do repositório local"
    if [ ! -d "$projeto/.git" ]; then
        info "Inicializando repositório Git local..."
        if ! github_run "git init" git -C "$projeto" init; then
            github_mostrar_falha "Não foi possível iniciar o Git" "git init"
            return 1
        fi
        ok "Repositório Git local inicializado."
        if github_run "branch principal" git -C "$projeto" branch -M "${GITHUB_BRANCH_PADRAO:-main}"; then
            ok "Branch principal preparada: ${GITHUB_BRANCH_PADRAO:-main}."
        else
            warn "Não foi possível renomear a branch agora; o envio continuará usando a branch atual."
        fi
    else
        ok "Repositório Git local já existe."
        github_log OK "git init" "Repositório já existente"
    fi

    info "Verificando proteção do .gitignore..."
    if ! garantir_gitignore_seguro "$projeto"; then
        github_mostrar_falha "Não foi possível preparar o .gitignore" ".gitignore"
        return 1
    fi
    ok ".gitignore preparado."

    if ! verificar_segredos_rastreados_git "$projeto"; then
        return 1
    fi
    ok "Verificação de segurança concluída."
    # Não configura identidade aqui: ela só é exigida quando houver commit.
    return 0
}

criar_ou_conectar_repo_github() {
    local projeto="$1" login nome_padrao nome_repo vis resposta remoto="origin" url
    login=$(gh api user --jq '.login' 2>>"$GITHUB_LOG_FILE" || true)
    if [ -z "$login" ]; then
        GITHUB_LAST_ERROR="Não foi possível consultar o usuário autenticado no GitHub."
        github_log ERROR repositório "$GITHUB_LAST_ERROR"
        github_mostrar_falha "Não foi possível identificar sua conta" "Consulta da conta GitHub" "$GITHUB_LAST_ERROR"
        return 1
    fi
    nome_padrao=$(normalizar_nome_repo_github "$(basename "$projeto")")

    cabecalho_tela "🐙 Primeira publicação" "Crie ou conecte o projeto ao GitHub"
    read -rp "Nome do repositório [$nome_padrao]: " nome_repo
    nome_repo=$(normalizar_nome_repo_github "${nome_repo:-$nome_padrao}")

    menu_unificado "🔒 Visibilidade" "Privado é a opção mais segura para começar" "[Enter/1] Privado  •  [2] Público  •  [0] Cancelar" \
        "1|🔒|Privado|Somente você e colaboradores autorizados" \
        "2|🌍|Público|Qualquer pessoa poderá visualizar o código"
    ler_opcao
    case "$RESPOSTA_MENU" in ""|1) vis="--private";; 2) vis="--public";; *) return 1;; esac

    if git -C "$projeto" remote get-url origin >/dev/null 2>>"$GITHUB_LOG_FILE"; then
        url=$(git -C "$projeto" remote get-url origin 2>>"$GITHUB_LOG_FILE" || true)
        [[ "$url" == *github.com* ]] || remoto="github"
    fi

    if gh repo view "$login/$nome_repo" >>"$GITHUB_LOG_FILE" 2>&1; then
        caixa_simples "Repositório já existe" "$login/$nome_repo" \
            "O Manager pode conectar este projeto local ao repositório existente."
        read -rp "Conectar? [S/n]: " resposta
        case "${resposta,,}" in n|nao|não) return 1;; esac
        if git -C "$projeto" remote get-url "$remoto" >/dev/null 2>>"$GITHUB_LOG_FILE"; then
            github_run "remote/set-url" git -C "$projeto" remote set-url "$remoto" "https://github.com/$login/$nome_repo.git" || return 1
        else
            github_run "remote/add" git -C "$projeto" remote add "$remoto" "https://github.com/$login/$nome_repo.git" || return 1
        fi
        GITHUB_REMOTE="$remoto"
        github_meta_salvar "$projeto" "$login/$nome_repo" "$remoto" "$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || printf '%s' "${GITHUB_BRANCH_PADRAO:-main}")"
        return 0
    fi

    if ! gh repo create "$login/$nome_repo" "$vis" --source "$projeto" --remote "$remoto" 2>&1 | tee -a "$GITHUB_LOG_FILE"; then
        GITHUB_LAST_ERROR="O GitHub CLI não conseguiu criar o repositório. Consulte o log para a mensagem completa."
        github_log ERROR repositório "$GITHUB_LAST_ERROR"
        github_mostrar_falha "Não foi possível criar o repositório" "gh repo create" "$GITHUB_LAST_ERROR"
        return 1
    fi
    github_log OK repositório "Repositório $login/$nome_repo criado; remote '$remoto'"
    GITHUB_REMOTE="$remoto"
    github_meta_salvar "$projeto" "$login/$nome_repo" "$remoto" "$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || printf '%s' "${GITHUB_BRANCH_PADRAO:-main}")"
}

enviar_projeto_github() {
    local projeto="$1" mensagem branch alteracoes url
    github_log_init
    github_log INFO início "Projeto: $(caminho_curto "$projeto")"
    garantir_ferramentas_github || { warn "Envio cancelado."; pause; return; }
    autenticar_github_manager || { pause; return; }
    preparar_repo_git_local "$projeto" || { pause; return; }

    if ! github_remote_existente "$projeto"; then
        criar_ou_conectar_repo_github "$projeto" || { warn "Publicação cancelada."; pause; return; }
    fi
    github_meta_carregar "$projeto" || github_sincronizar_vinculo_do_git "$projeto" "$GITHUB_REMOTE" || true
    if ! github_validar_vinculo_push "$projeto" "$GITHUB_REMOTE"; then
        cabecalho_tela "🛑 Envio bloqueado" "Proteção de repositório por projeto"
        caixa_simples_wrap "Destino divergente"             "$GITHUB_LAST_ERROR"             "Abra Configurar projeto para corrigir o vínculo."
        pause
        return 1
    fi

    branch=$(git -C "$projeto" symbolic-ref --short HEAD 2>>"$GITHUB_LOG_FILE" || true)
    [ -n "$branch" ] || branch="${GITHUB_BRANCH_PADRAO:-main}"
    alteracoes=$(git -C "$projeto" status --porcelain 2>>"$GITHUB_LOG_FILE" || true)

    if [ -n "$alteracoes" ]; then
        local novos modificados removidos repo_destino previa
        novos="$(printf '%s\n' "$alteracoes" | awk 'substr($0,1,2)=="??"{n++} END{print n+0}')"
        removidos="$(printf '%s\n' "$alteracoes" | awk 'substr($0,1,2) ~ /D/{n++} END{print n+0}')"
        modificados="$(printf '%s\n' "$alteracoes" | awk 'substr($0,1,2)!="??" && substr($0,1,2)!~/D/{n++} END{print n+0}')"
        repo_destino="$(github_repo_slug_de_url "$(git -C "$projeto" remote get-url "$GITHUB_REMOTE" 2>/dev/null || true)" 2>/dev/null || true)"
        cabecalho_tela "⬆️ Enviar para GitHub" "Somente o projeto selecionado"
        caixa_simples_wrap "Destino confirmado"             "Projeto: $(basename "$projeto")"             "Repositório: ${repo_destino:-não identificado}"             "Branch: $branch"             "Novos: $novos • Modificados: $modificados • Removidos: $removidos"             "Total: $(printf '%s\n' "$alteracoes" | sed '/^$/d' | wc -l | tr -d ' ') arquivo(s)"
        previa="$(printf '%s\n' "$alteracoes" | sed -n '1,8p' | sed -E 's/^..[[:space:]]*/• /')"
        [ -n "$previa" ] && caixa_simples_wrap "Prévia" "$previa"
        confirmar_acao "Criar commit apenas neste projeto e enviar?" "s" || return 0
        echo
        read -rp "Mensagem do commit [Atualização pelo Termux Manager]: " mensagem
        mensagem="${mensagem:-Atualização pelo Termux Manager}"

        if ! configurar_identidade_git_github "$projeto"; then
            github_mostrar_falha "Não foi possível configurar a identidade Git" "Identidade para o commit"
            pause
            return
        fi
        if ! github_run "git add" git -C "$projeto" add -A; then
            github_mostrar_falha "Falha ao preparar arquivos para commit" "git add"
            pause
            return
        fi
        verificar_segredos_rastreados_git "$projeto" || return
        if ! git -C "$projeto" commit -m "$mensagem" 2>&1 | tee -a "$GITHUB_LOG_FILE"; then
            GITHUB_LAST_ERROR="O Git não conseguiu criar o commit. Consulte o log para o detalhe completo."
            github_log ERROR commit "$GITHUB_LAST_ERROR"
            github_mostrar_falha "Não foi possível criar o commit" "git commit" "$GITHUB_LAST_ERROR"
            pause
            return
        fi
        github_log OK commit "Commit criado"
    fi

    if git -C "$projeto" rev-parse HEAD >/dev/null 2>>"$GITHUB_LOG_FILE"; then
        github_log INFO push "Enviando branch '$branch' para '$GITHUB_REMOTE'"
        if ! git -C "$projeto" push -u "$GITHUB_REMOTE" "$branch" 2>&1 | tee -a "$GITHUB_LOG_FILE"; then
            github_log ERROR push "GitHub recusou ou não concluiu o push"
            cabecalho_tela "⚠️ GitHub não aceitou o envio" "O repositório remoto pode ter alterações mais novas"
            caixa_simples "Nada foi apagado" \
                "Se o GitHub já possui commits, sincronize antes de tentar novamente." \
                "O Manager não força push automaticamente para proteger o histórico." \
                "Log: $(github_caminho_curto "$GITHUB_LOG_FILE")"
            info "Sugestão: git -C $(caminho_curto "$projeto") pull --rebase $GITHUB_REMOTE $branch"
            pause
            return
        fi
        github_log OK push "Push concluído"
    else
        warn "Não há commit para enviar."
        github_log INFO push "Nenhum commit existente"
        pause
        return
    fi

    url=$(git -C "$projeto" remote get-url "$GITHUB_REMOTE" 2>>"$GITHUB_LOG_FILE" || true)
    url=${url%.git}
    url=${url/git@github.com:/https:\/\/github.com\/}
    cabecalho_tela "✅ Enviado para o GitHub" "Publicação concluída"
    caixa_simples "Repositório" "${url:-GitHub}" "Branch: $branch" \
        "$([ -n "$alteracoes" ] && printf 'Novo commit enviado.' || printf 'Sem alterações locais; commits pendentes enviados.')" \
        "Log: $(github_caminho_curto "$GITHUB_LOG_FILE")"
    pause
}
