# Módulo: updater.sh
# Atualização completa ou isolada do Manager.sh.


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

# Formatação pequena e independente para o painel de rede. Não depende de
# outros módulos, o que também permite testar updater.sh isoladamente.
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

validar_manifesto_pacote_manager() {
    local pasta="$1" manifest="$1/MANIFEST.json" relative expected target actual total=0
    [ -f "$manifest" ] || { error "Pacote inválido: MANIFEST.json ausente."; return 1; }
    command -v sha256sum >/dev/null 2>&1 || { error "sha256sum não está disponível."; return 1; }
    while IFS=$'\t' read -r relative expected; do
        [ -n "$relative" ] || continue
        target="$pasta/$relative"
        [ -f "$target" ] || { error "Manifesto inválido: arquivo ausente: $relative"; return 1; }
        actual="$(sha256sum "$target" | awk '{print $1}')"
        [ "${actual,,}" = "${expected,,}" ] || { error "Falha de integridade em: $relative"; return 1; }
        total=$((total + 1))
    done < <(
        sed -n '/"files"[[:space:]]*:[[:space:]]*{/,/^[[:space:]]*}[[:space:]]*$/p' "$manifest" \
            | sed -nE 's/^[[:space:]]*"([^"]+)":[[:space:]]*"([0-9A-Fa-f]{64})",?[[:space:]]*$/\1\t\2/p'
    )
    [ "$total" -gt 0 ] || { error "Manifesto inválido: nenhum hash encontrado."; return 1; }
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

versao_arquivo_manager() {
    local arquivo="$1" versao=""
    versao=$(grep -m1 -E '^MANAGER_VERSION=' "$arquivo" 2>/dev/null | sed -E 's/^MANAGER_VERSION="?([^"[:space:]]+)"?.*/\1/')
    [ -n "$versao" ] || versao="não identificada"
    printf '%s' "$versao"
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

mostrar_ultima_atualizacao_manager() {
    local historico
    historico="$(arquivo_status_atualizacao)"
    cabecalho_tela "🕘 Última atualização" "Registro local do Manager"
    if [ ! -f "$historico" ]; then
        caixa_simples "Nenhum registro" "Ainda não há atualização confirmada pelo menu."
        pause
        return
    fi
    local data="" tipo="" arquivo="" anterior="" nova="" destino="" status=""
    while IFS='=' read -r chave valor; do
        valor="${valor%\"}"; valor="${valor#\"}"
        case "$chave" in
            DATA) data="$valor" ;;
            TIPO) tipo="$valor" ;;
            ARQUIVO) arquivo="$valor" ;;
            VERSAO_ANTERIOR) anterior="$valor" ;;
            VERSAO_NOVA) nova="$valor" ;;
            DESTINO) destino="$valor" ;;
            STATUS) status="$valor" ;;
        esac
    done < "$historico"
    caixa_simples "✅ Atualização registrada" \
        "Data: ${data:-não registrada}" \
        "Tipo: ${tipo:-não informado}" \
        "Arquivo: ${arquivo:-não informado}" \
        "Destino: ${destino:-pacote completo}" \
        "Versão: ${anterior:-?} → ${nova:-?}" \
        "Status: ${status:-desconhecido}"
    pause
}

listar_pacotes_completos() {
    ATUALIZACOES_ENCONTRADAS=()
    local arquivo
    # Aceita qualquer .zip na pasta Download, não só "manager*.zip". O
    # conteúdo é validado depois (precisa ter manager.sh e modules/ dentro),
    # então não há motivo para exigir um nome de arquivo específico — isso
    # só fazia atualizações sumirem da lista quando o navegador salvava com
    # outro nome (ex.: "manager (1).zip", "download.zip").
    while IFS= read -r -d '' arquivo; do
        ATUALIZACOES_ENCONTRADAS+=("$arquivo")
    done < <(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 -type f \
        -iname '*.zip' \
        -print0 2>/dev/null | sort -z)
}

listar_modulos_atualizacao() {
    ATUALIZACOES_ENCONTRADAS=()
    local arquivo nome
    while IFS= read -r -d '' arquivo; do
        nome="$(basename "$arquivo")"
        nome="${nome%.module.sh}.sh"
        if [ "$nome" = "manager.sh" ] || [ -f "$MODULES_DIR/$nome" ]; then
            ATUALIZACOES_ENCONTRADAS+=("$arquivo")
        fi
    done < <(find "$DOWNLOADS_DIR" -mindepth 1 -maxdepth 1 -type f \
        \( -iname 'manager.sh' -o -iname '*.module.sh' -o -iname '*.sh' \) \
        -print0 2>/dev/null | sort -z)
}

selecionar_atualizacao_lista() {
    local titulo="$1" descricao="$2"
    if [ ${#ATUALIZACOES_ENCONTRADAS[@]} -eq 0 ]; then
        cabecalho_tela "$titulo" "$descricao"
        caixa_simples "📭 Nenhum arquivo encontrado" \
            "Coloque o arquivo correto na pasta Download." \
            "Depois volte a esta opção."
        pause
        return 1
    fi
    cabecalho_tela "$titulo" "$descricao"
    caixa_linha_topo
    local i=1 arquivo tipo
    for arquivo in "${ATUALIZACOES_ENCONTRADAS[@]}"; do
        [[ "${arquivo,,}" == *.zip ]] && tipo="Pacote completo" || tipo="Arquivo individual"
        menu_opcao "$i" "📦" "$(basename "$arquivo")" "$tipo • versão $(versao_nome_pacote "$arquivo") • $(data_arquivo_manager "$arquivo")"
        i=$((i+1))
    done
    caixa_linha_baixo
    rodape_atalhos "[0] Voltar  •  [número] Selecionar"
    ler_opcao
    [ "$RESPOSTA_MENU" = 0 ] && return 1
    [[ "$RESPOSTA_MENU" =~ ^[0-9]+$ ]] || { feedback_curto "Opção inválida."; return 1; }
    [ "$RESPOSTA_MENU" -ge 1 ] && [ "$RESPOSTA_MENU" -le ${#ATUALIZACOES_ENCONTRADAS[@]} ] || { feedback_curto "Opção inválida."; return 1; }
    ATUALIZACAO_ESCOLHIDA="${ATUALIZACOES_ENCONTRADAS[$((RESPOSTA_MENU-1))]}"
}

instalar_pacote_manager() {
    local arquivo="$1"
    garantir_comando unzip unzip
    local updates_dir="$BASE_DIR/.updates" stamp tmp pacote modulo faltando=false
    stamp="$(date '+%Y%m%d_%H%M%S')"
    tmp="$updates_dir/extract_$stamp"
    mkdir -p "$updates_dir"; rm -rf "$tmp"; mkdir -p "$tmp"

    unzip -q "$arquivo" -d "$tmp" || { error "Falha ao extrair o pacote."; rm -rf "$tmp"; pause; return; }
    pacote="$tmp"
    if [ ! -f "$pacote/manager.sh" ]; then
        local raiz=(); shopt -s nullglob dotglob; raiz=("$tmp"/*); shopt -u nullglob dotglob
        [ ${#raiz[@]} -eq 1 ] && [ -d "${raiz[0]}" ] && pacote="${raiz[0]}"
    fi
    [ -f "$pacote/manager.sh" ] && [ -d "$pacote/modules" ] || { error "Pacote inválido: manager.sh ou modules/ ausente."; rm -rf "$tmp"; pause; return; }
    if ! validar_manifesto_pacote_manager "$pacote"; then
        rm -rf "$tmp"
        pause
        return 1
    fi

    for modulo in "${MODULOS_OBRIGATORIOS[@]}"; do
        [ -f "$pacote/modules/$modulo" ] || { error "Módulo ausente: $modulo"; faltando=true; }
    done
    [ "$faltando" = false ] || { rm -rf "$tmp"; pause; return; }

    local shfile
    while IFS= read -r -d '' shfile; do
        bash -n "$shfile" || { error "Erro de sintaxe em $(basename "$shfile")"; rm -rf "$tmp"; pause; return; }
    done < <(find "$pacote" -type f -name '*.sh' -print0)

    local nova_versao hash_atual hash_novo hash_principal_atual hash_principal_novo tamanho_novo linhas_novas
    nova_versao="$(versao_arquivo_manager "$pacote/manager.sh")"
    hash_atual="$(hash_pacote_manager "$BASE_DIR")"
    hash_novo="$(hash_pacote_manager "$pacote")"
    hash_principal_atual="$(hash_arquivo_manager "$SELF_PATH")"
    hash_principal_novo="$(hash_arquivo_manager "$pacote/manager.sh")"
    tamanho_novo="$(stat -c%s "$arquivo" 2>/dev/null || echo 0)"
    linhas_novas="$(find "$pacote" -type f -name '*.sh' -exec cat {} + | wc -l)"

    cabecalho_tela "🔼 Atualização completa" "Substitui manager.sh e todos os módulos"
    caixa_simples "Instalação atual" \
        "Versão: $MANAGER_VERSION" \
        "Pasta: $(caminho_curto "$BASE_DIR")" \
        "Hash do pacote: ${hash_atual:0:12}…" \
        "Hash principal: ${hash_principal_atual:0:12}…"
    caixa_simples "Pacote selecionado" \
        "Arquivo: $(basename "$arquivo")" \
        "Padrão GitHub: $(versao_nome_pacote "$arquivo")" \
        "Versão interna: $nova_versao" \
        "Data: $(data_arquivo_manager "$arquivo")" \
        "Tamanho: $(formatar_tamanho "$tamanho_novo")" \
        "Linhas Bash: $linhas_novas" \
        "Hash do pacote: ${hash_novo:0:12}…" \
        "Hash principal: ${hash_principal_novo:0:12}…"
    if [ -n "$hash_atual" ] && [ "$hash_atual" = "$hash_novo" ]; then
        ok "Este pacote completo já está instalado."
        rm -rf "$tmp"
        pause
        return
    fi
    confirmar_atualizacao_visual() {
        local escolha
        while true; do
            cabecalho_tela "📦 Atualização completa" "Revise as informações antes de continuar"
            caixa_linha_topo
            caixa_linha_texto "${C_BOLD}Resumo da atualização${C_RESET}" true
            caixa_linha_sep
            caixa_linha_texto "Versão atual: $MANAGER_VERSION"
            caixa_linha_texto "Nova versão: $nova_versao"
            caixa_linha_texto "Pacote: $(basename "$arquivo")"
            caixa_linha_texto "Tamanho: $(formatar_tamanho "$tamanho_novo")"
            caixa_linha_texto "Backup automático: ativado"
            caixa_linha_texto "Reinício automático: ativado"
            caixa_linha_sep
            menu_opcao "1" "⬆" "Atualizar agora" "Criar backup e instalar a nova versão"
            menu_opcao "2" "📋" "Ver detalhes técnicos" "Hashes, data, linhas e diretório de destino"
            menu_opcao "0" "↩" "Cancelar" "Voltar sem modificar a instalação"
            caixa_linha_baixo
            rodape_atalhos "[1] Atualizar  •  [2] Detalhes  •  [0] Cancelar"
            ler_opcao "Escolha uma opção: "
            escolha="$RESPOSTA_MENU"
            case "$escolha" in
                1) return 0 ;;
                2)
                    cabecalho_tela "📋 Detalhes da atualização" "Informações técnicas do pacote selecionado"
                    caixa_simples "Comparação"                         "Instalação: $(caminho_curto "$BASE_DIR")"                         "Versão atual: $MANAGER_VERSION"                         "Nova versão: $nova_versao"                         "Data do arquivo: $(data_arquivo_manager "$arquivo")"                         "Tamanho do ZIP: $(formatar_tamanho "$tamanho_novo")"                         "Linhas Bash: $linhas_novas"                         "Hash atual: ${hash_atual:0:16}…"                         "Hash novo: ${hash_novo:0:16}…"
                    pause
                    ;;
                0) return 1 ;;
                *) feedback_curto "Opção inválida." ;;
            esac
        done
    }

    confirmar_atualizacao_visual || { rm -rf "$tmp"; return; }

    # A tela é desenhada uma única vez. Nas etapas seguintes somente o bloco
    # de status é reescrito no mesmo lugar, evitando o efeito de recarregar a
    # página inteira a cada fase.
    local tamanho_extraido arquivos_pacote espaco_livre tamanho_backup_estimado
    tamanho_extraido="$(du -sb "$pacote" 2>/dev/null | awk '{print $1}')"
    [ -n "$tamanho_extraido" ] || tamanho_extraido=0
    arquivos_pacote="$(find "$pacote" -type f 2>/dev/null | wc -l | tr -d ' ')"
    espaco_livre="$(df -Pk "$BASE_DIR" 2>/dev/null | awk 'NR==2 {print $4 * 1024}')"
    [ -n "$espaco_livre" ] || espaco_livre=0
    tamanho_backup_estimado="$(du -sb "$BASE_DIR/manager.sh" "$BASE_DIR/modules" 2>/dev/null | awk '{s+=$1} END {print s+0}')"

    # Margem conservadora: pacote extraído + backup + uma segunda cópia dos
    # módulos durante a troca, acrescida de 20%.
    local espaco_necessario
    espaco_necessario=$(( (tamanho_extraido * 2 + tamanho_backup_estimado) * 120 / 100 ))
    if [ "$espaco_livre" -gt 0 ] && [ "$espaco_livre" -lt "$espaco_necessario" ]; then
        cabecalho_tela "⚠ Espaço insuficiente" "A atualização não foi iniciada"
        caixa_simples "Armazenamento"             "Disponível: $(formatar_tamanho "$espaco_livre")"             "Necessário: aproximadamente $(formatar_tamanho "$espaco_necessario")"             "Libere espaço e tente novamente."
        rm -rf "$tmp"
        pause
        return
    fi

    tela_atualizacao_iniciar() {
        # A atualização precisa escrever diretamente no terminal. Usar
        # cabecalho_tela aqui ativava o buffer global e fazia o novo Manager
        # herdar stdout apontando para um arquivo temporário após o exec.
        ui_buffer_flush 2>/dev/null || true
        tela_limpar
        local tela
        tela="$(
            caixa_linha_topo
            caixa_linha_texto "${C_BOLD}${C_WHITE}🔄 Atualizando Manager${C_RESET}" true
            caixa_linha_texto "${C_DIM}Versão $MANAGER_VERSION → $nova_versao${C_RESET}" true
            caixa_linha_baixo
            echo
            caixa_simples "Resumo da instalação"                 "Pacote: $(basename "$arquivo")"                 "Download: $(formatar_tamanho "$tamanho_novo") • Extraído: $(formatar_tamanho "$tamanho_extraido")"                 "Arquivos: $arquivos_pacote • Backup estimado: $(formatar_tamanho "$tamanho_backup_estimado")"                 "Espaço livre: $(formatar_tamanho "$espaco_livre")"
        )"
        printf '%s\n\n' "$tela"
        # Marca o início da área dinâmica. Cada atualização volta exatamente
        # para esta posição e substitui somente as linhas do progresso.
        printf '\033[s'
    }

    tela_atualizacao_etapa() {
        local etapa="$1" total="$2" titulo="$3" detalhe="$4" estado="${5:-em andamento}"
        local percentual=$(( etapa * 100 / total )) preenchido vazio barra=""
        ui_buffer_flush 2>/dev/null || true
        preenchido=$(( percentual / 5 )); vazio=$((20 - preenchido))
        barra="$(repetir_char '█' "$preenchido")$(repetir_char '░' "$vazio")"
        printf '\033[u\033[J'
        local bloco
        bloco="$(
            caixa_linha_topo
            caixa_linha_texto "${C_BOLD}Etapa $etapa de $total • $percentual%${C_RESET}" true
            caixa_linha_sep
            caixa_linha_texto "$barra"
            caixa_linha_texto "${C_BOLD}$titulo${C_RESET}"
            caixa_linha_texto "$detalhe"
            caixa_linha_texto "Status: $estado"
            caixa_linha_baixo
        )"
        printf '%s\n' "$bloco"
    }

    tela_atualizacao_iniciar

    local total_etapas=5
    tela_atualizacao_etapa 1 "$total_etapas" "Validando o pacote" "Estrutura e sintaxe verificadas." "concluída"
    sleep 0.35

    local backup="$updates_dir/manager_backup_$stamp.tar.gz"
    local -a itens_backup=(manager.sh modules)
    local item_backup
    for item_backup in install.sh README.md CHANGELOG.md RELEASE_STANDARD.md MANIFEST.json tools resources config; do
        [ -e "$BASE_DIR/$item_backup" ] && itens_backup+=("$item_backup")
    done
    tela_atualizacao_etapa 2 "$total_etapas" "Criando backup de segurança" "Destino: $(basename "$backup")"
    tar -czf "$backup" -C "$BASE_DIR" "${itens_backup[@]}" || { error "Falha ao criar backup."; rm -rf "$tmp"; pause; return; }
    tela_atualizacao_etapa 2 "$total_etapas" "Criando backup de segurança" "Destino: $(basename "$backup")" "concluída"
    sleep 0.35
    local novo_manager="$BASE_DIR/.manager_new_$stamp.sh" novos_modulos="$BASE_DIR/.modules_new_$stamp" antigos_modulos="$BASE_DIR/.modules_old_$stamp"
    tela_atualizacao_etapa 3 "$total_etapas" "Preparando a nova versão" "Normalizando e organizando os arquivos."
    # tr -d '\r' normaliza quebras de linha estilo Windows (\r\n), que podem
    # vir do arquivo baixado (edição no PC, apps de transferência, etc.) e
    # causar comportamento estranho em scripts Bash.
    tr -d '\r' < "$pacote/manager.sh" > "$novo_manager" || { error "Falha ao preparar manager.sh."; rm -rf "$tmp"; pause; return; }
    cp -R "$pacote/modules" "$novos_modulos" || { error "Falha ao preparar módulos."; rm -rf "$tmp" "$novo_manager"; pause; return; }
    local modfile
    while IFS= read -r -d '' modfile; do
        tr -d '\r' < "$modfile" > "$modfile.tmp" && mv -f "$modfile.tmp" "$modfile"
    done < <(find "$novos_modulos" -type f -name '*.sh' -print0)
    bash -n "$novo_manager" || { error "manager.sh ficou inválido após normalizar quebras de linha."; rm -rf "$tmp" "$novo_manager" "$novos_modulos"; pause; return; }
    chmod 700 "$novo_manager"; find "$novos_modulos" -type f -name '*.sh' -exec chmod 600 {} \;
    tela_atualizacao_etapa 3 "$total_etapas" "Preparando a nova versão" "Arquivos prontos para instalação." "concluída"
    sleep 0.35
    tela_atualizacao_etapa 4 "$total_etapas" "Aplicando a atualização" "Substituindo o núcleo e os módulos."
    mv "$MODULES_DIR" "$antigos_modulos" || { error "Falha ao preparar substituição."; rm -rf "$tmp" "$novo_manager" "$novos_modulos"; pause; return; }
    if mv "$novos_modulos" "$MODULES_DIR" && mv -f "$novo_manager" "$SELF_PATH"; then
        rm -rf "$antigos_modulos"
    else
        rm -rf "$MODULES_DIR"; mv "$antigos_modulos" "$MODULES_DIR" 2>/dev/null || true
        tar -xzf "$backup" -C "$BASE_DIR" 2>/dev/null || true
        error "Atualização falhou; o backup foi restaurado."; rm -rf "$tmp"; pause; return
    fi

    local auxiliar
    if ! {
        for auxiliar in install.sh README.md CHANGELOG.md RELEASE_STANDARD.md MANIFEST.json; do
            [ -f "$pacote/$auxiliar" ] && cp -f "$pacote/$auxiliar" "$BASE_DIR/$auxiliar"
        done
        for auxiliar in tools resources config; do
            if [ -d "$pacote/$auxiliar" ]; then
                mkdir -p "$BASE_DIR/$auxiliar"
                cp -a "$pacote/$auxiliar/." "$BASE_DIR/$auxiliar/"
            fi
        done
        [ -f "$BASE_DIR/install.sh" ] && chmod 700 "$BASE_DIR/install.sh" 2>/dev/null || true
    }; then
        tar -xzf "$backup" -C "$BASE_DIR" 2>/dev/null || true
        error "Falha ao sincronizar arquivos auxiliares; o backup foi restaurado."
        rm -rf "$tmp"
        pause
        return 1
    fi
    tela_atualizacao_etapa 4 "$total_etapas" "Aplicando a atualização" "Código, documentação e ferramentas sincronizados." "concluída"
    sleep 0.35
    tela_atualizacao_etapa 5 "$total_etapas" "Finalizando" "Registrando a atualização e preparando o reinício."
    rm -rf "$tmp"
    if [ "${ATUALIZACAO_LIMPAR_ARQUIVO:-false}" = true ]; then
        local pasta_download_remota
        pasta_download_remota="$(dirname "$arquivo")"
        rm -f -- "$arquivo" 2>/dev/null || true
        rmdir "$pasta_download_remota" 2>/dev/null || true
    fi
    cat > "$(arquivo_status_atualizacao)" <<EOF
DATA="$(date '+%d/%m/%Y %H:%M:%S')"
TIPO="${ATUALIZACAO_TIPO:-completa}"
ARQUIVO="$(basename "$arquivo")"
VERSAO_ANTERIOR="$MANAGER_VERSION"
VERSAO_NOVA="$nova_versao"
BACKUP="$(basename "$backup")"
STATUS="confirmada"
EOF
    # O atalho aponta para um caminho estável ($BASE_DIR/manager.sh), portanto
    # não precisa ser recriado em toda atualização. Além de redundante, essa
    # operação disparava helpers de UI antigos já carregados em memória.
    tela_atualizacao_etapa 5 "$total_etapas" "Finalizando" "Registro salvo e reinício preparado." "concluída"
    sleep 0.45

    # Garante que nenhuma saída permaneça presa no buffer antes de mostrar a
    # conclusão e, principalmente, antes de substituir o processo com exec.
    ui_buffer_flush 2>/dev/null || true
    tela_limpar
    local tela_final
    tela_final="$(
        caixa_linha_topo
        caixa_linha_texto "${C_BOLD}${C_WHITE}✅ Atualização concluída${C_RESET}" true
        caixa_linha_texto "${C_DIM}O Manager foi atualizado com segurança${C_RESET}" true
        caixa_linha_sep
        caixa_linha_texto "Versão anterior: $MANAGER_VERSION"
        caixa_linha_texto "Versão instalada: $nova_versao"
        caixa_linha_texto "Backup: $(basename "$backup")"
        caixa_linha_texto "Status: arquivos verificados e registro salvo"
        caixa_linha_sep
        caixa_linha_texto "O Manager será reiniciado automaticamente."
        caixa_linha_baixo
    )"
    printf '%s\n\n' "$tela_final"

    local contagem
    for contagem in 3 2 1; do
        printf "\r${C_CYAN}➜${C_RESET} Reiniciando em %s... " "$contagem"
        sleep 1
    done
    printf "\r${C_GREEN}✔${C_RESET} Carregando a versão %s...      \n" "$nova_versao"
    sleep 0.3

    # Última barreira de segurança: restaura stdout, cursor, sinais e lock.
    # Sem isso, o novo processo pode iniciar invisível em um arquivo temporário.
    ui_buffer_flush 2>/dev/null || true
    printf '\033[0m\033[?25h\033[r\033[?7h'
    stty sane 2>/dev/null || true
    liberar_bloqueio 2>/dev/null || true
    trap - EXIT INT TERM
    exec bash "$SELF_PATH"
}

instalar_modulo_manager() {
    local arquivo="$1" updates_dir="$BASE_DIR/.updates" stamp nome destino descricao
    stamp="$(date '+%Y%m%d_%H%M%S')"; mkdir -p "$updates_dir"
    bash -n "$arquivo" || { error "O arquivo possui erro de sintaxe."; pause; return; }
    nome="$(basename "$arquivo")"; nome="${nome%.module.sh}.sh"
    if [ "$nome" = "manager.sh" ]; then destino="$SELF_PATH"; descricao="arquivo principal"
    elif [ -f "$MODULES_DIR/$nome" ]; then destino="$MODULES_DIR/$nome"; descricao="módulo $nome"
    else error "O arquivo não corresponde a um módulo instalado."; pause; return; fi

    local hash_atual hash_novo tamanho_atual tamanho_novo linhas_atual linhas_novo
    hash_atual="$(hash_arquivo_manager "$destino")"; hash_novo="$(hash_arquivo_manager "$arquivo")"
    tamanho_atual="$(stat -c%s "$destino" 2>/dev/null || echo 0)"; tamanho_novo="$(stat -c%s "$arquivo" 2>/dev/null || echo 0)"
    linhas_atual="$(wc -l < "$destino")"; linhas_novo="$(wc -l < "$arquivo")"

    cabecalho_tela "🧩 Atualização de módulo" "Somente um arquivo será substituído"
    caixa_simples "Comparação" \
        "Destino: $descricao" \
        "Atual: $(formatar_tamanho "$tamanho_atual") • $linhas_atual linhas" \
        "Novo: $(formatar_tamanho "$tamanho_novo") • $linhas_novo linhas" \
        "Hash atual: ${hash_atual:0:12}…" \
        "Hash novo: ${hash_novo:0:12}…"
    [ "$hash_atual" = "$hash_novo" ] && { ok "Este arquivo já está instalado."; pause; return; }
    confirmar_acao "Substituir somente $descricao?" "n" || return

    local backup="$updates_dir/${nome}.backup_$stamp" temporario="$BASE_DIR/.update_${nome}_$stamp" hash_final hash_esperado
    cp "$destino" "$backup" || { error "Falha ao criar backup."; pause; return; }
    tr -d '\r' < "$arquivo" > "$temporario" || { error "Falha ao copiar o arquivo."; rm -f "$temporario"; pause; return; }
    bash -n "$temporario" || { error "A cópia temporária é inválida."; rm -f "$temporario"; pause; return; }
    # Calculado a partir do arquivo JÁ limpo (pós tr -d '\r'), não do original
    # em "$arquivo". Antes disso comparava com o hash do arquivo original,
    # que quase sempre é diferente quando o arquivo baixado tem quebras de
    # linha estilo Windows (\r\n) — fazendo a verificação abaixo falhar e
    # desfazer a atualização mesmo quando ela tinha dado certo.
    hash_esperado="$(hash_arquivo_manager "$temporario")"
    [ "$nome" = manager.sh ] && chmod 700 "$temporario" || chmod 600 "$temporario"
    mv -f "$temporario" "$destino" || { cp "$backup" "$destino"; error "Falha ao substituir o arquivo."; pause; return; }
    hash_final="$(hash_arquivo_manager "$destino")"
    if [ "$hash_final" != "$hash_esperado" ] || ! bash -n "$destino"; then
        cp "$backup" "$destino"; error "A verificação falhou; o backup foi restaurado."; pause; return
    fi
    cat > "$(arquivo_status_atualizacao)" <<EOF
DATA="$(date '+%d/%m/%Y %H:%M:%S')"
TIPO="módulo"
ARQUIVO="$(basename "$arquivo")"
DESTINO="$nome"
VERSAO_ANTERIOR="$MANAGER_VERSION"
VERSAO_NOVA="$MANAGER_VERSION"
STATUS="confirmada"
EOF
    ok "$descricao atualizado com sucesso."
    info "O Manager será fechado para recarregar os módulos."
    sleep 2; exit 0
}

atualizar_manager_local() {
    while true; do
        menu_unificado "🔄 Atualizar Manager" "GitHub main ou arquivo local"             "[0] Voltar  •  [1–4] Selecionar"             "1|🌐|Verificar no GitHub|Comparar com a branch main e atualizar automaticamente"             "2|📦|Atualizar por ZIP|Usar um pacote completo salvo em Downloads"             "3|🧩|Atualizar um módulo|Substituir somente um arquivo .sh"             "4|🕘|Ver última atualização|Confirmar data, arquivo e status"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1)
                GITHUB_UPDATE_INTERACTIVE=true
                github_status_render "🌐 Atualização pelo GitHub" \
                    "Branch: $MANAGER_GITHUB_BRANCH • versão instalada: $MANAGER_VERSION" \
                    "⏳ Abrindo conexão..." "Aguarde: nenhuma alteração será feita sem validação."
                sleep 0.15
                ATUALIZACAO_TIPO="github-main"
                verificar_atualizacao_github
                ATUALIZACAO_TIPO=""
                ;;
            2)
                if ! check_storage_access; then pause; continue; fi
                ATUALIZACAO_TIPO="completa-local"
                listar_pacotes_completos
                selecionar_atualizacao_lista "📦 Atualização completa" "Qualquer .zip válido do Manager no Download" || { ATUALIZACAO_TIPO=""; continue; }
                instalar_pacote_manager "$ATUALIZACAO_ESCOLHIDA"
                ATUALIZACAO_TIPO=""
                ;;
            3)
                if ! check_storage_access; then pause; continue; fi
                listar_modulos_atualizacao
                selecionar_atualizacao_lista "🧩 Atualizar um módulo" "Procura manager.sh ou arquivos .sh compatíveis" || continue
                instalar_modulo_manager "$ATUALIZACAO_ESCOLHIDA"
                ;;
            4) mostrar_ultima_atualizacao_manager ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
