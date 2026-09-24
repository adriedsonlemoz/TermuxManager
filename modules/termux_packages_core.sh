# Módulo: termux_packages_core.sh
# Núcleo de pacotes do Termux: repositórios, variante e estado básico.

coletar_repositorios_termux() {
    local -a fontes=()
    local arquivo prefixo="${PREFIX:-}"
    [ -n "$prefixo" ] || return 0
    [ -r "$prefixo/etc/apt/sources.list" ] && fontes+=("$prefixo/etc/apt/sources.list")
    for arquivo in "$prefixo"/etc/apt/sources.list.d/*.list; do
        [ -r "$arquivo" ] && fontes+=("$arquivo")
    done
    [ ${#fontes[@]} -gt 0 ] || return 0
    # APT aceita opções entre `deb` e a URL (ex.: [signed-by=...]).
    # Procurar a primeira URL HTTP(S) da linha evita ignorar esses repositórios.
    awk '$1 == "deb" { for (i=2; i<=NF; i++) if ($i ~ /^https?:\/\//) { print $i; break } }' \
        "${fontes[@]}" 2>/dev/null | awk '!seen[$0]++'
}

detectar_variante_termux() {
    if [ -n "${TERMUX_VARIANT_ID:-}" ] && [ -n "${TERMUX_VARIANT_LABEL:-}" ]; then
        return 0
    fi

    local versao="${TERMUX_VERSION:-}" repos="" repo_primario=""
    # `paste -d ', '` alterna os caracteres ',' e ' ' como delimitadores;
    # não produz o separador literal ", ". Isso quebrava o resumo com 2+
    # repositórios e podia fazer TERMUX_REPO_PRIMARY conter a lista inteira.
    repos="$(coletar_repositorios_termux | awk 'BEGIN { sep="" } { printf "%s%s", sep, $0; sep=", " } END { if (sep != "") print "" }' 2>/dev/null || true)"
    repo_primario="$(coletar_repositorios_termux | head -n 1 2>/dev/null || true)"
    [ -n "$repo_primario" ] || repo_primario="indisponível"

    TERMUX_VARIANT_ID="unknown"
    TERMUX_VARIANT_LABEL="Origem não identificada"
    TERMUX_VARIANT_SOURCE="Indefinida"
    TERMUX_REPO_PRIMARY="$repo_primario"
    TERMUX_REPO_SUMMARY="${repos:-indisponível}"

    case "$versao" in
        googleplay.*)
            TERMUX_VARIANT_ID="google-play"
            TERMUX_VARIANT_LABEL="Google Play"
            TERMUX_VARIANT_SOURCE="Google Play"
            ;;
        *)
            case "$repos $versao" in
                *termux.net*)
                    TERMUX_VARIANT_ID="google-play"
                    TERMUX_VARIANT_LABEL="Google Play"
                    TERMUX_VARIANT_SOURCE="Google Play"
                    ;;
                *packages.termux.dev*|*packages-cf.termux.dev*|*grimler.se*|*termux.dev*)
                    TERMUX_VARIANT_ID="github-fdroid"
                    TERMUX_VARIANT_LABEL="GitHub/F-Droid"
                    TERMUX_VARIANT_SOURCE="GitHub/F-Droid"
                    ;;
            esac
            ;;
    esac

    if [ "$TERMUX_VARIANT_ID" = "unknown" ] && [ -n "$versao" ] && [[ "$versao" =~ ^[0-9] ]]; then
        TERMUX_VARIANT_ID="github-fdroid"
        TERMUX_VARIANT_LABEL="GitHub/F-Droid"
        TERMUX_VARIANT_SOURCE="GitHub/F-Droid"
    fi
}

termux_origem_resumida() {
    detectar_variante_termux
    printf '%s' "${TERMUX_VARIANT_LABEL:-indisponível}"
}

termux_repositorio_resumido() {
    detectar_variante_termux
    printf '%s' "${TERMUX_REPO_PRIMARY:-indisponível}"
}

pacote_disponivel_termux() {
    local pacote="$1"
    command -v apt-cache >/dev/null 2>&1 || return 0
    apt-cache show "$pacote" 2>/dev/null | grep -q '^Package:[[:space:]]'
}

status_pacote() {
    local pacote="$1"
    if dpkg -s "$pacote" >/dev/null 2>&1; then
        printf 'Instalado'
    else
        printf 'Não instalado'
    fi
}

barra_percentual_simples() {
    local pct="${1:-0}" limite="${2:-}" largura
    if [ -n "$limite" ] && [[ "$limite" =~ ^[0-9]+$ ]]; then
        # 7 colunas são usadas por colchetes, espaço e percentual ("] 100%").
        largura=$((limite - 7))
    else
        largura=$((${LARGURA_CAIXA:-40} - 14))
    fi
    [ "$largura" -lt 5 ] && largura=5
    [ "$pct" -lt 0 ] && pct=0
    [ "$pct" -gt 100 ] && pct=100
    local cheio vazio
    cheio=$((largura * pct / 100))
    vazio=$((largura - cheio))
    printf '[%s%s] %3d%%' "$(repetir_char '=' "$cheio")" "$(repetir_char '-' "$vazio")" "$pct"
}

