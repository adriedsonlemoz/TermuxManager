# Módulo: projects_git.sh
# Estado, atualização e menus Git de um projeto. Carregado por projects_github.sh.

projeto_git_status_tela() {
    local projeto="$1" remoto_exib
    projeto_git_status_resumido "$projeto"
    nome_amigavel_projeto "$projeto"
    cabecalho_tela "🌿 Git do projeto" "$NOME_PROJETO"
    if [ "$PROJ_GIT_REPO" != true ]; then
        caixa_simples "Sem repositório Git" \
            "Este projeto ainda não possui .git." \
            "Use Enviar para GitHub para preparar e publicar."
        pause
        return 0
    fi
    remoto_exib="${PROJ_GIT_REMOTE:-não configurado}"
    caixa_simples_wrap "Estado atual" \
        "Branch: ${PROJ_GIT_BRANCH:-desconhecida}" \
        "Alterações locais: ${PROJ_GIT_CHANGES:-0}" \
        "Remoto: $remoto_exib"
    pause
}

listar_branches_projeto() {
    local projeto="$1" atual locais remotas
    cabecalho_tela "🌿 Branches" "$(basename "$projeto")"
    if [ ! -d "$projeto/.git" ] || ! comando_existe git; then
        caixa_simples "Git não preparado" "Este projeto ainda não possui branches."
        pause
        return 0
    fi
    atual="$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || true)"
    locais="$(git -C "$projeto" branch --format='%(refname:short)' 2>/dev/null || true)"
    remotas="$(git -C "$projeto" branch -r --format='%(refname:short)' 2>/dev/null | grep -v '/HEAD$' || true)"
    if [ -z "$locais" ]; then
        caixa_simples "Branches locais" "Nenhuma branch local disponível."
    else
        local -a itens=(); local b
        while IFS= read -r b; do
            [ -n "$b" ] || continue
            if [ "$b" = "$atual" ]; then itens+=("● $b (atual)"); else itens+=("○ $b"); fi
        done <<< "$locais"
        caixa_simples_wrap "Branches locais" "${itens[@]}"
    fi
    if [ -n "$remotas" ]; then
        local -a itens_remotos=(); local rb
        while IFS= read -r rb; do [ -n "$rb" ] && itens_remotos+=("↳ $rb"); done <<< "$remotas"
        caixa_simples_wrap "Branches remotas" "${itens_remotos[@]}"
    fi
    pause
}

atualizar_projeto_git() {
    local projeto="$1" remote branch alteracoes antes depois contagens ahead behind
    cabecalho_tela "⬇️ Atualizar projeto" "Sincronizar com o repositório remoto"
    if ! comando_existe git || [ ! -d "$projeto/.git" ]; then
        caixa_simples "Git não configurado" "Este projeto ainda não possui um repositório Git local."
        pause
        return 1
    fi
    branch="$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || true)"
    [ -n "$branch" ] || {
        caixa_simples "Branch indisponível" "Não foi possível identificar uma branch local ativa."
        pause
        return 1
    }
    remote=""
    if declare -F github_encontrar_remote_projeto >/dev/null 2>&1 && github_encontrar_remote_projeto "$projeto"; then
        remote="$GITHUB_REMOTE"
    else
        remote="origin"
        git -C "$projeto" remote get-url "$remote" >/dev/null 2>&1 || remote="$(git -C "$projeto" remote | head -n 1 || true)"
    fi
    if [ -z "$remote" ]; then
        caixa_simples "Sem remoto" "Nenhum repositório remoto foi configurado para este projeto."
        pause
        return 1
    fi
    local remote_url
    remote_url="$(git -C "$projeto" remote get-url "$remote" 2>/dev/null || true)"
    if [[ "$remote_url" == *github.com* ]]; then
        github_meta_carregar "$projeto" || github_sincronizar_vinculo_do_git "$projeto" "$remote" || true
        if ! github_validar_vinculo_push "$projeto" "$remote"; then
            caixa_simples_wrap "Atualização bloqueada"                 "$GITHUB_LAST_ERROR"                 "Corrija o vínculo em Git / GitHub → Configurar projeto."
            pause
            return 1
        fi
    fi
    alteracoes="$(git -C "$projeto" status --porcelain 2>/dev/null || true)"
    if [ -n "$alteracoes" ]; then
        caixa_simples_wrap "Alterações locais encontradas" \
            "Existem $(printf '%s\n' "$alteracoes" | sed '/^$/d' | wc -l | tr -d ' ') arquivo(s) alterado(s)." \
            "Para evitar perda ou conflito, o Manager não fará pull enquanto houver alterações locais." \
            "Envie/commite suas alterações primeiro ou resolva-as manualmente."
        pause
        return 1
    fi
    caixa_simples "Origem" "Remoto: $remote" "Branch: $branch" "Modo seguro: somente avanço rápido (fast-forward)"
    confirmar_acao "Buscar atualizações agora?" "s" || return 0
    antes="$(git -C "$projeto" rev-parse --short HEAD 2>/dev/null || true)"
    info "Consultando o remoto..."
    if ! git -C "$projeto" fetch "$remote" "$branch" >>"${GITHUB_LOG_FILE:-$LOG_FILE}" 2>&1; then
        error "Não foi possível consultar o remoto."
        pause
        return 1
    fi
    if ! git -C "$projeto" rev-parse "$remote/$branch" >/dev/null 2>&1; then
        caixa_simples "Branch remota ausente" "Não encontrei $remote/$branch no repositório remoto."
        pause
        return 1
    fi
    contagens="$(git -C "$projeto" rev-list --left-right --count "HEAD...$remote/$branch" 2>/dev/null || printf '0 0')"
    ahead="$(printf '%s' "$contagens" | awk '{print $1}')"
    behind="$(printf '%s' "$contagens" | awk '{print $2}')"
    if [ "${ahead:-0}" -gt 0 ] 2>/dev/null && [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
        caixa_simples_wrap "Histórico divergente" \
            "Local: ${ahead} commit(s) à frente." \
            "Remoto: ${behind} commit(s) à frente." \
            "O Manager não cria merge nem rebase automaticamente. Resolva manualmente para proteger o histórico."
        pause
        return 1
    fi
    if [ "${behind:-0}" -eq 0 ] 2>/dev/null; then
        cabecalho_tela "✅ Projeto atualizado" "$branch"
        if [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
            caixa_simples "Nada para baixar" "Seu projeto está ${ahead} commit(s) à frente do remoto." "Use Enviar para GitHub para publicar."
        else
            caixa_simples "Nada para baixar" "A branch local já está sincronizada com $remote/$branch."
        fi
        pause
        return 0
    fi
    info "Aplicando ${behind} commit(s) em modo fast-forward..."
    if ! git -C "$projeto" merge --ff-only "$remote/$branch" >>"${GITHUB_LOG_FILE:-$LOG_FILE}" 2>&1; then
        error "Não foi possível aplicar a atualização em modo seguro."
        pause
        return 1
    fi
    depois="$(git -C "$projeto" rev-parse --short HEAD 2>/dev/null || true)"
    cabecalho_tela "✅ Projeto atualizado" "$branch"
    caixa_simples "Sincronização concluída" \
        "Commit anterior: ${antes:-?}" \
        "Commit atual: ${depois:-?}" \
        "Recebidos: ${behind} commit(s)"
    pause
}

menu_git_projeto() {
    local projeto="$1"
    while true; do
        projeto_git_status_resumido "$projeto"
        menu_unificado "🌿 Git / GitHub" "${PROJ_GIT_LABEL}" "[0] Voltar  •  [1–7] Selecionar"             "1|🔎|Status do Git|Branch, alterações e remoto"             "2|⬇️|Atualizar do remoto|Somente fast-forward seguro"             "3|⬆️|Enviar para GitHub|Somente este projeto"             "4|🌿|Branches|Listar, criar e trocar"             "5|🔗|Repositório vinculado|Destino deste projeto"             "6|📝|Histórico de commits|Últimos commits locais"             "7|⚙️|Configurar projeto|Vínculo, repo e branch"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) projeto_git_status_tela "$projeto" ;;
            2) atualizar_projeto_git "$projeto" ;;
            3) enviar_projeto_github "$projeto" ;;
            4) menu_branches_projeto "$projeto" ;;
            5) github_repo_vinculado_tela "$projeto" ;;
            6) github_historico_commits "$projeto" ;;
            7) menu_config_github_projeto "$projeto" ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
