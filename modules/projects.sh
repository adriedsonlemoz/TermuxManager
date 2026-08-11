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

# ============================================================================
# GERENCIAR PROJETO (lista → seleciona → tela única com todas as ações)
# ============================================================================

gerenciar_projetos() {
    while true; do
        descobrir_entradas
        cabecalho_tela "📂 Projetos e gerenciamento" "${#PROJETOS_ENCONTRADOS[@]} projeto(s) detectado(s)"

        if [ ${#PROJETOS_ENCONTRADOS[@]} -eq 0 ]; then
            caixa_simples "📭 Lista vazia" "Use a importação assistida para adicionar seu primeiro projeto."
        else
            caixa_linha_topo
            local i=1 entrada caminho origem
            for entrada in "${PROJETOS_ENCONTRADOS[@]}"; do
                caminho="${entrada%%|*}"; origem="${entrada##*|}"
                nome_amigavel_projeto "$caminho"; rotulo_stack_projeto "$caminho"
                menu_opcao "$i" "📦" "$NOME_PROJETO$([ "$PROJETO_TEM_APELIDO" = true ] && printf " ⭐")" "$ROTULO_STACK • $origem"
                i=$((i+1))
            done
            caixa_linha_baixo
        fi

        echo
        caixa_linha_topo
        menu_opcao "L" "🧹" "Limpeza do Painel" "Excluir projeto, coleção de projetos ou todo o Painel"
        caixa_linha_baixo
        rodape_atalhos "[0] Voltar  •  [número] Gerenciar  •  [L] Limpeza"
        ler_opcao
        case "${RESPOSTA_MENU,,}" in
            0) return ;;
            l) menu_exclusao_painel ;;
            *)
                if [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] && [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#PROJETOS_ENCONTRADOS[@]} ]; then
                    entrada="${PROJETOS_ENCONTRADOS[$((RESPOSTA_MENU-1))]}"
                    tela_projeto "${entrada%%|*}"
                else
                    warn "Opção inválida."; pause
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
        ACOES_PROJETO+=("3|🧩|Testar sistema completo|Executar frontend e backend juntos")
        PROJ_ACAO_OFFSET=3
    else
        ACOES_PROJETO+=("1|🚀|Testar projeto|Instalar, validar e executar a stack detectada")
        PROJ_ACAO_OFFSET=1
    fi
    local n=$((PROJ_ACAO_OFFSET+1))
    ACOES_PROJETO+=("$n|📂|Abrir pasta|Abrir o diretório no Android"); n=$((n+1))
    ACOES_PROJETO+=("$n|📋|Copiar projeto|Reabrir o assistente de cópia"); n=$((n+1))
    ACOES_PROJETO+=("$n|🔧|Atualizar dependências|Reinstalar e verificar dependências"); n=$((n+1))
    ACOES_PROJETO+=("$n|✏️|Nome de exibição|Definir ou remover apelido no Manager"); n=$((n+1))
    ACOES_PROJETO+=("$n|🐙|Enviar para GitHub|Publicar ou enviar novas alterações com poucos passos"); n=$((n+1))
    ACOES_PROJETO+=("$n|🔍|Informações|Exibir nomes, stack, tamanho e estrutura"); n=$((n+1))
    ACOES_PROJETO+=("$n|💾|Fazer backup|Criar pacote compactado com data"); n=$((n+1))
    ACOES_PROJETO+=("$n|❌|Excluir projeto|Remover com opção de backup")
}

tela_projeto() {
    local projeto="$1" op base
    while [ -e "$projeto" ]; do
        detectar_estrutura_projeto "$projeto"; nome_amigavel_projeto "$projeto"; rotulo_stack_projeto "$projeto"
        montar_acoes_projeto "$projeto"
        cabecalho_tela "📦 $NOME_PROJETO" "$ROTULO_STACK"
        caixa_simples "🧭 Estrutura detectada" "📁 $projeto" \
            "🌐 Frontend: ${FRONT_FRAMEWORK:-Não detectado}" "🧰  Backend: ${BACK_FRAMEWORK:-Não detectado}"
        echo
        caixa_linha_topo
        local item n ic titulo desc
        for item in "${ACOES_PROJETO[@]}"; do IFS='|' read -r n ic titulo desc <<< "$item"; menu_opcao "$n" "$ic" "$titulo" "$desc"; done
        caixa_linha_baixo
        rodape_atalhos "[0] Voltar  •  [número] Executar ação"
        ler_opcao; op="$RESPOSTA_MENU"; [ "$op" = 0 ] && return
        if [ "$PROJ_MODO" = fullstack ]; then
            case "$op" in 1) testar_componente "$projeto" frontend;; 2) testar_componente "$projeto" backend;; 3) testar_componente "$projeto" ambos;; esac
            base=3
        else
            [ "$op" = 1 ] && testar_projeto "$projeto"
            base=1
        fi
        case "$op" in
            $((base+1))) abrir_pasta "$projeto" ;;
            $((base+2))) copiar_projeto_existente "$projeto" ;;
            $((base+3))) atualizar_dependencias_projeto "$projeto" ;;
            $((base+4))) alterar_nome_exibicao_projeto "$projeto" ;;
            $((base+5))) enviar_projeto_github "$projeto" ;;
            $((base+6))) mostrar_informacoes_projeto "$projeto" ;;
            $((base+7))) criar_backup_projeto "$projeto" ;;
            $((base+8))) excluir_projeto "$projeto" && return ;;
            0|1|2|3) : ;;
            *) warn "Opção inválida."; pause ;;
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
    local projeto="$1"
    title "Atualizar Dependências: $(basename "$projeto")"
    detectar_estrutura_projeto "$projeto"

    if [ "$PROJ_MODO" == "desconhecido" ]; then
        error "Não foi possível identificar a tecnologia do projeto."
        pause
        return
    fi

    if [ -n "$FRONT_DIR" ]; then
        info "Atualizando FRONTEND ($FRONT_FRAMEWORK)..."
        instalar_dependencias "$FRONT_DIR" "$FRONT_GERENCIADOR"
        verificar_instalacao "$FRONT_DIR" "$FRONT_GERENCIADOR"
    fi
    if [ -n "$BACK_DIR" ]; then
        info "Atualizando BACKEND ($BACK_FRAMEWORK)..."
        instalar_dependencias "$BACK_DIR" "$BACK_GERENCIADOR"
        verificar_instalacao "$BACK_DIR" "$BACK_GERENCIADOR"
    fi
    ok "Dependências atualizadas."
    pause
}

# ============================================================================
# GITHUB — PUBLICAÇÃO ASSISTIDA
# ============================================================================

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

github_log() {
    local nivel="$1" etapa="$2" mensagem="${3:-}"
    mkdir -p "$GITHUB_LOG_DIR" 2>/dev/null || true
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
        sed 's/^/    /' "$tmp" >> "$GITHUB_LOG_FILE" 2>/dev/null || true
    fi
    if [ "$rc" -eq 0 ]; then
        github_log OK "$etapa" "Concluído"
        GITHUB_LAST_ERROR=""
    else
        GITHUB_LAST_ERROR=$(tail -n 8 "$tmp" 2>/dev/null | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
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
    local projeto="$1" remoto url
    GITHUB_REMOTE=""
    while IFS= read -r remoto; do
        [ -n "$remoto" ] || continue
        url=$(git -C "$projeto" remote get-url "$remoto" 2>>"$GITHUB_LOG_FILE" || true)
        if [[ "$url" == *github.com* ]]; then
            GITHUB_REMOTE="$remoto"
            github_log OK remoto "GitHub já configurado em '$remoto'"
            return 0
        fi
    done < <(git -C "$projeto" remote 2>>"$GITHUB_LOG_FILE" || true)
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
        if github_run "branch principal" git -C "$projeto" branch -M main; then
            ok "Branch principal preparada."
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

    branch=$(git -C "$projeto" symbolic-ref --short HEAD 2>>"$GITHUB_LOG_FILE" || true)
    [ -n "$branch" ] || branch="main"
    alteracoes=$(git -C "$projeto" status --porcelain 2>>"$GITHUB_LOG_FILE" || true)

    if [ -n "$alteracoes" ]; then
        cabecalho_tela "🐙 Enviar para GitHub" "Alterações encontradas no projeto"
        caixa_simples "Resumo" \
            "Projeto: $(basename "$projeto")" \
            "Branch: $branch" \
            "Arquivos alterados: $(printf '%s\n' "$alteracoes" | sed '/^$/d' | wc -l | tr -d ' ')" \
            "Remoto: $GITHUB_REMOTE"
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

mostrar_informacoes_projeto() {
    local projeto="$1"
    nome_amigavel_projeto "$projeto"
    nome_package_projeto "$projeto"
    title "Informações: $NOME_PROJETO"

    local tamanho qtd_arquivos qtd_pastas modificado
    tamanho=$(du -sh "$projeto" 2>/dev/null | cut -f1)
    qtd_arquivos=$(find "$projeto" -type f 2>/dev/null | wc -l | tr -d ' ')
    qtd_pastas=$(find "$projeto" -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    modificado=$(date -r "$projeto" '+%d/%m/%Y %H:%M' 2>/dev/null)

    caixa_linha_topo
    caixa_linha_texto "${C_BOLD}$NOME_PROJETO${C_RESET}" true
    caixa_linha_sep
    caixa_linha_texto "🏷️ Exibição: ${NOME_PROJETO}"
    caixa_linha_texto "📂 Pasta: $(basename "$projeto")"
    [ -n "$NOME_PACKAGE_PROJETO" ] && caixa_linha_texto "📦 Package: ${NOME_PACKAGE_PROJETO}"
    caixa_linha_texto "📁 ${projeto}"
    if ! eh_painel_raiz "$projeto"; then
        rotulo_stack_projeto "$projeto"
        caixa_linha_texto "🧩 Tipo: ${ROTULO_STACK}"
    fi
    caixa_linha_texto "📊 Tamanho: ${tamanho:-?}"
    caixa_linha_texto "📄 Arquivos: ${qtd_arquivos}   📂 Pastas: ${qtd_pastas}"
    caixa_linha_texto "🕒 Modificado: ${modificado:-?}"
    caixa_linha_baixo

    pause
}

# Resolve o destino público dos backups de projetos. Os pacotes finais ficam
# visíveis no Android em Download/projetos/backups. BACKUPS_DIR continua sendo
# uma área interna legada do Painel e não é usada como destino final.
resolver_destino_backup_projetos() {
    if ! resolver_downloads_dir >/dev/null 2>&1; then
        error "Não foi possível acessar a pasta Downloads."
        info "Execute termux-setup-storage e conceda acesso ao armazenamento."
        return 1
    fi

    PROJECT_BACKUPS_DIR="$DOWNLOADS_DIR/projetos/backups"
    if ! mkdir -p "$PROJECT_BACKUPS_DIR" 2>>"$LOG_FILE"; then
        error "Não foi possível criar: $PROJECT_BACKUPS_DIR"
        return 1
    fi
    return 0
}

# Cria um TAR.GZ enxuto: dependências baixáveis, repositório Git, caches,
# resultados de build e temporários não entram no pacote. O código-fonte,
# manifests/locks, configurações, assets e demais arquivos do projeto ficam.
compactar_backup_projeto() {
    local origem="$1" destino="$2" nome
    nome="$(basename "$origem")"

    tar -czf "$destino" \
        --exclude='node_modules' --exclude='*/node_modules' \
        --exclude='.git' --exclude='*/.git' \
        --exclude='.next' --exclude='*/.next' \
        --exclude='.nuxt' --exclude='*/.nuxt' \
        --exclude='.svelte-kit' --exclude='*/.svelte-kit' \
        --exclude='.cache' --exclude='*/.cache' \
        --exclude='.parcel-cache' --exclude='*/.parcel-cache' \
        --exclude='.turbo' --exclude='*/.turbo' \
        --exclude='.vite' --exclude='*/.vite' \
        --exclude='coverage' --exclude='*/coverage' \
        --exclude='dist' --exclude='*/dist' \
        --exclude='build' --exclude='*/build' \
        --exclude='target' --exclude='*/target' \
        --exclude='vendor' --exclude='*/vendor' \
        --exclude='.venv' --exclude='*/.venv' \
        --exclude='venv' --exclude='*/venv' \
        --exclude='__pycache__' --exclude='*/__pycache__' \
        --exclude='.pytest_cache' --exclude='*/.pytest_cache' \
        --exclude='.mypy_cache' --exclude='*/.mypy_cache' \
        --exclude='tmp' --exclude='*/tmp' \
        --exclude='temp' --exclude='*/temp' \
        -C "$(dirname "$origem")" "$nome" 2>>"$LOG_FILE"
}

# Cria primeiro em uma área temporária privada, copia para Downloads, verifica
# integridade por SHA-256 e remove imediatamente a cópia temporária do Termux.
# Retorna o caminho público em BACKUP_PROJETO_RESULTADO.
gerar_backup_publico_projeto() {
    local origem="$1" rotulo="${2:-$(basename "$1")}" carimbo arquivo tmp_dir temporario destino hash_tmp hash_dest
    [ -d "$origem" ] || { error "Pasta não encontrada: $(caminho_curto "$origem")"; return 1; }
    resolver_destino_backup_projetos || return 1

    carimbo="$(date '+%Y-%m-%d_%H-%M-%S')"
    arquivo="${rotulo}_${carimbo}.tar.gz"
    tmp_dir="${SESSION_TMP_DIR:-$TMP_ROOT/session_$$}/backup"
    mkdir -p "$tmp_dir" || return 1
    temporario="$tmp_dir/$arquivo"
    destino="$PROJECT_BACKUPS_DIR/$arquivo"

    rm -f "$temporario"
    info "Compactando código e arquivos essenciais..."
    if ! compactar_backup_projeto "$origem" "$temporario"; then
        rm -f "$temporario"
        error "Falha ao criar o pacote de backup."
        return 1
    fi

    info "Copiando para Download/projetos/backups..."
    if ! cp -f "$temporario" "$destino" 2>>"$LOG_FILE"; then
        rm -f "$temporario"
        error "Falha ao copiar o backup para Downloads."
        return 1
    fi

    hash_tmp="$(sha256sum "$temporario" 2>/dev/null | awk '{print $1}')"
    hash_dest="$(sha256sum "$destino" 2>/dev/null | awk '{print $1}')"
    if [ -z "$hash_tmp" ] || [ "$hash_tmp" != "$hash_dest" ]; then
        rm -f "$destino" "$temporario"
        error "A verificação do backup falhou. O arquivo incompleto foi removido."
        return 1
    fi

    rm -f "$temporario"
    BACKUP_PROJETO_RESULTADO="$destino"
    log "INFO" "Backup público verificado: $origem -> $destino"
    return 0
}

criar_backup_projeto() {
    local projeto="$1" sem_pausa="${2:-false}" nome tamanho
    nome="$(basename "$projeto")"
    title "Backup: $nome"

    if gerar_backup_publico_projeto "$projeto" "$nome"; then
        tamanho=$(stat -c%s "$BACKUP_PROJETO_RESULTADO" 2>/dev/null || echo 0)
        ok "Backup criado e verificado."
        info "Destino: $BACKUP_PROJETO_RESULTADO"
        info "Tamanho: $(formatar_tamanho "$tamanho")"
        info "Ignorados: node_modules, .git, caches, builds e dependências regeneráveis."
        [ "$sem_pausa" = true ] || pause
        return 0
    fi

    error "Backup não concluído. Veja $(caminho_curto "$LOG_FILE") para detalhes."
    [ "$sem_pausa" = true ] || pause
    return 1
}


# ============================================================================
# CENTRO DE EXCLUSÃO DO PAINEL
# ============================================================================

quantidade_itens_diretos() {
    local alvo="$1"
    [ -d "$alvo" ] || { printf '0'; return; }
    find "$alvo" -mindepth 1 -maxdepth 1 -print 2>/dev/null | wc -l | tr -d ' '
}

backup_pasta_antes_excluir() {
    local alvo="$1" rotulo="$2"
    [ -d "$alvo" ] || return 0
    info "Criando backup antes da exclusão..."
    if gerar_backup_publico_projeto "$alvo" "$rotulo"; then
        ok "Backup salvo e verificado em Downloads."
        info "Destino: $BACKUP_PROJETO_RESULTADO"
        return 0
    fi
    error "Não foi possível criar um backup seguro. Exclusão cancelada."
    return 1
}

confirmar_exclusao_nivel() {
    local palavra="$1" descricao="$2"
    warn "$descricao"
    read -rp "Digite $palavra para confirmar: " resposta
    [ "$resposta" = "$palavra" ] || { info "Cancelado. Nada foi apagado."; pause; return 1; }
    return 0
}

selecionar_projeto_para_excluir() {
    descobrir_entradas
    if [ ${#PROJETOS_ENCONTRADOS[@]} -eq 0 ]; then
        warn "Nenhum projeto foi detectado."
        pause
        return
    fi
    cabecalho_tela "🗑️ Excluir um projeto" "Selecione exatamente o projeto a remover"
    caixa_linha_topo
    local i=1 entrada caminho origem
    for entrada in "${PROJETOS_ENCONTRADOS[@]}"; do
        caminho="${entrada%%|*}"; origem="${entrada##*|}"
        nome_amigavel_projeto "$caminho"
        menu_opcao "$i" "📦" "$NOME_PROJETO" "$origem"
        i=$((i+1))
    done
    caixa_linha_baixo
    rodape_atalhos "[0] Cancelar  •  [número] Selecionar"
    ler_opcao
    [ "$RESPOSTA_MENU" = 0 ] && return
    if [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] && [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#PROJETOS_ENCONTRADOS[@]} ]; then
        entrada="${PROJETOS_ENCONTRADOS[$((RESPOSTA_MENU-1))]}"
        excluir_projeto "${entrada%%|*}"
    else
        warn "Opção inválida."
        pause
    fi
}

limpar_conteudo_pasta_projetos() {
    local qtd tamanho fazer_backup
    qtd="$(quantidade_itens_diretos "$PROJETOS_DIR")"
    tamanho="$(du -sh "$PROJETOS_DIR" 2>/dev/null | cut -f1)"
    cabecalho_tela "🧹 Limpar projetos" "A pasta ~/Painel/projetos será preservada"
    caixa_simples "Resumo" "Itens diretos: ${qtd:-0}" "Tamanho: ${tamanho:-0}" \
        "Preserva: backups, arquivos da raiz do Painel e configurações"
    [ "${qtd:-0}" -gt 0 ] || { info "A pasta projetos já está vazia."; pause; return; }
    read -rp "Criar backup da pasta projetos antes de limpar? (S/n): " fazer_backup
    if [[ ! "$fazer_backup" =~ ^[nN]$ ]]; then
        backup_pasta_antes_excluir "$PROJETOS_DIR" "projetos_completo" || { pause; return; }
    fi
    confirmar_exclusao_nivel "LIMPAR" "Todos os itens dentro de $PROJETOS_DIR serão removidos." || return
    garantir_cwd_fora_do_alvo "$PROJETOS_DIR" || { error "Não foi possível mover o terminal para um diretório seguro."; pause; return 1; }
    find "$PROJETOS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    log "INFO" "Conteúdo de $PROJETOS_DIR removido; pasta preservada."
    ok "Todos os projetos foram removidos. A pasta projetos foi preservada."
    pause
}

excluir_pasta_projetos_completa() {
    local qtd tamanho fazer_backup
    qtd="$(quantidade_itens_diretos "$PROJETOS_DIR")"
    tamanho="$(du -sh "$PROJETOS_DIR" 2>/dev/null | cut -f1)"
    cabecalho_tela "🗑️ Excluir pasta projetos" "Remove a pasta e todo o seu conteúdo"
    caixa_simples "Resumo" "Itens diretos: ${qtd:-0}" "Tamanho: ${tamanho:-0}" \
        "O Manager recriará uma pasta projetos vazia para continuar funcionando"
    read -rp "Criar backup antes de excluir? (S/n): " fazer_backup
    if [[ -d "$PROJETOS_DIR" && ! "$fazer_backup" =~ ^[nN]$ ]]; then
        backup_pasta_antes_excluir "$PROJETOS_DIR" "pasta_projetos" || { pause; return; }
    fi
    confirmar_exclusao_nivel "PROJETOS" "A pasta $PROJETOS_DIR inteira será removida." || return
    garantir_cwd_fora_do_alvo "$PROJETOS_DIR" || { error "Não foi possível mover o terminal para um diretório seguro."; pause; return 1; }
    rm -rf -- "${PROJETOS_DIR:?}"
    mkdir -p "$PROJETOS_DIR"
    log "INFO" "Pasta projetos excluída e recriada vazia."
    ok "Pasta projetos removida e recriada vazia."
    pause
}

menu_exclusao_painel() {
    while true; do
        local qtd tamanho_painel tamanho_projetos
        qtd="$(quantidade_itens_diretos "$PROJETOS_DIR")"
        tamanho_painel="$(du -sh "$PAINEL_DIR" 2>/dev/null | cut -f1)"
        tamanho_projetos="$(du -sh "$PROJETOS_DIR" 2>/dev/null | cut -f1)"
        menu_unificado "🧹 Limpeza do Painel" "Escolha exatamente o nível de exclusão" \
            "[0] Voltar  •  Ações destrutivas exigem confirmação" \
            "1|📦|Excluir um projeto|Selecionar somente um projeto" \
            "2|🧹|Limpar conteúdo de projetos|Remove ${qtd:-0} item(ns), mantém a pasta • ${tamanho_projetos:-0}" \
            "3|🗑️|Excluir pasta projetos|Remove e recria ~/Painel/projetos vazia" \
            "4|⚠️|Excluir todo o Painel|Projetos, backups, arquivos e configurações • ${tamanho_painel:-0}"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) selecionar_projeto_para_excluir ;;
            2) limpar_conteudo_pasta_projetos ;;
            3) excluir_pasta_projetos_completa ;;
            4) excluir_painel_inteiro ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

excluir_projeto() {
    local projeto="$1" fazer_backup conf
    title "Excluir Projeto"
    warn "Isso removerá permanentemente: $projeto"
    read -rp "Deseja fazer um backup antes de excluir? (s/N): " fazer_backup
    if [[ "$fazer_backup" =~ ^[sS]$ ]]; then
        if ! criar_backup_projeto "$projeto" true; then
            error "O projeto NÃO foi excluído porque o backup não foi concluído."
            pause
            return 1
        fi
    fi
    read -rp "Confirma exclusão? (s/N): " conf
    if [[ "$conf" =~ ^[sS]$ ]]; then
        garantir_cwd_fora_do_alvo "$projeto" || { error "Não foi possível mover o terminal para um diretório seguro."; pause; return 1; }
        rm -rf -- "$projeto"
        ok "Projeto removido."
        if [[ "$fazer_backup" =~ ^[sS]$ ]]; then
            info "Backup preservado em: $BACKUP_PROJETO_RESULTADO"
        fi
        log "INFO" "Projeto excluído: $projeto"
        pause
        return 0
    else
        info "Exclusão cancelada."
        pause
        return 1
    fi
}
