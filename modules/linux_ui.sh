# Módulo: linux_ui.sh
# Menus e navegação do subsistema Linux no celular.

menu_linux_distro() {
    local alias="${1:-}" escolha
    [ -n "$alias" ] || return 1
    while true; do
        linux_coletar_info_distro "$alias" false
        menu_unificado "🐧 $LINUX_INFO_NAME" \
            "${LINUX_INFO_STATE_ICON} ${LINUX_INFO_STATE_LABEL} • ${LINUX_INFO_HEALTH_ICON} ${LINUX_INFO_HEALTH_LABEL} • $LINUX_INFO_SIZE" \
            "[0] Voltar  •  [1–9] Selecionar" \
            "1|⌨️|Iniciar terminal|Abrir no terminal" \
            "2|🖥️|Desktop / X11|Ambientes gráficos" \
            "3|🔄|Atualizar sistema|Atualizar pacotes" \
            "4|💾|Criar backup|Salvar em Downloads" \
            "5|🔎|Diagnóstico|Saúde e causa de falhas" \
            "6|ℹ️|Informações|Versão, arquitetura e tamanho" \
            "7|⏹️|Encerrar sessões|Ativas: $LINUX_INFO_SESSIONS" \
            "8|🩺|Reparar / reinstalar|Recriar a distro" \
            "9|🗑️|Remover distribuição|Excluir esta distro"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_abrir_terminal_distro "$alias" ;;
            2) linux_iniciar_desktop "$alias" ;;
            3) linux_atualizar_distro "$alias" ;;
            4) linux_backup_distro "$alias" ;;
            5) linux_exibir_diagnostico_distro "$alias" true ;;
            6) linux_exibir_info_distro "$alias" ;;
            7) linux_encerrar_sessoes_distro "$alias" ;;
            8) linux_resetar_distro "$alias" ;;
            9)
                linux_remover_distro "$alias"
                linux_coletar_instaladas || true
                printf '%s\n' "${LINUX_INSTALLED_DISTROS[@]}" | grep -Fxq "$alias" || return 0
                ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

linux_meus_linux() {
    local i escolha alias resumo estado saude tamanho arch desktops
    linux_garantir_proot_distro || { pause; return 1; }
    while true; do
        linux_coletar_instaladas || true
        if [ ${#LINUX_INSTALLED_DISTROS[@]} -eq 0 ]; then
            cabecalho_tela "🐧 Meus Linux" "Distribuições instaladas"
            caixa_simples "📭 Nenhuma distribuição instalada" \
                "Ainda não existe um Linux instalado neste aparelho." \
                "O Manager pode abrir a instalação agora."
            if confirmar_acao "Instalar uma distribuição agora?" "s"; then linux_instalar_distro; fi
            return 0
        fi

        local -a opcoes=()
        cabecalho_tela "🔎 Analisando distribuições" "Coletando tamanho, arquitetura e estado"
        printf '⏳ Verificando %d instalação(ões)...\n' "${#LINUX_INSTALLED_DISTROS[@]}"
        ui_buffer_flush 2>/dev/null || true
        for ((i=0; i<${#LINUX_INSTALLED_DISTROS[@]}; i++)); do
            alias="${LINUX_INSTALLED_DISTROS[$i]}"
            linux_coletar_info_distro "$alias" false
            resumo="${LINUX_INFO_STATE_ICON} ${LINUX_INFO_STATE_LABEL} • ${LINUX_INFO_HEALTH_ICON} ${LINUX_INFO_HEALTH_LABEL} • ${LINUX_INFO_SIZE} • ${LINUX_INFO_ARCH}"
            [ "$LINUX_INFO_DESKTOPS" != "nenhum" ] && resumo+=" • Desktop: $LINUX_INFO_DESKTOPS"
            opcoes+=("$((i+1))|🐧|$LINUX_INFO_NAME|$resumo")
        done
        menu_unificado "🐧 MEUS LINUX" "Escolha uma distribuição para administrar" \
            "[0] Voltar  •  [1–${#LINUX_INSTALLED_DISTROS[@]}] Abrir" "${opcoes[@]}"
        ler_opcao
        escolha="$RESPOSTA_MENU"
        [ "$escolha" = "0" ] && return 0
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le ${#LINUX_INSTALLED_DISTROS[@]} ]; then
            menu_linux_distro "${LINUX_INSTALLED_DISTROS[$((escolha-1))]}"
        else
            feedback_curto "Opção inválida."
        fi
    done
}

menu_linux_celular() {
    while true; do
        linux_avaliar_aparelho
        local proot_status="ausente" x11_status="ausente" instaladas=0
        command -v proot-distro >/dev/null 2>&1 && proot_status="pronto"
        linux_x11_companion_instalado && x11_status="pronto"
        if command -v proot-distro >/dev/null 2>&1; then
            linux_coletar_instaladas || true
            instaladas=${#LINUX_INSTALLED_DISTROS[@]}
        fi
        menu_unificado "🐧 LINUX NO CELULAR" "PRoot sem root • perfil ${LINUX_PROFILE}" \
            "[0] Voltar  •  [1–7] Selecionar" \
            "1|🐧|Meus Linux|$instaladas instalada(s) • administrar" \
            "2|⬇️|Instalar novo Linux|Escolher uma distribuição" \
            "3|♻️|Restaurar backup|Buscar em Downloads" \
            "4|🖥️|Termux:X11|Desktops e interface gráfica" \
            "5|📱|Compatibilidade|RAM, CPU e espaço" \
            "6|🩺|Ambiente PRoot|Diagnosticar e reparar" \
            "7|ℹ️|Status do Linux|PRoot: $proot_status • X11: $x11_status"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) linux_meus_linux ;;
            2) linux_instalar_distro ;;
            3) linux_restaurar_backup ;;
            4) menu_termux_x11 ;;
            5) linux_mostrar_perfil ;;
            6) menu_ambiente_proot ;;
            7)
                cabecalho_tela "ℹ️ Linux no celular" "Estado dos componentes"
                caixa_simples "Status" \
                    "Perfil: ${LINUX_PROFILE_ICON} ${LINUX_PROFILE}" \
                    "Distribuições instaladas: $instaladas" \
                    "proot-distro: $proot_status" \
                    "Termux:X11 companion: $x11_status" \
                    "Termux:X11 Android: $(linux_x11_apk_instalado && echo instalado || echo não detectado)" \
                    "Log: $(caminho_curto "$LINUX_LOG")"
                pause
                ;;
            0) return ;;
            *) warn "Opção inválida."; sleep 1 ;;
        esac
    done
}

