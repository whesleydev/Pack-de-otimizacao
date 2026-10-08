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

## ⚡ Caminho mais fácil (sem PC, 5 minutos)

Você só precisa de **um** app: o **Brevent**.

1. Instale o **Brevent** na Play Store.
2. Abra e siga o assistente (ele pede uma permissão uma única vez).
3. Volte aqui e abra o arquivo:

   👉 **`nivel-1-txt/00-aplicar-tudo.txt`**

4. Selecione **tudo**, **copie** e **cole** dentro do Brevent. Rode.
5. **Reinicie o celular.** Pronto — o pack está aplicado. ✅

> Não gostou de algo? Abra o **`nivel-1-txt/99-restaurar-tudo.txt`**, copie e cole
> no Brevent. **Volta tudo ao normal.**

---

## 🗂️ Como o pack está organizado

```
nivel-1-txt/   → comandos prontos para copiar e colar (Brevent)   ← comece aqui
nivel-2-sh/    → scripts automáticos (Shizuku ou root)
scripts/       → a "caixa de ferramentas" do pack
plugins/       → módulos para o AxManager (roda sozinho em segundo plano)
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
| **`99-restaurar-tudo.txt`** | **desfaz tudo** |

> 💡 **Dica de ouro:** antes de aplicar, salve um "snapshot" (nível 2:
> `sh scripts/snapshot.sh save`). Aí você volta ao estado exato com um comando.

---

## 🔥 Só para jogar (o que dá mais resultado)

1. `14-limpeza-cache-io.txt` — limpa a memória
2. `09-jogo-game-mode.txt` — modo jogo
3. `19-tuning-por-jogo.txt` — resolução/FPS do jogo (escolha 0.9 ou 0.75)
4. `10-free-fire.txt` — abre o jogo

Depois de jogar, cole o `13-descongelar-apps.txt` para liberar os apps.

> ⚠️ **Importante:** o tuning por jogo (19) só vale depois de **reabrir o jogo**.

---

## 🛠️ Quer automatizar? (opcional)

Se você tem **Shizuku** (sem root) ou **root**, use os scripts:

```sh
sh nivel-2-sh/run.sh            # menu completo
sh nivel-2-sh/run.sh all        # aplica tudo
sh nivel-2-sh/run.sh fluidez    # fluidez
sh nivel-2-sh/run.sh save       # salva o estado atual
sh nivel-2-sh/run.sh restore    # volta o último estado salvo
sh nivel-2-sh/run.sh deep detect   # o que seu aparelho suporta
sh nivel-2-sh/run.sh deep gaming on com.dts.freefireth  # MODO TURBO
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
