# Padrão de versões e publicações do Termux Manager

## Versionamento

O projeto usa Versionamento Semântico: `MAJOR.MINOR.PATCH`.

- **MAJOR:** mudança incompatível ou reestruturação ampla;
- **MINOR:** nova funcionalidade compatível;
- **PATCH:** correção, documentação ou melhoria visual sem quebra de compatibilidade.

Versão atual de referência: `1.0.102`.

## Padrão da release

Para a versão `X.Y.Z`, usar obrigatoriamente:

```text
Versão interna: X.Y.Z
Tag: vX.Y.Z
Título: Manager X.Y.Z
Pacote único: TermuxManager-vX.Y.Z.zip
Integridade: MANIFEST.json dentro do pacote
```

Para a versão atual:

```text
Versão interna: 1.0.102
Tag: v1.0.102
Título: Manager 1.0.102
Pacote único: TermuxManager-v1.0.102.zip
Integridade: MANIFEST.json dentro do pacote
```

Nunca reutilizar uma tag ou substituir silenciosamente o arquivo de uma versão publicada. Qualquer correção exige novo número.

## Arquivos que devem ser sincronizados

Antes de publicar, conferir:

- `MANAGER_VERSION` e cabeçalho em `manager.sh`;
- versão e release em `MANIFEST.json`;
- versão atual no `README.md`;
- nova entrada no topo de `CHANGELOG.md`;
- exemplo atual neste `RELEASE_STANDARD.md`;
- hashes de todos os arquivos no manifesto.

## Branches e commits

- `main`: versão estável;
- `develop`: integração das próximas mudanças;
- `feature/nome`: funcionalidade nova;
- `fix/nome`: correção.

Prefixos recomendados:

```text
feat: nova funcionalidade
fix: correção
docs: documentação
refactor: reorganização sem mudança funcional
style: alteração visual
chore: manutenção ou release
```

## Fluxo de publicação

1. atualizar código e documentação;
2. executar validações Bash;
3. atualizar `MANIFEST.json` e seus hashes;
4. executar `tools/build-release.sh`;
5. validar o SHA-256 exibido pelo build e os hashes internos do `MANIFEST.json`;
6. criar a tag `vX.Y.Z`;
7. criar a GitHub Release `Manager X.Y.Z` quando esse canal for usado;
8. anexar somente `TermuxManager-vX.Y.Z.zip`;
9. publicar as notas com o resumo do `CHANGELOG.md`.

## Validação mínima

```bash
bash -n manager.sh
for arquivo in modules/*.sh; do bash -n "$arquivo" || exit 1; done
bash tools/build-release.sh
sha256sum dist/TermuxManager-vX.Y.Z.zip
```


## Sincronização documental

Antes de publicar, revise `README.md`, `CHANGELOG.md`, `RELEASE_STANDARD.md` e `modules/help.sh`. A ajuda interna deve refletir os menus e fluxos da versão publicada.


## Validações de runtime

A partir da 1.0.48, releases que alterem `runtime.sh` ou seus submódulos `runtime_*.sh` devem validar pelo menos um servidor saudável e um processo que permaneça vivo sem abrir a porta. Releases que alterem diagnósticos devem confirmar que retornos de controle não geram incidentes e que as exportações removem segredos comuns.


### Diagnóstico GitHub
A integração GitHub deve registrar falhas em `~/.termux-manager/logs/github.log` e apresentar ao usuário a etapa que falhou. A preparação local não deve depender da obtenção da identidade remota até ser necessário criar um commit. Quando a sanitização global estiver disponível, mensagens e saídas gravadas pelo logger GitHub devem passar por ela. Em projetos com vários remotes, operações GitHub devem priorizar o vínculo registrado para o projeto e nunca tratar automaticamente um `origin` de outro provedor como repositório GitHub.

## Atualização pelo GitHub

A branch `main` é o canal estável usado pela atualização automática do Manager. Cada alteração publicada na `main` deve incrementar a versão e manter `MANIFEST.json`, README e CHANGELOG sincronizados. O Manager consulta o manifesto remoto, valida os hashes do arquivo baixado e cria backup antes de substituir a instalação atual.
