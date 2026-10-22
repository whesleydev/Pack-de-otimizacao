# Plugins AxManager de terceiros (open-source)

Aqui ficam plugins de **outros autores**, incluídos por serem de código aberto com
licença permissiva. Cada um mantém seu `LICENSE` original. **Não somos autores** destes.

> Regra do projeto: só entra conteúdo de terceiro com licença que permita
> redistribuição (MIT / Apache-2.0). Sem licença, não entra — vira só indicação.

| Plugin | Autor | Licença | Fonte | O que é |
|--------|-------|---------|-------|---------|
| Stellar-Tweaks | kanaodnd | Apache-2.0 | github.com/kanaodnd/Stellar-Tweaks | Daemon de performance em Rust. **Fonte completa incluída** (extraída do release v22.0). |
| Kang | DEMONNICA | Apache-2.0 | github.com/DEMONNICA/Kang | Otimização de performance e eficiência. |
| Sakoiire | DEMONNICA | Apache-2.0 | github.com/DEMONNICA/Sakoiire | Reduz a carga do sistema. |
| Aapt-for-Plugin | DEMONNICA | Apache-2.0 | github.com/DEMONNICA/Aapt-for-Plugin | Binários `aapt`/`aapt2` multi-arquitetura. |

## Onde pegar o instalável

Alguns autores publicam no GitHub só o `module.prop` + README; o **zip instalável** fica
na aba **Releases** do repositório ou em canal do autor (Telegram/Discord). Confira a
fonte antes de instalar:

- **Stellar-Tweaks** — fonte incluída aqui (`Stellar-Tweaks/`, extraída do release v22.0);
  releases em `github.com/kanaodnd/Stellar-Tweaks/releases`.
- **Kang / Sakoiire / Aapt-for-Plugin** — releases em `github.com/DEMONNICA/<nome>/releases`.

## Indicações (sem licença — não redistribuídos)

Famosos, mas **sem licença declarada** (por isso não estão no repositório):

- **Nova-Ultra** — `github.com/OdetteGD/Nova-Ultra---AxManager-Modules`
- **magiskap/axmanager-plugin** — `github.com/magiskap/axmanager-plugin` (coleção)
- **ARISE** — `github.com/ariseplugins/axmanager-plugin` (coleção; muitos zips marcados
  VIP/PAID, redistribuição duvidosa)

Para incluir qualquer um destes, é preciso **permissão escrita do autor**.

## Aviso

Módulos aplicam mudanças de sistema. Use por sua conta e risco, sempre com snapshot antes
(`sh scripts/snapshot.sh save`). Créditos e licenças são dos autores originais.
