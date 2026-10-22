# Pack OTM · Congelar Apps

Plugin AxManager (e KernelSU/APatch/Magisk) que **congela apps de fundo** para liberar
RAM, com **whitelist** (apps que nunca são congelados) e **blacklist** (apps a congelar).

Congelar um app o impede de rodar em segundo plano — ele não gasta RAM nem bateria até
você abrir de novo. É o que o Brevent faz, só que automático e com lista sua.

## Como funciona

- **Whitelist** — apps que **nunca** serão congelados (ex.: WhatsApp, banco, relógio).
- **Blacklist** — apps que **serão** congelados (já vem uma lista de bloat comum).
- **Proteção embutida** — apps do sistema/essenciais (SystemUI, telefone, teclado,
  Play Store, gerenciadores de root, Termux) **nunca** entram, mesmo se você pedir.

Dois modos:
| Modo | O que faz | Quando usar |
|------|-----------|-------------|
| `suspend` (padrão) | `pm suspend` + `force-stop` — estilo Brevent | recomendado |
| `soft` | `pm disable-user` + `force-stop` | se o suspend não pegar |

## Config — `/data/adb/packotm_freezer/config`
```
ENABLE_FREEZER=1
FREEZE_MODE=suspend
FREEZE_ON_BOOT=1
FREEZE_INTERVAL=180
CACHE_FREEZER=1
KILL_ON_FREEZE=1
AUTO_BLACKLIST=1
```

## Comandos (também no botão de ação)
```sh
sh apply.sh status                  # resumo + o que será congelado
sh apply.sh freeze                  # congela a blacklist agora
sh apply.sh unfreeze                # descongela tudo
sh apply.sh wl-add com.whatsapp     # nunca congelar
sh apply.sh bl-add com.exemplo      # congelar este
sh apply.sh freeze-app <pacote>     # congela 1 app
sh apply.sh restore                 # descongela tudo e para o serviço
```

## Instalar
```sh
sh scripts/build-plugins.sh   # gera releases/06-freezer.zip
```
No gerenciador: **Plugins → instalar** e escolha o zip. O `uninstall.sh` descongela tudo
antes de sair — não deixa app preso.

> ⚠️ Não congele app de banco/2FA nem o que você precisa receber notificação. Se algo
> parar de funcionar, rode `sh apply.sh unfreeze` (ou reinstale/desinstale o plugin).
