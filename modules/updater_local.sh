# Submódulo: updater_local.sh
# Descoberta e instalação de atualizações locais/isoladas.

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

