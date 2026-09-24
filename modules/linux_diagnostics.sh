# Módulo: linux_diagnostics.sh
# Diagnóstico de distribuições e do ambiente PRoot.
# Extraído de linux.sh para reduzir acoplamento e facilitar manutenção.

linux_diag_linha_unica() {
    printf '%s' "${1:-}" | tr '\r\n|' '   ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

linux_resolver_bin_sh() {
    local alias="${1:-}" root caminho alvo n=0
    LINUX_DIAG_ROOTFS=""
    LINUX_DIAG_SHELL_PATH=""
    LINUX_DIAG_SHELL_TARGET=""
    root="$(linux_container_rootfs "$alias" 2>/dev/null || true)"
    LINUX_DIAG_ROOTFS="$root"
    [ -n "$root" ] || return 1
    caminho="$root/bin/sh"
    LINUX_DIAG_SHELL_PATH="$caminho"
    [ -e "$caminho" ] || [ -L "$caminho" ] || return 2
    while [ -L "$caminho" ] && [ "$n" -lt 8 ]; do
        alvo="$(readlink "$caminho" 2>/dev/null || true)"
        [ -n "$alvo" ] || break
        if [[ "$alvo" = /* ]]; then
            caminho="$root$alvo"
        else
            caminho="$(dirname "$caminho")/$alvo"
        fi
        n=$((n + 1))
    done
    LINUX_DIAG_SHELL_TARGET="$caminho"
    [ -e "$caminho" ] || return 3
    return 0
}

linux_arquitetura_binario() {
    local arquivo="${1:-}" desc endian bytes b1 b2 machine
    [ -f "$arquivo" ] || return 1
    if command -v file >/dev/null 2>&1; then
        desc="$(file -Lb "$arquivo" 2>/dev/null || true)"
        case "$desc" in
            *aarch64*|*AArch64*|*ARM64*) printf 'aarch64\n'; return 0 ;;
            *x86-64*|*x86_64*) printf 'x86_64\n'; return 0 ;;
            *80386*|*i386*) printf 'i686\n'; return 0 ;;
            *RISC-V*|*riscv64*) printf 'riscv64\n'; return 0 ;;
            *ARM*) printf 'arm\n'; return 0 ;;
            *script*|*text*) printf 'script\n'; return 0 ;;
        esac
    fi
    # Fallback mínimo: lê e_machine diretamente do cabeçalho ELF.
    bytes="$(dd if="$arquivo" bs=1 skip=18 count=2 2>/dev/null | od -An -t u1 2>/dev/null || true)"
    read -r b1 b2 <<< "$bytes"
    [[ "${b1:-}" =~ ^[0-9]+$ ]] && [[ "${b2:-}" =~ ^[0-9]+$ ]] || return 1
    endian="$(dd if="$arquivo" bs=1 skip=5 count=1 2>/dev/null | od -An -t u1 2>/dev/null | tr -d ' ')"
    if [ "$endian" = "2" ]; then machine=$((b1 * 256 + b2)); else machine=$((b1 + b2 * 256)); fi
    case "$machine" in
        183) printf 'aarch64\n' ;;
        40) printf 'arm\n' ;;
        62) printf 'x86_64\n' ;;
        3) printf 'i686\n' ;;
        243) printf 'riscv64\n' ;;
        *) printf 'desconhecida\n' ;;
    esac
}

linux_loader_binario() {
    local arquivo="${1:-}" desc loader
    [ -f "$arquivo" ] || return 1
    command -v file >/dev/null 2>&1 || return 1
    desc="$(file -Lb "$arquivo" 2>/dev/null || true)"
    loader="$(printf '%s\n' "$desc" | sed -nE 's/.*interpreter ([^, ]+).*/\1/p' | head -n1)"
    [ -n "$loader" ] || return 1
    printf '%s\n' "$loader"
}

linux_qemu_disponivel_para() {
    case "${1:-}" in
        aarch64) command -v qemu-aarch64 >/dev/null 2>&1 || command -v qemu-aarch64-static >/dev/null 2>&1 ;;
        arm) command -v qemu-arm >/dev/null 2>&1 || command -v qemu-arm-static >/dev/null 2>&1 ;;
        x86_64) command -v qemu-x86_64 >/dev/null 2>&1 || command -v qemu-x86_64-static >/dev/null 2>&1 ;;
        i686) command -v qemu-i386 >/dev/null 2>&1 || command -v qemu-i386-static >/dev/null 2>&1 ;;
        riscv64) command -v qemu-riscv64 >/dev/null 2>&1 || command -v qemu-riscv64-static >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

linux_preparar_diagnostico_local() {
    local alias="${1:-}" rc=0 loader="" host manifest shell_arch="desconhecida"
    LINUX_DIAG_CODE=""
    LINUX_DIAG_REASON=""
    LINUX_DIAG_DETAIL=""
    LINUX_DIAG_ERROR=""
    LINUX_DIAG_HOST_ARCH="$(linux_proot_arquitetura_dispositivo "$(linux_arquitetura)" 2>/dev/null || linux_arquitetura)"
    LINUX_DIAG_MANIFEST_ARCH="$(linux_manifest_campo "$alias" arch 2>/dev/null || true)"
    LINUX_DIAG_SHELL_ARCH="desconhecida"
    LINUX_DIAG_LOADER=""
    LINUX_DIAG_LOADER_STATUS="não identificado"
    LINUX_DIAG_QEMU="não necessário"

    linux_resolver_bin_sh "$alias" || rc=$?
    case "$rc" in
        1)
            LINUX_DIAG_CODE="ROOTFS_MISSING"
            LINUX_DIAG_REASON="Rootfs ausente"
            LINUX_DIAG_DETAIL="A pasta principal da distribuição não foi encontrada."
            return 1
            ;;
        2)
            LINUX_DIAG_CODE="SHELL_MISSING"
            LINUX_DIAG_REASON="Shell ausente"
            LINUX_DIAG_DETAIL="O arquivo /bin/sh não existe dentro da distribuição."
            return 1
            ;;
        3)
            LINUX_DIAG_CODE="SHELL_TARGET_MISSING"
            LINUX_DIAG_REASON="Shell quebrado"
            LINUX_DIAG_DETAIL="O link /bin/sh aponta para um arquivo que não existe."
            return 1
            ;;
    esac

    shell_arch="$(linux_arquitetura_binario "$LINUX_DIAG_SHELL_TARGET" 2>/dev/null || printf 'desconhecida')"
    LINUX_DIAG_SHELL_ARCH="$shell_arch"
    loader="$(linux_loader_binario "$LINUX_DIAG_SHELL_TARGET" 2>/dev/null || true)"
    LINUX_DIAG_LOADER="$loader"
    if [ -n "$loader" ]; then
        if [ -e "$LINUX_DIAG_ROOTFS$loader" ]; then
            LINUX_DIAG_LOADER_STATUS="presente"
        else
            LINUX_DIAG_LOADER_STATUS="ausente"
            LINUX_DIAG_CODE="LOADER_MISSING"
            LINUX_DIAG_REASON="Loader ausente"
            LINUX_DIAG_DETAIL="O interpretador ELF '$loader' não existe no rootfs."
            return 1
        fi
    fi

    host="$LINUX_DIAG_HOST_ARCH"
    manifest="$LINUX_DIAG_MANIFEST_ARCH"
    if [ -n "$manifest" ] && [ "$shell_arch" != "desconhecida" ] && [ "$shell_arch" != "script" ] && [ "$manifest" != "$shell_arch" ]; then
        LINUX_DIAG_CODE="ARCH_MISMATCH"
        LINUX_DIAG_REASON="Arquitetura divergente"
        LINUX_DIAG_DETAIL="Manifesto: $manifest; /bin/sh: $shell_arch."
        return 1
    fi
    if [ "$shell_arch" != "desconhecida" ] && [ "$shell_arch" != "script" ] && [ -n "$host" ] && [ "$shell_arch" != "$host" ]; then
        if linux_qemu_disponivel_para "$shell_arch"; then
            LINUX_DIAG_QEMU="disponível"
        else
            LINUX_DIAG_QEMU="não detectado"
        fi
    fi
    return 0
}

linux_traduzir_erro_proot() {
    local erro="${1:-}" linha saida=""
    [ -n "$erro" ] || { printf 'Nenhum erro técnico registrado.
'; return 0; }

    [[ "$erro" == *"Exec format error"* ]] && saida+="• O PRoot recusou o formato do executável inicial.\n"
    [[ "$erro" == *"script but its interpreter"* ]] && saida+="• O interpretador necessário ao script não foi encontrado.\n"
    [[ "$erro" == *"ELF but its interpreter"* ]] && saida+="• O loader/interpretador ELF necessário ao binário pode estar ausente.\n"
    [[ "$erro" == *"foreign binary but qemu was not specified"* ]] && saida+="• O PRoot considera possível uma arquitetura estrangeira sem QEMU configurado.\n"
    [[ "$erro" == *"qemu does not work correctly"* ]] && saida+="• Se QEMU estiver sendo usado, ele pode não estar funcionando corretamente.\n"
    [[ "$erro" == *"loader was not found"* ]] && saida+="• O loader do sistema pode estar ausente ou não funcionar dentro do rootfs.\n"
    [[ "$erro" == *"can't chmod"* && "$erro" == *"/tmp/proot-"* ]] && saida+="• O PRoot falhou ao ajustar um arquivo temporário em /tmp.\n"
    [[ "$erro" == *"can't sanitize binding"* && "$erro" == *"/proc/self/fd/"* ]] && saida+="• Há um aviso de redirecionamento de entrada/saída; normalmente ele não é a causa principal.\n"
    [[ "$erro" == *"Permission denied"* ]] && saida+="• Uma permissão necessária foi recusada.\n"
    [[ "$erro" == *"No such file or directory"* ]] && saida+="• Um arquivo ou caminho necessário não foi encontrado.\n"

    if [ -z "$saida" ]; then
        saida="• O PRoot retornou uma falha que ainda não possui tradução específica no Manager.\n"
    fi
    printf '%b' "$saida"
}

linux_orientacao_diagnostico() {
    local codigo="${1:-${LINUX_DIAG_CODE:-UNKNOWN}}"
    case "$codigo" in
        PROOT_ENV_FAILURE)
            printf '%s
' "Atualize proot/proot-distro e teste novamente. Se várias distros falham igual, o problema tende a estar no ambiente PRoot, não em cada Linux."
            ;;
        ARCH_MISMATCH|EXEC_FORMAT)
            printf '%s
' "Confirme a ABI do Termux e reinstale a distro usando essa arquitetura. Não escolha ARM64 apenas porque a CPU é ARMv8."
            ;;
        QEMU_REQUIRED)
            printf '%s
' "Prefira uma imagem nativa da arquitetura do Termux. Emulação exige QEMU configurado corretamente."
            ;;
        LOADER_MISSING|SHELL_MISSING|SHELL_TARGET_MISSING|ROOTFS_MISSING)
            printf '%s
' "O rootfs parece incompleto. Use Reparar/reinstalar e teste a saúde novamente."
            ;;
        PERMISSION)
            printf '%s
' "Revise permissões e armazenamento do Termux, depois execute o teste novamente."
            ;;
        TIMEOUT)
            printf '%s
' "Feche tarefas pesadas, aguarde alguns segundos e repita o teste."
            ;;
        *)
            printf '%s
' "Use Testar novamente e exporte o log se o erro persistir."
            ;;
    esac
}

linux_testar_proot_host() {
    local out rc=0 host_shell
    LINUX_PROOT_HOST_ERROR=""
    command -v proot >/dev/null 2>&1 || { LINUX_PROOT_HOST_ERROR="Comando proot não encontrado."; return 1; }
    # Usa o shell nativo do próprio Termux. /system/bin/sh pode ter ABI diferente
    # em aparelhos cujo hardware é ARM64, mas o Termux está rodando em 32 bits.
    # Nesse caso, testar /system/bin/sh geraria um falso diagnóstico do PRoot.
    host_shell="${PREFIX:-}/bin/sh"
    [ -x "$host_shell" ] || host_shell="$(command -v sh 2>/dev/null || true)"
    [ -n "$host_shell" ] || { LINUX_PROOT_HOST_ERROR="Shell do Termux não encontrado."; return 1; }
    if command -v timeout >/dev/null 2>&1; then
        out="$(timeout 8 proot "$host_shell" -c 'printf __TM_PROOT_HOST_OK__' 2>&1)" || rc=$?
    else
        out="$(proot "$host_shell" -c 'printf __TM_PROOT_HOST_OK__' 2>&1)" || rc=$?
    fi
    if [ "$rc" -eq 0 ] && [[ "$out" == *"__TM_PROOT_HOST_OK__"* ]]; then
        return 0
    fi
    LINUX_PROOT_HOST_ERROR="$(printf '%s' "$out" | tr '\r\n' '  ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-600)"
    return 1
}


linux_pacote_versao() {
    local pacote="${1:-}"
    [ -n "$pacote" ] || return 1
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Version}' "$pacote" 2>/dev/null || printf 'não instalado'
    else
        printf 'indisponível'
    fi
}

linux_proot_tmp_dir() {
    if [ -n "${PREFIX:-}" ]; then
        printf '%s/tmp\n' "$PREFIX"
    elif [ -n "${TMPDIR:-}" ]; then
        printf '%s\n' "$TMPDIR"
    else
        printf '/tmp\n'
    fi
}

linux_testar_tmp_proot() {
    local dir arquivo
    LINUX_PROOT_TMP_ERROR=""
    dir="$(linux_proot_tmp_dir)"
    mkdir -p "$dir" 2>/dev/null || {
        LINUX_PROOT_TMP_ERROR="Não foi possível criar $dir."
        return 1
    }
    [ -w "$dir" ] || {
        LINUX_PROOT_TMP_ERROR="$dir não permite gravação."
        return 1
    }
    arquivo="$(mktemp "$dir/manager-proot-test.XXXXXX" 2>/dev/null || true)"
    [ -n "$arquivo" ] && [ -f "$arquivo" ] || {
        LINUX_PROOT_TMP_ERROR="Não foi possível criar arquivo temporário em $dir."
        return 1
    }
    printf 'manager-proot-temp-test\n' > "$arquivo" 2>/dev/null || {
        rm -f "$arquivo" 2>/dev/null || true
        LINUX_PROOT_TMP_ERROR="Falha ao gravar arquivo temporário."
        return 1
    }
    chmod 700 "$arquivo" 2>/dev/null || {
        rm -f "$arquivo" 2>/dev/null || true
        LINUX_PROOT_TMP_ERROR="Falha ao aplicar chmod no arquivo temporário."
        return 1
    }
    rm -f "$arquivo" 2>/dev/null || true
    return 0
}

linux_diagnosticar_ambiente_proot() {
    local host_ok="falhou" tmp_ok="falhou" cmd_proot="ausente" cmd_pd="ausente"
    LINUX_PROOT_ENV_PROOT_VERSION="$(linux_pacote_versao proot)"
    LINUX_PROOT_ENV_DISTRO_VERSION="$(linux_pacote_versao proot-distro)"
    LINUX_PROOT_ENV_TMP="$(linux_proot_tmp_dir)"
    LINUX_PROOT_ENV_HOST_ERROR=""
    LINUX_PROOT_ENV_TMP_ERROR=""
    command -v proot >/dev/null 2>&1 && cmd_proot="OK"
    command -v proot-distro >/dev/null 2>&1 && cmd_pd="OK"
    if linux_testar_tmp_proot; then
        tmp_ok="OK"
    else
        LINUX_PROOT_ENV_TMP_ERROR="${LINUX_PROOT_TMP_ERROR:-falha desconhecida}"
    fi
    if linux_testar_proot_host; then
        host_ok="OK"
    else
        LINUX_PROOT_ENV_HOST_ERROR="${LINUX_PROOT_HOST_ERROR:-falha desconhecida}"
    fi
    LINUX_PROOT_ENV_COMMANDS="$cmd_proot / $cmd_pd"
    LINUX_PROOT_ENV_TMP_STATUS="$tmp_ok"
    LINUX_PROOT_ENV_HOST_STATUS="$host_ok"
    if [ "$cmd_proot" = "OK" ] && [ "$cmd_pd" = "OK" ] && [ "$tmp_ok" = "OK" ] && [ "$host_ok" = "OK" ]; then
        LINUX_PROOT_ENV_STATUS="OK"
        return 0
    fi
    LINUX_PROOT_ENV_STATUS="PROBLEMA"
    return 1
}

linux_mostrar_diagnostico_proot() {
    linux_diagnosticar_ambiente_proot || true
    linux_coletar_instaladas >/dev/null 2>&1 || true
    cabecalho_tela "🩺 Ambiente PRoot" "Diagnóstico do motor Linux"
    caixa_simples_wrap "Componentes"         "Comandos proot / proot-distro: ${LINUX_PROOT_ENV_COMMANDS:-?}"         "proot: ${LINUX_PROOT_ENV_PROOT_VERSION:-?}"         "proot-distro: ${LINUX_PROOT_ENV_DISTRO_VERSION:-?}"         "Distros preservadas: ${#LINUX_INSTALLED_DISTROS[@]}"
    caixa_simples_wrap "Testes"         "Temporários: ${LINUX_PROOT_ENV_TMP_STATUS:-?} • $(caminho_curto "${LINUX_PROOT_ENV_TMP:-$(linux_proot_tmp_dir)}")"         "PRoot básico: ${LINUX_PROOT_ENV_HOST_STATUS:-?}"
    if [ -n "${LINUX_PROOT_ENV_TMP_ERROR:-}" ] || [ -n "${LINUX_PROOT_ENV_HOST_ERROR:-}" ]; then
        caixa_simples_wrap "Problema encontrado"             "${LINUX_PROOT_ENV_TMP_ERROR:-}"             "${LINUX_PROOT_ENV_HOST_ERROR:-}"
    else
        caixa_simples "Resultado" "✅ Ambiente PRoot básico funcionando."
    fi
    rodape_atalhos "[0] Voltar  •  [1] Reparar ambiente  •  [2] Testar novamente"
    ui_buffer_flush
}

linux_invalidar_todos_cache_saude() {
    rm -f "$LINUX_STATE_DIR"/info-cache/*.health 2>/dev/null || true
}

linux_reparar_ambiente_proot() {
    local tmpdir antes depois rc=0
    linux_coletar_instaladas >/dev/null 2>&1 || true
    antes=${#LINUX_INSTALLED_DISTROS[@]}
    cabecalho_tela "🛠️ Reparar PRoot" "Sem apagar distribuições"
    caixa_simples_wrap "O que será feito"         "Verificar a pasta temporária do Termux."         "Reinstalar somente proot e proot-distro."         "Limpar o cache de saúde do Manager e testar novamente."         "As $antes distro(s) instalada(s) não serão removidas."
    confirmar_acao "Continuar com o reparo do ambiente PRoot?" "s" || return 0

    tmpdir="$(linux_proot_tmp_dir)"
    mkdir -p "$tmpdir" 2>>"$LINUX_LOG" || rc=1
    chmod u+rwx "$tmpdir" 2>>"$LINUX_LOG" || rc=1
    # Remove apenas temporários criados pelos testes do próprio Manager.
    rm -f "$tmpdir"/manager-proot-test.* "$tmpdir"/tm-linux-health-* 2>/dev/null || true

    if [ "$rc" -ne 0 ]; then
        cabecalho_tela "🛠️ Reparar PRoot" "Falha antes da reinstalação"
        caixa_simples_wrap "Pasta temporária"             "Não foi possível preparar $(caminho_curto "$tmpdir")."             "O Manager não alterou as distribuições instaladas."
        pause
        return 1
    fi

    if declare -F executar_pkg_monitorado >/dev/null 2>&1; then
        if ! executar_pkg_monitorado "Reparando ambiente PRoot" 15 92             "Reinstalando componentes..." "proot e proot-distro" --             install -y --reinstall proot proot-distro; then
            cabecalho_tela "🛠️ Reparar PRoot" "Reinstalação não concluída"
            caixa_simples_wrap "Falha no pkg"                 "Não foi possível reinstalar proot/proot-distro."                 "As distribuições continuam preservadas."
            pause
            return 1
        fi
    else
        if ! pkg install -y --reinstall proot proot-distro >>"$LINUX_LOG" 2>&1; then
            cabecalho_tela "🛠️ Reparar PRoot" "Reinstalação não concluída"
            caixa_simples "Falha no pkg" "As distribuições continuam preservadas."
            pause
            return 1
        fi
    fi

    linux_invalidar_todos_cache_saude
    linux_coletar_instaladas >/dev/null 2>&1 || true
    depois=${#LINUX_INSTALLED_DISTROS[@]}
    linux_diagnosticar_ambiente_proot || true
    linux_log "reparo do ambiente PRoot concluído: status=${LINUX_PROOT_ENV_STATUS:-?} distros=$antes->$depois"
    cabecalho_tela "✅ Reparo do PRoot concluído" "Distribuições preservadas: $depois"
    caixa_simples_wrap "Resultado"         "PRoot básico: ${LINUX_PROOT_ENV_HOST_STATUS:-?}"         "Temporários: ${LINUX_PROOT_ENV_TMP_STATUS:-?}"         "proot: ${LINUX_PROOT_ENV_PROOT_VERSION:-?}"         "proot-distro: ${LINUX_PROOT_ENV_DISTRO_VERSION:-?}"
    if [ "${LINUX_PROOT_ENV_STATUS:-PROBLEMA}" != "OK" ]; then
        caixa_simples_wrap "Ainda há problema"             "O reparo não resolveu o teste básico do PRoot."             "Use o diagnóstico e exporte o log antes de reinstalar distros."
    else
        caixa_simples_wrap "Próximo teste"             "Abra Meus Linux e use Testar novamente na distro com problema."
    fi
    pause
}

menu_ambiente_proot() {
    local escolha
    while true; do
        linux_mostrar_diagnostico_proot
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_reparar_ambiente_proot ;;
            2) : ;;
            0|"") tela_limpar; return 0 ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}

linux_classificar_falha_saude() {
    local rc="${1:-1}" erro="${2:-}" host="${LINUX_DIAG_HOST_ARCH:-}" guest="${LINUX_DIAG_SHELL_ARCH:-}"
    # Diagnósticos estruturais encontrados antes da execução têm prioridade.
    if [ -n "${LINUX_DIAG_CODE:-}" ]; then
        return 0
    fi
    if [ "$rc" = "124" ]; then
        LINUX_DIAG_CODE="TIMEOUT"
        LINUX_DIAG_REASON="Inicialização demorou"
        LINUX_DIAG_DETAIL="O teste não respondeu dentro do limite de segurança."
    elif [[ "$erro" == *"Exec format error"* ]]; then
        # A mensagem do PRoot lista QEMU entre causas possíveis mesmo quando
        # ele não é a causa real. Só marcamos QEMU quando há arquitetura
        # estrangeira confirmada; caso contrário usamos o diagnóstico neutro.
        if [ -n "$guest" ] && [ "$guest" != "desconhecida" ] && [ "$guest" != "script" ] && \
           [ -n "$host" ] && [ "$guest" != "$host" ]; then
            LINUX_DIAG_CODE="QEMU_REQUIRED"
            LINUX_DIAG_REASON="Emulação necessária"
            LINUX_DIAG_DETAIL="Host: $host; /bin/sh: $guest; execução nativa incompatível."
        else
            if [ -n "$guest" ] && [ "$guest" != "desconhecida" ] && [ -n "$host" ] && [ "$guest" = "$host" ]; then
                LINUX_DIAG_CODE="PROOT_ENV_FAILURE"
                LINUX_DIAG_REASON="Falha do ambiente PRoot"
                LINUX_DIAG_DETAIL="A arquitetura da distro coincide com o Termux, mas o PRoot não conseguiu executar /bin/sh."
            else
                LINUX_DIAG_CODE="EXEC_FORMAT"
                LINUX_DIAG_REASON="Formato incompatível"
                if [ -n "$guest" ] && [ "$guest" != "desconhecida" ]; then
                    LINUX_DIAG_DETAIL="Host: ${host:-desconhecido}; /bin/sh: $guest."
                else
                    LINUX_DIAG_DETAIL="O Android/PRoot recusou o formato do /bin/sh desta distro."
                fi
            fi
        fi
    elif [[ "$erro" == *"qemu was not specified"* ]] && [ -n "$guest" ] && [ -n "$host" ] && [ "$guest" != "$host" ]; then
        LINUX_DIAG_CODE="QEMU_REQUIRED"
        LINUX_DIAG_REASON="Emulação necessária"
        LINUX_DIAG_DETAIL="A arquitetura da distro é diferente da arquitetura do Termux."
    elif [[ "$erro" == *"Permission denied"* ]]; then
        LINUX_DIAG_CODE="PERMISSION"
        LINUX_DIAG_REASON="Permissão inválida"
        LINUX_DIAG_DETAIL="O /bin/sh existe, mas não pôde ser executado."
    elif [[ "$erro" == *"No such file or directory"* ]] && [[ "$erro" == *"interpreter"* ]]; then
        LINUX_DIAG_CODE="LOADER_MISSING"
        LINUX_DIAG_REASON="Loader ausente"
        LINUX_DIAG_DETAIL="O interpretador dinâmico necessário ao binário não foi encontrado."
    elif [[ "$erro" == *"can't chmod"* && "$erro" == *"/tmp/proot-"* ]]; then
        LINUX_DIAG_CODE="PROOT_ENV_FAILURE"
        LINUX_DIAG_REASON="Falha do ambiente PRoot"
        LINUX_DIAG_DETAIL="O PRoot falhou ao criar ou ajustar arquivos temporários antes de iniciar a distro."
    elif [[ "$erro" == *"No such file or directory"* ]]; then
        LINUX_DIAG_CODE="FILE_MISSING"
        LINUX_DIAG_REASON="Arquivo ausente"
        LINUX_DIAG_DETAIL="Um arquivo necessário para iniciar a distribuição não foi encontrado."
    else
        if ! linux_testar_proot_host; then
            LINUX_DIAG_CODE="PROOT_ENV_FAILURE"
            LINUX_DIAG_REASON="Falha do ambiente PRoot"
            LINUX_DIAG_DETAIL="O teste básico do PRoot também falhou fora da distro; o ambiente do Termux precisa ser verificado."
        else
            LINUX_DIAG_CODE="PROOT_FAILURE"
            LINUX_DIAG_REASON="Falha no PRoot"
            LINUX_DIAG_DETAIL="O PRoot funciona no Termux, mas o proot-distro falhou ao iniciar esta distribuição."
        fi
    fi
}

linux_salvar_cache_saude() {
    local cache="${1:-}" agora="${2:-0}" status="${3:-unknown}"
    mkdir -p "$(dirname "$cache")" 2>/dev/null || true
    {
        printf '%s|%s|%s\n' "$agora" "$status" "$(linux_diag_linha_unica "${LINUX_DIAG_CODE:-}")"
        linux_diag_linha_unica "${LINUX_DIAG_REASON:-}"; printf '\n'
        linux_diag_linha_unica "${LINUX_DIAG_DETAIL:-}"; printf '\n'
        linux_diag_linha_unica "${LINUX_DIAG_ERROR:-}"; printf '\n'
    } > "$cache" 2>/dev/null || true
}

linux_carregar_cache_saude() {
    local cache="${1:-}" agora="${2:-0}" first salvo_ts salvo_status salvo_code
    [ -f "$cache" ] || return 1
    first="$(sed -n '1p' "$cache" 2>/dev/null || true)"
    IFS='|' read -r salvo_ts salvo_status salvo_code <<< "$first"
    if ! [[ "$agora" =~ ^[0-9]+$ ]] || ! [[ "${salvo_ts:-}" =~ ^[0-9]+$ ]] || \
       [ $((agora - salvo_ts)) -lt 0 ] || [ $((agora - salvo_ts)) -ge "$LINUX_INFO_CACHE_TTL" ]; then
        return 1
    fi
    # Caches antigos ou genéricos são refeitos para aproveitar o diagnóstico
    # de ambiente PRoot e a interpretação de arquitetura desta versão.
    if [ "${salvo_status:-}" = "problem" ] && { [ -z "${salvo_code:-}" ] || [ "$salvo_code" = "PROOT_FAILURE" ] || [ "$salvo_code" = "EXEC_FORMAT" ]; }; then
        return 1
    fi
    LINUX_INFO_HEALTH="${salvo_status:-unknown}"
    LINUX_DIAG_CODE="${salvo_code:-}"
    LINUX_DIAG_REASON="$(sed -n '2p' "$cache" 2>/dev/null || true)"
    LINUX_DIAG_DETAIL="$(sed -n '3p' "$cache" 2>/dev/null || true)"
    LINUX_DIAG_ERROR="$(sed -n '4p' "$cache" 2>/dev/null || true)"
    LINUX_INFO_HEALTH_ERROR="$LINUX_DIAG_ERROR"
    return 0
}

linux_testar_saude_distro() {
    local alias="${1:-}" forcar="${2:-false}" cache agora rc=0 saida="" errfile erro=""
    cache="$(linux_cache_info_arquivo "$alias")"
    agora="$(date +%s 2>/dev/null || printf '0')"

    # Coleta metadados locais sempre: é barato e permite explicar o estado mesmo com cache.
    linux_preparar_diagnostico_local "$alias" || true
    if [ "$forcar" != "true" ] && linux_carregar_cache_saude "$cache" "$agora"; then
        return 0
    fi

    errfile="${TMPDIR:-/tmp}/tm-linux-health-$$.log"
    : > "$errfile" 2>/dev/null || true
    if command -v timeout >/dev/null 2>&1 && [ "$(type -t proot-distro 2>/dev/null || true)" = "file" ]; then
        saida="$(timeout 8 proot-distro login "$alias" -- /bin/sh -lc 'printf __TM_HEALTH_OK__' 2>"$errfile")" || rc=$?
    else
        saida="$(proot-distro login "$alias" -- /bin/sh -lc 'printf __TM_HEALTH_OK__' 2>"$errfile")" || rc=$?
    fi
    erro="$(tail -n 14 "$errfile" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//' | cut -c1-1200)"

    if [ "$rc" -eq 0 ] && [[ "$saida" == *"__TM_HEALTH_OK__"* ]]; then
        LINUX_INFO_HEALTH="ok"
        LINUX_DIAG_CODE="OK"
        LINUX_DIAG_REASON="Inicialização normal"
        LINUX_DIAG_DETAIL="/bin/sh respondeu ao teste do Manager."
        LINUX_DIAG_ERROR=""
        LINUX_INFO_HEALTH_ERROR=""
    else
        LINUX_INFO_HEALTH="problem"
        # Se o preflight encontrou algo estrutural, mantém a causa. Caso contrário classifica stderr/rc.
        linux_classificar_falha_saude "$rc" "$erro"
        LINUX_DIAG_ERROR="$erro"
        LINUX_INFO_HEALTH_ERROR="$erro"
    fi
    linux_salvar_cache_saude "$cache" "$agora" "$LINUX_INFO_HEALTH"
    rm -f "$errfile" 2>/dev/null || true
}

linux_rotulo_curto_saude() {
    case "${LINUX_DIAG_CODE:-}" in
        OK) printf 'OK' ;;
        ARCH_MISMATCH|EXEC_FORMAT) printf 'Arquitetura' ;;
        QEMU_REQUIRED) printf 'QEMU' ;;
        ROOTFS_MISSING) printf 'Rootfs ausente' ;;
        SHELL_MISSING|SHELL_TARGET_MISSING) printf 'Shell ausente' ;;
        LOADER_MISSING) printf 'Loader ausente' ;;
        TIMEOUT) printf 'Timeout' ;;
        PROOT_ENV_FAILURE) printf 'Ambiente PRoot' ;;
        PERMISSION) printf 'Permissão' ;;
        FILE_MISSING) printf 'Arquivo ausente' ;;
        *) printf 'Inicialização' ;;
    esac
}

linux_limpar_ansi_log() {
    sed -E $'s/\x1B\[[0-9;?]*[ -\/]*[@-~]//g'
}

linux_redigir_log_exportado() {
    # Reutiliza a sanitização da Central de Diagnóstico quando disponível.
    # O fallback cobre os formatos mais comuns caso linux.sh seja carregado
    # isoladamente, antes de diagnostics.sh.
    if declare -F redigir_segredos >/dev/null 2>&1; then
        redigir_segredos
    else
        sed -E \
            -e 's/((API_KEY|TOKEN|PASSWORD|PASS|SECRET)[[:space:]]*[:=][[:space:]]*)[^[:space:]"]+/\1[REMOVIDO]/Ig' \
            -e 's/(Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+)[A-Za-z0-9._~+\/-]+=*/\1[REMOVIDO]/Ig'
    fi
}

linux_exportar_diagnostico_distro() {
    local alias="${1:-}" pasta carimbo slug destino shell_exib loader_exib erro_pt orientacao proot_status
    [ -n "$alias" ] || return 1
    linux_coletar_info_distro "$alias" false
    linux_coletar_contexto_arquitetura
    erro_pt="$(linux_traduzir_erro_proot "${LINUX_INFO_HEALTH_ERROR:-}")"
    orientacao="$(linux_orientacao_diagnostico "${LINUX_DIAG_CODE:-UNKNOWN}")"
    if linux_testar_proot_host; then
        proot_status="OK"
    else
        proot_status="FALHOU"
    fi

    if ! resolver_downloads_dir >/dev/null 2>&1; then
        cabecalho_tela "📥 Exportar diagnóstico" "$LINUX_INFO_NAME"
        caixa_simples_wrap "Downloads indisponível" \
            "Não foi possível acessar a pasta Downloads." \
            "Execute termux-setup-storage e tente novamente."
        pause
        return 1
    fi
    pasta="${DOWNLOADS_DIR:-$HOME/storage/downloads}"
    mkdir -p "$pasta" 2>/dev/null || true
    [ -d "$pasta" ] || {
        cabecalho_tela "📥 Exportar diagnóstico" "$LINUX_INFO_NAME"
        caixa_simples_wrap "Destino indisponível" "A pasta Downloads não está acessível."
        pause
        return 1
    }

    carimbo="$(date '+%Y%m%d-%H%M%S')"
    if declare -F sanitizar_nome_arquivo >/dev/null 2>&1; then
        slug="$(sanitizar_nome_arquivo "$alias")"
    else
        slug="$(printf '%s' "$alias" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g; s/-+/-/g')"
    fi
    [ -n "$slug" ] || slug="linux"
    destino="$pasta/linux-diagnostico-${slug}-${carimbo}.log"
    shell_exib="${LINUX_DIAG_SHELL_TARGET:-não localizado}"
    [ -n "${LINUX_DIAG_ROOTFS:-}" ] && shell_exib="${shell_exib#"$LINUX_DIAG_ROOTFS"}"
    loader_exib="${LINUX_DIAG_LOADER:-não identificado}"

    {
        printf 'Manager.sh — Diagnóstico Linux\n'
        printf 'Gerado em: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'Distribuição: %s\n' "$LINUX_INFO_NAME"
        printf 'Alias: %s\n\n' "$alias"

        printf '[Resumo em português]\n'
        printf 'Saúde: %s %s\n' "$LINUX_INFO_HEALTH_ICON" "$LINUX_INFO_HEALTH_LABEL"
        printf 'Código: %s\n' "${LINUX_DIAG_CODE:-UNKNOWN}"
        printf 'Motivo: %s\n' "${LINUX_DIAG_REASON:-não identificado}"
        printf 'Detalhe: %s\n' "${LINUX_DIAG_DETAIL:-sem detalhe adicional}"
        printf 'Teste básico do PRoot: %s\n\n' "$proot_status"

        printf '[Interpretação do erro em português]\n%s\n' "$erro_pt"
        printf '[O que fazer]\n%s\n\n' "$orientacao"

        printf '[Arquitetura interpretada]\n'
        printf 'CPU: %s\n' "${LINUX_ARCH_CPU_GEN:-não identificada}"
        printf 'Kernel: %s\n' "${LINUX_ARCH_KERNEL:-desconhecido}"
        printf 'Android ABI principal: %s\n' "${LINUX_ARCH_ANDROID_ABI:-não informada}"
        printf 'Android ABIs: %s\n' "${LINUX_ARCH_ANDROID_ABILIST:-não informadas}"
        printf 'Android ABIs 32-bit: %s\n' "${LINUX_ARCH_ANDROID_ABILIST32:-não informadas}"
        printf 'Android ABIs 64-bit: %s\n' "${LINUX_ARCH_ANDROID_ABILIST64:-não informadas}"
        printf 'Termux: %s (%s bits)\n' "${LINUX_ARCH_TERMUX:-desconhecida}" "${LINUX_ARCH_BITS:-?}"
        printf 'Distro (manifesto): %s\n' "${LINUX_DIAG_MANIFEST_ARCH:-não informado}"
        printf '/bin/sh: %s\n' "${LINUX_DIAG_SHELL_ARCH:-desconhecida}"
        printf 'Interpretação: %s\n' "${LINUX_ARCH_INTERPRETATION:-não disponível}"
        printf 'QEMU: %s\n\n' "${LINUX_DIAG_QEMU:-não verificado}"

        printf '[Arquivos]\n'
        printf 'Shell: %s\n' "$shell_exib"
        printf 'Loader: %s\n' "$loader_exib"
        printf 'Loader no rootfs: %s\n\n' "${LINUX_DIAG_LOADER_STATUS:-não verificado}"

        printf '[Erro original do PRoot — preservado]\n%s\n\n' "${LINUX_INFO_HEALTH_ERROR:-sem registro}"
        [ -n "${LINUX_PROOT_HOST_ERROR:-}" ] && printf '[Erro do teste básico do PRoot]\n%s\n\n' "$LINUX_PROOT_HOST_ERROR"

        printf '[Log recente do Linux]\n'
        if [ -f "$LINUX_LOG" ]; then
            tail -n 160 "$LINUX_LOG" | linux_limpar_ansi_log
        else
            printf 'Arquivo de log não encontrado: %s\n' "$LINUX_LOG"
        fi
    } | linux_redigir_log_exportado > "$destino"

    cabecalho_tela "📥 Exportar diagnóstico" "$LINUX_INFO_NAME"
    caixa_simples_wrap "Arquivo salvo" \
        "Diagnóstico em português salvo em Downloads." \
        "O erro técnico original também foi preservado." \
        "Arquivo: $(basename "$destino")"
    pause
}

linux_exibir_diagnostico_distro() {
    local alias="${1:-}" forcar="${2:-false}" shell_exib loader_exib escolha erro_pt orientacao proot_status
    [ -n "$alias" ] || return 1
    while true; do
        linux_coletar_info_distro "$alias" "$forcar"
        forcar=false
        linux_coletar_contexto_arquitetura
        shell_exib="${LINUX_DIAG_SHELL_TARGET:-não localizado}"
        [ -n "${LINUX_DIAG_ROOTFS:-}" ] && shell_exib="${shell_exib#"$LINUX_DIAG_ROOTFS"}"
        loader_exib="${LINUX_DIAG_LOADER:-não identificado}"
        erro_pt="$(linux_traduzir_erro_proot "${LINUX_INFO_HEALTH_ERROR:-}")"
        orientacao="$(linux_orientacao_diagnostico "${LINUX_DIAG_CODE:-UNKNOWN}")"
        if linux_testar_proot_host; then proot_status="OK"; else proot_status="falhou"; fi

        cabecalho_tela "🔎 Diagnóstico Linux" "$LINUX_INFO_NAME"
        caixa_simples_wrap "Resultado" \
            "Saúde: ${LINUX_INFO_HEALTH_ICON} ${LINUX_INFO_HEALTH_LABEL}" \
            "Motivo: ${LINUX_DIAG_REASON:-não identificado}" \
            "Código: ${LINUX_DIAG_CODE:-UNKNOWN}" \
            "PRoot base: $proot_status"

        caixa_simples_wrap "Arquitetura" \
            "CPU: ${LINUX_ARCH_CPU_GEN:-?} • Termux: ${LINUX_ARCH_TERMUX:-?} (${LINUX_ARCH_BITS:-?} bits)" \
            "Android ABI: ${LINUX_ARCH_ANDROID_ABI:-não informada}" \
            "Distro / shell: ${LINUX_DIAG_MANIFEST_ARCH:-?} / ${LINUX_DIAG_SHELL_ARCH:-?}" \
            "${LINUX_ARCH_INTERPRETATION:-}"

        caixa_simples_wrap "Interpretação do erro" "$erro_pt"
        caixa_simples_wrap "O que fazer" "$orientacao"

        caixa_simples_wrap "Arquivos" \
            "Shell: $shell_exib" \
            "Loader: $loader_exib" \
            "Loader no rootfs: ${LINUX_DIAG_LOADER_STATUS:-não verificado}" \
            "Log: $(caminho_curto "$LINUX_LOG")"

        rodape_atalhos "[0] Voltar  •  [1] Exportar log  •  [2] Testar novamente"
        ui_buffer_flush
        ler_opcao
        escolha="$RESPOSTA_MENU"
        case "$escolha" in
            1) linux_exportar_diagnostico_distro "$alias" ;;
            2) forcar=true ;;
            0|"") tela_limpar; return 0 ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
