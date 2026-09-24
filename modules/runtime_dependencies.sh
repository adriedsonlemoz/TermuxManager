# Módulo: runtime_dependencies.sh
# Dependências, configuração e testes de projeto.

garantir_env() {
    # Valida configuração sem presumir que todo projeto precisa de .env.
    # Frontends simples (React/Vite/Vue etc.) funcionam normalmente sem ele.
    local dir="$1"
    local tipo framework env_file="$dir/.env" exemplo="$dir/.env.example"

    detectar_stack "$dir"
    tipo="$DETECT_TIPO"
    framework="$DETECT_FRAMEWORK"

    if [ ! -f "$env_file" ]; then
        if [ "$tipo" = "frontend" ]; then
            log "INFO" "Frontend $framework sem .env em $dir; configuração opcional."
            return 0
        fi

        if [ -f "$exemplo" ]; then
            cp "$exemplo" "$env_file"
            warn "Configuração inicial criada em $(basename "$dir")/.env a partir de .env.example."
            info "Revise os valores antes de iniciar serviços externos como banco, Redis ou armazenamento."
        else
            log "INFO" "Nenhum .env encontrado em $dir; o projeto não declarou configuração obrigatória."
            return 0
        fi
    fi

    [ -f "$env_file" ] || return 0

    if [ "$tipo" = "frontend" ]; then
        local api_remota placeholders
        api_remota=$(grep -E '^(VITE_|NEXT_PUBLIC_|REACT_APP_).*(API_URL|BASE_URL|URL)=' "$env_file" 2>/dev/null \
            | grep -Ev '(localhost|127\.0\.0\.1)' || true)
        placeholders=$(printf '%s\n' "$api_remota" | grep -Ei '(SEU-|YOUR_|CHANGE_ME|EXAMPLE|<[^>]+>)' || true)

        if [ -n "$api_remota" ]; then
            caixa_linha_topo
            caixa_linha_texto "${C_BOLD}${C_YELLOW}⚠ API do frontend não está local${C_RESET}" true
            caixa_linha_sep
            if [ -n "$placeholders" ]; then
                caixa_linha_texto "O endereço contém um placeholder."
            else
                caixa_linha_texto "O frontend continuará usando uma API remota."
            fi
            while IFS= read -r linha; do
                [ -n "$linha" ] && caixa_linha_texto "$(truncar_caminho "$linha" $((LARGURA_CAIXA-6)))"
            done <<< "$api_remota"
            caixa_linha_texto "Para testar localmente, use localhost:<porta>/api."
            caixa_linha_baixo
        fi
        return 0
    fi

    # Regras exclusivas de backend. Só valida JWT quando o próprio projeto
    # declara ou referencia essa variável; Express por si só não exige JWT.
    local mongo_val jwt_declarado jwt_val
    mongo_val=$(grep -E '^MONGO_URI=' "$env_file" 2>/dev/null | cut -d= -f2- || true)
    if [ -n "$mongo_val" ] && echo "$mongo_val" | grep -Eq '(<usuario>|<senha>|SEU_|YOUR_|CHANGE_ME|^$)'; then
        warn "MONGO_URI em $(basename "$dir")/.env parece ser um placeholder."
        info "O backend pode aguardar conexão até atingir o timeout."
    fi

    jwt_declarado=false
    grep -qE '^JWT_SECRET=' "$env_file" "$exemplo" 2>/dev/null && jwt_declarado=true
    if [ "$jwt_declarado" = false ]; then
        grep -Rqs --exclude-dir=node_modules --exclude-dir=.git 'JWT_SECRET' "$dir" 2>/dev/null && jwt_declarado=true
    fi

    if [ "$jwt_declarado" = true ]; then
        jwt_val=$(grep -E '^JWT_SECRET=' "$env_file" 2>/dev/null | cut -d= -f2- || true)
        if [ -z "$jwt_val" ]; then
            warn "JWT_SECRET é usado pelo projeto, mas não possui valor em $(basename "$dir")/.env."
            info "Gere um segredo seguro com: openssl rand -hex 64"
        elif [ "${#jwt_val}" -lt 16 ]; then
            warn "JWT_SECRET possui menos de 16 caracteres e pode ser rejeitado pelo backend."
            info "Gere um segredo seguro com: openssl rand -hex 64"
        fi
    fi
}

hash_dependencias() {
    local dir="$1" arquivo saida=""
    for arquivo in package.json package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock requirements.txt pyproject.toml composer.json composer.lock go.mod go.sum Cargo.toml Cargo.lock pom.xml build.gradle build.gradle.kts; do
        [ -f "$dir/$arquivo" ] || continue
        if comando_existe sha256sum; then
            saida+="$(sha256sum "$dir/$arquivo" 2>/dev/null)"
        elif comando_existe shasum; then
            saida+="$(shasum -a 256 "$dir/$arquivo" 2>/dev/null)"
        else
            saida+="$(wc -c < "$dir/$arquivo" 2>/dev/null):$(date -r "$dir/$arquivo" +%s 2>/dev/null)"
        fi
    done
    printf '%s' "$saida" | { if comando_existe sha256sum; then sha256sum | cut -d' ' -f1; elif comando_existe shasum; then shasum -a 256 | cut -d' ' -f1; else cat; fi; }
}

# O estado de dependências fica fora do projeto. Assim uma atualização que
# substitui frontend/backend ou outros arquivos não apaga a assinatura e não
# força npm/pnpm/yarn a instalar tudo novamente sem necessidade.
dependency_stamp_path() {
    local dir="$1" base="$HOME/.termux-manager/dependencies" chave caminho
    mkdir -p "$base" 2>/dev/null || true
    caminho="$(cd "$dir" 2>/dev/null && pwd -P || printf '%s' "$dir")"
    if comando_existe sha256sum; then
        chave="$(printf '%s' "$caminho" | sha256sum | cut -d' ' -f1)"
    elif comando_existe shasum; then
        chave="$(printf '%s' "$caminho" | shasum -a 256 | cut -d' ' -f1)"
    else
        chave="$(printf '%s' "$caminho" | sed 's#[^A-Za-z0-9._-]#_#g')"
    fi
    printf '%s/%s.hash' "$base" "$chave"
}

integrity_stamp_path() {
    local dir="$1" dep
    dep="$(dependency_stamp_path "$dir")"
    printf '%s.integrity' "$dep"
}

integridade_cache_chave() {
    local dir="$1" deps_hash tree_sig
    deps_hash="$(hash_dependencias "$dir" 2>/dev/null || true)"
    [ -n "$deps_hash" ] || return 1
    [ -d "$dir/node_modules" ] || return 1
    # Assinatura leve dos diretórios de pacotes. É bem mais barata que npm ls
    # + require, mas ainda muda quando um pacote direto é alterado/corrompido.
    # maxdepth=2 cobre também pacotes com escopo (@scope/pacote).
    if comando_existe sha256sum; then
        tree_sig="$(find "$dir/node_modules" -mindepth 1 -maxdepth 2 -type d -printf '%P:%T@\n' 2>/dev/null | sort | sha256sum | cut -d' ' -f1)"
    else
        tree_sig="$(find "$dir/node_modules" -mindepth 1 -maxdepth 2 -type d -printf '%P:%T@\n' 2>/dev/null | sort | cksum | awk '{print $1}')"
    fi
    printf '%s:%s' "$deps_hash" "$tree_sig"
}

integridade_cache_valida() {
    local dir="$1" stamp chave salva
    stamp="$(integrity_stamp_path "$dir")"
    [ -f "$stamp" ] || return 1
    chave="$(integridade_cache_chave "$dir" 2>/dev/null || true)"
    [ -n "$chave" ] || return 1
    salva="$(cat "$stamp" 2>/dev/null || true)"
    [ "$chave" = "$salva" ]
}

marcar_integridade_validada() {
    local dir="$1" stamp chave
    stamp="$(integrity_stamp_path "$dir")"
    chave="$(integridade_cache_chave "$dir" 2>/dev/null || true)"
    [ -n "$chave" ] || return 0
    printf '%s
' "$chave" > "$stamp" 2>/dev/null || true
}

dependencias_presentes_basicas() {
    local dir="$1" gerenciador="$2"
    case "$gerenciador" in
        npm|pnpm|yarn) [ -d "$dir/node_modules" ] ;;
        composer) [ -d "$dir/vendor" ] ;;
        pip) comando_existe python && comando_existe pip ;;
        go) comando_existe go ;;
        cargo) comando_existe cargo ;;
        maven) comando_existe mvn ;;
        gradle) [ -f "$dir/gradlew" ] || comando_existe gradle ;;
        *) return 1 ;;
    esac
}

# Na primeira execução após atualizar o Manager pode existir node_modules sem
# assinatura externa. Faz uma checagem local e barata antes de baixar qualquer
# coisa. Para Node, os próprios gerenciadores validam dependências de topo.
verificar_integridade_node_modules() {
    # Validação local sem downloads. Evita falsos positivos de `npm ls --all`
    # (peer/transitivas opcionais) e registra exatamente qual etapa/pacote falhou.
    local dir="$1" log_tmp="${SESSION_TMP_DIR:-${TMPDIR:-/tmp}}/deps_integrity_$$.log"
    INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO=""
    mkdir -p "$(dirname "$log_tmp")" 2>/dev/null || return 1
    comando_existe node || { INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO="Node indisponível"; return 1; }
    comando_existe npm || { INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO="npm indisponível"; return 1; }
    [ -f "$dir/package.json" ] || { INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO="package.json ausente"; return 1; }
    [ -d "$dir/node_modules" ] || { INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO="node_modules ausente"; return 1; }

    # Testes repetidos do mesmo projeto não precisam percorrer npm ls + require
    # em toda execução. O cache é invalidado quando manifests ou node_modules
    # mudam; qualquer falha real na inicialização ainda aciona o reparo normal.
    if integridade_cache_valida "$dir"; then
        log "INFO" "Integridade reutilizada do cache em $(caminho_home_relativo "$dir")."
        return 0
    fi

    # Só valida dependências de topo. `--all` pode falhar por detalhes de peers
    # transitivos que não impedem o projeto de iniciar.
    if ! (cd "$dir" && npm ls --depth=0 --silent >"$log_tmp" 2>&1); then
        INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO="npm ls --depth=0 encontrou dependência direta ausente/inválida"
        log "WARN" "${INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO} em $(caminho_home_relativo "$dir")."
        tail -n 35 "$log_tmp" >> "$LOG_FILE" 2>/dev/null || true
        rm -f "$log_tmp" 2>/dev/null || true
        return 1
    fi

    if ! (cd "$dir" && node <<'NODE' >"$log_tmp" 2>&1
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const deps = Object.keys({ ...(pkg.dependencies || {}), ...(pkg.optionalDependencies || {}) });
let failed = false;
for (const name of deps) {
  try {
    require.resolve(name, { paths: [process.cwd()] });
  } catch (err) {
    failed = true;
    console.error(`PACOTE=${name}\nETAPA=require.resolve\n${String(err && err.stack ? err.stack : err)}`);
    continue;
  }
  try {
    require(name);
  } catch (err) {
    const text = String(err && err.stack ? err.stack : err);
    const missing = err && (err.code === 'MODULE_NOT_FOUND' || err.code === 'ERR_MODULE_NOT_FOUND');
    const missingFile = err && err.code === 'ENOENT' && /node_modules/.test(text);
    const esm = err && (err.code === 'ERR_REQUIRE_ESM' || err.code === 'ERR_PACKAGE_PATH_NOT_EXPORTED');
    if (esm || (!missing && !missingFile)) continue;
    failed = true;
    console.error(`PACOTE=${name}\nETAPA=require\n${text}`);
  }
}
process.exit(failed ? 1 : 0);
NODE
    ); then
        INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO="Falha ao carregar uma dependência direta"
        local pacote etapa
        pacote="$(sed -n 's/^PACOTE=//p' "$log_tmp" | head -n1)"
        etapa="$(sed -n 's/^ETAPA=//p' "$log_tmp" | head -n1)"
        [ -n "$pacote" ] && INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO+=" ($pacote${etapa:+ • $etapa})"
        log "WARN" "Integridade de node_modules falhou em $(caminho_home_relativo "$dir"): $INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO"
        tail -n 40 "$log_tmp" >> "$LOG_FILE" 2>/dev/null || true
        rm -f "$log_tmp" 2>/dev/null || true
        return 1
    fi
    rm -f "$log_tmp" 2>/dev/null || true
    marcar_integridade_validada "$dir"
    return 0
}

verificar_dependencias_existentes() {
    local dir="$1" gerenciador="$2"
    dependencias_presentes_basicas "$dir" "$gerenciador" || return 1
    case "$gerenciador" in
        npm)
            verificar_integridade_node_modules "$dir"
            ;;
        pnpm)
            comando_existe pnpm || return 1
            (cd "$dir" && pnpm list --depth 0 >/dev/null 2>&1)
            ;;
        yarn)
            comando_existe yarn || return 1
            (cd "$dir" && yarn list --depth=0 >/dev/null 2>&1) || \
                (cd "$dir" && yarn install --mode=skip-build --immutable --immutable-cache --check-cache >/dev/null 2>&1)
            ;;
        *)
            # Para os demais ecossistemas, a presença da pasta/comando é o
            # indicador seguro disponível sem disparar download ou build.
            return 0
            ;;
    esac
}

invalidar_cache_dependencias() {
    local dir="$1" stamp
    stamp="$(dependency_stamp_path "$dir")"
    rm -f "$stamp" "${stamp}.integrity" "$dir/.manager-deps.hash" 2>/dev/null || true
}

log_indica_dependencia_corrompida() {
    local logf="$1"
    [ -s "$logf" ] || return 1
    tail -n 120 "$logf" 2>/dev/null | grep -qiE \
        '(MODULE_NOT_FOUND|Cannot find module|ERR_MODULE_NOT_FOUND|Cannot find package|ENOENT.*node_modules|npm ERR!.*missing)'
}

reparar_dependencias_corrompidas() {
    # reparar_dependencias_corrompidas <dir> <gerenciador>
    local dir="$1" gerenciador="$2" nome log_tmp
    nome="$(basename "$dir")"
    mkdir -p "$SESSION_TMP_DIR"
    log_tmp="$SESSION_TMP_DIR/repair_${nome}_$$.log"
    invalidar_cache_dependencias "$dir"

    warn "Instalação de dependências de $nome parece corrompida. Reparando automaticamente..."
    case "$gerenciador" in
        npm)
            garantir_comando node nodejs || return 1
            comando_existe npm || return 1
            if [ -f "$dir/package-lock.json" ] || [ -f "$dir/npm-shrinkwrap.json" ]; then
                # Remove explicitamente antes do npm ci. Além de tornar o reparo
                # determinístico no Termux, evita sobras de árvores parcialmente copiadas.
                rm -rf "$dir/node_modules" || return 1
                (cd "$dir" && executar_com_progresso "Reparando dependências de $nome (npm ci)" "$log_tmp" npm ci) || return 1
            else
                rm -rf "$dir/node_modules" || return 1
                (cd "$dir" && executar_com_progresso "Reparando dependências de $nome" "$log_tmp" npm install) || return 1
            fi
            ;;
        pnpm)
            comando_existe pnpm || return 1
            rm -rf "$dir/node_modules" || return 1
            (cd "$dir" && executar_com_progresso "Reparando dependências de $nome" "$log_tmp" pnpm install --force) || return 1
            ;;
        yarn)
            comando_existe yarn || return 1
            rm -rf "$dir/node_modules" || return 1
            (cd "$dir" && executar_com_progresso "Reparando dependências de $nome" "$log_tmp" yarn install) || return 1
            ;;
        *)
            warn "Reparo automático ainda não está disponível para $gerenciador."
            return 1
            ;;
    esac

    if ! verificar_dependencias_existentes "$dir" "$gerenciador"; then
        error "As dependências ainda parecem inconsistentes após o reparo."
        [ -n "${INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO:-}" ] && error "Detalhe: $INTEGRIDADE_DEPENDENCIAS_ULTIMO_ERRO"
        return 1
    fi
    hash_dependencias "$dir" > "$(dependency_stamp_path "$dir")" 2>/dev/null || true
    ok "Dependências de $nome reparadas e verificadas."
    return 0
}

dependencias_atualizadas() {
    local dir="$1" gerenciador="$2" atual salvo stamp legado
    stamp="$(dependency_stamp_path "$dir")"
    dependencias_presentes_basicas "$dir" "$gerenciador" || return 1
    atual="$(hash_dependencias "$dir")"
    [ -n "$atual" ] || return 1

    # Migra a assinatura antiga que ficava dentro do projeto.
    legado="$dir/.manager-deps.hash"
    if [ ! -f "$stamp" ] && [ -f "$legado" ]; then
        salvo="$(cat "$legado" 2>/dev/null)"
        if [ "$atual" = "$salvo" ]; then
            printf '%s\n' "$atual" > "$stamp" 2>/dev/null || true
            rm -f "$legado" 2>/dev/null || true
        fi
    fi

    [ -f "$stamp" ] || return 1
    salvo="$(cat "$stamp" 2>/dev/null)"
    [ "$atual" = "$salvo" ]
}

executar_com_progresso() {
    # executar_com_progresso <titulo> <log_temporario> <comando...>
    local titulo="$1" log_tmp="$2"; shift 2
    local pid status=0 frame=0 ultima="" largura=68
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

    : > "$log_tmp"
    "$@" >"$log_tmp" 2>&1 &
    pid=$!

    trap 'kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; trap - INT; printf "\n"; return 130' INT

    if [ "$UI_LIVE_BOX_ACTIVE" = true ]; then
        caixa_linha_texto "${C_YELLOW}⏳${C_RESET} $titulo..."
        while kill -0 "$pid" 2>/dev/null; do
            ultima=$(tail -n 1 "$log_tmp" 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g')
            [ -z "$ultima" ] && ultima="Aguardando saída..."
            ultima="$(truncar_visivel "$ultima" 23)"
            printf '\033[1A\r\033[2K'
            caixa_linha_texto "${C_CYAN}${frames[$frame]}${C_RESET} $titulo • ${C_DIM}${ultima}${C_RESET}"
            frame=$(( (frame + 1) % ${#frames[@]} ))
            sleep 0.35
        done
        wait "$pid" || status=$?
        trap - INT
        printf '\033[1A\r\033[2K'
        if [ "$status" -eq 0 ]; then
            caixa_linha_texto "${C_GREEN}✔${C_RESET} $titulo concluído."
        else
            caixa_linha_texto "${C_RED}✘${C_RESET} $titulo falhou (código $status)."
        fi
    else
        printf '\n'
        while kill -0 "$pid" 2>/dev/null; do
            ultima=$(tail -n 1 "$log_tmp" 2>/dev/null | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g')
            [ -z "$ultima" ] && ultima="Aguardando saída do gerenciador de pacotes..."
            ultima=$(printf '%s' "$ultima" | cut -c1-$largura)
            printf '\r\033[2K  %s %s\n\033[2K     %s\033[1A' "${frames[$frame]}" "$titulo" "$ultima"
            frame=$(( (frame + 1) % ${#frames[@]} ))
            sleep 0.35
        done
        wait "$pid" || status=$?
        trap - INT
        printf '\r\033[2K\033[1B\r\033[2K'
        if [ "$status" -eq 0 ]; then
            printf '  ✓ %s concluído.\n' "$titulo"
        else
            printf '  ✗ %s falhou (código %s).\n' "$titulo" "$status"
        fi
    fi

    cat "$log_tmp" >> "$LOG_FILE" 2>/dev/null || true
    if [ "$status" -ne 0 ] && [ "$UI_LIVE_BOX_ACTIVE" != true ]; then
        echo
        tail -n 15 "$log_tmp" 2>/dev/null
        echo
    fi
    rm -f "$log_tmp"
    return "$status"
}

instalar_dependencias() (
    local dir="$1"
    local gerenciador="${2:-$DETECT_GERENCIADOR}"
    local nome="$(basename "$dir")" cmd_desc="" log_tmp stamp atual_hash
    mkdir -p "$SESSION_TMP_DIR"
    log_tmp="$SESSION_TMP_DIR/install_${nome}_$$.log"
    stamp="$(dependency_stamp_path "$dir")"

    cd "$dir" || { error "Não foi possível acessar $dir"; return 1; }
    garantir_env "$dir"

    if dependencias_atualizadas "$dir" "$gerenciador"; then
        # Caminho ultrarrápido usado imediatamente após uma importação/cópia.
        # Se os manifests continuam com a mesma assinatura e a árvore instalada
        # existe, não percorremos node_modules nem executamos npm ls/require.
        # Uma falha real na subida continua sendo detectada pelos health checks
        # e pelo reparo automático já existente.
        if [ "${TESTE_POS_IMPORTACAO_RAPIDO:-false}" = true ] && dependencias_presentes_basicas "$dir" "$gerenciador"; then
            ok "Dependências de $nome inalteradas • verificação profunda pulada (modo rápido)."
            return 0
        fi
        if verificar_dependencias_existentes "$dir" "$gerenciador"; then
            ok "Dependências de $nome já estão atualizadas e íntegras. Instalação ignorada."
            return 0
        fi
        warn "O cache indica dependências atualizadas, mas a instalação local está inconsistente."
        invalidar_cache_dependencias "$dir"
        if reparar_dependencias_corrompidas "$dir" "$gerenciador"; then
            return 0
        fi
        return 1
    fi

    # Se ainda não existe assinatura (por exemplo, primeiro teste após migrar
    # para esta versão), verifica o que já está instalado antes de reinstalar.
    if [ ! -f "$stamp" ] && verificar_dependencias_existentes "$dir" "$gerenciador"; then
        atual_hash="$(hash_dependencias "$dir")"
        [ -n "$atual_hash" ] && printf '%s\n' "$atual_hash" > "$stamp" 2>/dev/null || true
        ok "Dependências de $nome já existem e foram verificadas. Instalação ignorada."
        return 0
    fi

    case "$gerenciador" in
        npm)
            garantir_comando node nodejs || return 1
            cmd_desc="npm em $nome"
            if [ ! -d "$dir/node_modules" ] && { [ -f "$dir/package-lock.json" ] || [ -f "$dir/npm-shrinkwrap.json" ]; }; then
                if ! executar_com_progresso "Instalando $cmd_desc (npm ci rápido)" "$log_tmp" npm ci --prefer-offline --no-audit --no-fund --progress=false; then
                    warn "npm ci não pôde ser usado; tentando npm install compatível..."
                    executar_com_progresso "Instalando $cmd_desc" "$log_tmp" npm install --prefer-offline --no-audit --no-fund --progress=false || return 1
                fi
            else
                executar_com_progresso "Instalando $cmd_desc" "$log_tmp" npm install --prefer-offline --no-audit --no-fund --progress=false || return 1
            fi
            ;;
        pnpm)
            garantir_comando node nodejs || return 1
            if ! comando_existe pnpm; then
                executar_com_progresso "Instalando pnpm" "$log_tmp" npm install -g pnpm || return 1
            fi
            cmd_desc="pnpm em $nome"
            executar_com_progresso "Instalando $cmd_desc" "$log_tmp" pnpm install || return 1
            ;;
        yarn)
            garantir_comando node nodejs || return 1
            if ! comando_existe yarn; then
                executar_com_progresso "Instalando yarn" "$log_tmp" npm install -g yarn || return 1
            fi
            cmd_desc="yarn em $nome"
            executar_com_progresso "Instalando $cmd_desc" "$log_tmp" yarn install || return 1
            ;;
        pip)
            garantir_comando python python || return 1
            garantir_comando pip python-pip || return 1
            if [ -f requirements.txt ]; then
                executar_com_progresso "Instalando pip em $nome" "$log_tmp" pip install -r requirements.txt || return 1
            elif [ -f pyproject.toml ]; then
                executar_com_progresso "Instalando pip em $nome" "$log_tmp" pip install . || return 1
            fi
            ;;
        composer)
            garantir_comando php php || return 1
            garantir_comando composer composer || return 1
            executar_com_progresso "Instalando Composer em $nome" "$log_tmp" composer install --no-interaction || return 1
            ;;
        go)
            garantir_comando go golang || return 1
            executar_com_progresso "Baixando módulos Go de $nome" "$log_tmp" go mod download || return 1
            ;;
        cargo)
            garantir_comando cargo rust || return 1
            executar_com_progresso "Baixando crates de $nome" "$log_tmp" cargo fetch || return 1
            ;;
        maven)
            garantir_comando mvn maven || return 1
            garantir_comando java openjdk-17 || return 1
            executar_com_progresso "Preparando Maven em $nome" "$log_tmp" mvn install -DskipTests || return 1
            ;;
        gradle)
            garantir_comando java openjdk-17 || return 1
            if [ -f ./gradlew ]; then
                chmod +x ./gradlew
                executar_com_progresso "Preparando Gradle em $nome" "$log_tmp" ./gradlew build -x test || return 1
            else
                garantir_comando gradle gradle || return 1
                executar_com_progresso "Preparando Gradle em $nome" "$log_tmp" gradle build -x test || return 1
            fi
            ;;
        *)
            warn "Gerenciador de dependências não identificado. Pulando instalação automática."
            return 1
            ;;
    esac

    hash_dependencias "$dir" > "$stamp" 2>/dev/null || true
    rm -f "$dir/.manager-deps.hash" 2>/dev/null || true
    return 0
)

verificar_instalacao() {
    local dir="$1"
    local gerenciador="${2:-$DETECT_GERENCIADOR}"
    local pendencias=()

    case "$gerenciador" in
        npm|pnpm|yarn)
            [ ! -d "$dir/node_modules" ] && pendencias+=("node_modules não foi criado")
            ;;
        pip)
            comando_existe python || pendencias+=("python não instalado")
            ;;
        composer)
            [ ! -d "$dir/vendor" ] && pendencias+=("pasta vendor não foi criada")
            ;;
        go)
            comando_existe go || pendencias+=("go não instalado")
            ;;
        cargo)
            [ ! -f "$dir/Cargo.lock" ] && pendencias+=("Cargo.lock não gerado")
            ;;
        maven)
            comando_existe mvn || pendencias+=("maven não instalado")
            ;;
        gradle)
            [ ! -d "$dir/build" ] && [ ! -f "$dir/gradlew" ] && pendencias+=("build não gerado")
            ;;
    esac

    if [ ${#pendencias[@]} -eq 0 ]; then
        ok "Verificação concluída: todas as dependências estão instaladas."
        return 0
    else
        error "Pendências encontradas:"
        for p in "${pendencias[@]}"; do
            echo "   - $p"
        done
        return 1
    fi
}

# ============================================================================
# TESTAR PROJETO (fluxo principal)
# ============================================================================

finalizar_painel_teste_falha() {
    # finalizar_painel_teste_falha <projeto> <processo_front> <processo_back> <motivo>
    local projeto="$1" nome_front="$2" nome_back="$3" motivo="$4" escolha
    [ "${UI_LIVE_BOX_ACTIVE:-false}" = true ] && ui_live_box_end

    while true; do
        caixa_simples "⚠ Teste interrompido" \
            "$motivo" \
            "[1] Coletar logs do teste em Downloads" \
            "[2] Ver últimas linhas do backend" \
            "[0] Voltar"
        rodape_atalhos "[1] Coletar logs  •  [2] Backend  •  [0] Voltar"
        ui_buffer_flush
        read -r escolha
        case "$escolha" in
            1)
                if coletar_logs_teste_projeto "$projeto" "$nome_front" "$nome_back" "$motivo"; then
                    caixa_simples "📦 Logs coletados" \
                        "Arquivo: $(basename "$ULTIMO_RELATORIO_TESTE")" \
                        "Destino: $(caminho_home_relativo "$ULTIMO_RELATORIO_TESTE")" \
                        "Backend + frontend + Manager reunidos" \
                        "Segredos comuns: removidos"
                    pause
                    return 0
                fi
                error "Não foi possível exportar os logs do teste."
                pause
                return 1
                ;;
            2)
                local blog="$LOG_DIR/${nome_back}.log"
                if [ -f "$blog" ]; then
                    echo
                    tail -n 40 "$blog"
                    echo
                else
                    warn "Log do backend ainda não existe."
                fi
                pause
                ;;
            0|"") return 0 ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

preparar_logs_nova_execucao_teste() {
    # preparar_logs_nova_execucao_teste <processo_front> <processo_back>
    # Rotaciona logs ANTES de validar dependências. Assim, se a preparação falhar,
    # o relatório não anexa um erro de uma execução anterior do backend/frontend.
    local nome_front="$1" nome_back="$2" nome logf
    mkdir -p "$LOG_DIR"
    for nome in "$nome_back" "$nome_front"; do
        [ -n "$nome" ] || continue
        logf="$LOG_DIR/${nome}.log"
        if [ -s "$logf" ]; then
            mv -f "$logf" "${logf}.previous" 2>/dev/null || true
        fi
        : > "$logf"
    done
}

testar_componente() {
    local projeto="$1" alvo="$2"
    detectar_estrutura_projeto "$projeto"
    local nome_base nome_front_ident nome_back_ident
    nome_base="$(basename "$projeto")"
    nome_processo_projeto "$projeto" frontend; nome_front_ident="$NOME_PROCESSO"
    nome_processo_projeto "$projeto" backend; nome_back_ident="$NOME_PROCESSO"

    if [ "$PROJ_MODO" != "fullstack" ]; then
        testar_projeto "$projeto"
        return
    fi

    case "$alvo" in
        frontend)
            title "Testando Frontend: $FRONT_FRAMEWORK"
            instalar_dependencias "$FRONT_DIR" "$FRONT_GERENCIADOR"
            verificar_instalacao "$FRONT_DIR" "$FRONT_GERENCIADOR" || { pause; return; }
            DETECT_FRAMEWORK="$FRONT_FRAMEWORK"
            executar_em_background "$FRONT_DIR" "$FRONT_RUN_CMD" "$nome_front_ident" "$projeto" frontend || { pause; return; }
            esperar_porta_e_abrir "$nome_front_ident"
            ;;
        backend)
            title "Testando Backend: $BACK_FRAMEWORK"
            instalar_dependencias "$BACK_DIR" "$BACK_GERENCIADOR"
            verificar_instalacao "$BACK_DIR" "$BACK_GERENCIADOR" || { pause; return; }
            executar_em_background "$BACK_DIR" "$BACK_RUN_CMD" "$nome_back_ident" "$projeto" backend || { pause; return; }
            aguardar_backend_local "$BACK_DIR" "$nome_back_ident" 20 || true
            info "Log do backend: $(caminho_home_relativo "$LOG_DIR/${nome_back_ident}.log")"
            ;;
        ambos)
            local nome_back_teste="$nome_back_ident" nome_front_teste="$nome_front_ident"
            preparar_logs_nova_execucao_teste "$nome_front_teste" "$nome_back_teste"
            tela_limpar
            ui_live_box_begin "🧪 Testando Frontend + Backend" "$(basename "$projeto") • verificação integrada"

            ui_live_box_section "1/4 • Backend — $BACK_FRAMEWORK"
            info "Verificando configuração e dependências..."
            if ! instalar_dependencias "$BACK_DIR" "$BACK_GERENCIADOR"; then
                error "Falha ao preparar as dependências do backend."
                finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "Falha ao preparar dependências do backend."
                return
            fi
            if ! verificar_instalacao "$BACK_DIR" "$BACK_GERENCIADOR"; then
                error "Dependências do backend incompletas."
                finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "Dependências do backend incompletas."
                return
            fi

            ui_live_box_section "2/4 • Frontend — $FRONT_FRAMEWORK"
            info "Verificando configuração e dependências..."
            if ! instalar_dependencias "$FRONT_DIR" "$FRONT_GERENCIADOR"; then
                error "Falha ao preparar as dependências do frontend."
                finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "Falha ao preparar dependências do frontend."
                return
            fi
            if ! verificar_instalacao "$FRONT_DIR" "$FRONT_GERENCIADOR"; then
                error "Dependências do frontend incompletas."
                finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "Dependências do frontend incompletas."
                return
            fi

            ui_live_box_section "3/4 • Inicialização paralela"
            if ! executar_em_background "$BACK_DIR" "$BACK_RUN_CMD" "$nome_back_teste" "$projeto" backend; then
                error "Não foi possível iniciar o backend."
                finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "O processo do backend não pôde ser iniciado."
                return
            fi
            DETECT_FRAMEWORK="$FRONT_FRAMEWORK"
            if ! executar_em_background "$FRONT_DIR" "$FRONT_RUN_CMD" "$nome_front_teste" "$projeto" frontend; then
                error "Não foi possível iniciar o frontend."
                parar_processo "$nome_back_teste" >/dev/null 2>&1 || true
                finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "O processo do frontend não pôde ser iniciado."
                return
            fi
            if ! aguardar_backend_local "$BACK_DIR" "$nome_back_teste" 25; then
                if log_indica_dependencia_corrompida "$LOG_DIR/${nome_back_teste}.log"; then
                    warn "O log indica dependência ausente ou node_modules corrompido."
                    info "O Manager tentará um reparo limpo uma única vez."
                    parar_processo "$nome_back_teste" >/dev/null 2>&1 || true
                    if reparar_dependencias_corrompidas "$BACK_DIR" "$BACK_GERENCIADOR"; then
                        info "Reiniciando backend após o reparo..."
                        if executar_em_background "$BACK_DIR" "$BACK_RUN_CMD" "$nome_back_teste" "$projeto" backend \
                            && aguardar_backend_local "$BACK_DIR" "$nome_back_teste" 25; then
                            ok "Backend recuperado após reparar as dependências."
                        else
                            warn "O backend continua indisponível após o reparo automático."
                            parar_processo "$nome_front_teste" >/dev/null 2>&1 || true
                            finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "Backend continuou indisponível após reparar dependências corrompidas."
                            return
                        fi
                    else
                        parar_processo "$nome_front_teste" >/dev/null 2>&1 || true
                        finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "Falha ao reparar automaticamente as dependências do backend."
                        return
                    fi
                else
                    warn "Backend iniciado, mas o servidor não ficou disponível."
                    warn "Backend indisponível; o frontend iniciado em paralelo será encerrado."
                    parar_processo "$nome_front_teste" >/dev/null 2>&1 || true
                    finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "Backend ativo, mas o servidor não respondeu na porta esperada."
                    return
                fi
            fi
            ok "Backend disponível e respondendo localmente."

            ui_live_box_section "4/4 • Disponibilidade"
            if ! esperar_porta_e_abrir "$nome_front_teste"; then
                finalizar_painel_teste_falha "$projeto" "$nome_front_teste" "$nome_back_teste" "Frontend iniciado, mas o servidor não ficou disponível."
                return
            fi
            ui_live_box_end
            ;;
        *) error "Componente inválido." ;;
    esac
    pause
}

testar_projeto() {
    local projeto="$1"
    title "Testando Projeto: $(basename "$projeto")"

    detectar_estrutura_projeto "$projeto"

    case "$PROJ_MODO" in
        desconhecido)
            error "Não foi possível identificar a tecnologia do projeto."
            info "Verifique se existem arquivos como package.json, requirements.txt, composer.json, go.mod, Cargo.toml, pom.xml, build.gradle (na raiz ou em subpastas frontend/backend)."
            pause
            return
            ;;
        fullstack)
            ok "Projeto único identificado com FRONTEND + BACKEND."
            info "Frontend: $FRONT_FRAMEWORK  ($FRONT_DIR)"
            info "Backend:  $BACK_FRAMEWORK  ($BACK_DIR)"
            log "INFO" "Fullstack em $projeto -> front:$FRONT_FRAMEWORK back:$BACK_FRAMEWORK"

            echo
            info "Etapa 1/2 — preparando FRONTEND ($FRONT_FRAMEWORK)..."
            instalar_dependencias "$FRONT_DIR" "$FRONT_GERENCIADOR" || { error "Não foi possível preparar o frontend."; pause; return; }
            info "Etapa 2/2 — preparando BACKEND ($BACK_FRAMEWORK)..."
            instalar_dependencias "$BACK_DIR" "$BACK_GERENCIADOR" || { error "Não foi possível preparar o backend."; pause; return; }

            echo
            info "Verificação final..."
            echo -e "${C_BOLD}Frontend:${C_RESET}"
            verificar_instalacao "$FRONT_DIR" "$FRONT_GERENCIADOR"
            echo -e "${C_BOLD}Backend:${C_RESET}"
            verificar_instalacao "$BACK_DIR" "$BACK_GERENCIADOR"
            ;;
        simples_frontend)
            ok "Tecnologia detectada: $FRONT_FRAMEWORK (frontend)"
            info "Gerenciador de pacotes: $FRONT_GERENCIADOR"
            log "INFO" "Frontend em $projeto: $FRONT_FRAMEWORK / $FRONT_GERENCIADOR"
            instalar_dependencias "$FRONT_DIR" "$FRONT_GERENCIADOR" || { error "Não foi possível preparar o frontend."; pause; return; }
            echo; info "Verificação final..."
            verificar_instalacao "$FRONT_DIR" "$FRONT_GERENCIADOR"
            ;;
        simples_backend)
            ok "Tecnologia detectada: $BACK_FRAMEWORK (backend)"
            info "Gerenciador de pacotes: $BACK_GERENCIADOR"
            log "INFO" "Backend em $projeto: $BACK_FRAMEWORK / $BACK_GERENCIADOR"
            instalar_dependencias "$BACK_DIR" "$BACK_GERENCIADOR" || { error "Não foi possível preparar o backend."; pause; return; }
            echo; info "Verificação final..."
            verificar_instalacao "$BACK_DIR" "$BACK_GERENCIADOR"
            ;;
    esac

    menu_executar_projeto "$projeto"
}

# ============================================================================
# CONTROLE DE PIDFILES
# ============================================================================

