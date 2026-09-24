# Módulo: linux_distros.sh
# Descoberta, informações, instalação e manutenção de distribuições PRoot.

linux_distro_sessoes_ativas() {
    local alias="${1:-}" saida
    command -v proot-distro >/dev/null 2>&1 || { printf '0\n'; return; }
    saida="$(proot-distro ps 2>/dev/null || true)"
    if [ -z "$saida" ]; then
        printf '0\n'
        return
    fi
    printf '%s\n' "$saida" | awk -v a="$alias" 'NR>1 && $2==a {n++} END{print n+0}'
}

linux_distro_desktops_rootfs() {
    local alias="${1:-}" root id launcher caminho nomes=""
    root="$(linux_container_rootfs "$alias" 2>/dev/null || true)"
    [ -n "$root" ] || { printf 'nenhum\n'; return; }
    for id in xfce lxqt lxde mate openbox i3 kde gnome; do
        launcher="$(linux_desktop_launcher "$id" 2>/dev/null || true)"
        [ -n "$launcher" ] || continue
        caminho=""
        for base in usr/bin usr/local/bin bin; do
            [ -e "$root/$base/$launcher" ] && { caminho="$root/$base/$launcher"; break; }
        done
        if [ -n "$caminho" ]; then
            nomes+="${nomes:+, }$(linux_desktop_nome "$id")"
        fi
    done
    printf '%s\n' "${nomes:-nenhum}"
}

linux_distro_gerenciador_rootfs() {
    local alias="${1:-}" root
    root="$(linux_container_rootfs "$alias" 2>/dev/null || true)"
    [ -n "$root" ] || { printf 'desconhecido\n'; return; }
    [ -e "$root/usr/bin/apt-get" ] && { printf 'apt\n'; return; }
    [ -e "$root/usr/bin/pacman" ] && { printf 'pacman\n'; return; }
    if [ -e "$root/sbin/apk" ] || [ -e "$root/usr/bin/apk" ]; then printf 'apk\n'; return; fi
    [ -e "$root/usr/bin/dnf" ] && { printf 'dnf\n'; return; }
    [ -e "$root/usr/bin/zypper" ] && { printf 'zypper\n'; return; }
    printf 'desconhecido\n'
}

linux_distro_tamanho_kb() {
    local alias="${1:-}" root tamanho cache agora salvo_ts salvo_kb
    root="$(linux_container_rootfs "$alias" 2>/dev/null || true)"
    [ -n "$root" ] || { printf '0\n'; return; }
    cache="$(linux_cache_tamanho_arquivo "$alias")"
    agora="$(date +%s 2>/dev/null || printf '0')"
    if [ -f "$cache" ]; then
        IFS='|' read -r salvo_ts salvo_kb < "$cache" || true
        if [[ "$agora" =~ ^[0-9]+$ ]] && [[ "${salvo_ts:-}" =~ ^[0-9]+$ ]] && [[ "${salvo_kb:-}" =~ ^[0-9]+$ ]] && \
           [ $((agora - salvo_ts)) -ge 0 ] && [ $((agora - salvo_ts)) -lt "$LINUX_INFO_CACHE_TTL" ]; then
            printf '%s\n' "$salvo_kb"
            return
        fi
    fi
    tamanho="$(du -sk "$root" 2>/dev/null | awk 'NR==1{print $1}')"
    [[ "$tamanho" =~ ^[0-9]+$ ]] || tamanho=0
    mkdir -p "$(dirname "$cache")" 2>/dev/null || true
    printf '%s|%s\n' "$agora" "$tamanho" > "$cache" 2>/dev/null || true
    printf '%s\n' "$tamanho"
}

linux_coletar_info_distro() {
    local alias="${1:-}" forcar_saude="${2:-false}" nome versao arch imagem tamanho_kb sessoes desktops gerenciador
    nome="$(linux_os_release_campo "$alias" PRETTY_NAME 2>/dev/null || true)"
    [ -n "$nome" ] || nome="$(linux_os_release_campo "$alias" NAME 2>/dev/null || true)"
    [ -n "$nome" ] || nome="$alias"
    versao="$(linux_os_release_campo "$alias" VERSION_ID 2>/dev/null || true)"
    arch="$(linux_manifest_campo "$alias" arch 2>/dev/null || true)"
    [ -n "$arch" ] || arch="desconhecida"
    imagem="$(linux_manifest_campo "$alias" image_ref 2>/dev/null || true)"
    [ -n "$imagem" ] || imagem="origem não registrada"
    tamanho_kb="$(linux_distro_tamanho_kb "$alias")"
    sessoes="$(linux_distro_sessoes_ativas "$alias")"
    desktops="$(linux_distro_desktops_rootfs "$alias")"
    gerenciador="$(linux_distro_gerenciador_rootfs "$alias")"
    linux_testar_saude_distro "$alias" "$forcar_saude"

    LINUX_INFO_ALIAS="$alias"
    LINUX_INFO_NAME="$nome"
    LINUX_INFO_VERSION="$versao"
    LINUX_INFO_ARCH="$arch"
    LINUX_INFO_IMAGE="$imagem"
    LINUX_INFO_SIZE_KB="$tamanho_kb"
    LINUX_INFO_SIZE="$(linux_formatar_tamanho_kb "$tamanho_kb")"
    LINUX_INFO_SESSIONS="$sessoes"
    LINUX_INFO_DESKTOPS="$desktops"
    LINUX_INFO_PM="$gerenciador"
    if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
        LINUX_INFO_HEALTH_ICON="✅"
        LINUX_INFO_HEALTH_LABEL="OK"
    else
        LINUX_INFO_HEALTH_ICON="⚠️"
        LINUX_INFO_HEALTH_LABEL="$(linux_rotulo_curto_saude)"
    fi
    if [ "$sessoes" -gt 0 ] 2>/dev/null; then
        LINUX_INFO_STATE_ICON="🟢"
        LINUX_INFO_STATE_LABEL="Em execução (${sessoes})"
    else
        LINUX_INFO_STATE_ICON="⚪"
        LINUX_INFO_STATE_LABEL="Parado"
    fi
}

linux_exibir_info_distro() {
    local alias="${1:-}"
    linux_coletar_info_distro "$alias" true
    cabecalho_tela "🐧 $LINUX_INFO_NAME" "Informações da distribuição"
    caixa_simples "Estado" \
        "Alias: $alias" \
        "Estado: ${LINUX_INFO_STATE_ICON} ${LINUX_INFO_STATE_LABEL}" \
        "Saúde: ${LINUX_INFO_HEALTH_ICON} ${LINUX_INFO_HEALTH_LABEL}" \
        "Tamanho atual: $LINUX_INFO_SIZE"
    caixa_simples "Sistema" \
        "Versão: ${LINUX_INFO_VERSION:-não informada}" \
        "Arquitetura: $LINUX_INFO_ARCH" \
        "Imagem de origem: $LINUX_INFO_IMAGE" \
        "Gerenciador: $(linux_descrever_gerenciador_distro "$LINUX_INFO_PM")" \
        "Desktop(s): $LINUX_INFO_DESKTOPS"
    if [ "$LINUX_INFO_HEALTH" != "ok" ]; then
        caixa_simples "⚠ Diagnóstico" \
            "Motivo: ${LINUX_DIAG_REASON:-não identificado}" \
            "Código: ${LINUX_DIAG_CODE:-UNKNOWN}" \
            "Use Diagnóstico para ver os detalhes."
    fi
    pause
}

linux_nome_container_imagem() {
    local ref="${1:-}" nome
    nome="${ref%%@*}"
    nome="${nome##*/}"
    if [[ "$nome" == *:* ]]; then nome="${nome%%:*}"; fi
    nome="$(printf '%s' "$nome" | tr -cd 'A-Za-z0-9._-')"
    [ -n "$nome" ] || nome="linux"
    printf '%s\n' "$nome"
}

linux_imagem_referencia_valida() {
    local ref="${1:-}"
    [ -n "$ref" ] || return 1
    [ ${#ref} -le 255 ] || return 1
    [[ "$ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/:@+-]*$ ]]
}

linux_selecionar_instalada() {
    local titulo="${1:-Selecionar distribuição}" subtitulo="${2:-Distribuições instaladas}" i escolha
    linux_coletar_instaladas || true
    if [ ${#LINUX_INSTALLED_DISTROS[@]} -eq 0 ]; then
        cabecalho_tela "🐧 Nenhuma distribuição instalada" "É preciso instalar uma distribuição antes de continuar"
        caixa_simples "Próximo passo" \
            "Ainda não há nenhum Linux instalado pelo proot-distro." \
            "O Manager pode abrir agora a tela de instalação." \
            "Você não precisa digitar alias manualmente."
        if confirmar_acao "Instalar uma distribuição agora?" "s"; then
            linux_instalar_distro
        fi
        return 1
    fi

    local -a opcoes=()
    for ((i=0; i<${#LINUX_INSTALLED_DISTROS[@]}; i++)); do
        opcoes+=("$((i+1))|🐧|${LINUX_INSTALLED_DISTROS[$i]}|Distribuição instalada")
    done
    while true; do
        menu_unificado "$titulo" "$subtitulo" "[0] Voltar  •  [1–${#LINUX_INSTALLED_DISTROS[@]}] Selecionar" "${opcoes[@]}"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        [ "$escolha" = "0" ] && return 1
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#LINUX_INSTALLED_DISTROS[@]} ]; then
            LINUX_DISTRO_ALIAS="${LINUX_INSTALLED_DISTROS[$((escolha-1))]}"
            return 0
        fi
        feedback_curto "Opção inválida."
    done
}

linux_listar_distros() {
    linux_meus_linux
}

linux_pesquisar_imagem() {
    local termo escolha i saida
    if ! proot-distro help 2>/dev/null | grep -qE '(^|[[:space:]])search([[:space:]]|$)'; then
        cabecalho_tela "🔎 Pesquisar distribuição" "Recurso não disponível nesta versão do proot-distro"
        caixa_simples "Atualização necessária" \
            "Esta instalação do proot-distro não oferece pesquisa no Docker Hub." \
            "Use uma das distribuições recomendadas pelo Manager ou atualize o pacote."
        pause
        return 1
    fi
    ui_preparar_prompt
    printf 'Pesquisar no Docker Hub (ex.: ubuntu, debian, alpine): '
    IFS= read -r termo
    termo="${termo//$'\r'/}"
    termo="${termo#${termo%%[![:space:]]*}}"
    termo="${termo%${termo##*[![:space:]]}}"
    [[ "$termo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { warn "Pesquisa inválida."; sleep 1; return 1; }

    cabecalho_tela "🔎 Pesquisando imagens" "Docker Hub • $termo"
    caixa_simples "Aguarde" "Consultando opções disponíveis..." "Nenhuma instalação será iniciada sem sua confirmação."
    ui_buffer_flush 2>/dev/null || true
    saida="$(proot-distro search -q -l 8 "$termo" 2>>"$LINUX_LOG")" || {
        error "Não foi possível pesquisar imagens agora."
        pause
        return 1
    }
    LINUX_SEARCH_RESULTS=()
    while IFS= read -r linha; do
        linux_imagem_referencia_valida "$linha" && LINUX_SEARCH_RESULTS+=("$linha")
    done <<< "$saida"
    [ ${#LINUX_SEARCH_RESULTS[@]} -gt 0 ] || { warn "Nenhuma imagem encontrada para '$termo'."; pause; return 1; }

    local -a opcoes=()
    for ((i=0; i<${#LINUX_SEARCH_RESULTS[@]}; i++)); do
        opcoes+=("$((i+1))|📦|${LINUX_SEARCH_RESULTS[$i]}|Imagem pública encontrada no Docker Hub")
    done
    while true; do
        menu_unificado "🔎 Resultados" "Selecione uma imagem para instalar" "[0] Voltar  •  [1–${#LINUX_SEARCH_RESULTS[@]}] Selecionar" "${opcoes[@]}"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        [ "$escolha" = "0" ] && return 1
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#LINUX_SEARCH_RESULTS[@]} ]; then
            LINUX_DISTRO_IMAGE="${LINUX_SEARCH_RESULTS[$((escolha-1))]}"
            return 0
        fi
        feedback_curto "Opção inválida."
    done
}

linux_instalar_imagem() {
    local imagem="$1" nome_amigavel="${2:-$1}" arch_proot alias rc=0
    linux_imagem_referencia_valida "$imagem" || { error "Referência de imagem inválida: $imagem"; pause; return 1; }
    LINUX_DISTRO_IMAGE="$imagem"
    linux_mostrar_compatibilidade_imagem "$imagem" "$nome_amigavel" || return 0
    arch_proot="$(linux_proot_arquitetura_dispositivo "$(linux_arquitetura)" 2>/dev/null || true)"
    alias="$(linux_nome_container_imagem "$imagem")"
    cabecalho_tela "⬇️ Instalar distribuição" "$nome_amigavel"
    caixa_simples "Distribuição selecionada" \
        "Imagem: $imagem" \
        "Nome local: $alias" \
        "Arquitetura da instalação: ${arch_proot:-automática}" \
        "Fonte: Docker/OCI via proot-distro" \
        "A instalação pode consumir vários GB após atualizações e programas."
    confirmar_acao "Instalar '$nome_amigavel' agora?" || return 0

    mkdir -p "$(dirname "$LINUX_LOG")"
    cabecalho_tela "⬇️ Instalando $nome_amigavel" "Não feche o Termux durante download e extração"
    caixa_simples "Etapa atual" \
        "Arquitetura: ${arch_proot:-automática}" \
        "Baixando e extraindo a imagem..." \
        "Ao terminar, o Manager fará um teste real de inicialização."
    ui_buffer_flush 2>/dev/null || true

    if [ -n "$arch_proot" ] && proot-distro install --help 2>/dev/null | grep -q -- '--architecture'; then
        proot-distro install "$imagem" --architecture "$arch_proot" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    elif [ -n "$arch_proot" ]; then
        DISTRO_ARCH="$arch_proot" proot-distro install "$imagem" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    else
        proot-distro install "$imagem" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    fi

    if [ "$rc" -ne 0 ]; then
        error "A instalação de '$imagem' falhou."
        printf 'Log: %s\n' "$(caminho_curto "$LINUX_LOG")"
        pause
        return 1
    fi

    linux_log "distribuição instalada: $imagem arch=${arch_proot:-auto}"
    linux_invalidar_cache_distro "$alias"
    cabecalho_tela "🩺 Validando distribuição" "$alias"
    caixa_simples "Teste pós-instalação" \
        "A imagem foi extraída." \
        "Agora o Manager verificará /bin/sh e os dados do sistema." \
        "Uma distro quebrada não será marcada silenciosamente como pronta."
    ui_buffer_flush 2>/dev/null || true
    linux_coletar_info_distro "$alias" true
    if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
        caixa_simples "✅ Instalação validada" \
            "Sistema: $LINUX_INFO_NAME" \
            "Arquitetura: $LINUX_INFO_ARCH" \
            "Tamanho atual: $LINUX_INFO_SIZE" \
            "Saúde: OK" \
            "Abra 'Meus Linux' para iniciar, atualizar ou configurar o desktop."
    else
        caixa_simples "⚠ Instalação precisa de atenção" \
            "A distribuição foi criada, mas /bin/sh não conseguiu iniciar." \
            "Arquitetura solicitada: ${arch_proot:-automática}" \
            "Arquitetura registrada: $LINUX_INFO_ARCH" \
            "Use 'Meus Linux' > '$alias' > Reparar / reinstalar." \
            "O Manager mostrará esta distro como 'Problema'."
        linux_log "saúde pós-instalação falhou: $alias imagem=$imagem arch=$arch_proot"
    fi
    pause
}

linux_instalar_distro() {
    linux_garantir_proot_distro || { pause; return 1; }
    linux_avaliar_aparelho
    local escolha
    while true; do
        menu_unificado "⬇️ INSTALAR DISTRIBUIÇÃO" "${LINUX_PROFILE_ICON} ${LINUX_PROFILE} • CPU $(linux_arquitetura) • $(linux_formatar_gb_kb "$LINUX_FREE_KB") livres" \
            "[0] Voltar  •  [1–7] Selecionar" \
            "1|🐧|Ubuntu 24.04|Boa base para desktops gráficos • imagem ubuntu:24.04" \
            "2|🐧|Debian 12|Estável e versátil para desktop gráfico" \
            "3|🪶|Alpine 3.23|Muito leve • melhor para terminal e servidores" \
            "4|🎩|Fedora 44|Sistema moderno • consumo maior" \
            "5|🦎|openSUSE Leap 15|Alternativa estável" \
            "6|🪨|Rocky Linux 10|Base corporativa • uso principalmente terminal" \
            "7|🔎|Pesquisar outra imagem|Pesquisar no Docker Hub e escolher por número"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_instalar_imagem "ubuntu:24.04" "Ubuntu 24.04"; return ;;
            2) linux_instalar_imagem "debian:12" "Debian 12"; return ;;
            3) linux_instalar_imagem "alpine:3.23" "Alpine 3.23"; return ;;
            4) linux_instalar_imagem "fedora:44" "Fedora 44"; return ;;
            5) linux_instalar_imagem "opensuse/leap:15" "openSUSE Leap 15"; return ;;
            6) linux_instalar_imagem "rockylinux/rockylinux:10" "Rocky Linux 10"; return ;;
            7)
                if linux_pesquisar_imagem; then
                    linux_instalar_imagem "$LINUX_DISTRO_IMAGE" "$LINUX_DISTRO_IMAGE"
                    return
                fi
                ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

linux_abrir_terminal_distro() {
    local alias="${1:-}" escolha
    linux_garantir_proot_distro || { pause; return 1; }
    if [ -n "$alias" ]; then
        LINUX_DISTRO_ALIAS="$alias"
    else
        linux_selecionar_instalada "⌨️ Iniciar Linux" "Escolha uma distribuição" || return 0
    fi

    while true; do
        linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" false
        if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
            break
        fi
        menu_unificado "⚠ Linux com problema" \
            "$LINUX_DISTRO_ALIAS • ${LINUX_DIAG_REASON:-falha ao iniciar}" \
            "[0] Voltar  •  [1–3] Selecionar" \
            "1|🔎|Ver diagnóstico|Causa e detalhes técnicos" \
            "2|🧪|Testar novamente|Refazer o teste sem cache" \
            "3|🩺|Reparar / reinstalar|Recriar esta distribuição"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_exibir_diagnostico_distro "$LINUX_DISTRO_ALIAS" false ;;
            2)
                linux_invalidar_cache_distro "$LINUX_DISTRO_ALIAS"
                linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" true
                if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
                    ok "Teste concluído: distribuição saudável."
                    sleep 1
                    break
                fi
                feedback_curto "Ainda há problema: ${LINUX_DIAG_REASON:-inicialização}."
                ;;
            3) linux_resetar_distro "$LINUX_DISTRO_ALIAS" ;;
            0) return 1 ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done

    cabecalho_tela "⌨️ Iniciar Linux" "Abrindo $LINUX_DISTRO_ALIAS"
    caixa_simples "Sessão Linux" \
        "Distribuição: $LINUX_INFO_NAME" \
        "Alias: $LINUX_DISTRO_ALIAS" \
        "Use exit para voltar ao Manager."
    ui_buffer_flush 2>/dev/null || true
    sleep 0.3
    linux_log "iniciando terminal: $LINUX_DISTRO_ALIAS"
    if ! proot-distro login "$LINUX_DISTRO_ALIAS"; then
        linux_invalidar_cache_distro "$LINUX_DISTRO_ALIAS"
        error "Não foi possível iniciar '$LINUX_DISTRO_ALIAS'."
        pause
    fi
}

linux_remover_distro() {
    local alias="${1:-}"
    linux_garantir_proot_distro || { pause; return 1; }
    if [ -n "$alias" ]; then LINUX_DISTRO_ALIAS="$alias"; else linux_selecionar_instalada "🗑️ Remover distribuição" "Selecione o Linux que será apagado" || return 0; fi
    linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" false
    cabecalho_tela "🗑️ Remover distribuição" "Exclusão permanente"
    caixa_simples "⚠ Atenção" \
        "Distribuição: $LINUX_INFO_NAME ($LINUX_DISTRO_ALIAS)" \
        "Tamanho atual: $LINUX_INFO_SIZE" \
        "Todos os arquivos que existirem somente dentro dela serão apagados." \
        "Use Criar backup antes se houver dados importantes."
    confirmar_acao "Remover '$LINUX_DISTRO_ALIAS' permanentemente?" "n" || return 0
    confirmar_acao "Confirma a exclusão definitiva?" "n" || return 0

    if proot-distro remove "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG"; then
        linux_log "distribuição removida: $LINUX_DISTRO_ALIAS"
        linux_invalidar_cache_distro "$LINUX_DISTRO_ALIAS"
        ok "Distribuição removida."
    else
        error "Falha ao remover a distribuição."
    fi
    pause
}

linux_resetar_distro() {
    local alias="${1:-}" imagem arch rc=0
    linux_garantir_proot_distro || { pause; return 1; }
    if [ -n "$alias" ]; then LINUX_DISTRO_ALIAS="$alias"; else linux_selecionar_instalada "🩺 Reparar / reinstalar" "Escolha a distribuição a ser recriada" || return 0; fi
    imagem="$(linux_manifest_campo "$LINUX_DISTRO_ALIAS" image_ref 2>/dev/null || true)"
    arch="$(linux_proot_arquitetura_dispositivo "$(linux_arquitetura)" 2>/dev/null || true)"
    linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" false
    cabecalho_tela "🩺 Reparar / reinstalar" "Recriar na arquitetura deste Termux"
    caixa_simples "⚠ Reinstalação destrutiva" \
        "Distribuição: $LINUX_INFO_NAME ($LINUX_DISTRO_ALIAS)" \
        "Imagem: ${imagem:-não registrada}" \
        "Arquitetura correta: ${arch:-automática}" \
        "Todos os dados internos da distribuição serão perdidos." \
        "Crie um backup antes se houver arquivos importantes."
    confirmar_acao "Reinstalar '$LINUX_DISTRO_ALIAS'?" "n" || return 0

    if [ -n "$imagem" ] && linux_imagem_referencia_valida "$imagem"; then
        caixa_simples "Correção de arquitetura" \
            "A distro será removida e recriada da imagem original." \
            "A arquitetura será definida explicitamente para evitar Exec format error."
        proot-distro remove "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
        if [ "$rc" -eq 0 ]; then
            if [ -n "$arch" ] && proot-distro install --help 2>/dev/null | grep -q -- '--architecture'; then
                proot-distro install "$imagem" --name "$LINUX_DISTRO_ALIAS" --architecture "$arch" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
            elif [ -n "$arch" ]; then
                DISTRO_ARCH="$arch" proot-distro install --override-alias "$LINUX_DISTRO_ALIAS" "$imagem" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
            else
                proot-distro install "$imagem" --name "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
            fi
        fi
    else
        proot-distro reset "$LINUX_DISTRO_ALIAS" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    fi

    linux_invalidar_cache_distro "$LINUX_DISTRO_ALIAS"
    if [ "$rc" -eq 0 ]; then
        linux_coletar_info_distro "$LINUX_DISTRO_ALIAS" true
        if [ "$LINUX_INFO_HEALTH" = "ok" ]; then
            linux_log "distribuição reparada: $LINUX_DISTRO_ALIAS arch=${arch:-auto}"
            ok "Distribuição reinstalada e validada."
        else
            error "A reinstalação terminou, mas a distro ainda falhou no teste de saúde."
        fi
    else
        error "Falha ao reinstalar a distribuição."
    fi
    pause
}

linux_atualizar_distro() {
    local alias="${1:-}" gerenciador script rc=0
    [ -n "$alias" ] || return 1
    linux_coletar_info_distro "$alias" true
    if [ "$LINUX_INFO_HEALTH" != "ok" ]; then
        cabecalho_tela "⚠ Não é possível atualizar" "$alias"
        caixa_simples "Distribuição com problema" \
            "Motivo: ${LINUX_DIAG_REASON:-falha ao iniciar}" \
            "Código: ${LINUX_DIAG_CODE:-UNKNOWN}" \
            "Use Diagnóstico ou Reparar antes de atualizar."
        pause
        return 1
    fi
    gerenciador="$LINUX_INFO_PM"
    case "$gerenciador" in
        apt) script='export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get -y upgrade' ;;
        pacman) script='pacman -Syu --noconfirm' ;;
        apk) script='apk update && apk upgrade' ;;
        dnf) script='dnf -y upgrade' ;;
        zypper) script='zypper --non-interactive refresh && zypper --non-interactive update' ;;
        *)
            cabecalho_tela "🔄 Atualizar Linux" "$alias"
            caixa_simples "Gerenciador não reconhecido" "Não encontrei um gerenciador de pacotes suportado nesta distribuição."
            pause
            return 1
            ;;
    esac
    cabecalho_tela "🔄 Atualizar Linux" "$LINUX_INFO_NAME"
    caixa_simples "Atualização do sistema" \
        "Gerenciador: $(linux_descrever_gerenciador_distro "$gerenciador")" \
        "Esta operação atualiza os pacotes dentro da distribuição." \
        "Ela não reinstala nem apaga seus arquivos."
    confirmar_acao "Atualizar '$alias' agora?" "s" || return 0
    ui_buffer_flush 2>/dev/null || true
    proot-distro login "$alias" -- /bin/sh -lc "$script" 2>&1 | tee -a "$LINUX_LOG" || rc=${PIPESTATUS[0]}
    linux_invalidar_cache_distro "$alias"
    if [ "$rc" -eq 0 ]; then ok "Sistema atualizado."; else error "A atualização terminou com erro."; fi
    pause
}

