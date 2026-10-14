# 👋 COMECE AQUI

Bem-vindo ao **Pack de Otimização**. Em poucos minutos seu celular fica mais
**rápido**, o **toque responde na hora** e os **jogos rodam mais lisos** — sem
instalar nada estranho e **com como voltar atrás** se você não gostar.

---

## 🎁 O que você vai sentir

| Antes | Depois |
|-------|--------|
| Animação lenta ao abrir app | Abre **na hora** (animações zeradas) |
| Toque parece "atrasado" | Toque **sem atraso** |
| Jogo engasga / FPS baixo | **Mais FPS** e menos travada |
| Tela "arrastando" | Rolagem **lisa** no Hz máximo |
| Apps pesados atrapalhando | Jogo abre **limpo** |

---

## 🎛️ Menu-mestre — o jeito mais simples de usar tudo

Se você tem **Termux** (ou Shizuku/root), um comando só abre o menu que gerencia
o pack inteiro:

```sh
sh pack.sh
```

Aparece uma lista numerada: aplicar, reverter, performance, jogo, Free Fire,
debloat, **DNS (privacidade/anúncios/latência)**, **executar módulos e plugins da
pasta**, toque, snapshots e mais. Escolha o número e pronto. Para sair, `0`.

> Sem PC? O menu também funciona pelo **Termux**. Com PC, dá para rodar por **ADB**.

### 🖥️ Prefere pelo navegador? Tem o painel 00deUdia Otimizações

Um comando sobe o painel e te dá uma URL para abrir no PC (mesma rede Wi-Fi):

```sh
sh main.sh web start
```

No painel você escolhe o **DNS**, limpa **RAM/cache**, troca o **renderizador**
(OpenGL/Vulkan), seleciona um **app/jogo** para usar ANGLE/Vulkan, ajusta o **touch** e
muito mais — tudo com botões. Ações de risco (como debloat) **perguntam antes**. Precisa
de **PHP** (Termux: `pkg install php`). O `main.sh` também **baixa os recursos full** do
pack (`sh main.sh baixar`).

---

## ⚡ Caminho mais fácil (sem PC, 5 minutos)

Você só precisa de **um** app: o **Brevent**.

1. Instale o **Brevent** na Play Store.
2. Abra e siga o assistente (ele pede uma permissão uma única vez).
3. Volte aqui e abra o arquivo:

   👉 **`00 Otimizações/Comandos Brevent/00-aplicar-tudo.txt`**

4. Selecione **tudo**, **copie** e **cole** dentro do Brevent. Rode.
5. **Reinicie o celular.** Pronto — o pack está aplicado. ✅

> Não gostou de algo? Abra o **`00 Otimizações/Comandos Brevent/99-restaurar-tudo.txt`**, copie e cole
> no Brevent. **Volta tudo ao normal.**

---

## 🗂️ Como o pack está organizado

```
00 Otimizações/
  Comandos Brevent/   → comandos prontos para copiar e colar (Brevent)   ← comece aqui
  Scripts SH/         → scripts automáticos (Shizuku ou root)
  Plugins AxManager/  → plugins do AxManager (roda sozinho em segundo plano)
    Nossos/             os nossos 6 plugins
    Terceiros-open-source/ plugins de outros (só licença livre)
  Modulos/            → módulos extras do pack (WS7_OFF7, NexaCore, Astrax…)
pack.sh        → MENU-MESTRE: gerencia tudo por um menu numerado
scripts/       → a "caixa de ferramentas" do pack
docs/          → guias detalhados
```

Cada `.txt` do nível 1 trata de **um assunto**. Você pode usar só o que quiser.

---

## 🎯 Os arquivos mais úteis (nível 1)

| Arquivo | Para quê |
|---------|----------|
| **`00-aplicar-tudo.txt`** | aplica o pack inteiro de uma vez |
| `18-fluidez.txt` | animações 0 + toque sem atraso + Hz máximo |
| `19-tuning-por-jogo.txt` | mais FPS só no jogo (não mexe no celular) |
| `10-free-fire.txt` | prepara e abre o Free Fire |
| `11-sensibilidade-touch.txt` | perfis de mira (headshot, sniper, spray) |
| `14-limpeza-cache-io.txt` | libera RAM e cache |
| `20-otimizacoes-profundas.txt` | ANGLE/Vulkan por jogo + debloat real |
| `21-debloat-bloatware.txt` | remove bloatware sem root (reversível) |
| **`99-restaurar-tudo.txt`** | **desfaz tudo** |

> 💡 **Dica de ouro:** antes de aplicar, salve um "snapshot" (nível 2:
> `sh scripts/snapshot.sh save`). Aí você volta ao estado exato com um comando.

---

## 🔥 Só para jogar (o que dá mais resultado)

1. `14-limpeza-cache-io.txt` — limpa a memória
2. `12-congelar-apps.txt` — congela apps de fundo (respeita a whitelist)
3. `09-jogo-game-mode.txt` — modo jogo
4. `19-tuning-por-jogo.txt` — resolução/FPS do jogo (escolha 0.9 ou 0.75)
5. `10-free-fire.txt` — abre o jogo

Depois de jogar, cole o `13-descongelar-apps.txt` para liberar os apps.

> 💡 No `12-congelar-apps.txt`, edite a `WHITELIST` no topo e coloque o que você
> **não** quer que seja congelado (WhatsApp, banco, relógio...). O resto da lista é
> congelado. Ou use o plugin **06-freezer**, que faz isso sozinho com um botão.

> ⚠️ **Importante:** o tuning por jogo (19) só vale depois de **reabrir o jogo**.

---

## 🛠️ Quer automatizar? (opcional)

Se você tem **Shizuku** (sem root) ou **root**, use os scripts:

```sh
sh 00 Otimizações/Scripts SH/run.sh            # menu completo
sh 00 Otimizações/Scripts SH/run.sh all        # aplica tudo
sh 00 Otimizações/Scripts SH/run.sh fluidez    # fluidez
sh 00 Otimizações/Scripts SH/run.sh save       # salva o estado atual
sh 00 Otimizações/Scripts SH/run.sh restore    # volta o último estado salvo
sh 00 Otimizações/Scripts SH/run.sh deep detect   # o que seu aparelho suporta
sh 00 Otimizações/Scripts SH/run.sh deep gaming on com.dts.freefireth  # MODO TURBO
```

E se você usa **AxManager**, instale o plugin e deixe ele **rodando sozinho 24h**:

```sh
sh scripts/build-plugins.sh
# instale releases/02-webui-control.zip (tem painel web)
```

---

## ❓ Dúvidas rápidas

**É seguro?** Sim. Tudo é reversível — o `99-restaurar-tudo.txt` desfaz.

**Preciso de root?** Não. O caminho fácil (Brevent) não precisa.

**Vai apagar meus dados?** Não. O pack só ajusta configurações.

**Funciona em qualquer celular?** Na maioria (Android 11+). Ajustes de toque e de
tela variam por aparelho — teste e ajuste.

**Meu jogo pode ser banido?** O tuning por jogo (19) usa um recurso **oficial do
Android**, não é mod nem hack. Ainda assim, use por sua conta e risco.

**Não funcionou / deu problema?** Cole o `99-restaurar-tudo.txt`. Se algo sumir,
veja a seção **Solução de problemas** em `docs/tutorial.md`.

---

## 📚 Quer entender tudo a fundo?

Leia o **[tutorial completo](docs/tutorial.md)** — explica cada nível e cada comando,
com o que faz e como voltar atrás.

---

**Bom proveito! Seu celular (e seu jogo) vão agradecer. 🚀**
