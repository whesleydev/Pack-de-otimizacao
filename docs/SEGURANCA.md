# Segurança — tokens e limpeza do repositório

Este documento registra um **incidente de segurança** e o procedimento de correção.

## O que aconteceu

O arquivo `apps_otm.zip` (≈ 50 MB) foi **versionado e enviado ao `main` público**. Ele
continha:

- **dumps de conversa** (`conversation_*.zip`, `event_*.json`) com **um token de acesso
  do GitHub (`ghp_…`)** em texto puro;
- zips de **módulos** (Phoenix, VOID TOUCH, Ben Universal, MOs Premium, WS7_OFF7,
  VeuLexier, CPU/GPU JHONZXIT). Os de terceiros foram **removidos** do repositório;
  WS7_OFF7, VOID TOUCH e VeuLexier são do autor e foram mantidos
  (ver [`ROADMAP.md`](ROADMAP.md), item 1).

Segundo o dono do projeto, o token foi gerado **para este projeto** (não é de terceiro).
Ainda assim, ficou exposto em repositório público e deve ser tratado como comprometido
até ser revogado.

> ⚠️ **Remover o arquivo em um commit novo NÃO resolve sozinho:** ele continua no
> histórico do git (e em forks/clones/caches do GitHub) até ser purgado.

## Ação 1 — já aplicada neste commit

- `apps_otm.zip` foi **removido do versionamento** (`git rm --cached`).
- Adicionado ao `.gitignore` para não voltar.
- O arquivo local foi **preservado** (não foi apagado do disco).

Isso impede novas exposições, mas **não** limpa o histórico.

## Ação 2 — revogar o token exposto (recomendado)

Como o token é do próprio projeto, revogar é simples (e barato):

1. Revogue em **https://github.com/settings/tokens** (Tokens classic) — apague o token
   deste projeto.
2. Auditar: **https://github.com/settings/security-log** e
   `GET /repos/whesleydev/Pack-de-otimizacao/events` para uso indevido.

> O dono considerou o risco baixo por ser um token dedicado ao projeto. Ainda assim,
> como ele ficou em repositório público, revogar é a única forma de neutralizar de vez.

## Ação 3 — purgar o histórico (feito pelo dono do repositório)

Escolha **uma** ferramenta. Faça backup do repo antes.

### Opção A — `git filter-repo` (recomendado)

```sh
# instale: pip install git-filter-repo
git clone --mirror https://github.com/whesleydev/Pack-de-otimizacao.git repo.git
cd repo.git
git filter-repo --path apps_otm.zip --invert-paths
git push --force --all
git push --force --tags
```

### Opção B — BFG Repo-Cleaner

```sh
java -jar bfg.jar --delete-files apps_otm.zip repo.git
cd repo.git && git reflog expire --expire=now --all && git gc --prune=now --aggressive
git push --force
```

### Depois de purgar

- Force-push reescreve o histórico: **avise colaboradores** para re-clonarem.
- Abra um **ticket no GitHub Support** pedindo o GC dos objetos órfãos (o arquivo pode
  continuar acessível por SHA por um tempo mesmo após o force-push).
- Considere o token **comprometido para sempre** — a revogação (Ação 2) é o que
  realmente neutraliza o risco.

## Prevenção (já configurada)

- `.gitignore` bloqueia `*.zip`, `conversation_*.zip`, `event_*.json`, `apps_otm.zip`.
- Antes de commitar, rode:

```sh
sh scripts/check-secrets.sh          # procura tokens/chaves em arquivos versionados
```

- Nunca versione dumps de conversa, backups de app ou arquivos de estado local.
