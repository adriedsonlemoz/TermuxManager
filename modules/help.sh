# Módulo: help.sh
# Ajuda integrada do Termux Manager.

ajuda_primeira_instalacao() {
    cabecalho_tela "🚀 Primeira instalação" "Instalação automática recomendada"
    caixa_simples "1. Instalar o Termux" \
        "GitHub: https://github.com/termux/termux-app/releases" \
        "Google Play: https://play.google.com/store/apps/details?id=com.termux" \
        "A edição Google Play exige Android 11+ e pode ter diferenças da edição GitHub/F-Droid."
    echo
    caixa_simples "2. Liberar armazenamento" \
        "Execute: termux-setup-storage" \
        "Aceite a permissão de arquivos solicitada pelo Android."
    echo
    caixa_simples "3. Instalar o Manager" \
        "Se precisar: pkg install -y curl" \
        "Depois execute:" \
        "curl -fsSL https://raw.githubusercontent.com/adriedsonlemoz/TermuxManager/main/install.sh | bash"
    echo
    caixa_simples "O instalador faz sozinho" \
        "Confirma o acesso ao armazenamento antes da instalação." \
        "Baixa a versão estável diretamente da branch main." \
        "Se apt/dpkg estiver ocupado, aguarda sem inundar a tela." \
        "Valida os hashes declarados em MANIFEST.json e a sintaxe dos scripts." \
        "Instala, preserva backup da versão anterior e abre o Manager."
    echo
    caixa_simples "Primeira abertura" \
        "O assistente salva o progresso de cada etapa e retoma de onde parou." \
        "Durante pkg/apt, tempo e atividade continuam visíveis mesmo sem nova saída." \
        "Ctrl+C abre opções seguras para tentar novamente, pular ou retomar depois." \
        "Depois da configuração, abra normalmente com: manager"
    echo
    caixa_simples "Alternativa manual" \
        "Repositório: https://github.com/adriedsonlemoz/TermuxManager" \
        "Use Code > Download ZIP somente se quiser fazer a instalação manual." \
        "O instalador automático continua sendo o método recomendado."
    pause
}

ajuda_atualizacoes() {
    cabecalho_tela "🔄 Como atualizar" "Pacote completo ou módulo individual"
    caixa_simples "Atualização pelo GitHub — recomendada" \
        "1. Abra Manager > Atualizar Manager." \
        "2. Escolha Verificar no GitHub." \
        "3. O Manager compara a versão instalada com a branch main." \
        "4. Se houver versão nova, mostra o changelog, valida, cria backup e atualiza." \
        "Não é necessário criar GitHub Releases. A branch main é o canal estável."
    echo
    caixa_simples "Atualização por ZIP — alternativa" \
        "1. Coloque TermuxManager-vX.Y.Z.zip em Downloads." \
        "2. Abra Atualizar Manager > Atualizar por ZIP." \
        "3. Selecione o pacote desejado." \
        "O mesmo fluxo de validação e backup é aplicado."
    echo
    caixa_simples "Durante a atualização" \
        "A tela permanece fixa e altera somente a etapa atual." \
        "São exibidos versão, tamanho, arquivos, espaço livre e progresso." \
        "Antes do reinício, a saída e o estado do terminal são restaurados."
    echo
    caixa_simples "Atualização de módulo" \
        "Use somente quando receber um arquivo .sh específico." \
        "O arquivo é validado antes de substituir o módulo instalado."
    echo
    caixa_simples "Conclusão" \
        "Após reiniciar, uma tela confirma que a nova versão está ativa." \
        "Ela mostra versão, pacote, data e aparece uma única vez."
    pause
}

ajuda_estrutura() {
    cabecalho_tela "🧩 Estrutura do Manager" "Arquivos da instalação modular"
    caixa_simples "Arquivo principal" \
        "manager.sh — carrega os módulos e inicia o aplicativo"
    echo
    caixa_simples "Módulos" \
        "core.sh — base, logs, bloqueio e utilitários" \
        "config.sh — preferências persistentes" \
        "ui.sh — caixas, menus e renderização atômica" \
        "import.sh — assistente, análise e cópia" \
        "projects.sh — projetos, ações e Centro de exclusão" \
        "runtime.sh — carregador do runtime" \
        "runtime_detect.sh — stack e estrutura dos projetos" \
        "runtime_dependencies.sh — configuração, dependências e testes" \
        "runtime_processes.sh — processos, portas, execução e saúde" \
        "termux.sh — ambiente, ferramentas e primeira configuração" \
        "updater.sh — atualização, backup e reinício" \
        "settings.sh — preferências gerais e carregador de configurações" \
        "settings_fish.sh — Fish Shell e experiência interativa" \
        "settings_shortcuts.sh — atalhos globais manager e mm" \
        "settings_maintenance.sh — restauração, limpeza e manutenção" \
        "help.sh — ajuda integrada" \
        "app.sh — menu principal e página Sobre"
    echo
    caixa_simples "Interface responsiva" \
        "As caixas usam a largura disponível do terminal, sem teto fixo." \
        "Uma pequena margem evita quebra automática na última coluna." \
        "Painéis vivos mantêm a largura estável enquanto a operação executa."
    echo
    caixa_simples "Dados operacionais" \
        "~/Painel — projetos, logs e configurações" \
        "Download/projetos/backups — backups de projetos" \
        "~/scripts/manager — código do Manager" \
        "$PREFIX/bin/manager — atalho global"
    pause
}

ajuda_menus() {
    cabecalho_tela "📋 Funções do menu" "Acesso direto às funções principais"
    caixa_simples "Menu principal"         "Gerenciar projetos: abrir, testar e organizar."         "Em execução: processos ativos, portas, logs e parada."         "Importar projeto: pasta, arquivos ou ZIP de Downloads."         "Linux no celular: PRoot, distribuições, Termux:X11 e ambientes gráficos."         "Ambiente e ferramentas: pacotes, Termux e diagnóstico."         "Atualizar Manager: GitHub main, ZIP local ou módulo."         "Configurações: aparência, caminhos, execução e manutenção."         "Ajuda e Sobre: manual, versão, changelog e desenvolvedor."
    pause
}

ajuda_importacao() {
    cabecalho_tela "📥 Importação de projetos" "Como funciona a cópia"
    caixa_simples "Origem e formatos" \
        "A lista começa sempre na raiz de Downloads." \
        "Aceita pasta inteira, arquivos selecionados ou pacote ZIP." \
        "O destino pode ser ~/Painel ou ~/Painel/projetos."
    echo
    caixa_simples "Progresso" \
        "A análise e a cópia mostram contagem como 10/254, 20/254 e 100%." \
        "Ao terminar, aparecem velocidade média, tempo total, arquivos e pastas."
    echo
    caixa_simples "Conflitos" \
        "É possível substituir, ignorar, renomear ou decidir arquivo por arquivo."
    echo
    caixa_simples "Após concluir" \
        "Pressione ENTER para retornar ao menu de importação." \
        "O Manager não é encerrado após a cópia."
    pause
}

ajuda_execucao() {
    cabecalho_tela "▶️ Execução de projetos" "Dependências, portas e processos"
    caixa_simples "Preparação" \
        "O Manager detecta frontend, backend, fullstack e monorepos." \
        "Dependências só são reinstaladas quando os arquivos relevantes mudam."
    echo
    caixa_simples "Portas" \
        "A porta é detectada pelo processo e seus filhos." \
        "Logs são usados apenas como fallback estrito com :porta explícita."
    echo
    caixa_simples "Projetos em execução" \
        "A tela reutiliza a porta validada e mostra PID, logs e ações de parada."
    echo
    caixa_simples "Projeto não abriu" \
        "Confira backend/.env, frontend/.env e os logs em ~/Painel/.logs."
    pause
}

ajuda_ferramentas_fish() {
    cabecalho_tela "🧰 Ferramentas e Fish" "Ambiente de desenvolvimento"
    caixa_simples "Ambientes de desenvolvimento" \
        "Web, Python, Java, Go, Rust, Ruby, PHP e compilação." \
        "Recomendado analisa ~/Painel e instala somente o que falta."
    echo
    caixa_simples "Ferramentas instaladas" \
        "Mostra comandos, versões e o estado dos ambientes." \
        "Bancos podem ser instalados separadamente."
    echo
    caixa_simples "Fish Shell" \
        "Instala, define como padrão, configura sugestões, prompt, histórico e atalhos." \
        "Também pode ocultar mensagens iniciais e mostrar tempo da sessão."
    echo
    caixa_simples "Limpeza do Fish" \
        "Remove apenas configurações do shell administradas pelo Manager." \
        "Não remove Python, Node.js, PHP, Git, projetos ou outros pacotes."
    pause
}

ajuda_limpeza_manutencao() {
    cabecalho_tela "🧹 Limpeza e manutenção" "Ações com níveis de segurança"
    caixa_simples "Centro de exclusão do Painel" \
        "Exclui um projeto, limpa o conteúdo de projetos, recria a pasta projetos" \
        "ou remove todo o ~/Painel com confirmação reforçada."
    echo
    caixa_simples "Restaurar Manager" \
        "Limpa preferências, logs, cache e estado interno." \
        "Preserva projetos e backups e retorna ao assistente inicial."
    echo
    caixa_simples "Desinstalar Manager" \
        "Remove o aplicativo e os atalhos criados por ele." \
        "Projetos e backups do Painel são preservados."
    pause
}

ajuda_problemas() {
    cabecalho_tela "🛟 Solução de problemas" "Correções rápidas"
    caixa_simples "Permission denied" \
        "bash ~/scripts/manager/manager.sh" \
        "ou: chmod +x ~/scripts/manager/manager.sh"
    echo
    caixa_simples "Comando manager não encontrado" \
        "Abra Configurações > Atalhos do Manager." \
        "Use Instalar ou reparar atalho."
    echo
    caixa_simples "Download não aparece" \
        "Execute termux-setup-storage." \
        "Depois use Ambiente Termux > Armazenamento."
    echo
    caixa_simples "Projeto não inicia" \
        "Veja os logs do componente e confirme .env, dependências e porta." \
        "Cada projeto usa identidade interna pelo caminho real; ~/Painel e ~/Painel/projetos/* não compartilham runtime/cache." \
        "Em falhas do teste integrado, use Coletar logs: o TXT mostra projeto, backend/frontend resolvidos e caches usados." \
        "Se node_modules estiver corrompido ou surgir MODULE_NOT_FOUND, o Manager invalida o cache e tenta um reparo limpo uma vez." \
        "Em execução usa verde somente quando a porta está respondendo." \
        "Amarelo significa processo vivo, mas servidor indisponível ou não confirmado."
    echo
    caixa_simples "Menu ou prompt ficou misturado" \
        "Atualize para a versão mais recente." \
        "As telas atuais usam renderização atômica e um prompt por vez."
    echo
    caixa_simples "Atualização não aplicada" \
        "Abra Atualizar Manager > Última atualização." \
        "Confira versão, pacote, hash, backup e status." \
        "Se a 1.0.44 parar na etapa 5, instale a 1.0.45 diretamente pelo unzip."
    pause
}

ajuda_diagnosticos() {
    cabecalho_tela "🩺 Central de Diagnóstico" "Manager, projetos e Termux"
    caixa_simples "Erros do Manager" \
        "Captura falhas técnicas com código, arquivo, linha, função e comando." \
        "O log principal também fica disponível para consulta."
    echo
    caixa_simples "Erros dos projetos" \
        "Lista apenas os logs existentes de frontend, backend e outros processos." \
        "Os padrões de erro aparecem numerados para exportação individual."
    echo
    caixa_simples "Erros do Termux" \
        "Reúne pkg, dpkg, ambiente, armazenamento e o diagnóstico atual." \
        "Não coleta logcat ou outros registros internos do Android."
    echo
    caixa_simples "Exportação segura" \
        "Selecione um número para copiar o erro com contexto para Downloads." \
        "Exportar todos cria uma pasta com Manager, projetos e Termux separados." \
        "Pacote completo reúne as mesmas categorias em um arquivo compactado." \
        "Senhas, tokens e credenciais comuns são removidos da cópia."
    pause
}

ajuda_seguranca() {
    cabecalho_tela "🔐 Segurança e backups" "Proteções usadas pelo Manager"
    caixa_simples "Atualizações" \
        "Scripts são verificados com bash -n." \
        "Hashes validam os arquivos e um backup é criado antes da troca."
    echo
    caixa_simples "Exclusões" \
        "Ações coletivas mostram tamanho e conteúdo afetado." \
        "Operações de maior risco exigem palavra de confirmação." \
        "Backups de projetos vão para Download/projetos/backups." \
        "Dependências, caches e builds regeneráveis não entram no pacote."
    echo
    caixa_simples "GitHub" \
        "A publicação usa o GitHub CLI oficial e HTTPS." \
        "Privado é o padrão na criação de novos repositórios." \
        "Segredos comuns entram no .gitignore e arquivos sensíveis já rastreados bloqueiam o push." \
        "Falhas mostram a etapa real e são registradas em ~/.termux-manager/logs/github.log." \
        "O Manager nunca força push automaticamente."
    echo
    caixa_simples "Processos" \
        "PIDs são verificados antes de encerrar." \
        "Metadados inativos são removidos sem afetar outros projetos."
    echo
    caixa_simples "Configuração" \
        "Somente chaves conhecidas são aceitas." \
        "Arquivos de configuração não são executados como scripts."
    pause
}

menu_ajuda() {
    while true; do
        menu_unificado "❓ Ajuda" "Manual rápido dentro do Manager" \
            "[0] Voltar  •  [1–11] Selecionar" \
            "1|🚀|Primeira instalação|Storage, extração e primeira abertura" \
            "2|🔄|Como atualizar|Pacote completo, módulo e reinício" \
            "3|📋|Funções do menu|O que cada área faz" \
            "4|📥|Importação de projetos|Análise, progresso e conflitos" \
            "5|▶️|Execução de projetos|Dependências, portas e processos" \
            "6|🧰|Ferramentas e Fish|Pacotes instalados e shell" \
            "7|🧹|Limpeza e manutenção|Painel, restauração e desinstalação" \
            "8|🧩|Estrutura do projeto|Arquivos e módulos" \
            "9|🛟|Solução de problemas|Erros comuns e correções" \
            "10|🔐|Segurança e backups|Validação e proteção" \
            "11|🩺|Central de Diagnóstico|Erros numerados e exportação para Downloads" \
            "R|📖|Abrir README|Manual completo do projeto"
        ler_opcao
        case "$RESPOSTA_MENU" in
            1) ajuda_primeira_instalacao ;;
            2) ajuda_atualizacoes ;;
            3) ajuda_menus ;;
            4) ajuda_importacao ;;
            5) ajuda_execucao ;;
            6) ajuda_ferramentas_fish ;;
            7) ajuda_limpeza_manutencao ;;
            8) ajuda_estrutura ;;
            9) ajuda_problemas ;;
            10) ajuda_seguranca ;;
            11) ajuda_diagnosticos ;;
            r|R)
                cabecalho_tela "📖 README.md" "Documentação completa"
                caixa_simples "Arquivo local" "$(caminho_curto "$BASE_DIR/README.md")" \
                    "Use: cat ~/scripts/manager/README.md" \
                    "O conteúdo também aparece na página inicial do GitHub."
                pause
                ;;
            0) return ;;
            *) feedback_curto "Opção inválida." ;;
        esac
    done
}
