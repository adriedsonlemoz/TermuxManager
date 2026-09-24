# Termux Manager

Gerenciador modular de projetos para **Termux no Android**, desenvolvido por **Adriedson Aparecido Lemos**.

O Termux Manager organiza, importa, prepara, executa e mantém projetos locais por meio de uma interface de terminal com menus estáveis, progresso em tempo real, logs, backups, atalhos globais e controle de processos.

**Versão atual:** 1.0.91  

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
- instalação e gerenciamento de distribuições Linux sem root com `proot-distro`;
- configuração assistida do Termux:X11 com múltiplos ambientes gráficos;
- diagnóstico de RAM, CPU e espaço com orientação de desempenho antes de usar Linux gráfico;
- configuração completa e limpeza segura do Fish Shell;
- atalhos globais `manager` e `mm`;
- atualização completa ou de módulo com backup e validação;
- manutenção, restauração e desinstalação segura;
- Centro de exclusão do Painel com vários níveis de remoção;
- renderização atômica dos menus, sem linhas “caindo” ou prompts sobrepostos.

## Primeira instalação

A instalação principal usa **um único comando**, depois de liberar o armazenamento do Android. Você não precisa baixar o ZIP manualmente, procurar o arquivo em Downloads nem executar comandos de extração.

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

O instalador e a configuração inicial do Manager agora **detectam automaticamente** se o Termux em uso é da **Google Play** ou da linha **GitHub/F-Droid**, registram essa origem nos diagnósticos e adaptam a instalação das ferramentas recomendadas quando um pacote não existir naquela variante.

**https://github.com/termux-play-store**

### 2. Libere o acesso ao armazenamento

Antes de instalar o Manager pela primeira vez, abra o Termux e execute:

```bash
termux-setup-storage
```

Quando o Android solicitar, **autorize o acesso aos arquivos**. Esse passo cria os atalhos de armazenamento usados pelo Manager para Downloads, backups, diagnósticos e importação de projetos.

> O instalador também tenta executar `termux-setup-storage` automaticamente quando o acesso ainda não estiver disponível, mas a confirmação da permissão continua dependendo do usuário no Android.

### 3. Instale o Termux Manager com um comando

Se `curl` ainda não existir no seu Termux, execute uma vez:

```bash
pkg install -y curl
```

Depois copie e execute **esta linha inteira**:

```bash
curl -fsSL https://raw.githubusercontent.com/adriedsonlemoz/TermuxManager/main/install.sh | bash
```

Pronto. O instalador oficial faz automaticamente o restante:

1. verifica se o acesso ao armazenamento Android já foi liberado e chama `termux-setup-storage` quando necessário;
2. baixa a versão estável diretamente da branch `main` do repositório;
3. verifica se `unzip`/ferramentas básicas já existem antes de instalar qualquer pacote;
4. se outro `apt`/`dpkg` estiver trabalhando, aguarda a liberação e mostra apenas um status controlado, sem repetir dezenas de linhas de `Waiting for cache lock`;
5. extrai o projeto e confere a versão declarada;
6. valida os hashes de todos os arquivos listados em `MANIFEST.json`;
7. valida `manager.sh` e os módulos com `bash -n`;
8. instala em `~/scripts/manager`, preservando backup da instalação anterior;
9. abre o Termux Manager.

Esse fluxo **não depende de uma GitHub Release publicada**. Enquanto `main` for o canal estável do projeto, o comando acima continua funcionando mesmo que a página de Releases esteja vazia.

> O comando recomendado não executa mais `pkg install curl` toda vez. Se o seu Termux realmente não tiver `curl`, instale-o uma única vez com `pkg install curl` e repita o comando.

Na primeira abertura, o Manager confirma o acesso ao armazenamento, atualiza o ambiente, instala as ferramentas recomendadas e configura o comando global `manager`.

A primeira configuração é retomável: cada etapa concluída é salva. Se uma instalação de pacote ficar sem novas mensagens, o Manager continua mostrando **tempo decorrido** e **tempo desde a última atividade** em vez de parecer congelado. `Ctrl+C` durante uma instalação monitorada não fecha mais o Manager; abre opções para **tentar novamente**, **pular o pacote** ou **retomar depois**. Ao abrir novamente, etapas já concluídas e pacotes já instalados não são repetidos.

Durante a instalação de ferramentas, o Manager também distingue pacotes **já instalados**, **ausentes** e **indisponíveis na variante atual do Termux**. Pacotes que não existirem naquela edição são marcados como indisponíveis e não derrubam o assistente de configuração.

Após a atualização inicial do Termux, o assistente agora mostra uma mensagem explícita informando que a etapa terminou e que a próxima fase continuará automaticamente. Isso evita a sensação de travamento naquela tela de resumo/log.

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

O menu principal usa um modelo híbrido: as funções mais usadas ficam visíveis diretamente e apenas as opções realmente secundárias permanecem agrupadas. Isso evita a sensação de ficar procurando funções em vários submenus.

As opções principais são:

- **Gerenciar projetos:** abrir, testar e organizar os projetos detectados.
- **Em execução:** visualizar processos, serviços e portas ativos.
- **Importar projeto:** importar pasta, arquivo ou ZIP.
- **Linux no celular:** acesso direto a distribuições, PRoot e Termux:X11.
- **Ambiente e ferramentas:** instalação de ferramentas, manutenção do Termux e diagnóstico rápido.
- **Atualizar Manager:** atualização pela branch `main`, ZIP local ou módulo individual.
- **Configurações:** preferências e manutenção.
- **Ajuda e Sobre:** manual, versão e informações do desenvolvedor.

O cabeçalho também mostra um resumo curto da origem do Termux, quantidade de projetos e componentes ativos.

### Atualização direta pela branch `main`

Em **Manager → Atualizar Manager → Verificar no GitHub**, o Manager consulta diretamente a branch `main` do repositório oficial. Não é necessário criar Releases ou tags manualmente para esse fluxo.

Quando existe uma versão mais nova, o Manager:

1. compara a versão instalada com `MANIFEST.json` da `main`;
2. mostra a nova versão e o trecho correspondente do `CHANGELOG.md`;
3. pede confirmação antes de modificar qualquer arquivo;
4. baixa o ZIP da branch `main`;
5. valida todos os hashes declarados em `MANIFEST.json` e a sintaxe dos scripts;
6. cria backup da instalação atual;
7. sincroniza código, documentação, instalador e ferramentas auxiliares;
8. reinicia automaticamente na nova versão.

Se a consulta falhar ou a integridade do pacote não conferir, a instalação atual permanece intacta. A atualização por ZIP em Downloads continua disponível como alternativa.

Durante a consulta ao GitHub, o Manager agora mantém uma tela de atividade visível com estados como **Conectando ao GitHub**, **Carregando informações**, **Baixando atualização** e **Validando pacote**. Em conexões lentas, o tempo de espera continua sendo atualizado e o download mostra quantidade baixada e velocidade média aproximada, reduzindo a impressão de travamento.

Nenhuma função foi removida; apenas as funções relacionadas passaram a ficar agrupadas em submenus.

As descrições exibidas abaixo das opções de menu são resumidas automaticamente para telas móveis. Quando precisam ser reduzidas, o corte procura terminar em uma palavra completa para evitar textos quebrados no meio.

## Linux no celular

A interface de Linux prioriza uso leigo: distribuições instaladas são detectadas automaticamente e todas as ações principais usam **seleção numerada**, sem exigir que o usuário memorize aliases. A instalação oferece Ubuntu 24.04, Debian 12, Alpine, Fedora, openSUSE e Rocky Linux como atalhos, além de pesquisa opcional no Docker Hub. Referências OCI com versão, como `ubuntu:24.04`, são aceitas corretamente.

A área **Meus Linux** centraliza as distribuições já instaladas. A lista mostra nome do sistema, estado da sessão, saúde, arquitetura, tamanho atual e desktops detectados. Ao selecionar uma distro, o Manager abre um painel próprio com **Iniciar terminal**, **Desktop/X11**, **Atualizar sistema**, **Criar backup**, **Informações completas**, **Encerrar sessões**, **Reparar/reinstalar** e **Remover**.

O tamanho do rootfs é medido localmente e fica em cache curto para evitar percorrer milhares de arquivos a cada abertura do menu. A saúde também é testada com `/bin/sh`. Quando o teste falha, o Manager mostra uma causa curta na lista — por exemplo **Arquitetura**, **QEMU**, **Loader ausente**, **Ambiente PRoot** ou **Timeout** — e oferece um diagnóstico completo.

O diagnóstico diferencia **geração da CPU** (por exemplo ARMv8), **ABI do Android** (`armeabi-v7a`/`arm64-v8a`), **arquitetura usada pelo Termux** (`arm`/`aarch64`) e **32/64 bits do processo**. Assim, um aparelho pode possuir CPU ARMv8 e ainda executar um Termux 32-bit; nesse caso as distros nativas continuam seguindo a arquitetura real do Termux.

Mensagens conhecidas do PRoot são interpretadas em português na tela, com uma orientação curta do que verificar. Na exportação para Downloads, o relatório mantém primeiro a interpretação em português e preserva o erro técnico original em uma seção separada, para facilitar suporte e pesquisa.

A opção **Ambiente PRoot** diagnostica separadamente o motor usado pelas distros: verifica os comandos `proot`/`proot-distro`, versões instaladas, a pasta temporária interna do Termux e executa um teste com o shell nativo do próprio Termux. O reparo reinstala apenas esses componentes, invalida diagnósticos antigos e **não apaga as distribuições instaladas**.

A opção **Restaurar backup** procura arquivos compatíveis na pasta Downloads, mostra distro, tamanho e data antes da restauração e usa o `proot-distro restore`. Se a distro do backup já existir, o Manager oferece criar primeiro um novo backup de segurança da instalação atual. O arquivo original em Downloads é preservado.

O cache de saúde guarda também o motivo da falha. Caches antigos que só sabiam “Problema” são reavaliados automaticamente para produzir um diagnóstico explicativo. Na tentativa de iniciar uma distro com falha, o usuário pode **Ver diagnóstico**, **Testar novamente** ou **Reparar/reinstalar**.

Quando nenhuma distribuição estiver instalada, **Meus Linux** oferece abrir a instalação imediatamente, em vez de pedir um alias inexistente.

Em **Linux no celular**, acessível diretamente pelo menu principal, o Manager pode preparar uma distribuição Linux sem exigir root. O fluxo usa o `proot-distro` instalado pelo próprio Termux e consulta dinamicamente a lista de distribuições disponíveis, em vez de manter uma lista fixa no código.

O submenu permite:

- analisar RAM, CPU, arquitetura, Android e espaço livre antes da instalação;
- verificar **antes do download** se a imagem selecionada publica uma variante OCI compatível com a arquitetura do aparelho;
- forçar explicitamente a arquitetura escolhida no `proot-distro install` e executar um teste pós-instalação para evitar containers com `Exec format error`;
- classificar o aparelho em perfil **Básico**, **Intermediário** ou **Desktop**, sempre como estimativa orientativa;
- instalar `proot-distro` quando necessário;
- listar e instalar distribuições disponíveis;
- administrar cada distro por um painel próprio com tamanho, arquitetura, imagem de origem, estado, saúde, gerenciador de pacotes e desktops instalados;
- iniciar uma distribuição em modo terminal ou desktop;
- atualizar os pacotes do sistema usando APT, Pacman, APK, DNF ou Zypper;
- criar backup completo em Downloads pelo `proot-distro backup`;
- restaurar backups encontrados em Downloads pelo `proot-distro restore`, com confirmação antes de substituir uma distro existente;
- encerrar sessões ativas pelo `proot-distro kill`;
- diagnosticar e reparar o ambiente PRoot sem remover as distros instaladas;
- resetar/reinstalar ou remover uma distribuição com confirmações reforçadas;
- instalar `x11-repo` e `termux-x11-nightly`;
- baixar o APK oficial nightly do Termux:X11 para Downloads e abrir o instalador do Android;
- escolher entre **XFCE, LXQt, LXDE, MATE, Openbox, i3, KDE Plasma e GNOME**;
- classificar cada ambiente como muito leve, leve, médio, pesado ou muito pesado e destacar os mais indicados para o perfil do aparelho;
- instalar ambientes gráficos automaticamente em distribuições com `apt`, `pacman`, `apk`, `dnf` ou `zypper`, usando alternativas de pacote/grupo quando necessário;
- detectar os ambientes já instalados e evitar reinstalações desnecessárias;
- permitir **mais de um desktop na mesma distribuição** e escolher qual iniciar;
- iniciar o desktop selecionado usando Termux:X11 e `--shared-tmp`;
- tratar KDE Plasma e GNOME como opções avançadas, mostrando avisos de consumo e limitações do PRoot antes da instalação;
- encerrar a sessão X11 e consultar orientações para tela preta, cores trocadas ou lentidão.

O perfil de desempenho é conservador. Em aparelhos com pouca RAM ou pouco armazenamento, o Manager avisa que uma interface gráfica pode apresentar lentidão, encerramentos ou travamentos e recomenda priorizar o modo terminal. O usuário ainda pode continuar se quiser testar.

Antes de baixar uma distribuição do Docker Hub, o Manager também traduz a arquitetura do Termux para a arquitetura OCI correspondente (`aarch64 → arm64`, `arm → arm`, `x86_64 → amd64`, `i686 → 386` e `riscv64 → riscv64`) e consulta as arquiteturas publicadas para a tag escolhida. O resultado aparece como **Compatível**, **Não confirmado** ou **Incompatível nativamente**. Quando a imagem é confirmada como incompatível, o download é bloqueado para evitar desperdício de dados e armazenamento. Se a consulta não puder ser confirmada, o usuário ainda pode prosseguir e o `proot-distro` fará a validação durante a instalação. As consultas bem-sucedidas ficam em cache local por algumas horas para evitar chamadas repetidas.

O Termux:X11 possui duas partes: o pacote companion dentro do Termux e o aplicativo Android. O Manager instala automaticamente a parte do Termux e pode baixar o APK oficial, mas a confirmação final de instalação continua sendo feita pelo Android.

A recomendação do desktop acompanha o perfil calculado pelo Manager: aparelhos básicos priorizam LXDE/Openbox/i3; intermediários destacam XFCE/LXQt; aparelhos com mais margem recebem XFCE/LXQt/MATE como opções recomendadas e podem testar KDE Plasma. GNOME continua disponível como opção avançada, pois costuma depender mais de serviços de sistema que não existem normalmente em PRoot.

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

## Ferramentas e ambientes de desenvolvimento

O menu **Instalar ferramentas** foi organizado por ambientes: **Web, Python, Java, Go, Rust, Ruby, PHP, Compilação, Bancos de dados, Arquivos e Terminal**. A tela principal mostra se cada ambiente está completo, incompleto ou ausente.

A opção **Recomendado** analisa os projetos existentes em `~/Painel` procurando `package.json`, `requirements.txt`, `pyproject.toml`, `composer.json`, `go.mod`, `Cargo.toml`, `pom.xml` e arquivos Gradle. Depois oferece instalar **somente as ferramentas que realmente estão faltando**.

Instalações com vários pacotes são tentadas primeiro **em lote**, reduzindo chamadas repetidas ao `apt/pkg`; se o lote falhar, o Manager faz fallback individual para identificar o pacote problemático. Instalações automáticas solicitadas pelos módulos de projeto/GitHub também usam o mesmo instalador robusto.

Em **Instalar ferramentas → Ferramentas instaladas**, o Manager abre um painel dos principais ambientes de desenvolvimento. Cada ambiente mostra se está **completo, incompleto ou ausente**, quais comandos faltam e as versões reais dos componentes detectados. É possível entrar no ambiente e instalar somente o que estiver faltando. A lista completa de ferramentas continua disponível em uma opção separada.

A detecção prioriza o **comando realmente funcional** antes de considerar um pacote ausente. Isso evita pedir novamente `nodejs`, Java, Rust ou outras ferramentas quando uma versão equivalente já fornece os comandos necessários.

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
Versão: 1.0.91
Tag: v1.0.91
Release: Manager 1.0.91
Pacote único: TermuxManager-v1.0.91.zip
Integridade: MANIFEST.json dentro do próprio pacote
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
│   ├── linux.sh
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

## Painel de projetos

Em **Gerenciar projetos**, cada projeto mostra um resumo rápido da stack, estado do Git e componentes ativos. Ao abrir um projeto, o Manager exibe também tamanho e pasta antes das ações.

A área **Git / GitHub** centraliza o status do repositório, envio de alterações, branches locais e a opção **Atualizar do remoto**. A atualização usa somente avanço rápido (`fast-forward`): se houver arquivos locais alterados ou histórico divergente, o Manager não sobrescreve nem cria merge automaticamente.

## Envio simplificado para GitHub

Dentro de **Gerenciar projetos → projeto → Git / GitHub → Enviar para GitHub**, o Manager prepara o Git e o GitHub CLI automaticamente. Na primeira publicação ele instala `git`/`gh` se necessário, conduz o login oficial do GitHub, cria um `.gitignore` de proteção, inicializa o repositório local, configura uma identidade Git local com o endereço `noreply` do GitHub e pergunta apenas o nome do repositório e a visibilidade (privado por padrão). Depois disso, os próximos envios reutilizam o repositório remoto e normalmente exigem apenas a mensagem do commit.

O Manager **não usa `push --force` automaticamente**. Se o remoto tiver histórico diferente, o envio é interrompido e o usuário recebe orientação para sincronizar primeiro. Arquivos sensíveis comuns (`.env`, `.npmrc`, chaves privadas, credenciais) são ignorados por padrão; se algum deles já estiver rastreado pelo Git, o envio é bloqueado até ser removido do índice. Quando o projeto é a raiz `~/Painel`, estados internos do Manager e `~/Painel/projetos` também ficam fora da publicação.


### Reparo automático de dependências

No teste de projetos Node, o Manager valida `node_modules` antes de reutilizar o cache. Se detectar uma instalação inconsistente ou se o servidor falhar com `MODULE_NOT_FOUND`, a assinatura é invalidada e o Manager tenta um reparo limpo uma única vez. Projetos com lockfile usam `npm ci`; sem lockfile, `node_modules` é recriado com `npm install`.
