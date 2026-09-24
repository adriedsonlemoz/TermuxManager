# Módulo: termux_tools.sh
# Ambientes e ferramentas de desenvolvimento do Termux.

versao_ferramenta_instalada() {
    local cmd="$1"; shift
    command -v "$cmd" >/dev/null 2>&1 || return 1
    local out
    out=$("$@" 2>&1 | head -n 1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$out" ] || out="instalado"
    printf '%s' "$out"
}

mostrar_lista_ferramentas_detectadas() {
    local -a linguagens=() web=() shells=() compilacao=() bancos=() utilitarios=() java=()
    local v total=0

    adicionar_ferramenta() {
        local categoria="$1" nome="$2" cmd="$3"; shift 3
        command -v "$cmd" >/dev/null 2>&1 || return 0
        local versao
        versao=$(versao_ferramenta_instalada "$cmd" "$@" 2>/dev/null || printf 'instalado')
        case "$categoria" in
            linguagens) linguagens+=("$nome: $versao") ;;
            web) web+=("$nome: $versao") ;;
            shells) shells+=("$nome: $versao") ;;
            compilacao) compilacao+=("$nome: $versao") ;;
            bancos) bancos+=("$nome: $versao") ;;
            utilitarios) utilitarios+=("$nome: $versao") ;;
            java) java+=("$nome: $versao") ;;
        esac
        total=$((total + 1))
    }

    adicionar_ferramenta linguagens "Python" python python --version
    adicionar_ferramenta linguagens "pip" pip pip --version
    adicionar_ferramenta linguagens "PHP" php php --version
    adicionar_ferramenta linguagens "Ruby" ruby ruby --version
    adicionar_ferramenta linguagens "Perl" perl perl -v
    adicionar_ferramenta linguagens "Go" go go version
    adicionar_ferramenta linguagens "Rust" rustc rustc --version

    adicionar_ferramenta web "Node.js" node node --version
    adicionar_ferramenta web "npm" npm npm --version
    adicionar_ferramenta web "pnpm" pnpm pnpm --version
    adicionar_ferramenta web "Yarn" yarn yarn --version
    adicionar_ferramenta web "Composer" composer composer --version
    adicionar_ferramenta web "Git" git git --version
    adicionar_ferramenta web "GitHub CLI" gh gh --version

    adicionar_ferramenta java "Java" java java -version
    adicionar_ferramenta java "Javac" javac javac -version
    adicionar_ferramenta java "Gradle" gradle gradle --version
    adicionar_ferramenta java "Maven" mvn mvn -version

    adicionar_ferramenta shells "Fish" fish fish --version
    adicionar_ferramenta shells "Bash" bash bash --version
    adicionar_ferramenta shells "Zsh" zsh zsh --version
    adicionar_ferramenta shells "Nano" nano nano --version
    adicionar_ferramenta shells "Micro" micro micro --version
    adicionar_ferramenta shells "Vim" vim vim --version
    adicionar_ferramenta shells "Neovim" nvim nvim --version

    adicionar_ferramenta compilacao "Clang" clang clang --version
    adicionar_ferramenta compilacao "GCC" gcc gcc --version
    adicionar_ferramenta compilacao "Make" make make --version
    adicionar_ferramenta compilacao "CMake" cmake cmake --version
    adicionar_ferramenta compilacao "pkg-config" pkg-config pkg-config --version

    adicionar_ferramenta bancos "SQLite" sqlite3 sqlite3 --version
    adicionar_ferramenta bancos "PostgreSQL" psql psql --version
    adicionar_ferramenta bancos "MariaDB" mariadb mariadb --version
    adicionar_ferramenta bancos "Redis" redis-server redis-server --version
    adicionar_ferramenta bancos "Mongo Shell" mongosh mongosh --version

    adicionar_ferramenta utilitarios "curl" curl curl --version
    adicionar_ferramenta utilitarios "wget" wget wget --version
    adicionar_ferramenta utilitarios "rsync" rsync rsync --version
    adicionar_ferramenta utilitarios "zip" zip zip -v
    adicionar_ferramenta utilitarios "unzip" unzip unzip -v
    adicionar_ferramenta utilitarios "jq" jq jq --version
    adicionar_ferramenta utilitarios "OpenSSL" openssl openssl version
    adicionar_ferramenta utilitarios "SSH" ssh ssh -V
    adicionar_ferramenta utilitarios "tmux" tmux tmux -V

    cabecalho_tela "📋 Ferramentas instaladas" "Somente ferramentas detectadas no Termux"
    caixa_simples "Resumo"         "Ferramentas detectadas: $total"         "Pacotes instalados no Termux: $(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | wc -l | tr -d ' ')"         "PREFIX: $(caminho_curto "$PREFIX")"
    caixa_simples "Ambientes"         "Web: $(ambiente_status_comandos node git curl)"         "Python: $(ambiente_status_comandos python)"         "Java: $(ambiente_status_comandos java)"         "Go: $(ambiente_status_comandos go)"         "Rust: $(ambiente_status_comandos cargo rustc)"         "PHP: $(ambiente_status_comandos php composer)"

    exibir_categoria_instalada() {
        local titulo="$1"; shift
        [ "$#" -gt 0 ] || return 0
        caixa_simples "$titulo" "$@"
    }

    exibir_categoria_instalada "🐍 Linguagens" "${linguagens[@]}"
    exibir_categoria_instalada "🌐 Web e versionamento" "${web[@]}"
    exibir_categoria_instalada "☕ Java" "${java[@]}"
    exibir_categoria_instalada "📝 Shells e editores" "${shells[@]}"
    exibir_categoria_instalada "🔧 Compilação" "${compilacao[@]}"
    exibir_categoria_instalada "💾 Bancos de dados" "${bancos[@]}"
    exibir_categoria_instalada "📦 Utilitários" "${utilitarios[@]}"

    if [ "$total" -eq 0 ]; then
        caixa_simples "Nenhuma ferramenta detectada"             "O Termux possui apenas os componentes básicos."             "Use Instalar ferramentas para adicionar pacotes."
    fi

    unset -f adicionar_ferramenta exibir_categoria_instalada
    pause
}

ambiente_dev_configurar() {
    local id="${1:-}"
    AMB_DEV_ID="$id"
    AMB_DEV_TITULO=""
    AMB_DEV_ICONE="🧰"
    AMB_DEV_COMANDOS=()
    AMB_DEV_ROTULOS=()
    AMB_DEV_PACOTES=()
    case "$id" in
        web)
            AMB_DEV_TITULO="Desenvolvimento Web"; AMB_DEV_ICONE="🌐"
            AMB_DEV_COMANDOS=(node npm git curl)
            AMB_DEV_ROTULOS=("Node.js" npm Git curl)
            AMB_DEV_PACOTES=(nodejs git curl wget)
            ;;
        python)
            AMB_DEV_TITULO="Python"; AMB_DEV_ICONE="🐍"
            AMB_DEV_COMANDOS=(python pip)
            AMB_DEV_ROTULOS=(Python pip)
            AMB_DEV_PACOTES=(python)
            ;;
        java)
            AMB_DEV_TITULO="Java"; AMB_DEV_ICONE="☕"
            AMB_DEV_COMANDOS=(java javac)
            AMB_DEV_ROTULOS=(Java Javac)
            AMB_DEV_PACOTES=()
            ;;
        go)
            AMB_DEV_TITULO="Go"; AMB_DEV_ICONE="🐹"
            AMB_DEV_COMANDOS=(go git)
            AMB_DEV_ROTULOS=(Go Git)
            AMB_DEV_PACOTES=(golang git)
            ;;
        rust)
            AMB_DEV_TITULO="Rust"; AMB_DEV_ICONE="🦀"
            AMB_DEV_COMANDOS=(cargo rustc)
            AMB_DEV_ROTULOS=(Cargo Rustc)
            AMB_DEV_PACOTES=(rust clang pkg-config git)
            ;;
        ruby)
            AMB_DEV_TITULO="Ruby"; AMB_DEV_ICONE="💎"
            AMB_DEV_COMANDOS=(ruby)
            AMB_DEV_ROTULOS=(Ruby)
            AMB_DEV_PACOTES=(ruby clang make pkg-config)
            ;;
        php)
            AMB_DEV_TITULO="PHP"; AMB_DEV_ICONE="🐘"
            AMB_DEV_COMANDOS=(php composer)
            AMB_DEV_ROTULOS=(PHP Composer)
            AMB_DEV_PACOTES=(php composer git)
            ;;
        build)
            AMB_DEV_TITULO="Compilação"; AMB_DEV_ICONE="🔧"
            AMB_DEV_COMANDOS=(clang make cmake pkg-config)
            AMB_DEV_ROTULOS=(Clang Make CMake pkg-config)
            AMB_DEV_PACOTES=(clang make cmake pkg-config)
            ;;
        *) return 1 ;;
    esac
}

ambiente_dev_contar() {
    local id="${1:-}" cmd presentes=0 total=0
    ambiente_dev_configurar "$id" || return 1
    for cmd in "${AMB_DEV_COMANDOS[@]}"; do
        total=$((total + 1))
        command -v "$cmd" >/dev/null 2>&1 && presentes=$((presentes + 1))
    done
    AMB_DEV_PRESENTES="$presentes"
    AMB_DEV_TOTAL="$total"
    AMB_DEV_FALTAM=$((total - presentes))
}

ambiente_dev_status() {
    local id="${1:-}"
    ambiente_dev_contar "$id" || { printf 'Desconhecido'; return 1; }
    if [ "$AMB_DEV_FALTAM" -eq 0 ]; then
        printf '✅ Completo'
    elif [ "$AMB_DEV_PRESENTES" -eq 0 ]; then
        printf '○ Não instalado'
    else
        printf '⚠ Incompleto (%d falta)' "$AMB_DEV_FALTAM"
    fi
}

ambiente_dev_faltantes() {
    local id="${1:-}" i cmd saida=""
    ambiente_dev_configurar "$id" || return 1
    for ((i=0; i<${#AMB_DEV_COMANDOS[@]}; i++)); do
        cmd="${AMB_DEV_COMANDOS[$i]}"
        if ! command -v "$cmd" >/dev/null 2>&1; then
            saida+="${saida:+, }${AMB_DEV_ROTULOS[$i]}"
        fi
    done
    printf '%s' "${saida:-nenhum}"
}

versao_comando_curta() {
    local cmd="${1:-}" out=""
    command -v "$cmd" >/dev/null 2>&1 || { printf 'ausente'; return; }
    case "$cmd" in
        java) out="$(java -version 2>&1 | head -n1)" ;;
        javac) out="$(javac -version 2>&1 | head -n1)" ;;
        go) out="$(go version 2>&1 | head -n1)" ;;
        php) out="$(php --version 2>&1 | head -n1)" ;;
        git) out="$(git --version 2>&1 | head -n1)" ;;
        curl) out="$(curl --version 2>&1 | head -n1)" ;;
        make) out="$(make --version 2>&1 | head -n1)" ;;
        *) out="$("$cmd" --version 2>&1 | head -n1 || true)" ;;
    esac
    [ -n "$out" ] || out="instalado"
    printf '%s' "$out"
}

instalar_faltantes_ambiente_dev() {
    local id="${1:-}"
    ambiente_dev_configurar "$id" || return 1
    if [ "$id" = java ]; then
        instalar_jdk_recomendado
        return $?
    fi
    instalar_lista_pacotes "$AMB_DEV_TITULO" "${AMB_DEV_PACOTES[@]}"
}

menu_detalhe_ambiente_dev() {
    local id="${1:-}" escolha i cmd rotulo linha
    while true; do
        ambiente_dev_contar "$id" || return 1
        local -a linhas=()
        for ((i=0; i<${#AMB_DEV_COMANDOS[@]}; i++)); do
            cmd="${AMB_DEV_COMANDOS[$i]}"; rotulo="${AMB_DEV_ROTULOS[$i]}"
            if command -v "$cmd" >/dev/null 2>&1; then
                linha="✅ $rotulo: $(versao_comando_curta "$cmd")"
            else
                linha="○ $rotulo: ausente"
            fi
            linhas+=("$linha")
        done
        cabecalho_tela "$AMB_DEV_ICONE $AMB_DEV_TITULO" "$(ambiente_dev_status "$id")"
        caixa_simples_wrap "Componentes" "${linhas[@]}"
        if [ "$AMB_DEV_FALTAM" -gt 0 ]; then
            caixa_simples "Faltando" "$(ambiente_dev_faltantes "$id")"
        fi
        rodape_atalhos "[0] Voltar  •  [1] Instalar o que falta"
        ui_buffer_flush
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) instalar_faltantes_ambiente_dev "$id" ;;
            0|"") return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

mostrar_ferramentas_instaladas() {
    local escolha id completos incompletos ausentes status
    while true; do
        completos=0; incompletos=0; ausentes=0
        for id in web python java go rust ruby php build; do
            ambiente_dev_contar "$id" || continue
            if [ "$AMB_DEV_FALTAM" -eq 0 ]; then
                completos=$((completos + 1))
            elif [ "$AMB_DEV_PRESENTES" -eq 0 ]; then
                ausentes=$((ausentes + 1))
            else
                incompletos=$((incompletos + 1))
            fi
        done
        menu_unificado "📋 Painel de ferramentas" \
            "$completos completos • $incompletos incompletos • $ausentes ausentes" \
            "[0] Voltar  •  [1–9] Abrir" \
            "1|🌐|Web|$(ambiente_dev_status web)" \
            "2|🐍|Python|$(ambiente_dev_status python)" \
            "3|☕|Java|$(ambiente_dev_status java)" \
            "4|🐹|Go|$(ambiente_dev_status go)" \
            "5|🦀|Rust|$(ambiente_dev_status rust)" \
            "6|💎|Ruby|$(ambiente_dev_status ruby)" \
            "7|🐘|PHP|$(ambiente_dev_status php)" \
            "8|🔧|Compilação|$(ambiente_dev_status build)" \
            "9|📦|Todas as ferramentas|Lista completa detectada"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) menu_detalhe_ambiente_dev web ;;
            2) menu_detalhe_ambiente_dev python ;;
            3) menu_detalhe_ambiente_dev java ;;
            4) menu_detalhe_ambiente_dev go ;;
            5) menu_detalhe_ambiente_dev rust ;;
            6) menu_detalhe_ambiente_dev ruby ;;
            7) menu_detalhe_ambiente_dev php ;;
            8) menu_detalhe_ambiente_dev build ;;
            9) mostrar_lista_ferramentas_detectadas ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

status_comando_curto() {
    local cmd="${1:-}"
    if command -v "$cmd" >/dev/null 2>&1; then
        printf 'Instalado'
    else
        printf 'Ausente'
    fi
}

ambiente_status_comandos() {
    local faltam=0 total=0 cmd
    for cmd in "$@"; do
        total=$((total + 1))
        command -v "$cmd" >/dev/null 2>&1 || faltam=$((faltam + 1))
    done
    if [ "$faltam" -eq 0 ]; then
        printf 'Completo'
    elif [ "$faltam" -eq "$total" ]; then
        printf 'Não instalado'
    else
        printf 'Incompleto (%d falta)' "$faltam"
    fi
}

java_pacote_recomendado() {
    if pacote_disponivel_termux openjdk-17; then
        printf 'openjdk-17'
    elif pacote_disponivel_termux openjdk-21; then
        printf 'openjdk-21'
    else
        printf 'openjdk-17'
    fi
}

menu_java_versoes() {
    local -a opcoes=() pacotes=()
    local n=1 p escolha
    for p in openjdk-17 openjdk-21; do
        pacote_disponivel_termux "$p" || continue
        opcoes+=("$n|☕|$p|$(status_pacote "$p")")
        pacotes+=("$p")
        n=$((n + 1))
    done
    if [ ${#pacotes[@]} -eq 0 ]; then
        cabecalho_tela "☕ Java" "Versões disponíveis"
        caixa_simples "Nenhum JDK listado" "O repositório atual não anunciou OpenJDK 17/21."
        pause
        return
    fi
    while true; do
        menu_unificado "☕ Versões do Java" "Somente versões disponíveis" "[0] Voltar" "${opcoes[@]}"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        [ "$escolha" = 0 ] && return
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#pacotes[@]} ]; then
            instalar_lista_pacotes "${pacotes[$((escolha-1))]}" "${pacotes[$((escolha-1))]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}

instalar_jdk_recomendado() {
    local jdk
    if command -v java >/dev/null 2>&1; then
        cabecalho_tela "☕ Java" "JDK"
        caixa_simples "✅ Java detectado" "Um JDK já está disponível no Termux." "Use Outras versões somente se quiser instalar outra versão."
        pause
        return 0
    fi
    jdk="$(java_pacote_recomendado)"
    instalar_lista_pacotes "JDK recomendado" "$jdk"
}

instalar_java_completo() {
    local jdk
    if command -v java >/dev/null 2>&1; then
        instalar_lista_pacotes "Ambiente Java completo" gradle maven
    else
        jdk="$(java_pacote_recomendado)"
        instalar_lista_pacotes "Ambiente Java completo" "$jdk" gradle maven
    fi
}

menu_java() {
    local jdk
    while true; do
        jdk="$(java_pacote_recomendado)"
        menu_unificado "☕ Ambiente Java" "Java: $(status_comando_curto java)" "[0] Voltar" \
            "1|☕|JDK recomendado|$jdk" \
            "2|📚|Outras versões|OpenJDK disponíveis" \
            "3|🐘|Gradle|$(status_comando_curto gradle)" \
            "4|📦|Maven|$(status_comando_curto mvn)" \
            "5|🧰|Java completo|JDK, Gradle e Maven"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_jdk_recomendado ;;
            2) menu_java_versoes ;;
            3) instalar_lista_pacotes "Gradle" gradle ;;
            4) instalar_lista_pacotes "Maven" maven ;;
            5) instalar_java_completo ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

instalar_gerenciadores_js() {
    local -a por_pkg=() por_npm=()
    local p
    for p in pnpm yarn; do
        if command -v "$p" >/dev/null 2>&1; then
            continue
        elif pacote_disponivel_termux "$p"; then
            por_pkg+=("$p")
        else
            por_npm+=("$p")
        fi
    done
    [ ${#por_pkg[@]} -gt 0 ] && instalar_lista_pacotes "Gerenciadores JavaScript" "${por_pkg[@]}"
    if [ ${#por_npm[@]} -gt 0 ]; then
        command -v npm >/dev/null 2>&1 || instalar_lista_pacotes "Node.js" nodejs || return 1
        cabecalho_tela "🌐 JavaScript" "Gerenciadores adicionais"
        caixa_simples "Instalação via npm" "Pacotes: ${por_npm[*]}" "Serão instalados globalmente."
        confirmar_acao "Instalar via npm?" "s" || return 0
        npm install -g "${por_npm[@]}" >>"$TERMUX_SETUP_LOG" 2>&1 \
            && ok "Gerenciadores JavaScript instalados." \
            || error "Falha ao instalar gerenciadores JavaScript."
        pause
    fi
    if [ ${#por_pkg[@]} -eq 0 ] && [ ${#por_npm[@]} -eq 0 ]; then
        cabecalho_tela "🌐 JavaScript" "Gerenciadores"
        caixa_simples "✅ Pronto" "pnpm e Yarn já estão disponíveis."
        pause
    fi
}

menu_web_dev() {
    while true; do
        menu_unificado "🌐 Desenvolvimento Web" "Node: $(status_comando_curto node) • Git: $(status_comando_curto git)" "[0] Voltar" \
            "1|🧰|Essenciais|Node.js, Git, curl e wget" \
            "2|⬢|Node.js|$(status_comando_curto node)" \
            "3|📦|pnpm / Yarn|Gerenciadores JavaScript" \
            "4|🌐|Git / GitHub|Git e GitHub CLI" \
            "5|✅|Web completo|Essenciais + GitHub CLI"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_lista_pacotes "Web essencial" nodejs git curl wget ;;
            2) instalar_lista_pacotes "Node.js" nodejs ;;
            3) instalar_gerenciadores_js ;;
            4) instalar_lista_pacotes "Git e GitHub" git gh ;;
            5) instalar_lista_pacotes "Web completo" nodejs git curl wget gh ; instalar_gerenciadores_js ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_python_dev() {
    while true; do
        menu_unificado "🐍 Ambiente Python" "Python: $(status_comando_curto python)" "[0] Voltar" \
            "1|🐍|Python básico|Interpretador e pip" \
            "2|🔧|Compilação nativa|Clang, Make e pkg-config" \
            "3|🧰|Python completo|Básico + compilação nativa"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_lista_pacotes "Python básico" python ;;
            2) instalar_lista_pacotes "Compilação para Python" clang make pkg-config ;;
            3) instalar_lista_pacotes "Python completo" python clang make pkg-config ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_compilacao_dev() {
    while true; do
        menu_unificado "🔧 Compilação" "Ferramentas nativas" "[0] Voltar" \
            "1|🔧|Kit básico|Clang, Make e pkg-config" \
            "2|🏗️|CMake|$(status_comando_curto cmake)" \
            "3|🧰|Kit completo|Clang, Make, CMake e pkg-config"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_lista_pacotes "Compilação básica" clang make pkg-config ;;
            2) instalar_lista_pacotes "CMake" cmake ;;
            3) instalar_lista_pacotes "Compilação completa" clang make cmake pkg-config ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

menu_bancos_dev() {
    while true; do
        menu_unificado "💾 Bancos de dados" "Instale somente o necessário" "[0] Voltar" \
            "1|📄|SQLite|Leve • $(status_comando_curto sqlite3)" \
            "2|🐘|PostgreSQL|Servidor • $(status_comando_curto psql)" \
            "3|🗄️|MariaDB|Servidor • $(status_comando_curto mariadb)" \
            "4|⚡|Redis|Cache • $(status_comando_curto redis-server)"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) instalar_lista_pacotes "SQLite" sqlite ;;
            2) instalar_lista_pacotes "PostgreSQL" postgresql ;;
            3) instalar_lista_pacotes "MariaDB" mariadb ;;
            4) instalar_lista_pacotes "Redis" redis ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

adicionar_pacote_unico() {
    local pacote="$1"; shift
    local existente
    for existente in "$@"; do [ "$existente" = "$pacote" ] && return 1; done
    return 0
}

ferramentas_recomendadas_projetos() {
    local raiz="${PAINEL_DIR:-$HOME/Painel}" arquivo base dir jdk
    local -a arquivos=() pacotes=() motivos=()
    local node=0 python=0 php=0 go=0 rust=0 java_maven=0 java_gradle=0 projetos=0
    [ -d "$raiz" ] || {
        cabecalho_tela "🧠 Recomendado" "Análise dos projetos"
        caixa_simples "Nenhum Painel encontrado" "Ainda não há projetos para analisar."
        pause
        return 0
    }
    while IFS= read -r arquivo; do arquivos+=("$arquivo"); done < <(
        find "$raiz" -maxdepth 6 -type f \
            \( -name package.json -o -name requirements.txt -o -name pyproject.toml -o -name composer.json -o -name go.mod -o -name Cargo.toml -o -name pom.xml -o -name build.gradle -o -name build.gradle.kts \) \
            -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' 2>/dev/null | head -n 300
    )
    declare -A vistos=()
    for arquivo in "${arquivos[@]}"; do
        dir="$(dirname "$arquivo")"
        [ -z "${vistos[$dir]:-}" ] && { vistos[$dir]=1; projetos=$((projetos + 1)); }
        base="$(basename "$arquivo")"
        case "$base" in
            package.json) node=$((node + 1)) ;;
            requirements.txt|pyproject.toml) python=$((python + 1)) ;;
            composer.json) php=$((php + 1)) ;;
            go.mod) go=$((go + 1)) ;;
            Cargo.toml) rust=$((rust + 1)) ;;
            pom.xml) java_maven=$((java_maven + 1)) ;;
            build.gradle|build.gradle.kts) java_gradle=$((java_gradle + 1)) ;;
        esac
    done

    if [ "$node" -gt 0 ]; then
        command -v node >/dev/null 2>&1 || pacotes+=(nodejs)
        command -v git >/dev/null 2>&1 || pacotes+=(git)
    fi
    if [ "$python" -gt 0 ]; then command -v python >/dev/null 2>&1 || pacotes+=(python); fi
    if [ "$php" -gt 0 ]; then
        command -v php >/dev/null 2>&1 || pacotes+=(php)
        command -v composer >/dev/null 2>&1 || pacotes+=(composer)
    fi
    if [ "$go" -gt 0 ]; then command -v go >/dev/null 2>&1 || pacotes+=(golang); fi
    if [ "$rust" -gt 0 ]; then command -v cargo >/dev/null 2>&1 || pacotes+=(rust); fi
    if [ "$java_maven" -gt 0 ] || [ "$java_gradle" -gt 0 ]; then
        if ! command -v java >/dev/null 2>&1; then jdk="$(java_pacote_recomendado)"; pacotes+=("$jdk"); fi
        if [ "$java_maven" -gt 0 ]; then command -v mvn >/dev/null 2>&1 || pacotes+=(maven); fi
        if [ "$java_gradle" -gt 0 ]; then command -v gradle >/dev/null 2>&1 || pacotes+=(gradle); fi
    fi

    # Remove duplicatas preservando a ordem.
    local -a unicos=()
    local item achou u
    for item in "${pacotes[@]}"; do
        achou=false
        for u in "${unicos[@]}"; do [ "$u" = "$item" ] && { achou=true; break; }; done
        [ "$achou" = false ] && unicos+=("$item")
    done

    cabecalho_tela "🧠 Recomendado" "Ferramentas para seus projetos"
    caixa_simples "Projetos detectados" \
        "Pastas analisadas: $projetos" \
        "Node: $node • Python: $python • PHP: $php" \
        "Go: $go • Rust: $rust • Java: $((java_maven + java_gradle))"
    if [ ${#unicos[@]} -eq 0 ]; then
        caixa_simples "✅ Ambiente pronto" "Nenhuma ferramenta obrigatória está faltando."
        pause
        return 0
    fi
    caixa_simples "Faltando" "${unicos[*]}"
    confirmar_acao "Instalar somente o que falta?" "s" || return 0
    instalar_lista_pacotes "Recomendado para projetos" "${unicos[@]}"
}

menu_instalar_ferramentas() {
    while true; do
        menu_unificado "🧰 Instalar ferramentas" "Ambientes de desenvolvimento" "[0] Voltar  •  [1–9/A–E] Selecionar" \
            "1|📋|Ferramentas instaladas|Versões e ambientes" \
            "2|🧠|Recomendado|Analisar seus projetos" \
            "3|🌐|Web|$(ambiente_status_comandos node git curl)" \
            "4|🐍|Python|$(ambiente_status_comandos python)" \
            "5|☕|Java|$(ambiente_status_comandos java)" \
            "6|🐹|Go|$(ambiente_status_comandos go)" \
            "7|🦀|Rust|$(ambiente_status_comandos cargo rustc)" \
            "8|💎|Ruby|$(ambiente_status_comandos ruby)" \
            "9|🐘|PHP|$(ambiente_status_comandos php composer)" \
            "A|🔧|Compilação|Clang, Make e CMake" \
            "B|💾|Bancos|SQLite, PostgreSQL e outros" \
            "C|📦|Arquivos e dados|ZIP, unzip e jq" \
            "D|📝|Terminal e editores|Nano, Micro e Fish" \
            "E|🧩|Pacote manual|Nomes do pkg"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) mostrar_ferramentas_instaladas ;;
            2) ferramentas_recomendadas_projetos ;;
            3) menu_web_dev ;;
            4) menu_python_dev ;;
            5) menu_java ;;
            6) instalar_lista_pacotes "Ambiente Go" golang git ;;
            7) instalar_lista_pacotes "Ambiente Rust" rust clang pkg-config git ;;
            8) instalar_lista_pacotes "Ambiente Ruby" ruby clang make pkg-config ;;
            9) instalar_lista_pacotes "Ambiente PHP" php composer git ;;
            [Aa]) menu_compilacao_dev ;;
            [Bb]) menu_bancos_dev ;;
            [Cc]) instalar_lista_pacotes "Arquivos e dados" zip unzip jq ;;
            [Dd]) instalar_lista_pacotes "Terminal e editores" nano micro fish ;;
            [Ee])
                cabecalho_tela "📝 Instalação manual" "Use nomes válidos do pkg"
                local -a manuais=()
                read -rp "Pacotes separados por espaço: " -a manuais
                [ ${#manuais[@]} -gt 0 ] && instalar_lista_pacotes "Pacotes selecionados" "${manuais[@]}"
                ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
