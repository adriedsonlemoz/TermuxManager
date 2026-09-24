# Submódulo: updater_core.sh
# Estado compartilhado, versões, hashes e validação de integridade.

MANAGER_GITHUB_BRANCH="${TERMUX_MANAGER_GITHUB_BRANCH:-main}"
MANAGER_GITHUB_RAW_BASE="${TERMUX_MANAGER_GITHUB_RAW_BASE:-https://raw.githubusercontent.com/adriedsonlemoz/TermuxManager/${MANAGER_GITHUB_BRANCH}}"
MANAGER_GITHUB_MANIFEST_URL="${TERMUX_MANAGER_GITHUB_MANIFEST_URL:-${MANAGER_GITHUB_RAW_BASE}/MANIFEST.json}"
MANAGER_GITHUB_CHANGELOG_URL="${TERMUX_MANAGER_GITHUB_CHANGELOG_URL:-${MANAGER_GITHUB_RAW_BASE}/CHANGELOG.md}"
MANAGER_GITHUB_ARCHIVE_URL="${TERMUX_MANAGER_GITHUB_ARCHIVE_URL:-https://github.com/adriedsonlemoz/TermuxManager/archive/refs/heads/${MANAGER_GITHUB_BRANCH}.zip}"
GITHUB_REMOTE_VERSION=""
GITHUB_REMOTE_CHANGELOG=""
GITHUB_UPDATE_STATE="unknown"
GITHUB_UPDATE_INTERACTIVE="${GITHUB_UPDATE_INTERACTIVE:-false}"
GITHUB_CURL_ERROR=""

versao_semver_valida() {
    [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

versao_semver_maior() {
    local a="$1" b="$2" a1 a2 a3 b1 b2 b3
    versao_semver_valida "$a" && versao_semver_valida "$b" || return 1
    IFS=. read -r a1 a2 a3 <<< "$a"
    IFS=. read -r b1 b2 b3 <<< "$b"
    if ((10#$a1 > 10#$b1)); then return 0; fi
    if ((10#$a1 < 10#$b1)); then return 1; fi
    if ((10#$a2 > 10#$b2)); then return 0; fi
    if ((10#$a2 < 10#$b2)); then return 1; fi
    ((10#$a3 > 10#$b3))
}

versao_arquivo_manager() {
    local arquivo="$1" versao=""
    versao=$(grep -m1 -E '^MANAGER_VERSION=' "$arquivo" 2>/dev/null | sed -E 's/^MANAGER_VERSION="?([^"[:space:]]+)"?.*/\1/')
    [ -n "$versao" ] || versao="não identificada"
    printf '%s' "$versao"
}

updater_caminho_manifesto_seguro() {
    local caminho="${1:-}" parte
    local -a _updater_partes=()
    [ -n "$caminho" ] || return 1
    [[ "$caminho" != /* ]] || return 1
    [[ "$caminho" != *\\* ]] || return 1
    IFS='/' read -r -a _updater_partes <<< "$caminho"
    for parte in "${_updater_partes[@]}"; do
        [ "$parte" = ".." ] && return 1
    done
    return 0
}

validar_manifesto_pacote_manager() {
    local pasta="$1" manifest="$1/MANIFEST.json" relative expected target actual total=0
    local versao_manifesto versao_manager obrigatorio
    local -A declarados=()

    [ -f "$manifest" ] || { error "Pacote inválido: MANIFEST.json ausente."; return 1; }
    command -v sha256sum >/dev/null 2>&1 || { error "sha256sum não está disponível."; return 1; }

    versao_manifesto="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' "$manifest" | head -n1)"
    versao_manager="$(versao_arquivo_manager "$pasta/manager.sh")"
    if ! versao_semver_valida "$versao_manifesto" || ! versao_semver_valida "$versao_manager"; then
        error "Manifesto inválido: versão ausente ou inválida."
        return 1
    fi
    if [ "$versao_manifesto" != "$versao_manager" ]; then
        error "Manifesto inválido: versão $versao_manifesto não corresponde ao manager.sh ($versao_manager)."
        return 1
    fi

    while IFS=$'\t' read -r relative expected; do
        [ -n "$relative" ] || continue
        if ! updater_caminho_manifesto_seguro "$relative"; then
            error "Manifesto inválido: caminho inseguro: $relative"
            return 1
        fi
        target="$pasta/$relative"
        [ -f "$target" ] && [ ! -L "$target" ] || { error "Manifesto inválido: arquivo ausente ou não regular: $relative"; return 1; }
        actual="$(sha256sum "$target" | awk '{print $1}')"
        [ "${actual,,}" = "${expected,,}" ] || { error "Falha de integridade em: $relative"; return 1; }
        declarados["$relative"]=1
        total=$((total + 1))
    done < <(
        sed -n '/"files"[[:space:]]*:[[:space:]]*{/,/^[[:space:]]*}[[:space:]]*$/p' "$manifest" \
            | sed -nE 's/^[[:space:]]*"([^"]+)"[[:space:]]*:[[:space:]]*"([0-9A-Fa-f]{64})",?[[:space:]]*$/\1\t\2/p'
    )
    [ "$total" -gt 0 ] || { error "Manifesto inválido: nenhum hash encontrado."; return 1; }

    obrigatorio="manager.sh"
    [ "${declarados[$obrigatorio]:-}" = 1 ] || { error "Manifesto incompleto: manager.sh não possui hash declarado."; return 1; }

    while IFS= read -r -d '' target; do
        relative="${target#"$pasta/"}"
        [ "${declarados[$relative]:-}" = 1 ] || {
            error "Manifesto incompleto: script sem hash declarado: $relative"
            return 1
        }
    done < <(find "$pasta/modules" -type f -name '*.sh' -print0 2>/dev/null)

    return 0
}

validar_zip_manager_seguro() {
    local arquivo="$1" lista entrada
    command -v unzip >/dev/null 2>&1 || { error "unzip não está disponível."; return 1; }
    lista="$(unzip -Z1 "$arquivo" 2>/dev/null)" || { error "Pacote ZIP inválido ou ilegível."; return 1; }
    [ -n "$lista" ] || { error "Pacote ZIP vazio."; return 1; }

    while IFS= read -r entrada; do
        [ -n "$entrada" ] || continue
        if [[ "$entrada" = /* || "$entrada" = *\\* || "/$entrada/" = *"/../"* ]]; then
            error "Pacote ZIP rejeitado: caminho inseguro detectado: $entrada"
            return 1
        fi
    done <<< "$lista"
    return 0
}

hash_arquivo_manager() {
    local arquivo="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$arquivo" 2>/dev/null | awk '{print $1}'
    else
        cksum "$arquivo" 2>/dev/null | awk '{print $1}'
    fi
}

hash_pacote_manager() {
    local pasta="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        (
            cd "$pasta" || exit 1
            find manager.sh modules -type f -print0 2>/dev/null \
                | sort -z \
                | xargs -0 sha256sum 2>/dev/null \
                | sha256sum \
                | awk '{print $1}'
        )
    else
        (
            cd "$pasta" || exit 1
            find manager.sh modules -type f -print 2>/dev/null \
                | sort \
                | while IFS= read -r arquivo; do cksum "$arquivo"; done \
                | cksum \
                | awk '{print $1}'
        )
    fi
}

versao_nome_pacote() {
    local nome
    nome="$(basename "$1")"
    if [[ "$nome" =~ ^(TermuxManager|manager)-v([0-9]+\.[0-9]+\.[0-9]+)\.zip$ ]]; then
        printf '%s' "${BASH_REMATCH[2]}"
    else
        printf '%s' "não padronizado"
    fi
}

data_arquivo_manager() {
    local arquivo="$1"
    date -r "$arquivo" '+%d/%m/%Y %H:%M' 2>/dev/null || echo "não disponível"
}

arquivo_status_atualizacao() {
    printf '%s' "$BASE_DIR/.updates/last-update.conf"
}
