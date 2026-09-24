# Módulo: projects.sh
# Manager.sh — módulo

# ============================================================================
# DESCOBERTA DE PROJETOS (identifica pastas de projeto de verdade)
# ============================================================================

MARCADORES_PROJETO_EXATOS=(package.json composer.json Cargo.toml pyproject.toml requirements.txt go.mod pom.xml build.gradle build.gradle.kts angular.json)
MARCADORES_PROJETO_GLOB=(vite.config next.config nuxt.config svelte.config)

eh_projeto_valido() {
    # eh_projeto_valido <dir>  → 0 se a pasta tem cara de projeto de verdade
    local dir="$1"
    [ -d "$dir" ] || return 1
    local m
    for m in "${MARCADORES_PROJETO_EXATOS[@]}"; do
        [ -f "$dir/$m" ] && return 0
    done
    shopt -s nullglob
    for m in "${MARCADORES_PROJETO_GLOB[@]}"; do
        local matches=("$dir/${m}".*)
        if [ ${#matches[@]} -gt 0 ]; then
            shopt -u nullglob
            return 0
        fi
    done
    # Também aceita um monorepo com subpastas frontend/backend reconhecíveis
    local sub nome
    for sub in "$dir"/*/; do
        [ -d "$sub" ] || continue
        nome=$(basename "${sub%/}" | tr '[:upper:]' '[:lower:]')
        case "$nome" in
            frontend|front|client|web|backend|back|server|api)
                for m in "${MARCADORES_PROJETO_EXATOS[@]}"; do
                    if [ -f "$sub$m" ]; then
                        shopt -u nullglob
                        return 0
                    fi
                done
                ;;
        esac
    done
    shopt -u nullglob
    return 1
}

# Verdadeiro se o item está direto na raiz de ~/Painel (não dentro de
# ~/Painel/projetos). Usado para não exibir Tipo/stack nesses casos.
eh_painel_raiz() {
    [ "$(dirname "$1")" == "$PAINEL_DIR" ]
}

# Monta um rótulo curto de stack ("React + Node", "Laravel", "Desconhecido")
# usando a detecção de estrutura já existente. Preenche $ROTULO_STACK.
rotulo_stack_projeto() {
    local dir="$1"
    detectar_estrutura_projeto "$dir"
    case "$PROJ_MODO" in
        fullstack)         ROTULO_STACK="$FRONT_FRAMEWORK + $BACK_FRAMEWORK" ;;
        simples_frontend)  ROTULO_STACK="$FRONT_FRAMEWORK" ;;
        simples_backend)   ROTULO_STACK="$BACK_FRAMEWORK" ;;
        *)                 ROTULO_STACK="Não identificado" ;;
    esac
}

# Preenche três arrays globais a partir de ~/Painel e ~/Painel/projetos:
#   PROJETOS_ENCONTRADOS  → "caminho|origem"
#   ARQUIVOS_COMUNS       → "caminho|origem"  (arquivos soltos na raiz do Painel)
#   BACKUPS_ENCONTRADOS   → nomes de arquivo dentro de backups/
descobrir_entradas() {
    PROJETOS_ENCONTRADOS=(); ARQUIVOS_COMUNS=(); BACKUPS_ENCONTRADOS=()
    local base f nome origem_label
    local -A adicionados=()

    # Cada diretório de primeiro nível é uma unidade de projeto. A detecção de
    # estrutura interna decide se é monorepo; subpastas frontend/backend nunca
    # são promovidas a projetos independentes do mesmo sistema.
    for base in "$PAINEL_DIR" "$PROJETOS_DIR"; do
        [ -d "$base" ] || continue
        [ "$base" = "$PAINEL_DIR" ] && origem_label="~/Painel" || origem_label="~/Painel/projetos"
        if [ "$base" = "$PAINEL_DIR" ]; then
            detectar_estrutura_projeto "$PAINEL_DIR"
            if [ "$PROJ_MODO" = fullstack ] && [ "$FRONT_DIR" != "$PAINEL_DIR" ] && [ "$BACK_DIR" != "$PAINEL_DIR" ]; then
                # A raiz do Painel representa um único projeto/monorepo. As
                # pastas de componentes detectadas (frontend/backend etc.)
                # pertencem a ele e não devem reaparecer como projetos
                # independentes na mesma listagem.
                PROJETOS_ENCONTRADOS+=("$PAINEL_DIR|~/Painel (monorepo)")
                adicionados["$PAINEL_DIR"]=1
                [ -n "$FRONT_DIR" ] && adicionados["$FRONT_DIR"]=1
                [ -n "$BACK_DIR" ] && adicionados["$BACK_DIR"]=1
            fi
        fi
        while IFS= read -r -d '' f; do
            nome="$(basename "$f")"
            [[ "$nome" == .* || "$nome" == projetos || "$nome" == backups ]] && continue
            [ -n "${adicionados[$f]:-}" ] && continue
            if [ -d "$f" ] && eh_projeto_valido "$f"; then
                PROJETOS_ENCONTRADOS+=("$f|$origem_label")
                adicionados["$f"]=1
            elif [ -f "$f" ]; then
                ARQUIVOS_COMUNS+=("$f|$origem_label")
            fi
        done < <(find "$base" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z)
    done

    if [ -d "$BACKUPS_DIR" ]; then
        while IFS= read -r -d '' f; do BACKUPS_ENCONTRADOS+=("$(basename "$f")"); done \
            < <(find "$BACKUPS_DIR" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
    fi
}

# ============================================================================
# LISTAGEM
# ============================================================================
# LISTAGEM (somente visualização)
# ============================================================================

listar_projetos() {
    title "📦 Projetos Encontrados"
    descobrir_entradas

    if [ ${#PROJETOS_ENCONTRADOS[@]} -eq 0 ]; then
        warn "Nenhum projeto encontrado ainda."
        info "Use \"Importar projeto\" no menu principal para trazer algo do Downloads."
        pause
        return
    fi

    local i=1 entrada caminho origem
    for entrada in "${PROJETOS_ENCONTRADOS[@]}"; do
        caminho="${entrada%%|*}"; origem="${entrada##*|}"
        echo -e "${C_BOLD}${C_WHITE}$i) $(basename "$caminho")${C_RESET}"
        echo -e "   📁 ${C_DIM}${origem}${C_RESET}"
        if ! eh_painel_raiz "$caminho"; then
            rotulo_stack_projeto "$caminho"
            echo -e "   🧩 Tipo: ${C_CYAN}${ROTULO_STACK}${C_RESET}"
        fi
        separador
        i=$((i+1))
    done

    if [ ${#ARQUIVOS_COMUNS[@]} -gt 0 ]; then
        echo
        echo -e "${C_DIM}📄 Arquivos comuns: ${#ARQUIVOS_COMUNS[@]} item(ns) (README, configs soltos etc.)${C_RESET}"
    fi
    if [ ${#BACKUPS_ENCONTRADOS[@]} -gt 0 ]; then
        echo -e "${C_DIM}💾 Backups salvos: ${#BACKUPS_ENCONTRADOS[@]}${C_RESET}"
    fi

    pause
}

# Metadados de exibição são mantidos FORA dos projetos para que o Manager não
# altere package.json nem crie arquivos auxiliares dentro do código-fonte.
# Cada caminho recebe um arquivo próprio em ~/.termux-manager/projects/.
diretorio_metadados_projetos() {
    PROJECT_METADATA_DIR="$HOME/.termux-manager/projects"
    mkdir -p "$PROJECT_METADATA_DIR" 2>/dev/null || return 1
}

arquivo_apelido_projeto() {
    local projeto="$1" chave
    diretorio_metadados_projetos || return 1
    if comando_existe sha256sum; then
        chave=$(printf '%s' "$projeto" | sha256sum | awk '{print $1}')
    else
        chave=$(printf '%s' "$projeto" | cksum | awk '{print $1}')
    fi
    ARQUIVO_APELIDO_PROJETO="$PROJECT_METADATA_DIR/${chave}.name"
}

ler_apelido_projeto() {
    local projeto="$1"
    APELIDO_PROJETO=""
    arquivo_apelido_projeto "$projeto" || return 1
    [ -f "$ARQUIVO_APELIDO_PROJETO" ] || return 0
    IFS= read -r APELIDO_PROJETO < "$ARQUIVO_APELIDO_PROJETO" || true
}

salvar_apelido_projeto() {
    local projeto="$1" apelido="$2"
    arquivo_apelido_projeto "$projeto" || return 1
    if [ -z "$apelido" ]; then
        rm -f -- "$ARQUIVO_APELIDO_PROJETO"
    else
        printf '%s\n' "$apelido" > "$ARQUIVO_APELIDO_PROJETO"
    fi
}

# Lê o nome técnico declarado pelo projeto, exclusivamente para informações.
# A identificação visual do Manager não depende mais do package.json.
nome_package_projeto() {
    local projeto="$1" arq nome=""
    for arq in "$projeto/package.json" "$projeto/frontend/package.json" "$projeto/client/package.json" "$projeto/backend/package.json" "$projeto/server/package.json"; do
        [ -f "$arq" ] || continue
        nome=$(grep -m1 -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' "$arq" 2>/dev/null | sed -E 's/.*:[[:space:]]*"([^"]+)"/\1/')
        [ -n "$nome" ] && break
    done
    NOME_PACKAGE_PROJETO="$nome"
}

# Nome principal: apelido personalizado (se houver) > nome da pasta.
# package.json continua sendo usado para stack e detalhes, mas não para renomear
# visualmente um projeto no Manager.
nome_amigavel_projeto() {
    local projeto="$1" nome
    ler_apelido_projeto "$projeto"
    PROJETO_TEM_APELIDO=false
    if [ -n "$APELIDO_PROJETO" ]; then
        nome="$APELIDO_PROJETO"
        PROJETO_TEM_APELIDO=true
    else
        nome="$(basename "$projeto")"
        [ "$projeto" == "$PAINEL_DIR" ] && [ "$nome" == "Painel" ] && nome="Projeto do Painel"
    fi
    NOME_PROJETO="$nome"
}

alterar_nome_exibicao_projeto() {
    local projeto="$1" atual novo
    nome_amigavel_projeto "$projeto"
    atual="$NOME_PROJETO"
    cabecalho_tela "✏️ Nome de exibição" "Personalize sem alterar o projeto"
    caixa_simples "Projeto" "Nome atual: $atual" "Pasta: $(basename "$projeto")"         "O apelido fica salvo somente nas configurações do Manager."
    echo
    read -rp "Novo nome (vazio remove o apelido): " novo
    # Remove quebras de linha/controle e espaços extremos acidentais.
    novo=$(printf '%s' "$novo" | tr -d '\r\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    if salvar_apelido_projeto "$projeto" "$novo"; then
        if [ -n "$novo" ]; then
            ok "Nome de exibição alterado para: $novo"
        else
            ok "Apelido removido. O nome da pasta voltou a ser usado."
        fi
    else
        error "Não foi possível salvar o nome de exibição."
    fi
    pause
}


# Resumo leve usado na lista e no painel de cada projeto.
projeto_git_status_resumido() {
    local projeto="$1" branch alteracoes remoto
    PROJ_GIT_REPO=false
    PROJ_GIT_BRANCH=""
    PROJ_GIT_CHANGES=0
    PROJ_GIT_REMOTE=""
    PROJ_GIT_LABEL="Sem Git"
    comando_existe git || return 0
    [ -d "$projeto/.git" ] || return 0
    PROJ_GIT_REPO=true
    branch="$(git -C "$projeto" symbolic-ref --short HEAD 2>/dev/null || git -C "$projeto" rev-parse --short HEAD 2>/dev/null || true)"
    alteracoes="$(git -C "$projeto" status --porcelain 2>/dev/null || true)"
    if declare -F github_encontrar_remote_projeto >/dev/null 2>&1 && github_encontrar_remote_projeto "$projeto"; then
        remoto="$GITHUB_REMOTE_URL"
    else
        remoto="$(git -C "$projeto" remote get-url origin 2>/dev/null || true)"
        if [ -z "$remoto" ]; then
            local primeiro
            primeiro="$(git -C "$projeto" remote 2>/dev/null | head -n 1 || true)"
            [ -n "$primeiro" ] && remoto="$(git -C "$projeto" remote get-url "$primeiro" 2>/dev/null || true)"
        fi
    fi
    PROJ_GIT_BRANCH="${branch:-sem branch}"
    PROJ_GIT_CHANGES="$(printf '%s\n' "$alteracoes" | sed '/^$/d' | wc -l | tr -d ' ')"
    PROJ_GIT_REMOTE="$remoto"
    if [ "${PROJ_GIT_CHANGES:-0}" -gt 0 ] 2>/dev/null; then
        PROJ_GIT_LABEL="Git $PROJ_GIT_BRANCH • ${PROJ_GIT_CHANGES} alt."
    else
        PROJ_GIT_LABEL="Git $PROJ_GIT_BRANCH • limpo"
    fi
}

projeto_componentes_ativos() {
    local projeto="$1" nome pf qtd=0
    PROJ_COMPONENTES_ATIVOS=0
    declare -F id_projeto >/dev/null 2>&1 || return 0
    declare -F pid_ativo >/dev/null 2>&1 || return 0
    [ -d "${PID_DIR:-}" ] || return 0
    id_projeto "$projeto"
    for pf in "$PID_DIR/${ID_PROJETO}_"*.pid; do
        [ -e "$pf" ] || continue
        pid_ativo "$pf" && qtd=$((qtd + 1))
    done
    PROJ_COMPONENTES_ATIVOS="$qtd"
}

projeto_tamanho_resumido() {
    local projeto="$1" valor
    valor="$(du -sh "$projeto" 2>/dev/null | awk '{print $1}' || true)"
    printf '%s' "${valor:-?}"
}

projeto_resumo_rapido() {
    local projeto="$1"
    rotulo_stack_projeto "$projeto"
    projeto_git_status_resumido "$projeto"
    projeto_componentes_ativos "$projeto"
    PROJ_RESUMO="$ROTULO_STACK • $PROJ_GIT_LABEL"
    if [ "${PROJ_COMPONENTES_ATIVOS:-0}" -gt 0 ] 2>/dev/null; then
        PROJ_RESUMO+=" • ${PROJ_COMPONENTES_ATIVOS} ativo(s)"
    else
        PROJ_RESUMO+=" • parado"
    fi
}

# ============================================================================
# GESTÃO E PAINEL DO PROJETO
# ============================================================================

gerenciar_projetos() {
    while true; do
        descobrir_entradas
        if [ ${#PROJETOS_ENCONTRADOS[@]} -eq 0 ]; then
            cabecalho_tela "📂 Meus projetos" "Nenhum projeto detectado"
            caixa_simples "📭 Lista vazia" "Use a importação assistida para adicionar seu primeiro projeto."
            rodape_atalhos "[0] Voltar  •  [L] Limpeza"
            ler_opcao
            case "${RESPOSTA_MENU,,}" in 0) return ;; l) menu_exclusao_painel ;; *) feedback_curto "Opção inválida." ;; esac
            continue
        fi

        local i=1 entrada caminho origem total_ativos=0
        local -a opcoes=()
        for entrada in "${PROJETOS_ENCONTRADOS[@]}"; do
            caminho="${entrada%%|*}"; origem="${entrada##*|}"
            nome_amigavel_projeto "$caminho"
            projeto_resumo_rapido "$caminho"
            total_ativos=$((total_ativos + ${PROJ_COMPONENTES_ATIVOS:-0}))
            opcoes+=("$i|📦|$NOME_PROJETO$([ "$PROJETO_TEM_APELIDO" = true ] && printf ' ⭐')|$PROJ_RESUMO")
            i=$((i+1))
        done
        opcoes+=("L|🧹|Limpeza do Painel|Excluir projetos e backups com confirmação")
        menu_unificado "📂 MEUS PROJETOS" \
            "${#PROJETOS_ENCONTRADOS[@]} projeto(s) • ${total_ativos} componente(s) ativo(s)" \
            "[0] Voltar  •  [número] Abrir  •  [L] Limpeza" \
            "${opcoes[@]}"
        ler_opcao
        case "${RESPOSTA_MENU,,}" in
            0) return ;;
            l) menu_exclusao_painel ;;
            *)
                if [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] && [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#PROJETOS_ENCONTRADOS[@]} ]; then
                    entrada="${PROJETOS_ENCONTRADOS[$((RESPOSTA_MENU-1))]}"
                    tela_projeto "${entrada%%|*}"
                else
                    feedback_curto "Opção inválida."
                fi
                ;;
        esac
    done
}

montar_acoes_projeto() {
    local projeto="$1"
    ACOES_PROJETO=()
    detectar_estrutura_projeto "$projeto"
    if [ "$PROJ_MODO" = fullstack ]; then
        ACOES_PROJETO+=("1|🚀|Testar frontend|Instalar, validar e executar $FRONT_FRAMEWORK")
        ACOES_PROJETO+=("2|🧰|Testar backend|Instalar, validar e executar $BACK_FRAMEWORK")
        ACOES_PROJETO+=("3|🧩|Testar sistema completo|Frontend e backend juntos")
        PROJ_ACAO_OFFSET=3
    else
        ACOES_PROJETO+=("1|🚀|Testar projeto|Instalar, validar e executar")
        PROJ_ACAO_OFFSET=1
    fi
    local n=$((PROJ_ACAO_OFFSET+1))
    ACOES_PROJETO+=("$n|🌿|Git / GitHub|Status, atualizar, enviar e branches"); n=$((n+1))
    ACOES_PROJETO+=("$n|🔧|Dependências|Atualizar e verificar pacotes"); n=$((n+1))
    ACOES_PROJETO+=("$n|💾|Fazer backup|Salvar cópia em Downloads"); n=$((n+1))
    ACOES_PROJETO+=("$n|🔍|Informações|Stack, tamanho e estrutura"); n=$((n+1))
    ACOES_PROJETO+=("$n|📂|Abrir pasta|Abrir diretório no Android"); n=$((n+1))
    ACOES_PROJETO+=("$n|📋|Copiar projeto|Criar outra cópia do projeto"); n=$((n+1))
    ACOES_PROJETO+=("$n|✏️|Nome de exibição|Definir apelido no Manager"); n=$((n+1))
    ACOES_PROJETO+=("$n|❌|Excluir projeto|Remover com opção de backup")
}

tela_projeto() {
    local projeto="$1" op base tamanho execucao git_texto
    while [ -e "$projeto" ]; do
        detectar_estrutura_projeto "$projeto"
        nome_amigavel_projeto "$projeto"
        projeto_resumo_rapido "$projeto"
        montar_acoes_projeto "$projeto"
        tamanho="$(projeto_tamanho_resumido "$projeto")"
        if [ "${PROJ_COMPONENTES_ATIVOS:-0}" -gt 0 ] 2>/dev/null; then
            execucao="${PROJ_COMPONENTES_ATIVOS} componente(s) ativo(s)"
        else
            execucao="Parado"
        fi
        git_texto="$PROJ_GIT_LABEL"
        cabecalho_tela "📦 $NOME_PROJETO" "$ROTULO_STACK"
        caixa_simples_wrap "Resumo" \
            "Git: $git_texto" \
            "Execução: $execucao" \
            "Tamanho: $tamanho" \
            "Pasta: $(caminho_curto "$projeto")"
        echo
        caixa_linha_topo
        local item n ic titulo desc
        for item in "${ACOES_PROJETO[@]}"; do
            IFS='|' read -r n ic titulo desc <<< "$item"
            menu_opcao "$n" "$ic" "$titulo" "$desc"
        done
        caixa_linha_baixo
        rodape_atalhos "[0] Voltar  •  [número] Executar ação"
        ler_opcao
        op="$RESPOSTA_MENU"
        [ "$op" = 0 ] && return
        if [ "$PROJ_MODO" = fullstack ]; then
            case "$op" in
                1) testar_componente "$projeto" frontend ;;
                2) testar_componente "$projeto" backend ;;
                3) testar_componente "$projeto" ambos ;;
            esac
            base=3
        else
            [ "$op" = 1 ] && testar_projeto "$projeto"
            base=1
        fi
        case "$op" in
            $((base+1))) menu_git_projeto "$projeto" ;;
            $((base+2))) atualizar_dependencias_projeto "$projeto" ;;
            $((base+3))) criar_backup_projeto "$projeto" ;;
            $((base+4))) mostrar_informacoes_projeto "$projeto" ;;
            $((base+5))) abrir_pasta "$projeto" ;;
            $((base+6))) copiar_projeto_existente "$projeto" ;;
            $((base+7))) alterar_nome_exibicao_projeto "$projeto" ;;
            $((base+8))) excluir_projeto "$projeto" && return ;;
            0|1|2|3) : ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

abrir_pasta() {
    local projeto="$1"
    title "Abrindo pasta"
    info "$projeto"
    if comando_existe termux-open; then
        termux-open "$projeto" >>"$LOG_FILE" 2>&1
        ok "Pasta aberta (ou explorador de arquivos acionado)."
    else
        warn "termux-open não encontrado. Instalando termux-api..."
        instalar_pkg_termux termux-api
        if comando_existe termux-open; then
            termux-open "$projeto"
        else
            info "Caminho da pasta: $projeto"
        fi
    fi
    pause
}

# Reabre o fluxo de cópia/importação usando o próprio projeto como origem,
# permitindo levá-lo pra outro destino (Painel, Painel/projetos, achatado etc).
copiar_projeto_existente() {
    local projeto="$1"
    menu_unificado "📋 Copiar projeto" "Escolha o formato da nova cópia" \
        "[0] Voltar  •  [1–3] Selecionar" \
        "1|📁|Pasta completa|Mantém nome e estrutura do projeto" \
        "2|📄|Arquivos da raiz|Copia somente arquivos soltos para ~/Painel" \
        "3|📂|Conteúdo da pasta|Mescla o conteúdo diretamente em ~/Painel"
    ler_opcao
    case "$RESPOSTA_MENU" in
        0) return ;;
        1)
            menu_unificado "📍 Destino da cópia" "Selecione a área de destino" "[0] Voltar" \
                "1|📂|~/Painel|Área principal" "2|📁|~/Painel/projetos|Coleção de projetos"
            ler_opcao
            case "$RESPOSTA_MENU" in 1) destino="$PAINEL_DIR";; 2) destino="$PROJETOS_DIR";; *) return;; esac
            [ "$destino/$(basename "$projeto")" = "$projeto" ] && { error "Origem e destino são iguais."; pause; return; }
            motor_copia "$projeto" "$destino" false
            ;;
        2)
            local arquivos=() f i=1 itens=()
            while IFS= read -r -d '' f; do arquivos+=("$f"); done < <(find "$projeto" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)
            [ ${#arquivos[@]} -gt 0 ] || { warn "Nenhum arquivo na raiz."; pause; return; }
            cabecalho_tela "📄 Selecionar arquivos" "Informe números separados por espaço"
            caixa_linha_topo
            for f in "${arquivos[@]}"; do menu_opcao "$i" "📄" "$(basename "$f")" "Arquivo da raiz"; i=$((i+1)); done
            caixa_linha_baixo
            read -rp "Arquivos: " -a indices
            local idx
            for idx in "${indices[@]}"; do [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le ${#arquivos[@]} ] && itens+=("${arquivos[$((idx-1))]}"); done
            for f in "${itens[@]}"; do [ -e "$PAINEL_DIR/$(basename "$f")" ] && { warn "Já existe: $(basename "$f")"; continue; }; cp -a "$f" "$PAINEL_DIR/"; ok "Copiado: $(basename "$f")"; done
            pause
            ;;
        3) motor_copia "$projeto" "$PAINEL_DIR" true ;;
        *) warn "Opção inválida."; pause ;;
    esac
}

atualizar_dependencias_projeto() {
    local projeto="$1" falhas=0 cwd_inicial
    cwd_inicial="$(pwd -P 2>/dev/null || printf '%s' "${HOME:-/}")"
    title "Atualizar Dependências: $(basename "$projeto")"
    detectar_estrutura_projeto "$projeto"

    if [ "$PROJ_MODO" == "desconhecido" ]; then
        error "Não foi possível identificar a tecnologia do projeto."
        pause
        return 1
    fi

    if [ -n "$FRONT_DIR" ]; then
        info "Atualizando FRONTEND ($FRONT_FRAMEWORK)..."
        if ! instalar_dependencias "$FRONT_DIR" "$FRONT_GERENCIADOR"; then
            error "Falha ao instalar dependências do frontend."
            falhas=$((falhas + 1))
        elif ! verificar_instalacao "$FRONT_DIR" "$FRONT_GERENCIADOR"; then
            falhas=$((falhas + 1))
        fi
    fi
    if [ -n "$BACK_DIR" ]; then
        info "Atualizando BACKEND ($BACK_FRAMEWORK)..."
        if ! instalar_dependencias "$BACK_DIR" "$BACK_GERENCIADOR"; then
            error "Falha ao instalar dependências do backend."
            falhas=$((falhas + 1))
        elif ! verificar_instalacao "$BACK_DIR" "$BACK_GERENCIADOR"; then
            falhas=$((falhas + 1))
        fi
    fi

    # instalar_dependencias entra no diretório do componente. Volta ao ponto de
    # origem para não deixar o terminal preso dentro do último frontend/backend.
    cd "$cwd_inicial" 2>/dev/null || cd "${HOME:-/}" 2>/dev/null || true

    if [ "$falhas" -eq 0 ]; then
        ok "Dependências atualizadas e verificadas."
        pause
        return 0
    fi
    error "Atualização concluída com $falhas falha(s)."
    info "Revise as mensagens acima antes de executar o projeto."
    pause
    return 1
}

# ============================================================================
# SUBMÓDULOS DE PROJETOS
# ============================================================================
PROJECTS_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$PROJECTS_MODULE_DIR/projects_github.sh"
# shellcheck source=/dev/null
source "$PROJECTS_MODULE_DIR/projects_storage.sh"
