# Módulo: config.sh
# Manager.sh — módulo

# ============================================================================
# DETECÇÃO DE TERMINAL (largura + suporte a cor)
# ============================================================================

CORES_ATIVADAS=true   # sobrescrito por carregar_config()
LARGURA_CAIXA=38

detectar_terminal() {
    local cols_tput cols_stty cols
    cols_tput=$(tput cols 2>/dev/null || echo 0)
    cols_stty=$(stty size 2>/dev/null | awk '{print $2}')
    cols_stty=${cols_stty:-0}

    # Alguns estados do Termux mantêm COLUMNS/tput desatualizados depois da
    # tela alternativa. Quando as duas leituras existem, usa a menor para
    # garantir que as caixas nunca ultrapassem a largura realmente visível.
    if [ "$cols_tput" -gt 0 ] 2>/dev/null && [ "$cols_stty" -gt 0 ] 2>/dev/null; then
        [ "$cols_tput" -lt "$cols_stty" ] && cols=$cols_tput || cols=$cols_stty
    elif [ "$cols_stty" -gt 0 ] 2>/dev/null; then
        cols=$cols_stty
    else
        cols=$cols_tput
    fi

    if [ "$cols" -gt 0 ] 2>/dev/null; then
        # A interface acompanha a largura real do terminal. Mantemos apenas
        # duas colunas livres para evitar auto-wrap na última coluna em alguns
        # terminais Android. Não existe mais teto fixo de 46 colunas.
        LARGURA_CAIXA=$((cols - 2))
    fi
    [ "$LARGURA_CAIXA" -lt 24 ] && LARGURA_CAIXA=24
    return 0
}

aplicar_cores() {
    if [ "$CORES_ATIVADAS" != true ]; then
        C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
        C_CYAN=''; C_MAGENTA=''; C_BOLD=''; C_DIM=''; C_WHITE=''
    fi
}

# ============================================================================
# CONFIGURAÇÕES PERSISTIDAS (Menu > Configurações)
# ============================================================================

EXCLUSOES_PADRAO="node_modules .git dist build"
DESCRICOES_ATIVADAS=true
ICONES_ATIVADOS=true
ABRIR_NAVEGADOR_AUTO=true
CONFIRMAR_EXECUCAO=true
MOSTRAR_LOG_FALHA=true
DIAGNOSTICO_NA_ABERTURA=false
LIMPAR_TEMPORARIOS_AUTO=true
TEMPO_DETECTAR_PORTA=15
PAUSA_ERRO_SEGUNDOS=1
LOG_MAX_MB=5
DESTINO_IMPORTACAO_PADRAO="perguntar"
CONFLITO_PADRAO="perguntar"
CONFIRMAR_COPIA=true

carregar_config() {
    # Lê somente chaves conhecidas. Não executa o arquivo como código Bash.
    if [ -f "$CONFIG_FILE" ]; then
        local linha chave valor
        while IFS= read -r linha || [ -n "$linha" ]; do
            [[ "$linha" == \#* || -z "$linha" ]] && continue
            chave="${linha%%=*}"
            valor="${linha#*=}"
            valor="${valor%\"}"; valor="${valor#\"}"
            case "$chave" in
                CORES_ATIVADAS)
                    [[ "$valor" == true || "$valor" == false ]] && CORES_ATIVADAS="$valor"
                    ;;
                EXCLUSOES_PADRAO) EXCLUSOES_PADRAO="$valor" ;;
                DESCRICOES_ATIVADAS|ICONES_ATIVADOS|ABRIR_NAVEGADOR_AUTO|CONFIRMAR_EXECUCAO|MOSTRAR_LOG_FALHA|DIAGNOSTICO_NA_ABERTURA|LIMPAR_TEMPORARIOS_AUTO|CONFIRMAR_COPIA)
                    [[ "$valor" == true || "$valor" == false ]] && printf -v "$chave" '%s' "$valor"
                    ;;
                TEMPO_DETECTAR_PORTA|PAUSA_ERRO_SEGUNDOS|LOG_MAX_MB)
                    [[ "$valor" =~ ^[0-9]+$ ]] && printf -v "$chave" '%s' "$valor"
                    ;;
                DESTINO_IMPORTACAO_PADRAO)
                    [[ "$valor" == perguntar || "$valor" == painel || "$valor" == projetos ]] && DESTINO_IMPORTACAO_PADRAO="$valor"
                    ;;
                CONFLITO_PADRAO)
                    [[ "$valor" == perguntar || "$valor" == substituir || "$valor" == pular || "$valor" == renomear ]] && CONFLITO_PADRAO="$valor"
                    ;;
            esac
        done < "$CONFIG_FILE"
    fi
    LOG_MAX_BYTES=$((LOG_MAX_MB * 1024 * 1024))
    aplicar_cores
}

salvar_config() {
    cat > "$CONFIG_FILE" <<EOF
CORES_ATIVADAS=$CORES_ATIVADAS
EXCLUSOES_PADRAO="$EXCLUSOES_PADRAO"
DESCRICOES_ATIVADAS=$DESCRICOES_ATIVADAS
ICONES_ATIVADOS=$ICONES_ATIVADOS
ABRIR_NAVEGADOR_AUTO=$ABRIR_NAVEGADOR_AUTO
CONFIRMAR_EXECUCAO=$CONFIRMAR_EXECUCAO
MOSTRAR_LOG_FALHA=$MOSTRAR_LOG_FALHA
DIAGNOSTICO_NA_ABERTURA=$DIAGNOSTICO_NA_ABERTURA
LIMPAR_TEMPORARIOS_AUTO=$LIMPAR_TEMPORARIOS_AUTO
TEMPO_DETECTAR_PORTA=$TEMPO_DETECTAR_PORTA
PAUSA_ERRO_SEGUNDOS=$PAUSA_ERRO_SEGUNDOS
LOG_MAX_MB=$LOG_MAX_MB
DESTINO_IMPORTACAO_PADRAO="$DESTINO_IMPORTACAO_PADRAO"
CONFLITO_PADRAO="$CONFLITO_PADRAO"
CONFIRMAR_COPIA=$CONFIRMAR_COPIA
EOF
}

