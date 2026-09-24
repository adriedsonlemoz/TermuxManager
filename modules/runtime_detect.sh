# Módulo: runtime_detect.sh
# Detecção de stack e estrutura de projetos.

# ============================================================================
# DETECÇÃO DE TECNOLOGIA
# ============================================================================

# Variáveis globais preenchidas por detectar_stack()
DETECT_TIPO=""          # frontend | backend | fullstack | desconhecido
DETECT_FRAMEWORK=""     # nome amigável
DETECT_GERENCIADOR=""   # npm | pnpm | yarn | pip | composer | go | cargo | maven/gradle
DETECT_RUN_CMD=""       # comando sugerido para rodar

node_package_dependency_names() {
    # Retorna somente dependências reais do package.json. A implementação
    # antiga coletava qualquer chave JSON e podia confundir nome de script,
    # configuração ou metadata com framework instalado.
    local pkgjson="$1" py=""
    [ -f "$pkgjson" ] || return 1

    if comando_existe jq; then
        jq -r '((.dependencies // {}) + (.devDependencies // {}) + (.optionalDependencies // {}) + (.peerDependencies // {})) | keys[]' "$pkgjson" 2>/dev/null
        return $?
    fi
    if comando_existe node; then
        node - "$pkgjson" <<'NODE' 2>/dev/null
const fs = require('fs');
const file = process.argv[2];
const pkg = JSON.parse(fs.readFileSync(file, 'utf8'));
const deps = Object.assign({}, pkg.dependencies || {}, pkg.devDependencies || {}, pkg.optionalDependencies || {}, pkg.peerDependencies || {});
Object.keys(deps).forEach(k => console.log(k));
NODE
        return $?
    fi
    if comando_existe python3; then py=python3; elif comando_existe python; then py=python; fi
    if [ -n "$py" ]; then
        "$py" - "$pkgjson" <<'PYJSON' 2>/dev/null
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    pkg = json.load(f)
keys = set()
for section in ('dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies'):
    value = pkg.get(section) or {}
    if isinstance(value, dict):
        keys.update(value)
for key in sorted(keys):
    print(key)
PYJSON
        return $?
    fi

    # Fallback conservador para instalações mínimas: restringe a busca aos
    # blocos de dependências em package.json formatado em múltiplas linhas.
    sed -nE '/"(dependencies|devDependencies|optionalDependencies|peerDependencies)"[[:space:]]*:[[:space:]]*\{/,/^[[:space:]]*\}/p' "$pkgjson" 2>/dev/null \
        | grep -oE '"[a-zA-Z0-9@/_.-]+"[[:space:]]*:' \
        | sed -E 's/^"([^"]+)".*/\1/' \
        | grep -Ev '^(dependencies|devDependencies|optionalDependencies|peerDependencies)$' \
        | sort -u
}

node_package_script_exists() {
    local pkgjson="$1" script="$2" py=""
    [ -f "$pkgjson" ] || return 1
    case "$script" in *[!A-Za-z0-9:_-]*|'') return 1 ;; esac

    if comando_existe jq; then
        jq -e --arg script "$script" '.scripts?[$script] | type == "string"' "$pkgjson" >/dev/null 2>&1
        return $?
    fi
    if comando_existe node; then
        node - "$pkgjson" "$script" <<'NODE' >/dev/null 2>&1
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const value = pkg.scripts && pkg.scripts[process.argv[3]];
process.exit(typeof value === 'string' ? 0 : 1);
NODE
        return $?
    fi
    if comando_existe python3; then py=python3; elif comando_existe python; then py=python; fi
    if [ -n "$py" ]; then
        "$py" - "$pkgjson" "$script" <<'PYJSON' >/dev/null 2>&1
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    pkg = json.load(f)
value = (pkg.get('scripts') or {}).get(sys.argv[2])
raise SystemExit(0 if isinstance(value, str) else 1)
PYJSON
        return $?
    fi

    sed -nE '/"scripts"[[:space:]]*:[[:space:]]*\{/,/^[[:space:]]*\}/p' "$pkgjson" 2>/dev/null \
        | grep -qE '"'"$script"'"[[:space:]]*:'
}

detectar_stack() {
    local dir="$1"
    DETECT_TIPO="desconhecido"
    DETECT_FRAMEWORK="Desconhecido"
    DETECT_GERENCIADOR=""
    DETECT_RUN_CMD=""

    if [ -f "$dir/package.json" ]; then
        local pkgjson="$dir/package.json"
        local deps
        deps="$(node_package_dependency_names "$pkgjson" 2>/dev/null || true)"

        # Gerenciador de pacotes
        if [ -f "$dir/pnpm-lock.yaml" ]; then
            DETECT_GERENCIADOR="pnpm"
        elif [ -f "$dir/yarn.lock" ]; then
            DETECT_GERENCIADOR="yarn"
        else
            DETECT_GERENCIADOR="npm"
        fi

        if echo "$deps" | grep -qiE '^next$'; then
            DETECT_TIPO="frontend"; DETECT_FRAMEWORK="Next.js"
        elif echo "$deps" | grep -qiE '^nuxt$'; then
            DETECT_TIPO="frontend"; DETECT_FRAMEWORK="Nuxt"
        elif echo "$deps" | grep -qiE '^@angular/core$'; then
            DETECT_TIPO="frontend"; DETECT_FRAMEWORK="Angular"
        elif echo "$deps" | grep -qiE '^svelte$'; then
            DETECT_TIPO="frontend"; DETECT_FRAMEWORK="Svelte"
        elif echo "$deps" | grep -qiE '^vue$'; then
            DETECT_TIPO="frontend"; DETECT_FRAMEWORK="Vue"
        elif echo "$deps" | grep -qiE '^vite$'; then
            DETECT_TIPO="frontend"; DETECT_FRAMEWORK="Vite"
        elif echo "$deps" | grep -qiE '^react$'; then
            DETECT_TIPO="frontend"; DETECT_FRAMEWORK="React"
        elif echo "$deps" | grep -qiE '^@nestjs/core$'; then
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="NestJS"
        elif echo "$deps" | grep -qiE '^express$'; then
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="Express"
        else
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="Node.js"
        fi

        # Comando de execução (procura scripts dev/start)
        if node_package_script_exists "$pkgjson" dev; then
            DETECT_RUN_CMD="$DETECT_GERENCIADOR run dev"
        elif node_package_script_exists "$pkgjson" start; then
            DETECT_RUN_CMD="$DETECT_GERENCIADOR run start"
        else
            DETECT_RUN_CMD="$DETECT_GERENCIADOR start"
        fi

        # Força o dev server a subir em 127.0.0.1 (nunca no IP da rede).
        # Isso evita a varredura lenta de interfaces de rede no Termux/Android
        # e sobrescreve qualquer "host: true" deixado no arquivo de config
        # do projeto (flag de linha de comando tem prioridade sobre o config).
        if [ "$DETECT_TIPO" == "frontend" ]; then
            case "$DETECT_FRAMEWORK" in
                Vite|React|Vue|Svelte|Nuxt)
                    DETECT_RUN_CMD="$DETECT_RUN_CMD -- --host 127.0.0.1"
                    ;;
                Next.js)
                    DETECT_RUN_CMD="$DETECT_RUN_CMD -- -H 127.0.0.1"
                    ;;
                Angular)
                    DETECT_RUN_CMD="$DETECT_RUN_CMD -- --host 127.0.0.1"
                    ;;
            esac
        fi
        return
    fi

    if [ -f "$dir/pyproject.toml" ]; then
        DETECT_GERENCIADOR="pip"
        if grep -qi "fastapi" "$dir/pyproject.toml"; then
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="FastAPI"
            DETECT_RUN_CMD="uvicorn main:app --reload --host 0.0.0.0"
        elif grep -qi "django" "$dir/pyproject.toml"; then
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="Django"
            DETECT_RUN_CMD="python manage.py runserver 0.0.0.0:8000"
        elif grep -qi "flask" "$dir/pyproject.toml"; then
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="Flask"
            DETECT_RUN_CMD="flask run --host=0.0.0.0"
        else
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="Python"
            DETECT_RUN_CMD="python main.py"
        fi
        return
    fi

    if [ -f "$dir/requirements.txt" ]; then
        DETECT_GERENCIADOR="pip"
        if grep -qi "fastapi" "$dir/requirements.txt"; then
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="FastAPI"
            DETECT_RUN_CMD="uvicorn main:app --reload --host 0.0.0.0"
        elif grep -qi "django" "$dir/requirements.txt"; then
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="Django"
            DETECT_RUN_CMD="python manage.py runserver 0.0.0.0:8000"
        elif grep -qi "flask" "$dir/requirements.txt"; then
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="Flask"
            DETECT_RUN_CMD="flask run --host=0.0.0.0"
        else
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="Python"
            DETECT_RUN_CMD="python main.py"
        fi
        return
    fi

    if [ -f "$dir/composer.json" ]; then
        DETECT_GERENCIADOR="composer"
        if grep -qi "laravel/framework" "$dir/composer.json"; then
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="Laravel"
            DETECT_RUN_CMD="php artisan serve --host=0.0.0.0"
        else
            DETECT_TIPO="backend"; DETECT_FRAMEWORK="PHP"
            DETECT_RUN_CMD="php -S 0.0.0.0:8000"
        fi
        return
    fi

    if [ -f "$dir/go.mod" ]; then
        DETECT_TIPO="backend"; DETECT_FRAMEWORK="Go"
        DETECT_GERENCIADOR="go"
        DETECT_RUN_CMD="go run ."
        return
    fi

    if [ -f "$dir/Cargo.toml" ]; then
        DETECT_TIPO="backend"; DETECT_FRAMEWORK="Rust"
        DETECT_GERENCIADOR="cargo"
        DETECT_RUN_CMD="cargo run"
        return
    fi

    if [ -f "$dir/pom.xml" ]; then
        DETECT_TIPO="backend"; DETECT_FRAMEWORK="Java (Maven)"
        DETECT_GERENCIADOR="maven"
        DETECT_RUN_CMD="mvn spring-boot:run"
        return
    fi

    if [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
        DETECT_TIPO="backend"; DETECT_FRAMEWORK="Java/Kotlin (Gradle)"
        DETECT_GERENCIADOR="gradle"
        DETECT_RUN_CMD="./gradlew bootRun"
        return
    fi
}

# ----------------------------------------------------------------------------
# Detecção de estrutura fullstack (um projeto só, com pastas de frontend
# e backend dentro dele — ex: frontend/ e backend/, client/ e server/, etc.)
# ----------------------------------------------------------------------------

PROJ_MODO=""          # simples_frontend | simples_backend | fullstack | desconhecido
FRONT_DIR=""; FRONT_FRAMEWORK=""; FRONT_GERENCIADOR=""; FRONT_RUN_CMD=""
BACK_DIR="";  BACK_FRAMEWORK="";  BACK_GERENCIADOR="";  BACK_RUN_CMD=""

detectar_estrutura_projeto() {
    local dir="$1"
    PROJ_MODO="desconhecido"
    FRONT_DIR=""; FRONT_FRAMEWORK=""; FRONT_GERENCIADOR=""; FRONT_RUN_CMD=""
    BACK_DIR="";  BACK_FRAMEWORK="";  BACK_GERENCIADOR="";  BACK_RUN_CMD=""

    # 1) Tenta primeiro o próprio diretório raiz (projeto simples)
    detectar_stack "$dir"
    if [ "$DETECT_TIPO" == "frontend" ]; then
        FRONT_DIR="$dir"; FRONT_FRAMEWORK="$DETECT_FRAMEWORK"
        FRONT_GERENCIADOR="$DETECT_GERENCIADOR"; FRONT_RUN_CMD="$DETECT_RUN_CMD"
    elif [ "$DETECT_TIPO" == "backend" ]; then
        BACK_DIR="$dir"; BACK_FRAMEWORK="$DETECT_FRAMEWORK"
        BACK_GERENCIADOR="$DETECT_GERENCIADOR"; BACK_RUN_CMD="$DETECT_RUN_CMD"
    fi

    # 2) Procura subpastas típicas de frontend/backend (mesmo se o passo 1
    #    já achou algo — assim detectamos monorepos completos)
    local sub nome
    for sub in "$dir"/*/; do
        [ -d "$sub" ] || continue
        sub="${sub%/}"
        nome=$(basename "$sub" | tr '[:upper:]' '[:lower:]')
        case "$nome" in
            frontend|front|client|web|ui|app|webapp)
                if [ -z "$FRONT_DIR" ]; then
                    detectar_stack "$sub"
                    if [ "$DETECT_TIPO" != "desconhecido" ]; then
                        FRONT_DIR="$sub"; FRONT_FRAMEWORK="$DETECT_FRAMEWORK"
                        FRONT_GERENCIADOR="$DETECT_GERENCIADOR"; FRONT_RUN_CMD="$DETECT_RUN_CMD"
                    fi
                fi
                ;;
            backend|back|server|api)
                if [ -z "$BACK_DIR" ]; then
                    detectar_stack "$sub"
                    if [ "$DETECT_TIPO" != "desconhecido" ]; then
                        BACK_DIR="$sub"; BACK_FRAMEWORK="$DETECT_FRAMEWORK"
                        BACK_GERENCIADOR="$DETECT_GERENCIADOR"; BACK_RUN_CMD="$DETECT_RUN_CMD"
                    fi
                fi
                ;;
        esac
    done

    if [ -n "$FRONT_DIR" ] && [ -n "$BACK_DIR" ]; then
        PROJ_MODO="fullstack"
    elif [ -n "$FRONT_DIR" ]; then
        PROJ_MODO="simples_frontend"
    elif [ -n "$BACK_DIR" ]; then
        PROJ_MODO="simples_backend"
    else
        PROJ_MODO="desconhecido"
    fi
}

# ============================================================================
# INSTALAÇÃO DE DEPENDÊNCIAS
# ============================================================================

