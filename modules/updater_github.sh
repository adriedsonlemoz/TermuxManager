# Submódulo: updater_github.sh
# Consulta e download de atualizações pela branch configurada.

github_formatar_bytes() {
    local bytes="${1:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if [ "$bytes" -ge 1073741824 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1f GB", b/1073741824}'
    elif [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1f MB", b/1048576}'
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1f KB", b/1024}'
    else
        printf '%s B' "$bytes"
    fi
}

# Desenha imediatamente o estado de uma operação de rede. O flush explícito é
# importante: sem ele a tela podia permanecer aparentemente parada enquanto o
# curl aguardava o GitHub.
github_status_render() {
    [ "${GITHUB_UPDATE_INTERACTIVE:-false}" = true ] || return 0
    declare -F tela_limpar >/dev/null 2>&1 || return 0
    declare -F caixa_simples >/dev/null 2>&1 || return 0
    declare -F ui_buffer_flush >/dev/null 2>&1 && ui_buffer_flush 2>/dev/null || true
    tela_limpar
    caixa_simples "$1" "$2" "$3" "$4"
    printf '\n%s\n' "${5:-Aguarde. A instalação atual ainda não foi modificada.}"
}

# Executa curl em segundo plano e mantém uma tela viva enquanto a rede responde.
# No download grande mostra bytes, velocidade média e tempo decorrido. Em
# consultas pequenas mostra apenas atividade/tempo para não parecer travamento.
github_fetch_to_file() {
    local url="$1" destino="$2" titulo="$3" detalhe="$4" max_time="${5:-30}" mostrar_bytes="${6:-false}"
    local erro="${destino}.curl-error" pid inicio agora decorrido bytes=0 velocidade=0 nota rc=0
    command -v curl >/dev/null 2>&1 || return 2
    rm -f -- "$destino" "$erro"

    github_status_render "$titulo" "$detalhe" "Conectando ao GitHub..." "Tempo aguardando: 0s" \
        "Não pressione Ctrl+C. O Manager mostrará o andamento aqui."

    curl -fL -sS --retry 2 --connect-timeout 8 --max-time "$max_time" -o "$destino" "$url" 2>"$erro" &
    pid=$!
    inicio="$(date +%s)"

    while kill -0 "$pid" 2>/dev/null; do
        agora="$(date +%s)"
        decorrido=$((agora - inicio))
        [ "$decorrido" -lt 0 ] && decorrido=0
        if [ "$mostrar_bytes" = true ] && [ -f "$destino" ]; then
            bytes="$(stat -c%s "$destino" 2>/dev/null || echo 0)"
            [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
            [ "$decorrido" -gt 0 ] && velocidade=$((bytes / decorrido)) || velocidade=0
            if [ "$decorrido" -ge 6 ]; then
                nota="A conexão pode estar lenta, mas o download continua."
            else
                nota="Download em andamento. A instalação atual continua intacta."
            fi
            github_status_render "$titulo" "$detalhe" \
                "Baixado: $(github_formatar_bytes "$bytes") • ~$(github_formatar_bytes "$velocidade")/s" \
                "Tempo decorrido: ${decorrido}s" "$nota"
        else
            if [ "$decorrido" -ge 6 ]; then
                nota="Ainda aguardando resposta do GitHub. Isso não é travamento."
            else
                nota="Consultando a branch ${MANAGER_GITHUB_BRANCH}."
            fi
            github_status_render "$titulo" "$detalhe" "Carregando informações..." \
                "Tempo aguardando: ${decorrido}s" "$nota"
        fi
        sleep 1
    done

    if wait "$pid"; then
        rc=0
    else
        rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
        GITHUB_CURL_ERROR="$(tail -n 2 "$erro" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+$//')"
        rm -f -- "$destino" "$erro"
        return "$rc"
    fi
    rm -f -- "$erro"
    return 0
}


consultar_atualizacao_github() {
    command -v curl >/dev/null 2>&1 || return 2
    local manifest changelog versao manifest_tmp changelog_tmp rc=0 tmpbase
    tmpbase="${TMPDIR:-/tmp}"
    mkdir -p "$tmpbase" 2>/dev/null || true
    manifest_tmp="$(mktemp "$tmpbase/termux-manager-manifest.XXXXXX")" || return 1
    changelog_tmp="$(mktemp "$tmpbase/termux-manager-changelog.XXXXXX")" || { rm -f "$manifest_tmp"; return 1; }

    github_fetch_to_file "$MANAGER_GITHUB_MANIFEST_URL" "$manifest_tmp" \
        "🌐 Conectando ao GitHub" "Repositório: adriedsonlemoz/TermuxManager • branch $MANAGER_GITHUB_BRANCH" 20 false || rc=$?
    if [ "$rc" -ne 0 ]; then
        rm -f "$manifest_tmp" "$changelog_tmp"
        [ "$rc" -eq 2 ] && return 2
        return 1
    fi

    manifest="$(cat "$manifest_tmp" 2>/dev/null)"
    versao="$(printf '%s\n' "$manifest" | sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' | head -n1)"
    if ! versao_semver_valida "$versao"; then
        rm -f "$manifest_tmp" "$changelog_tmp"
        return 1
    fi

    GITHUB_REMOTE_VERSION="$versao"
    if [ "$GITHUB_REMOTE_VERSION" = "$MANAGER_VERSION" ]; then
        GITHUB_UPDATE_STATE="same"
    elif versao_semver_maior "$GITHUB_REMOTE_VERSION" "$MANAGER_VERSION"; then
        GITHUB_UPDATE_STATE="new"
    else
        GITHUB_UPDATE_STATE="older"
    fi

    github_status_render "✅ Conectado ao GitHub" \
        "Versão instalada: $MANAGER_VERSION • GitHub: $GITHUB_REMOTE_VERSION" \
        "Manifesto carregado com sucesso." "Carregando changelog..." \
        "Aguarde enquanto o Manager consulta os detalhes da versão."

    if github_fetch_to_file "$MANAGER_GITHUB_CHANGELOG_URL" "$changelog_tmp" \
        "📋 Carregando atualização" "Versão $GITHUB_REMOTE_VERSION encontrada na branch $MANAGER_GITHUB_BRANCH" 15 false; then
        changelog="$(cat "$changelog_tmp" 2>/dev/null)"
    else
        changelog=""
    fi
    GITHUB_REMOTE_CHANGELOG="$(printf '%s\n' "$changelog" | awk -v v="$GITHUB_REMOTE_VERSION" '
        $0 ~ "^## \\[" v "\\]" {show=1; next}
        show && /^## \[/ {exit}
        show {print}
    ' | sed '/^[[:space:]]*$/d' | head -n 10)"
    rm -f "$manifest_tmp" "$changelog_tmp"
    return 0
}


verificar_atualizacao_github() {
    local consulta_rc=0
    GITHUB_UPDATE_INTERACTIVE=true
    GITHUB_CURL_ERROR=""

    github_status_render "🌐 Atualização pelo GitHub" \
        "Repositório: adriedsonlemoz/TermuxManager" \
        "Branch: $MANAGER_GITHUB_BRANCH • Instalada: $MANAGER_VERSION" \
        "⏳ Conectando ao GitHub..." "A tela será atualizada automaticamente durante a consulta."
    # Dá ao terminal móvel tempo para pintar o estado inicial antes de iniciar
    # qualquer operação de rede. Evita a impressão de que a opção 1 travou.
    sleep 0.20

    consultar_atualizacao_github || consulta_rc=$?
    if [ "$consulta_rc" -ne 0 ]; then
        GITHUB_UPDATE_INTERACTIVE=false
        cabecalho_tela "🌐 Atualização pelo GitHub" "Falha na consulta"
        if [ "$consulta_rc" -eq 2 ]; then
            caixa_simples "⚠ curl não disponível" "Instale curl e tente novamente."
        else
            caixa_simples "⚠ Não foi possível consultar o GitHub" \
                "Verifique sua conexão com a internet." \
                "${GITHUB_CURL_ERROR:-O GitHub não respondeu dentro do tempo esperado.}" \
                "A instalação atual não foi modificada."
        fi
        pause
        return 1
    fi
    GITHUB_UPDATE_INTERACTIVE=false

    cabecalho_tela "🌐 Atualização pelo GitHub" "Consulta concluída • branch $MANAGER_GITHUB_BRANCH"
    case "$GITHUB_UPDATE_STATE" in
        same)
            caixa_simples "✅ Manager atualizado" \
                "Instalada: $MANAGER_VERSION" \
                "GitHub main: $GITHUB_REMOTE_VERSION" \
                "Nenhuma atualização é necessária."
            pause
            return 0
            ;;
        older)
            caixa_simples "ℹ A main não é mais nova" \
                "Instalada: $MANAGER_VERSION" \
                "GitHub main: $GITHUB_REMOTE_VERSION" \
                "Nenhuma alteração será aplicada."
            pause
            return 0
            ;;
        new)
            caixa_simples "🆕 Nova versão disponível" \
                "Versão atual: $MANAGER_VERSION" \
                "Nova versão: $GITHUB_REMOTE_VERSION" \
                "Fonte: GitHub / branch main" \
                "Backup automático: ativado"
            if [ -n "$GITHUB_REMOTE_CHANGELOG" ]; then
                local -a linhas_changelog=()
                while IFS= read -r linha; do [ -n "$linha" ] && linhas_changelog+=("$linha"); done <<< "$GITHUB_REMOTE_CHANGELOG"
                [ ${#linhas_changelog[@]} -gt 0 ] && caixa_simples "O que mudou" "${linhas_changelog[@]}"
            fi
            confirmar_acao "Baixar e instalar a versão $GITHUB_REMOTE_VERSION agora?" "n" || return 0
            ;;
    esac

    local updates_dir="$BASE_DIR/.updates" stamp download_dir arquivo tamanho_download
    stamp="$(date '+%Y%m%d_%H%M%S')"
    download_dir="$updates_dir/github_$stamp"
    arquivo="$download_dir/TermuxManager-v${GITHUB_REMOTE_VERSION}.zip"
    mkdir -p "$download_dir"

    GITHUB_UPDATE_INTERACTIVE=true
    if ! github_fetch_to_file "$MANAGER_GITHUB_ARCHIVE_URL" "$arquivo" \
        "⬇ Baixando atualização" "GitHub main → versão $GITHUB_REMOTE_VERSION" 120 true; then
        GITHUB_UPDATE_INTERACTIVE=false
        rm -rf "$download_dir"
        cabecalho_tela "⬇ Atualização pelo GitHub" "Download interrompido"
        caixa_simples "⚠ Falha no download" \
            "${GITHUB_CURL_ERROR:-Não foi possível baixar o arquivo da branch main.}" \
            "A instalação atual permanece intacta." \
            "Tente novamente quando a conexão estiver estável."
        pause
        return 1
    fi
    tamanho_download="$(stat -c%s "$arquivo" 2>/dev/null || echo 0)"
    github_status_render "✅ Download concluído" \
        "Versão: $GITHUB_REMOTE_VERSION • Branch: $MANAGER_GITHUB_BRANCH" \
        "Baixado: $(github_formatar_bytes "$tamanho_download")" \
        "Próxima etapa: validar pacote e criar backup." \
        "A instalação será alterada somente depois que todas as verificações passarem."
    sleep 1
    GITHUB_UPDATE_INTERACTIVE=false

    ATUALIZACAO_LIMPAR_ARQUIVO=true
    instalar_pacote_manager "$arquivo"
    ATUALIZACAO_LIMPAR_ARQUIVO=false
    rm -rf "$download_dir" 2>/dev/null || true
}

