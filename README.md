# Termux Manager

Gerenciador modular de projetos para **Termux no Android**, desenvolvido por **Adriedson Aparecido Lemos**.

O Termux Manager organiza, importa, prepara, executa e mantém projetos locais por meio de uma interface de terminal com menus estáveis, progresso em tempo real, logs, backups, atalhos globais e controle de processos.

**Versão atual:** 1.0.70  

### Pós-importação direto ao projeto (1.0.64)

Depois de uma importação bem-sucedida, o Manager não obriga mais o retorno ao menu principal. É possível **testar o projeto recém-importado**, **abrir seu menu de gerenciamento**, **importar outro projeto** ou voltar ao início. O caminho usado é exatamente o destino da cópia.

A análise de arquivos também foi dividida em duas fases. Enquanto o total ainda é desconhecido, a tela mostra quantos arquivos foram encontrados sem inventar uma porcentagem. Depois, com o total conhecido, exibe o percentual real de cálculo de tamanho antes de iniciar a cópia.


### Isolamento por caminho do projeto (1.0.63)

O runtime, processos e caches distinguem cada projeto pelo caminho canônico. Assim `~/Painel` e `~/Painel/projetos/<nome>` permanecem isolados mesmo quando possuem pastas `backend`/`frontend` semelhantes. O teste integrado também rotaciona logs no início e o relatório de erro informa os diretórios efetivamente resolvidos. A validação npm considera dependências de topo e registra o pacote/etapa responsável quando houver inconsistência.

**Canal:** Estável  
**Repositório:** https://github.com/adriedsonlemoz/TermuxManager

### Identificação de projetos

O Manager usa o **nome da pasta** como identidade padrão do projeto. O campo `name` do `package.json` é mantido como informação técnica e para apoio à detecção da stack. Em **Gerenciar projetos → Nome de exibição**, é possível definir um apelido sem modificar o projeto; ele é salvo em `~/.termux-manager/projects/`.

## Painel de teste integrado
Ao executar frontend + backend juntos, o Manager usa um painel único com quatro etapas (Backend, Frontend, Inicialização e Disponibilidade). Status, avisos, PID, logs e detecção de servidor permanecem dentro da moldura visual durante a execução. Quando uma etapa falha, o painel é encerrado corretamente e o Manager oferece **Coletar logs do teste**, gerando em Downloads um único TXT sanitizado com logs de backend, frontend, Manager e metadados de processo.


## Recursos principais

- importação de pastas, arquivos e ZIPs;
- progresso de análise e cópia com contador de arquivos, velocidade e tempo;
- descoberta de projetos em `~/Painel` e `~/Painel/projetos`;
- detecção de frontend, backend, fullstack e monorepos;
- instalação de dependências com feedback visual e cache por assinatura;
- execução conjunta ou separada de componentes;
- detecção de portas pelo PID e processos filhos;
- registro de PIDs, portas e logs;
- Central de Diagnóstico com erros numerados do Manager, projetos e Termux;
- exportação sanitizada de um erro, log completo ou pacote de suporte;
- abertura automática do navegador;
- instalação e inventário de ferramentas do Termux;
- configuração completa e limpeza segura do Fish Shell;
- atalhos globais `manager` e `mm`;
- atualização completa ou de módulo com backup e validação;
- manutenção, restauração e desinstalação segura;
- Centro de exclusão do Painel com vários níveis de remoção;
- renderização atômica dos menus, sem linhas “caindo” ou prompts sobrepostos.

## Primeira instalação

A instalação recomendada foi simplificada para **um único comando**. Você não precisa baixar o ZIP manualmente, procurar o arquivo em Downloads nem executar vários comandos de extração.

### 1. Instale o Termux

Escolha **uma** das opções abaixo. Evite misturar o aplicativo principal e complementos do Termux vindos de fontes diferentes.

#### Opção A — Termux pelo GitHub

Página oficial:

**https://github.com/termux/termux-app/releases**

1. Abra a release estável mais recente.
2. Em **Assets**, baixe o APK compatível com seu Android/aparelho.
3. Instale o APK e abra o Termux.
4. Aguarde a preparação inicial terminar.

> Se usar Termux:API, Termux:Widget, Termux:Boot ou outros complementos, mantenha-os em uma origem compatível com a instalação principal.

#### Opção B — Termux pelo Google Play

Página oficial:

**https://play.google.com/store/apps/details?id=com.termux**

1. Instale o Termux pelo Google Play.
2. Abra o aplicativo e aguarde a preparação inicial terminar.
3. Depois execute o comando de instalação do Manager mostrado abaixo.

A edição do Google Play é mantida separadamente da edição GitHub/F-Droid e atualmente exige **Android 11 ou superior**. Alguns recursos e complementos podem ter diferenças. Informações dessa edição:

**https://github.com/termux-play-store**

### 2. Instale o Termux Manager com um comando

No Termux, copie e execute **esta linha inteira**:

```bash
pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/adriedsonlemoz/TermuxManager/main/install.sh | bash
```

Pronto. O instalador oficial faz automaticamente o restante:

1. baixa a versão estável diretamente da branch `main` do repositório;
2. instala `unzip`/ferramentas básicas se estiverem faltando;
3. extrai o projeto e confere a versão declarada;
4. valida os hashes de todos os arquivos listados em `MANIFEST.json`;
5. valida `manager.sh` e os módulos com `bash -n`;
6. instala em `~/scripts/manager`;
7. preserva um backup se já existir uma instalação;
8. abre o Termux Manager.

Esse fluxo **não depende de uma GitHub Release publicada**. Enquanto `main` for o canal estável do projeto, o comando acima continua funcionando mesmo que a página de Releases esteja vazia.

Na primeira abertura, o próprio Manager solicita acesso ao armazenamento, atualiza o ambiente, instala as ferramentas recomendadas e configura o comando global `manager`.

Depois da configuração inicial, basta abrir com:

```bash
manager
```

### Instalação manual (alternativa)

Use esta opção apenas se não quiser executar o instalador automático.

Abra o repositório:

**https://github.com/adriedsonlemoz/TermuxManager**

Use **Code → Download ZIP** para baixar a cópia atual da branch `main`. Depois extraia o conteúdo e execute `manager.sh`. Esse método é destinado a instalação manual; o comando automático acima continua sendo o método recomendado porque também valida o `MANIFEST.json` e cria backup de uma instalação anterior.

## Menu principal

- **Gerenciar projetos:** listar, abrir, executar, copiar, excluir e limpar o Painel.
- **Em execução:** acompanhar processos, portas, logs e parar componentes.
  - 🟢 servidor disponível: PID ativo e porta realmente respondendo;
  - 🟡 processo ativo: PID existe, mas a porta não abriu ou o log indica falha;
  - 🔴 encerrado: PID não existe mais e os metadados são limpos.
- **Importar projeto:** importar pasta, arquivos ou ZIP por assistente.
- **Instalar ferramentas:** instalar pacotes e listar somente as ferramentas já detectadas.
- **Ambiente Termux:** armazenamento, atualização, diagnóstico e manutenção.
- **Atualizar Manager:** atualizar o pacote completo ou um módulo.
- **Configurações:** aparência, caminhos, execução, Fish, atalhos, diagnóstico e manutenção.
- **Sobre:** versão, ambiente, repositório e changelog.
- **Ajuda:** manual resumido e atualizado dentro do aplicativo.

## Importação de projetos

A origem padrão da importação é sempre a própria pasta **Downloads**. O Manager não entra automaticamente em `Downloads/projetos`, então um ZIP recém-baixado aparece imediatamente na lista sem precisar ser movido antes.

O assistente permite:

- importar uma pasta inteira;
- selecionar arquivos soltos;
- extrair um ZIP;
- copiar o conteúdo sem manter a pasta externa;
- escolher `~/Painel` ou `~/Painel/projetos` como destino;
- substituir, ignorar, renomear ou confirmar conflitos individualmente.

Durante análise e cópia, o painel avança em tempo real:

```text
10/254 arquivos
20/254 arquivos
30/254 arquivos
...
254/254 arquivos
```

Ao terminar, mostra velocidade média, tempo total, arquivos copiados e pastas criadas. Depois de `ENTER`, retorna ao menu de importação sem encerrar o Manager.

Caminhos exibidos pela interface são abreviados a partir de `$HOME`: por exemplo, `/data/data/com.termux/files/home/Painel/.logs/app.log` aparece como `~/Painel/.logs/app.log`. Caminhos absolutos continuam sendo usados internamente pelos comandos.

## Execução, dependências e portas

O Manager detecta comandos de execução e gerenciadores de dependências. Em projetos fullstack, frontend e backend são tratados separadamente. O painel vivo de teste mantém largura fixa durante toda a execução; mensagens menores apenas recebem espaço interno e não deslocam a borda da caixa.

Antes de instalar dependências, o Manager verifica se elas já estão presentes. A assinatura dos manifests/lockfiles fica fora do projeto, em `~/.termux-manager/dependencies/`, para sobreviver a atualizações que substituam arquivos do projeto. Se ainda não houver assinatura, `node_modules`/`vendor` existentes são verificados antes de qualquer reinstalação.

A detecção de porta:

1. procura sockets associados ao PID e aos processos filhos;
2. valida a porta encontrada;
3. usa o log apenas como fallback estrito com `:porta` explícita;
4. grava a porta validada nos metadados do processo;
5. reutiliza o mesmo valor na página **Em execução**.

Isso evita interpretar números de IP, versões ou mensagens do log como portas.

## Ferramentas instaladas

Em **Instalar ferramentas → Ferramentas instaladas**, o Manager exibe apenas comandos realmente encontrados no Termux, com versão quando disponível.

Categorias:

- linguagens: Python, PHP, Ruby, Go, Rust e outras;
- web: Node.js, npm, pnpm, Yarn, Composer e Git;
- Java: Java, Javac, Gradle e Maven;
- shells e editores: Fish, Bash, Zsh, Nano, Micro, Vim e Neovim;
- compilação: Clang, GCC, Make, CMake e pkg-config;
- bancos: SQLite, PostgreSQL, MariaDB, Redis e Mongo Shell;
- utilitários: curl, wget, rsync, ZIP, jq, OpenSSL, SSH e tmux.

Ferramentas ausentes ficam ocultas.

## Fish Shell

Em **Configurações → Fish Shell**, é possível:

- instalar o Fish;
- defini-lo como shell padrão;
- ativar autosugestões e completações;
- configurar prompt, Git, histórico e atalhos;
- ocultar os banners do Termux e do Fish;
- mostrar mensagem de boas-vindas personalizada;
- mostrar o tempo total da sessão ao sair;
- restaurar o Bash;
- limpar somente as configurações do shell.

A limpeza do Fish não remove Python, Node.js, PHP, Git, projetos ou outros pacotes.


## Interface responsiva

A interface usa a largura real disponível no terminal. As caixas deixam apenas uma pequena margem lateral de segurança e se adaptam a celulares, rotação de tela, tablets e terminais maiores. Painéis de operações longas congelam a largura durante a execução para impedir que a borda direita varie conforme o tamanho das mensagens.

## Atalhos globais

O comando principal é instalado em:

```text
$PREFIX/bin/manager
```

Ele funciona em Bash e Fish. O submenu **Atalhos do Manager** permite instalar, reparar, verificar e remover `manager` e `mm`.

## Centro de exclusão do Painel

Disponível em:

```text
Gerenciar projetos → Limpeza do Painel
Configurações → Limpeza do Painel
```

Permite:

1. excluir um projeto individual;
2. limpar o conteúdo de `~/Painel/projetos`, preservando a pasta;
3. excluir e recriar `~/Painel/projetos` vazia;
4. excluir todo o `~/Painel`.

Antes de ações coletivas, o Manager mostra quantidade, tamanho e conteúdo afetado, oferece backup opcional e exige confirmação proporcional ao risco.

Backups de projetos são exportados para `Download/projetos/backups`. O Manager ignora dependências e artefatos regeneráveis como `node_modules`, `.git`, caches, `dist`, `build`, ambientes virtuais e diretórios equivalentes. A cópia temporária é removida do Termux somente depois que o arquivo em Downloads é validado por SHA-256.

## Atualizações

O padrão oficial é:

```text
Versão: 1.0.70
Tag: v1.0.70
Release: Manager 1.0.70
Pacote: manager-v1.0.70.zip
Checksum: manager-v1.0.70.sha256
```

### Transição da versão 1.0.44

A versão 1.0.44 possui uma falha no próprio processo de atualização: ao chegar em **Etapa 5 de 5**, a saída pode ficar presa no buffer da interface. O pacote é aplicado, mas o Manager reiniciado fica invisível no terminal.

Para instalar a 1.0.45 uma única vez, feche a execução presa com `Ctrl+C` e atualize diretamente da pasta Downloads:

```bash
unzip -o ~/storage/downloads/manager-v1.0.45.zip -d ~/scripts/manager
manager
```

A partir da 1.0.45, as próximas atualizações podem voltar a ser feitas normalmente pelo menu interno.

Na atualização completa, o Manager:

1. identifica e valida o ZIP;
2. mostra versão atual e nova;
3. informa tamanho compactado, tamanho extraído e quantidade de arquivos;
4. verifica espaço livre e estimativa do backup;
5. cria backup da instalação;
6. aplica a atualização em uma tela fixa;
7. registra a atualização sem recriar atalhos desnecessariamente;
8. restaura a saída, o cursor e o estado do terminal;
9. libera o bloqueio da instância antes do reinício;
10. reinicia a nova versão com a saída visível no terminal;
11. exibe uma confirmação pós-atualização, uma única vez, provando que a nova versão está ativa.

## Manutenção do Manager

Em **Configurações → Manutenção do Manager**:

- **Restaurar instalação:** limpa preferências, cache, logs e estado interno, preservando projetos e backups.
- **Desinstalar Manager:** remove o aplicativo e seus atalhos com confirmação reforçada, preservando os projetos do Painel.

## Estrutura principal

```text
~/scripts/manager/
├── manager.sh
├── modules/
│   ├── app.sh
│   ├── config.sh
│   ├── core.sh
│   ├── diagnostics.sh
│   ├── help.sh
│   ├── import.sh
│   ├── projects.sh
│   ├── runtime.sh
│   ├── settings.sh
│   ├── termux.sh
│   ├── ui.sh
│   └── updater.sh
├── tools/build-release.sh
├── README.md
├── CHANGELOG.md
├── RELEASE_STANDARD.md
└── MANIFEST.json
```

## Teste rápido e reimportação

Para ciclos frequentes de copiar um pacote completo e testar novamente, o Manager otimiza o caminho crítico:

- ao **substituir** um projeto, `node_modules` é preservado quando `package.json`/lockfiles continuam iguais;
- dependências já validadas usam cache de integridade leve antes de executar verificações profundas;
- instalações novas priorizam o cache local do npm e desativam audit/fund/progresso durante a preparação;
- no teste do **sistema completo**, backend e frontend sobem em paralelo depois da preparação das dependências;
- a disponibilidade é detectada em intervalos curtos, sem a antiga espera fixa de 1 segundo por processo.

Se os manifestos de dependência mudarem, o Manager não reutiliza `node_modules` antigo e volta automaticamente ao fluxo seguro de instalação/reparo.

## Central de Diagnóstico

Abra **Configurações → Central de Diagnóstico**. A área separa os registros em:

A central também possui **Exportar todos os relatórios**, que cria em Downloads uma pasta datada com `manager/`, `projetos/` e `termux/`, além do **Pacote completo de suporte**, que compacta as mesmas categorias.

- **Manager:** falhas internas capturadas, comandos, arquivo, linha e código de saída;
- **Projetos:** logs de frontend, backend e outros processos iniciados pelo Manager;
- **Termux:** operações do `pkg`/`dpkg`, ambiente, armazenamento e diagnóstico atual.

Dentro de cada arquivo, os padrões de erro aparecem numerados. É possível selecionar um número e copiar somente aquele erro com linhas de contexto para Downloads, ou exportar o log completo.

A opção **Pacote completo de suporte** cria um arquivo com pastas separadas:

```text
manager/
projetos/
termux/
```

Antes de exportar, o Manager remove valores comuns de senhas, tokens, chaves, URLs de banco com credenciais e cabeçalhos de autorização. O arquivo original não é alterado. Ainda assim, revise o relatório antes de compartilhar.

A central cobre os registros do ambiente Termux. Logs internos do Android, como `logcat`, dependem de permissões externas e não são coletados.

Locais principais:

```text
~/Painel/.logs
~/Painel/.logs/diagnostics
~/scripts/manager/logs
~/Painel/projetos
Download/projetos/backups
```

## Solução rápida de problemas

### `manager: command not found`

Abra **Configurações → Atalhos do Manager → Instalar ou reparar atalho**.

### Projeto não inicia

Confira:

- `backend/.env` e `frontend/.env`;
- dependências;
- logs em `~/Painel/.logs`;
- portas exibidas em **Em execução**.

### Downloads não aparece

```bash
termux-setup-storage
```

Depois use **Ambiente Termux → Armazenamento**.

### Atualização não aplicada

Abra **Atualizar Manager → Última atualização** e confira versão, pacote, hash, backup e status.

## Build de release

```bash
cd ~/scripts/manager
bash tools/build-release.sh
```

Os arquivos são gerados em `dist/`.

## Licença

Projeto de uso pessoal e educacional. Defina uma licença explícita no repositório antes de aceitar contribuições externas.


## Saúde de processos — 1.0.48

A existência do PID, sozinha, não significa mais que o servidor está saudável. O Manager revalida a porta antes de exibir o estado verde. Processos como `node --watch` que permanecem vivos após o servidor interno falhar aparecem em amarelo, e o fluxo de sistema completo não inicia o frontend enquanto o backend estiver indisponível.

## Envio simplificado para GitHub

Dentro de **Gerenciar projetos → projeto → Enviar para GitHub**, o Manager prepara o Git e o GitHub CLI automaticamente. Na primeira publicação ele instala `git`/`gh` se necessário, conduz o login oficial do GitHub, cria um `.gitignore` de proteção, inicializa o repositório local, configura uma identidade Git local com o endereço `noreply` do GitHub e pergunta apenas o nome do repositório e a visibilidade (privado por padrão). Depois disso, os próximos envios reutilizam o repositório remoto e normalmente exigem apenas a mensagem do commit.

O Manager **não usa `push --force` automaticamente**. Se o remoto tiver histórico diferente, o envio é interrompido e o usuário recebe orientação para sincronizar primeiro. Arquivos sensíveis comuns (`.env`, `.npmrc`, chaves privadas, credenciais) são ignorados por padrão; se algum deles já estiver rastreado pelo Git, o envio é bloqueado até ser removido do índice. Quando o projeto é a raiz `~/Painel`, estados internos do Manager e `~/Painel/projetos` também ficam fora da publicação.


### Reparo automático de dependências

No teste de projetos Node, o Manager valida `node_modules` antes de reutilizar o cache. Se detectar uma instalação inconsistente ou se o servidor falhar com `MODULE_NOT_FOUND`, a assinatura é invalidada e o Manager tenta um reparo limpo uma única vez. Projetos com lockfile usam `npm ci`; sem lockfile, `node_modules` é recriado com `npm install`.
