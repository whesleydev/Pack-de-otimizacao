# Segurança — tokens e limpeza do repositório

Este documento registra um **incidente de segurança** e o procedimento de correção.

## O que aconteceu

O arquivo `apps_otm.zip` (≈ 50 MB) foi **versionado e enviado ao `main` público**. Ele
continha:

- **dumps de conversa** (`conversation_*.zip`, `event_*.json`) com **um token de acesso
  do GitHub (`ghp_…`)** em texto puro;
- zips de **módulos de terceiros** (Phoenix, VOID TOUCH, Ben Universal, MOs Premium,
  WS7_OFF7, VeuLexier, CPU/GPU JHONZXIT) — ver [`../THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md).

O token **não é** o que foi usado para publicar este pack (verificado por comparação),
mas **é um token válido de terceiro** e ficou exposto em repositório público.

> ⚠️ **Remover o arquivo em um commit novo NÃO resolve sozinho:** ele continua no
> histórico do git (e em forks/clones/caches do GitHub) até ser purgado.

## Ação 1 — já aplicada neste commit

- `apps_otm.zip` foi **removido do versionamento** (`git rm --cached`).
- Adicionado ao `.gitignore` para não voltar.
- O arquivo local foi **preservado** (não foi apagado do disco).

Isso impede novas exposições, mas **não** limpa o histórico.

## Ação 2 — revogar o token exposto (URGENTE)

1. Peça a quem gerou o token para revogá-lo em **https://github.com/settings/tokens**
   (Tokens classic) — ou, se for de uma organização, no painel da org.
2. Se você não sabe de quem é, revogue **todos** os tokens classic e **gire** os
   secrets de CI/automações.
3. Auditar: **https://github.com/settings/security-log** e
   `GET /repos/whesleydev/Pack-de-otimizacao/events` para uso indevido.

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
