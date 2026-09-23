# Changelog

## [1.0.73] - 2026-09-23

### Adicionado
- Detecção automática da origem do Termux no instalador e no Manager, diferenciando **Google Play** e **GitHub/F-Droid** com registro da variante nas telas e diagnósticos.
- Novo teste `tools/test-termux-variant.sh` para validar a identificação das duas variantes suportadas.

### Melhorado
- A instalação de ferramentas agora verifica se cada pacote existe na variante atual do Termux antes de tentar instalá-lo. Pacotes ausentes naquela edição passam a ser marcados como **indisponíveis**, sem interromper a configuração inicial.
- A página **Sobre**, o diagnóstico do ambiente e a ajuda de primeira instalação agora mostram a origem detectada do Termux e o repositório APT principal.
- O instalador `install.sh` agora informa na tela a variante detectada do Termux antes de baixar e instalar o Manager.

### Corrigido
- Evitada falha desnecessária da primeira configuração quando um pacote recomendado não existe em determinada variante do Termux.

## [1.0.72] - 2026-09-23

- Primeira configuração agora salva progresso por etapa e retoma de onde parou; atualização do Termux e pacotes já concluídos não são repetidos após uma interrupção.
- Monitor de `apt/pkg` passou a exibir tempo decorrido e tempo desde a última saída, evitando a impressão de congelamento quando um pacote demora.
- `apt-get` usa tentativas e timeouts controlados de rede/lock para reduzir esperas indefinidas em repositórios lentos.
- `Ctrl+C` durante uma instalação monitorada não encerra mais o Manager: abre opções para tentar novamente, pular o pacote ou retomar a configuração depois.
- Ao adiar a configuração inicial, o Manager não marca mais o assistente como concluído; ele volta na próxima abertura.
- Restauração/desinstalação também removem o novo estado parcial do assistente.

## [1.0.71] - 2026-09-23

- Primeira instalação deixou de executar `pkg install -y curl` sem necessidade; o comando recomendado agora chama diretamente o instalador quando `curl` já está disponível.
- O instalador detecta `apt`/`dpkg` já em execução, aguarda de forma controlada e evita inundar o terminal com mensagens repetidas de `Waiting for cache lock`.
- O monitor de pacotes do assistente também espera operações concorrentes antes de iniciar outro `apt`/`dpkg`.
- Padronizada a entrega em um único arquivo `TermuxManager-vX.Y.Z.zip`; o checksum externo separado foi removido do padrão e a integridade continua protegida pelos hashes internos de `MANIFEST.json`.
- `build-release.sh`, README, ajuda interna, updater e padrão de release foram sincronizados com o pacote único.
- Adicionado teste automático de sincronização de versão/release para evitar documentação e metadados divergentes.

## [1.0.70] - 2026-09-23

### Correção do instalador automático
- Corrigido o erro `404` na primeira instalação quando o repositório ainda não possui GitHub Releases publicadas.
- `install.sh` deixou de depender de `/releases/latest` e agora baixa diretamente a versão estável da branch `main`.
- O instalador valida `MANIFEST.json`, confere os hashes dos arquivos, verifica a versão interna e executa `bash -n` antes de substituir a instalação atual.
- Mantidos backup automático e abertura do Manager ao final da instalação.
- README e ajuda interna foram ajustados para explicar que a instalação automática não depende da página de Releases.
- Adicionado teste de integração local do instalador para reproduzir a extração e instalação sem acesso à rede.

## [1.0.69] - 2026-09-23

### Instalação simplificada
- Adicionado `install.sh` oficial para transformar a primeira instalação em um único comando.
- O instalador consulta automaticamente a release estável mais recente, baixa o pacote e seu SHA-256 e verifica a integridade antes de instalar.
- O instalador prepara dependências mínimas, valida `manager.sh` e os módulos com `bash -n`, confere a versão interna e preserva backup de uma instalação existente.
- README passou a recomendar `pkg install -y curl && curl -fsSL .../install.sh | bash`, eliminando a necessidade de localizar manualmente o ZIP em Downloads.
- Fluxo manual foi mantido apenas como alternativa.
- Ajuda interna de primeira instalação atualizada para o novo fluxo automático.

## [1.0.68] - 2026-09-23

### Primeira instalação
- Reescrito o tutorial inicial do README em etapas, começando pela instalação do próprio Termux.
- Adicionados links oficiais para o Termux via GitHub e Google Play, com explicação das diferenças entre as distribuições.
- Documentado que a edição atual do Google Play exige Android 11 ou superior e é mantida separadamente da edição GitHub/F-Droid.
- Adicionado link direto para as releases do Termux Manager e aviso para não usar `Source code (zip)`/`Code > Download ZIP` no lugar do pacote `manager-vX.Y.Z.zip`.
- Melhoradas as instruções de `termux-setup-storage`, Downloads, `unzip`, primeira abertura e solução de pacote não encontrado/`Permission denied`.
- Ajuda interna de primeira instalação atualizada para acompanhar o novo fluxo.
- README e padrão de release sincronizados com a versão atual.

## [1.0.67] - 2026-08-10

### Desempenho pós-cópia
- O atalho **Testar agora** exibido imediatamente após importar/copiar um projeto ativa um caminho ultrarrápido exclusivo para essa execução.
- Quando `package.json`/lockfile mantêm a assinatura já conhecida e `node_modules` existe, o Manager não executa `npm ls`, `require()` em massa nem percorre a árvore de módulos antes de subir o servidor.
- Frontend e backend continuam iniciando em paralelo; health checks e reparo automático permanecem como rede de segurança caso uma dependência realmente esteja quebrada.
- Testes iniciados posteriormente pelo menu normal continuam usando a validação completa/cacheada.

## [1.0.66] - 2026-08-10

### Desempenho
- Reimportação completa agora preserva `node_modules` quando `package.json` e lockfiles não mudaram, mesmo ao substituir a pasta inteira do projeto; a árvore é movida temporariamente e restaurada sem cópia pesada nem novo `npm install`.
- O cache de integridade de dependências usa uma assinatura leve dos diretórios de pacotes para evitar repetir `npm ls` + carregamento de módulos em testes consecutivos sem perder a detecção de alterações/corrupção comum.
- Instalações npm novas com lockfile tentam `npm ci --prefer-offline --no-audit --no-fund --progress=false`, com fallback automático para `npm install` quando necessário.
- Inicialização de processos remove a espera fixa de 1 segundo e verifica encerramento imediato após uma janela curta.
- Detecção de porta/saúde passa a consultar em intervalos menores, reduzindo o tempo até reconhecer um servidor que já subiu.
- A opção **Testar sistema completo / Executar sistema** inicia frontend e backend em paralelo depois que as dependências estão prontas; se o backend falhar, o frontend é encerrado automaticamente.
- Novo teste de regressão garante que dependências sejam preservadas somente quando os manifestos realmente são iguais.

## [1.0.65] - 2026-08-10

### Diagnóstico Android
- Central de Diagnóstico ganhou coleta opcional de informações do Android via Rish/Shizuku, incluindo CPU, RAM/ZRAM, OOM, processos, bateria, temperaturas e armazenamento.
- Adicionado teste de armazenamento em menu separado para não aumentar desnecessariamente o tamanho dos relatórios normais.
- O Manager verifica se o Shizuku está ativo antes de iniciar a coleta privilegiada e mantém diagnóstico básico como fallback.

## [1.0.64] - 2026-08-09

- Novo fluxo pós-importação: após copiar um projeto, é possível testar imediatamente, abrir diretamente o menu daquele projeto, importar outro pacote ou voltar ao menu principal.
- O atalho **Testar agora** usa diretamente o destino recém-importado, sem redescobrir ou exigir nova seleção; projetos fullstack iniciam pelo teste integrado frontend + backend.
- Corrigido progresso enganoso de análise que aparecia em 100% durante toda a descoberta por usar o número encontrado como total provisório.
- A análise agora possui duas fases explícitas: **Descobrindo arquivos** (sem porcentagem falsa enquanto o total é desconhecido) e **Calculando tamanho** (percentual real após conhecer o total).
- A linha de item analisado passa a usar `➜ Verificando:` em vez de ícone de pasta para arquivos.
- O motor de cópia ganhou modo sem pausa final para permitir continuidade direta do assistente, preservando o comportamento anterior nas demais chamadas.
- Adicionado teste de regressão para o pós-importação e para impedir o retorno do falso 100% na fase de descoberta.

## [1.0.63] - 2026-08-09

- Isolamento de runtime reforçado: IDs de processo usam hash do caminho canônico do projeto, evitando colisões entre `~/Painel` e `~/Painel/projetos/*`.
- O teste integrado agora usa os mesmos IDs isolados para frontend/backend em todos os fluxos.
- Logs de teste são rotacionados antes da preparação de dependências, impedindo relatórios com erros de execuções anteriores.
- Validação npm passou de `npm ls --all` para dependências de topo + carregamento direto, reduzindo falsos positivos de peers transitivos.
- Falhas de integridade registram pacote/etapa responsável no log do Manager.
- Reparo com lockfile remove explicitamente `node_modules` antes de `npm ci`.
- Relatório de teste passa a mostrar projeto selecionado, backend/frontend resolvidos e caminhos de cache de dependências.

## [1.0.62] - 2026-08-09

### Corrigido
- O cache de dependências não considera mais apenas a presença de `node_modules`: projetos Node passam por uma verificação estrutural (`npm ls --all`) e por uma carga segura das dependências diretas CommonJS para detectar instalações parcialmente corrompidas.
- Falhas `MODULE_NOT_FOUND`, `ERR_MODULE_NOT_FOUND` e equivalentes durante a inicialização passam a ser classificadas como erro de dependência.
- O teste integrado tenta reparar automaticamente uma instalação Node corrompida uma única vez e reinicia o backend antes de desistir. Com `package-lock.json`/`npm-shrinkwrap.json`, o reparo usa `npm ci`; sem lockfile, recria `node_modules` com `npm install`.
- A assinatura externa de dependências é invalidada quando a instalação local não passa na verificação de integridade.
- O relatório de teste não duplica mais o texto de remoção em variáveis como `REDIS_URL`; os valores continuam ocultos.

### Melhorado
- Mensagens do teste agora distinguem servidor degradado de falha causada por dependências.
- O reparo automático registra o diagnóstico e valida novamente a instalação antes de reutilizar o cache.

## [1.0.61] - 2026-08-09

- Adicionada coleta integrada dos logs de teste para Downloads, reunindo backend, frontend, log do Manager e metadados de execução em um único TXT sanitizado.
- Em falhas do teste Frontend + Backend, a tela agora oferece coletar os logs ou visualizar as últimas linhas do backend.
- Corrigidos retornos antecipados que podiam deixar o painel vivo aberto e quebrar a moldura das telas seguintes.
- Corrigida exibição de caminho absoluto do log em falhas de servidor; caminhos sob HOME agora aparecem como `~/...`.
- Melhoradas mensagens de falha de disponibilidade do backend/frontend.

## [1.0.60] - 2026-08-09

### GitHub: diagnóstico e preparação corrigidos
- Corrigida a mensagem genérica **Não foi possível preparar o repositório Git local**: cada etapa agora informa o ponto exato da falha.
- Criado log dedicado em `~/.termux-manager/logs/github.log`, com etapa, comando, código de saída e mensagem retornada pelas ferramentas.
- `git init`, preparação da branch, `.gitignore`, autenticação, identidade, criação/conexão do repositório, commit e push passam a registrar diagnóstico próprio.
- A identidade Git deixa de fazer parte da inicialização do repositório; ela só é configurada quando houver um commit a criar.
- Falha em `gh api user` não faz mais o Manager dizer incorretamente que `git init` ou o repositório local falhou.
- Saídas importantes de `gh auth login`, `gh repo create`, `git commit` e `git push` deixam de ser descartadas e também aparecem no log.
- A tela de erro mostra o caminho curto do log e o detalhe disponível da etapa que falhou.
- Mantidas as proteções de `.gitignore`, bloqueio de segredos rastreados e ausência de `push --force`.
- Teste de regressão GitHub ampliado para cobrir o log dedicado e garantir que a identidade não volte a bloquear a preparação local.

## [1.0.59] - 2026-08-09

### GitHub integrado ao menu do projeto
- Adicionada a ação **Enviar para GitHub** dentro do menu de cada projeto.
- Primeira publicação instala `git` e GitHub CLI (`gh`) automaticamente quando necessário e conduz o login oficial via `gh auth login`.
- Nome do repositório vem preenchido a partir da pasta; visibilidade **Privada** é o padrão e pode ser escolhida como Pública.
- Se o projeto ainda não possui Git, o Manager inicializa o repositório e configura a branch principal.
- A identidade Git local é preenchida com o usuário autenticado e o endereço `noreply` do GitHub, sem alterar a configuração global do aparelho.
- Repositórios GitHub já conectados são reutilizados; `origin` de outro serviço é preservado e o GitHub usa um remote separado.
- Próximos envios detectam alterações, criam commit e executam push sem repetir a configuração inicial.
- O Manager nunca executa `push --force` automaticamente; divergências remotas são interrompidas de forma segura.
- `.gitignore` recebe uma seção gerenciada para dependências, builds e credenciais comuns.
- Arquivos sensíveis já rastreados (`.env`, `.npmrc`, chaves e credenciais) bloqueiam o envio até serem removidos do índice.
- Em projetos diretamente em `~/Painel`, arquivos internos do Manager, backups, temporários e `~/Painel/projetos` são protegidos contra publicação acidental.
- Ajuda interna, README, manifesto e padrão de release atualizados.

## [1.0.58] - 2026-08-07

### Interface responsiva
- As caixas do Manager deixam de usar teto fixo de 46 colunas e passam a ocupar praticamente toda a largura disponível do terminal, preservando apenas uma margem de segurança de duas colunas.
- A largura é recalculada ao limpar/renderizar telas e imediatamente antes de painéis vivos, acompanhando mudanças de orientação e redimensionamento do terminal.
- Painéis vivos continuam congelando a largura durante cada operação, portanto mensagens curtas ou longas não deslocam a borda direita.
- A tela alternativa de preparação do Termux permanece responsiva e segue usando a largura real do terminal.
- A mensagem de boas-vindas opcional do Fish também deixa de usar moldura fixa e passa a acompanhar a largura da sessão.
- Adicionado teste de regressão para garantir que terminais largos não voltem a ser limitados a 46 colunas.
- README, padrão de release, manifesto e ajuda interna foram atualizados para a 1.0.58.

## [1.0.57] - 2026-08-07

- A importação passa a listar sempre a raiz de `Downloads`; o Manager não troca automaticamente a origem para `Downloads/projetos`.
- O painel vivo de **Testar projeto** congela a largura da caixa durante a execução, evitando que a borda direita acompanhe o tamanho das mensagens de progresso.
- O cache de dependências foi movido para `~/.termux-manager/dependencies/`, fora do código do projeto, para sobreviver a atualizações/substituições.
- Antes de executar `npm install`, `pnpm install` ou `yarn install`, o Manager verifica dependências já existentes quando ainda não há cache conhecido; instalações válidas são reutilizadas.
- A assinatura antiga `.manager-deps.hash` é migrada automaticamente quando válida.
- README, padrão de release e ajuda interna foram atualizados para refletir o novo fluxo.

## [1.0.56] - 2026-08-07

### Corrigido
- Quando `~/Painel` é detectado como um projeto fullstack/monorepo, seus componentes internos de frontend e backend deixam de ser listados novamente como projetos independentes.
- Projetos reais armazenados em `~/Painel/projetos/<nome>` continuam aparecendo individualmente no gerenciamento.
- Adicionado teste de regressão para impedir que a listagem volte a duplicar `frontend` e `backend` do projeto raiz do Painel.

## [1.0.55] - 2026-08-07

### Importação e organização de projetos
- A importação volta a permitir escolher entre `~/Painel` e `~/Painel/projetos` para qualquer projeto, sem regras específicas por nome.
- `~/Painel` é o único destino que aceita o conteúdo do projeto solto diretamente na raiz.
- `~/Painel/projetos` nunca recebe arquivos de projeto soltos: o Manager cria obrigatoriamente `~/Painel/projetos/<nome-do-projeto>` e copia o conteúdo para dentro dela.
- ZIPs com uma única pasta externa usam essa pasta apenas para inferir o nome do projeto; a camada não é duplicada na cópia.
- ZIPs sem pasta externa inferem o nome pelo arquivo do pacote. Sufixos semânticos claros como `-1.2.3` e `-v1.2.3` são removidos do nome da pasta criada, sem alterar nomes legítimos como `api-v2` ou `projeto-2026`.
- A etapa de destino mostra antecipadamente a pasta final que será criada em Projetos.
- Conflitos em uma pasta de projeto existente permitem mesclar com segurança ou substituir somente aquela pasta; o Painel continua tratando conflitos arquivo por arquivo.
- Adicionados testes de regressão específicos para as regras de destino e nomeação de projetos.

## [1.0.54] - 2026-08-07

### Importação e caminhos
- ZIPs de projeto agora são importados pelo conteúdo: uma única pasta externa de embalagem é ignorada automaticamente e seus itens são mesclados diretamente em `~/Painel`.
- ZIPs que já possuem arquivos na raiz também são mesclados diretamente em `~/Painel`, sem criar pastas derivadas do nome/versionamento do arquivo ZIP.
- A importação manual de uma pasta passa a recomendar **Importar para o Painel**; preservar a pasta externa continua disponível como modo avançado.
- A revisão da importação mostra quando a camada externa será ignorada e apresenta uma prévia dos primeiros itens que chegarão ao Painel.
- Caminhos exibidos na interface foram normalizados para a forma curta baseada em `~`, evitando expor `/data/data/com.termux/files/home/...` em mensagens de logs, Downloads, backups e diagnósticos.
- Adicionado teste de regressão para ZIP com e sem pasta externa.

## [1.0.53] - 2026-08-07

### Projetos e identificação
- O nome principal exibido em **Projetos e gerenciamento** passa a usar o nome da pasta, em vez do campo `name` do `package.json`.
- O `package.json` continua sendo usado para detectar stack e agora aparece separadamente em **Informações** quando possui um nome técnico.
- Adicionada a ação **Nome de exibição**, permitindo definir ou remover um apelido personalizado sem modificar nenhum arquivo do projeto.
- Apelidos são persistidos fora dos projetos em `~/.termux-manager/projects/`; projetos com apelido recebem uma estrela na listagem.

## [1.0.52] - 2026-08-07

### Corrigido
- Recupera automaticamente o diretório de trabalho quando o Manager é aberto com um CWD que já foi removido, evitando a repetição de `shell-init: ... getcwd(): No such file or directory`.
- Antes de excluir, limpar ou substituir uma pasta de projeto, o Manager verifica se o terminal está dentro da árvore afetada e muda para `$HOME` (com fallback para `/`) antes da operação.
- A proteção foi aplicada à substituição durante importações, exclusão individual de projeto, limpeza de `~/Painel/projetos`, exclusão da pasta `projetos` e exclusão completa do Painel.

## [1.0.51] - 2026-08-07

### Corrigido
- Corrige falha de importação via `rsync` com `getcwd(): No such file or directory` quando o shell permanecia em uma pasta removida ou substituída durante a sessão.
- O `rsync` agora é iniciado a partir de um diretório estável (`$HOME`, com fallback para `/`), mantendo origem e destino absolutos e sem depender do diretório atual do shell.

## [1.0.50] - 2026-08-07

### Backups de projetos
- Backups criados em **Gerenciar projetos → Fazer backup** passam a ser exportados para `Download/projetos/backups`.
- Backups preventivos antes da exclusão usam o mesmo destino público e permanecem acessíveis pelo Android.
- O pacote é criado temporariamente no Termux, copiado para Downloads, validado por SHA-256 e a cópia temporária é removida imediatamente após a verificação.
- `node_modules`, `.git`, caches, ambientes virtuais, dependências regeneráveis e diretórios de build não entram mais no backup, reduzindo bastante o tamanho do arquivo.
- Se um backup solicitado antes da exclusão falhar, a exclusão do projeto é cancelada para evitar perda de dados.
- Adicionado teste de regressão para destino, integridade, limpeza temporária e exclusões do pacote.

## [1.0.49] - 2026-08-07

### Interface de teste fullstack
- Redesenhada a tela **Testando Frontend + Backend** como um painel único em moldura azul.
- Backend, frontend, inicialização dos serviços e disponibilidade agora aparecem em quatro etapas visuais.
- Mensagens `INFO`, `OK`, `WARN` e `ERROR` permanecem dentro da moldura durante o teste integrado.
- O progresso de instalação de dependências também respeita o painel, mantendo feedback ao vivo sem quebrar o layout.
- Falhas do servidor deixam de despejar trechos crus do log dentro do painel; a Central de Diagnóstico é indicada para detalhes completos.
- Corrigido o cálculo de largura visual com caracteres UTF-8/emojis para reduzir truncamentos e bordas desalinhadas no Termux.

## [1.0.48] - 2026-08-07

### Corrigido
- Restaurado o bloco de execução de projetos removido acidentalmente, incluindo `executar_em_background`, espera de portas, abertura do navegador e menu de execução.
- Corrigidas declarações `local` que podiam montar caminhos `.pid`, `.log` e `.meta` sem o nome do processo.
- Portas persistidas são revalidadas antes de serem consideradas ativas.
- Retornos normais de funções (`return`, `break`, `continue`) não geram mais incidentes técnicos falsos.
- Entrada de menu inválida passa a ser aviso do usuário, não erro interno.

### Adicionado
- Estado de saúde dos processos: 🟢 servidor disponível, 🟡 processo ativo/servidor indisponível e 🔴 encerrado.
- Detecção antecipada de falhas de servidor pelo log, incluindo `Failed running`, erros não tratados e falhas comuns do Node.
- `Exportar todos os relatórios`: cria em Downloads uma pasta com relatórios separados por Manager, projetos e Termux.
- Teste de regressão para processo saudável e processo vivo com servidor falho.

## [1.0.47] - 2026-08-07

### Central de Diagnóstico
- Substituída a listagem simples de logs por uma central organizada em Manager, projetos e Termux.
- Falhas Bash não tratadas passam a ser capturadas com código de saída, arquivo, linha, função e comando.
- Erros encontrados dentro dos logs são apresentados com números para seleção.
- Permite exportar um erro específico com 20 linhas de contexto antes e depois, ou o log completo.
- Exportações são copiadas para Downloads com nome, data, versão e informações do ambiente.
- Novo pacote completo de suporte com as categorias `manager/`, `projetos/` e `termux/`.
- Valores comuns de senhas, tokens, chaves, credenciais de banco e autorização são removidos das cópias exportadas.
- Adicionado diagnóstico atual do Termux com arquitetura, espaço, pacotes, `dpkg --audit` e `termux-info`.
- Nova ação para limpar apenas registros de diagnóstico, preservando projetos, pacotes e configurações.

## [1.0.46] - 2026-08-06

### Adicionado
- Nova tela pós-atualização exibida somente uma vez após o reinício.
- A tela confirma versão anterior e nova, pacote, data, reinício e execução ativa.
- A confirmação funciona ao atualizar diretamente da versão 1.0.45 pelo menu interno.
- O registro futuro de atualização passa a incluir também o nome do backup criado.

### Corrigido
- Corrigida a chamada restante da função inexistente `success` ao abrir o repositório; agora usa `ok`.
- A tela pós-atualização serve como teste visual de que o novo processo realmente iniciou e voltou ao terminal.

## [1.0.45] - 2026-08-06

### Corrigido
- Corrigido o travamento aparente da atualização completa na **Etapa 5 de 5**.
- A causa era o buffer global da interface: o `exec` reiniciava o Manager com `stdout` ainda apontando para um arquivo temporário.
- A tela de progresso agora escreve diretamente no terminal e altera somente o bloco dinâmico.
- O fluxo final restaura explicitamente saída, cursor, modo do terminal, traps e bloqueio antes do reinício.
- Removida a recriação redundante dos atalhos durante a atualização; o atalho já aponta para o caminho estável do `manager.sh`.
- Adicionada proteção no encerramento para liberar qualquer buffer de UI ainda ativo.
- Adicionado teste de regressão que confirma que a nova versão imprime no terminal após o `exec`.

### Migração
- A transição da versão 1.0.44 para 1.0.45 deve ser feita uma única vez por extração direta, pois o processo que executa a atualização ainda é o updater defeituoso já carregado em memória.

## [1.0.44] - 2026-08-06

### Documentação e ajuda
- README consolidado e atualizado para refletir todas as funções até a versão 1.0.44.
- Ajuda interna reescrita com instalação atual, atualização visual, reinício do shell, importação em tempo real, portas validadas, ferramentas instaladas, Fish, atalhos e Centro de exclusão.
- Removidas referências antigas a `manager.zip`, `chmod` obrigatório e atualização que apenas fecha o Manager.
- Adicionados tópicos específicos de importação, execução, ferramentas, Fish, limpeza, manutenção e solução de problemas.
- Manifesto, hashes e padrão de release sincronizados.

## 1.0.43 — 2026-08-06

- Reorganiza a conclusão da primeira configuração em duas telas isoladas.
- Exibe a versão instalada antes de qualquer ação adicional.
- Adiciona opções para reiniciar o shell agora, continuar para o menu ou sair sem reiniciar.
- Evita mistura entre mensagens do atalho, prompts e menu principal.
- Informa claramente que o reinício do shell é recomendado para aplicar todas as alterações.

## 1.0.40 — 2026-08-06

### Corrigido

- Corrigida a detecção incorreta da porta `1` ao iniciar frontends em `127.0.0.1`.
- A leitura de logs agora exige `:porta` explícita e não confunde o último octeto do endereço IP com uma porta.
- Removida a busca ampla por textos como `port 23`, que podia capturar versões e outros números do log.
- A porta é detectada primeiro pelo socket realmente aberto pelo PID ou por seus processos filhos.
- A porta validada é salva nos metadados e reutilizada na tela **Projetos em execução**.
- O log permanece somente como fallback estrito; se necessário, usa-se a porta padrão do framework.

## 1.0.38 — 2026-08-06

- Progresso da importação agora avança durante a análise e a cópia.
- O contador exibe incrementos reais, como `10/254`, `20/254` e `30/254`.
- A cópia com `rsync` passa a acompanhar arquivos processados, com fallback pela porcentagem global.
- O arquivo atual é exibido no painel sempre que disponível.

## [1.0.41] - 2026-08-06

### Adicionado
- Nova opção **Ferramentas instaladas** em **Instalar ferramentas**.
- Lista somente ferramentas realmente detectadas no Termux.
- Organização por linguagens, web, Java, shells e editores, compilação, bancos e utilitários.
- Exibição da versão detectada de cada ferramenta.
- Resumo com total de ferramentas reconhecidas e total de pacotes instalados no Termux.

## [1.0.40] - 2026-08-06

### Corrigido
- Restauradas as funções globais `pid_ativo` e `limpar_pidfiles_inativos`.
- Remoção automática de PID files inválidos ou pertencentes a processos encerrados.
- Corrigida a função `porta_processo`, que chamava a si mesma ao tentar salvar a porta.
- A tela principal e a página de processos ativos voltam a abrir sem `command not found`.

## [1.0.37] - 2026-08-06

### Corrigido
- Reinício após atualização não envia mais SIGTERM para o próprio Manager.
- O bloqueio de instância é liberado antes do `exec`, permitindo que a nova versão assuma normalmente no Fish e no Bash.

## [1.0.36] - 2026-08-06

### Corrigido
- O painel de importação agora substitui `calculando...` pelos valores finais ao atingir 100%.
- Projetos concluídos em menos de três segundos passam a mostrar velocidade média e tempo total.
- O tempo estimado final agora aparece como `total`, evitando um estado visual incompleto.

## [1.0.35] - 2026-08-06

### Corrigido
- Corrigida a mensagem final da importação que chamava a função inexistente `success`.
- O fluxo agora usa a função visual padrão `ok`, exibe a confirmação e retorna ao menu sem erro.

## [1.0.34] - 2026-08-06

### Correção de importação
- Corrigido encerramento indevido do Manager ao terminar uma importação de projeto.
- O problema não era causado pelo `rsync`: havia um `exit 0` fixo ao final do fluxo de cópia.
- Após uma importação bem-sucedida, o Manager agora exibe a confirmação e retorna ao menu de importação.
- Instalar o `rsync` durante a operação não encerra mais o aplicativo.

## [1.0.33] - 2026-08-06

### Documentação e manutenção
- README totalmente consolidado para refletir o estado atual do Manager, sem blocos históricos duplicados.
- Todas as referências fixas de versão foram sincronizadas com a release atual.
- Padrão de release revisado com checklist de arquivos, validação e publicação.
- Changelog normalizado em um único formato e mantido como fonte do histórico detalhado.
- Cabeçalhos antigos dos módulos deixaram de carregar números de versão desatualizados.
- Manifesto e hashes regenerados após a sincronização documental.

## [1.0.32] - 2026-08-06

- Novo Centro de exclusão do Painel acessível por Gerenciar projetos e Configurações.
- Permite excluir um projeto individual, limpar apenas o conteúdo de `~/Painel/projetos`, excluir/recriar a pasta `projetos` ou apagar todo o `Painel`.
- Backup opcional antes das exclusões da coleção de projetos.
- Resumos exibem quantidade de itens, tamanho e exatamente o que será preservado.
- Confirmações por palavra-chave diferentes conforme o nível de risco.

## [1.0.31] - 2026-08-06

- Eliminado globalmente o efeito de menus sendo desenhados linha por linha.
- Adicionado buffer de renderização para telas compostas por vários helpers.
- Cabeçalhos, caixas, conteúdo e rodapés agora aparecem juntos antes da interação.
- Compatibilidade mantida com telas antigas, assistentes, confirmações e páginas especiais.
- Mensagens de progresso liberam o buffer automaticamente antes de operações demoradas.

## [1.0.30] - 2026-08-06

### Menu
- **Instalar ferramentas** foi movido do submenu Ambiente Termux para o menu principal.
- O acesso a pacotes Web, Java, Python, PHP, compilação, bancos, arquivos e editores agora fica visível logo na tela inicial.
- O submenu Ambiente Termux foi simplificado para atualização de pacotes, armazenamento, diagnóstico e manutenção.

## [1.0.29] - 2026-08-06

### Interface
- O menu principal agora é montado completamente em memória antes de ser exibido.
- Cabeçalho, opções e rodapé aparecem de uma só vez, sem o efeito de linhas “caindo” na tela.
- A melhoria também beneficia os demais menus que usam a interface unificada.

## [1.0.28] - 2026-08-06

### Corrigido
- A página Sobre não apaga mais as informações ao desenhar o menu de ações.
- Informações e ações agora ficam reunidas em uma única tela estável.
- Caminhos longos são reduzidos para evitar texto cortado e bordas quebradas.

## [1.0.27] - 2026-08-06

### Alterado
- Substituída a confirmação simples `(s/N)` por uma tela visual integrada ao Manager.
- Adicionadas opções para atualizar agora, ver detalhes técnicos ou cancelar.
- O resumo exibe versões, nome e tamanho do pacote, backup e reinício automático.

## [1.0.26] - 2026-08-06

### Melhorias
- O histórico de versões não usa mais o paginador `less`, eliminando a indicação confusa `(END)`.
- Novo leitor interno com páginas numeradas e comandos visíveis para avançar, voltar ou retornar à página Sobre.
- Ao chegar à última página, `ENTER` retorna automaticamente ao menu.

## [1.0.25] - 2026-08-06

### Melhorias
- A tela de atualização completa agora permanece fixa e altera somente o texto da etapa atual, sem limpar ou recarregar toda a página.
- Adicionada barra de progresso visual com percentual por etapa.
- O resumo pré-instalação informa tamanho do ZIP, tamanho extraído, quantidade de arquivos, espaço livre e estimativa do backup.
- A atualização verifica previamente se existe espaço seguro para pacote, cópias temporárias e backup.

## [1.0.24] - 2026-08-06

### Alterado
- Página **Sobre** redesenhada com identidade, versão, canal, desenvolvedor e licença.
- Inclusão do repositório oficial `adriedsonlemoz/TermuxManager`.
- Exibição do diretório instalado, shell atual, configuração e estado do comando global.
- Novas ações para abrir o GitHub, consultar o changelog e exibir o endereço do projeto.
- Remoção das instruções antigas de instalação da página Sobre.

## [1.0.23] - 2026-08-06

- Comando global `manager` oferecido durante a configuração inicial.
- Atalho curto opcional `mm`.
- Atalhos instalados em `$PREFIX/bin`, compatíveis com Bash e Fish.
- Novo submenu **Configurações → Atalhos do Manager** para instalar, reparar, verificar e remover atalhos.
- Atualizações completas reparam automaticamente os atalhos existentes.
- Desinstalação remove com segurança apenas atalhos criados pelo Manager.

## [1.0.22] - 2026-08-06

- README atualizado para localizar automaticamente o pacote mais recente em Downloads usando o padrão `manager-v*.zip`.
- `chmod +x` removido do fluxo principal de instalação e mantido apenas como solução de emergência.
- Instalação inicial passa a executar o Manager com `bash`, permitindo que ele aplique internamente as permissões necessárias.

## [1.0.21] - 2026-08-06

- README revisado para instalação limpa usando `manager-v1.0.21.zip`.
- Documentação atualizada para reinício automático após atualização.
- Inclusão das rotinas de manutenção, desinstalação, Fish e padrão oficial de release.
- Correção da estrutura esperada do ZIP, sem pasta duplicada.

## [1.0.20] - 2026-08-06

### Adicionado
- Padrão oficial de publicação no GitHub.
- Nome de pacote `manager-vX.Y.Z.zip`.
- Geração automática de checksum SHA-256.
- Script de empacotamento em `tools/build-release.sh`.
- Identificação visual de pacotes padronizados no atualizador.

### Mantido
- Compatibilidade com pacotes ZIP antigos, mesmo sem nome padronizado.
