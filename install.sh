#!/data/data/com.termux/files/usr/bin/bash
# Instalador oficial do Termux Manager.
# Uso recomendado:
#   curl -fsSL https://raw.githubusercontent.com/adriedsonlemoz/TermuxManager/main/install.sh | bash

set -Euo pipefail

REPOSITORY="adriedsonlemoz/TermuxManager"
BRANCH="${TERMUX_MANAGER_BRANCH:-main}"
SOURCE_URL="${TERMUX_MANAGER_SOURCE_URL:-https://github.com/${REPOSITORY}/archive/refs/heads/${BRANCH}.zip}"
INSTALL_DIR="${TERMUX_MANAGER_INSTALL_DIR:-${HOME}/scripts/manager}"
BACKUP_ROOT="${TERMUX_MANAGER_BACKUP_ROOT:-${HOME}/.termux-manager/backups}"
TMP_BASE="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
TMP_DIR=""

info() { printf '\n▶ %s\n' "$*"; }
ok()   { printf '✅ %s\n' "$*"; }
fail() { printf '❌ %s\n' "$*" >&2; exit 1; }

cleanup() {
    [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ] && rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT INT TERM

command -v pkg >/dev/null 2>&1 || fail "Este instalador deve ser executado dentro do Termux."
command -v curl >/dev/null 2>&1 || fail "curl não foi encontrado. Execute 'pkg install curl' e tente novamente."

TERMUX_VARIANT_ID=""
TERMUX_VARIANT_LABEL=""
TERMUX_REPO_PRIMARY=""

coletar_repositorios_termux() {
    local -a fontes=()
    local arquivo prefixo="${PREFIX:-}"
    [ -n "$prefixo" ] || return 0
    [ -r "$prefixo/etc/apt/sources.list" ] && fontes+=("$prefixo/etc/apt/sources.list")
    for arquivo in "$prefixo"/etc/apt/sources.list.d/*.list; do
        [ -r "$arquivo" ] && fontes+=("$arquivo")
    done
    [ ${#fontes[@]} -gt 0 ] || return 0
    awk '/^[[:space:]]*deb[[:space:]]+https?:\/\// {print $2}' "${fontes[@]}" 2>/dev/null | awk '!seen[$0]++'
}

detectar_variante_termux() {
    [ -n "${TERMUX_VARIANT_LABEL:-}" ] && return 0
    local versao="${TERMUX_VERSION:-}" repos=""
    repos="$(coletar_repositorios_termux | paste -sd ', ' - 2>/dev/null || true)"
    TERMUX_REPO_PRIMARY="$(printf '%s' "$repos" | awk -F', ' 'NF{print $1; exit}')"
    [ -n "$TERMUX_REPO_PRIMARY" ] || TERMUX_REPO_PRIMARY="indisponível"
    TERMUX_VARIANT_ID="unknown"
    TERMUX_VARIANT_LABEL="Origem não identificada"
    case "$versao $repos" in
        googleplay.*|*termux.net*)
            TERMUX_VARIANT_ID="google-play"
            TERMUX_VARIANT_LABEL="Google Play"
            ;;
        *packages.termux.dev*|*packages-cf.termux.dev*|*grimler.se*|*termux.dev*)
            TERMUX_VARIANT_ID="github-fdroid"
            TERMUX_VARIANT_LABEL="GitHub/F-Droid"
            ;;
        *)
            if [ -n "$versao" ] && [[ "$versao" =~ ^[0-9] ]]; then
                TERMUX_VARIANT_ID="github-fdroid"
                TERMUX_VARIANT_LABEL="GitHub/F-Droid"
            fi
            ;;
    esac
}

pids_pkg_ativos() {
    local proc pid nome estado
    for proc in /proc/[0-9]*; do
        [ -r "$proc/comm" ] || continue
        IFS= read -r nome < "$proc/comm" || continue
        case "$nome" in
            apt|apt-get|dpkg|dpkg-deb)
                pid="${proc##*/}"
                estado="$(awk '/^State:/{print $2; exit}' "$proc/status" 2>/dev/null || true)"
                [ "$estado" = "Z" ] && continue
                printf '%s ' "$pid"
                ;;
        esac
    done
}

aguardar_pkg_livre() {
    local timeout="${TERMUX_MANAGER_PKG_LOCK_TIMEOUT:-180}"
    local inicio=$SECONDS decorrido pids anunciou=0 ultima=-1
    while :; do
        pids="$(pids_pkg_ativos)"
        pids="${pids% }"
        [ -z "$pids" ] && break
        decorrido=$((SECONDS - inicio))
        if [ "$decorrido" -ge "$timeout" ]; then
            [ "$anunciou" -eq 1 ] && [ -t 1 ] && printf '\n'
            fail "O gerenciador de pacotes continua ocupado (PID(s): $pids). Aguarde a outra instalação terminar e execute o instalador novamente."
        fi
        if [ -t 1 ]; then
            printf '\r⏳ O Termux já está instalando/atualizando pacotes. Aguardando... %ss/%ss  ' "$decorrido" "$timeout"
            anunciou=1
        elif [ "$ultima" -lt 0 ] || [ $((decorrido - ultima)) -ge 15 ]; then
            printf '⏳ Gerenciador de pacotes ocupado (PID(s): %s). Aguardando... %ss/%ss\n' "$pids" "$decorrido" "$timeout"
            ultima="$decorrido"
            anunciou=1
        fi
        sleep 2
    done
    if [ "$anunciou" -eq 1 ]; then
        [ -t 1 ] && printf '\n'
        ok "Gerenciador de pacotes liberado."
    fi
}

detectar_variante_termux
info "Termux detectado: ${TERMUX_VARIANT_LABEL:-Origem não identificada}"
printf 'Versão: %s
' "${TERMUX_VERSION:-indisponível}"
printf 'Repositório: %s

' "${TERMUX_REPO_PRIMARY:-indisponível}"

# O acesso a Downloads depende de uma permissão do Android. O instalador tenta
# preparar isso antes de instalar o Manager, mas a confirmação da janela de
# permissão continua sendo feita pelo próprio usuário.
if [ "${TERMUX_MANAGER_SKIP_STORAGE_SETUP:-0}" != "1" ]; then
    if [ -d "$HOME/storage/downloads" ] || [ -d "$HOME/storage/shared" ]; then
        ok "Armazenamento Android já está disponível."
    elif command -v termux-setup-storage >/dev/null 2>&1; then
        info "Preparando acesso ao armazenamento Android"
        printf '%s
' "Aceite a permissão de arquivos quando o Android solicitar."
        termux-setup-storage >/dev/null 2>&1 || true
        sleep 2
        if [ -d "$HOME/storage/downloads" ] || [ -d "$HOME/storage/shared" ]; then
            ok "Acesso ao armazenamento liberado."
        else
            printf '%s
' "⚠ A permissão ainda não foi detectada. O Manager pode ser instalado, mas Downloads só ficará disponível depois que você conceder o acesso."
        fi
    else
        printf '%s
' "⚠ termux-setup-storage não foi encontrado. O Manager seguirá sem preparar Downloads."
    fi
fi

mkdir -p "$TMP_BASE"
TMP_DIR="$(mktemp -d "$TMP_BASE/termux-manager-install.XXXXXX")" || fail "Não foi possível criar a pasta temporária."

necessarios=()
command -v unzip >/dev/null 2>&1 || necessarios+=(unzip)
command -v sha256sum >/dev/null 2>&1 || necessarios+=(coreutils)
if [ ${#necessarios[@]} -gt 0 ]; then
    aguardar_pkg_livre
    info "Preparando ferramentas necessárias: ${necessarios[*]}"
    pkg_log="$TMP_DIR/pkg-install.log"
    if ! pkg install -y "${necessarios[@]}" >"$pkg_log" 2>&1; then
        printf '%s\n' "Últimas mensagens do pkg:" >&2
        tail -n 12 "$pkg_log" >&2 2>/dev/null || true
        fail "Não foi possível instalar as ferramentas necessárias."
    fi
fi
archive_path="$TMP_DIR/TermuxManager.zip"
source_dir="$TMP_DIR/source"
mkdir -p "$source_dir"

info "Baixando a versão estável da branch $BRANCH"
curl -fL --retry 3 --connect-timeout 20 -o "$archive_path" "$SOURCE_URL" \
    || fail "Não foi possível baixar o Termux Manager do GitHub."

info "Extraindo e validando o projeto"
unzip -q "$archive_path" -d "$source_dir" || fail "Não foi possível extrair o pacote baixado."

stage_dir="$source_dir"
if [ ! -f "$stage_dir/manager.sh" ] || [ ! -d "$stage_dir/modules" ]; then
    stage_dir=""
    candidatos=0
    for candidato in "$source_dir"/*; do
        [ -d "$candidato" ] || continue
        if [ -f "$candidato/manager.sh" ] && [ -d "$candidato/modules" ]; then
            stage_dir="$candidato"
            candidatos=$((candidatos + 1))
        fi
    done
    [ "$candidatos" -eq 1 ] || fail "Pacote inválido: não foi possível identificar uma única raiz do Termux Manager."
fi

[ -f "$stage_dir/MANIFEST.json" ] || fail "Pacote inválido: MANIFEST.json não encontrado."

bash -n "$stage_dir/manager.sh" || fail "manager.sh contém erro de sintaxe."
for module in "$stage_dir"/modules/*.sh; do
    [ -f "$module" ] || continue
    bash -n "$module" || fail "Erro de sintaxe em ${module##*/}."
done

internal_version="$(sed -nE 's/^MANAGER_VERSION="([^"]+)".*/\1/p' "$stage_dir/manager.sh" | head -n 1)"
manifest_version="$(sed -nE 's/^[[:space:]]*"version":[[:space:]]*"([^"]+)".*/\1/p' "$stage_dir/MANIFEST.json" | head -n 1)"
[ -n "$internal_version" ] || fail "Não foi possível identificar a versão interna."
[ -n "$manifest_version" ] || fail "Não foi possível identificar a versão do manifesto."
[ "$internal_version" = "$manifest_version" ] || fail "Versão interna ($internal_version) difere do manifesto ($manifest_version)."

manifest_entries=0
while IFS=$'\t' read -r relative expected; do
    [ -n "$relative" ] || continue
    target="$stage_dir/$relative"
    [ -f "$target" ] || fail "Manifesto inválido: arquivo ausente: $relative"
    actual="$(sha256sum "$target" | awk '{print $1}')"
    [ "${actual,,}" = "${expected,,}" ] || fail "Integridade inválida em: $relative"
    manifest_entries=$((manifest_entries + 1))
done < <(
    sed -n '/"files"[[:space:]]*:[[:space:]]*{/,/^[[:space:]]*}[[:space:]]*$/p' "$stage_dir/MANIFEST.json" \
        | sed -nE 's/^[[:space:]]*"([^"]+)":[[:space:]]*"([0-9A-Fa-f]{64})",?[[:space:]]*$/\1\t\2/p'
)
[ "$manifest_entries" -gt 0 ] || fail "Manifesto inválido: nenhum hash de arquivo foi encontrado."
ok "Manifesto validado: $manifest_entries arquivos conferidos"

info "Instalando Termux Manager $internal_version"
mkdir -p "$(dirname "$INSTALL_DIR")"
new_dir="${INSTALL_DIR}.new.$$"
old_dir="${INSTALL_DIR}.old.$$"
rm -rf -- "$new_dir" "$old_dir"
cp -a "$stage_dir" "$new_dir" || fail "Não foi possível preparar a nova instalação."

backup_dir=""
if [ -e "$INSTALL_DIR" ]; then
    mkdir -p "$BACKUP_ROOT"
    backup_dir="$BACKUP_ROOT/installer-$(date +%Y%m%d-%H%M%S)"
    cp -a "$INSTALL_DIR" "$backup_dir" || fail "Não foi possível criar o backup da instalação atual."
    mv "$INSTALL_DIR" "$old_dir" || fail "Não foi possível preparar a substituição da instalação atual."
fi

if ! mv "$new_dir" "$INSTALL_DIR"; then
    [ -e "$old_dir" ] && mv "$old_dir" "$INSTALL_DIR" 2>/dev/null || true
    fail "Não foi possível concluir a instalação. A instalação anterior foi preservada quando possível."
fi
rm -rf -- "$old_dir"

ok "Termux Manager $internal_version instalado em $INSTALL_DIR"
[ -n "$backup_dir" ] && printf 'Backup anterior: %s\n' "$backup_dir"

if [ "${TERMUX_MANAGER_SKIP_LAUNCH:-0}" = "1" ]; then
    ok "Instalação concluída sem abrir o Manager (modo de teste)."
    exit 0
fi

info "Abrindo o Termux Manager"
if [ -r /dev/tty ]; then
    exec bash "$INSTALL_DIR/manager.sh" </dev/tty
else
    exec bash "$INSTALL_DIR/manager.sh"
fi
