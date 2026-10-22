# Apps para instalar e usar o pack

Os aplicativos que dão **acesso privilegiado** ao telefone (o que o pack precisa para
funcionar). Sem um deles, os `.txt` e scripts não conseguem aplicar nada.

> 🌐 **Guia visual completo:** abra [`index.html`](index.html) (o site do pack) — ele
> explica cada app, cada nível e traz uma área de comandos prontos.

## Qual app eu preciso?

| Seu caso | Instale | Nível que libera |
|----------|---------|------------------|
| Quero **sem root**, só com o celular | **Brevent** | Nível 1 (`.txt`) |
| Quero **sem root**, com automação | **Termux** + **Shizuku** | Níveis 1 e 2 |
| Quero **sem root**, com painel/plugins | **AxManager (Axeron)** | Níveis 1 a 4 |
| Tenho **root** (Magisk/KernelSU/APatch) | o gerenciador de root | Níveis 1 a 4 |

## Apps (em ordem de uso)

### 1. Brevent — congelar apps sem root
- **O que faz:** coloca apps em segundo plano para dormir (force-stop/crash), sem root.
- **Pacote:** `me.piebridge.brevent` · **Autor:** Jianyu Studio
- **Como instalar:** Play Store ou APK oficial. Depois de instalar, **ative** pelo
  computador uma vez (WebUSB em <https://brevent.sh>) ou via ADB:
  ```sh
  adb -d shell 'output=$(pm path me.piebridge.brevent); export CLASSPATH=${output#:}; \
  app_process /system/bin me.piebridge.brevent.server.BreventServer bootstrap; \
  /system/bin/sh /data/local/tmp/brevent.sh'
  ```
- **No pack:** use os arquivos `00 Otimizações/Comandos Brevent/*.txt` (copiar e colar
  no campo de comando do Brevent).

### 2. Shizuku — shell privilegiado sem root
- **O que faz:** dá aos apps a permissão de "shell" (o mesmo nível do `adb`), sem root.
- **Pacote:** `moe.shizuku.privileged.api` · **Autor:** RikkaApps
- **Como instalar:** Play Store. Ative por **depuração sem fio** (Android 11+) ou ADB.
- **No pack:** combine com o **Termux** para rodar os scripts do nível 2.

### 3. Termux — terminal no celular
- **O que faz:** roda os scripts `sh` do pack direto no telefone, sem computador.
- **Pacote:** `com.termux` · **Autor:** Termux
- **Instale pela F-Droid ou GitHub** (a versão da Play Store está descontinuada).
- **No pack:** `sh "00 Otimizações/Scripts SH/run.sh"` (menu completo).

### 4. AxManager (Axeron) — gerenciador de plugins + WebUI, sem root
- **O que faz:** roda comandos shell e **plugins** (módulos) sem root, com interface web.
- **Pacote:** `frb.axeron.manager` · **Autor:** fahrez182
- **Site/repo:** <https://fahrez182.github.io/AxManager> ·
  <https://github.com/fahrez182/AxManager>
- **No pack:** instale os plugins de `00 Otimizações/Plugins AxManager/Nossos/`
  (níveis 3 e 4) — inclusive o **WebUI Control** e o **Congelar Apps**.

### 5. Gerenciador de root (opcional) — Magisk / KernelSU / APatch
- **O que faz:** acesso root para as otimizações profundas (sysfs, GPU, térmico).
- **No pack:** libera tudo (`deep-tune.sh`), mas **não é obrigatório** — o pack funciona
  sem root nos níveis 1, 2 e na maior parte do 3/4.

## Segurança

- Baixe **só** das fontes oficiais (Play Store, F-Droid, GitHub dos autores).
- O pack **não redistribui** esses apps — são de terceiros. Aqui só indicamos onde pegar.
- Antes de aplicar qualquer coisa, salve um snapshot: `sh scripts/snapshot.sh save`.

## Legado

- **`apps_otm.zip`** (na raiz, ~50 MB) é um pacote **legado** de APKs de terceiros.
  Ele **não** é usado pelo pack atual e está fora do controle de versão (por segurança —
  pode conter dumps/credenciais). Não redistribua. Veja `docs/SEGURANCA.md`.
