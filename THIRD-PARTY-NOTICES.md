# Avisos de Terceiros (Third-Party Notices)

Este repositório **reúne** módulos de terceiros em `modules/`. A autoria de cada módulo
pertence aos respectivos autores. Este arquivo existe para dar **transparência legal**:
sem licença explícita, o padrão é **todos os direitos reservados**, e redistribuir ou
vender exige **permissão escrita do autor**.

> ⚠️ **Leia antes de vender.** Dos 16 módulos em `modules/`, apenas **2** trazem arquivo
> de licença. Os outros **14 não têm licença declarada** — não podem ser empacotados,
> redistribuídos ou vendidos sem autorização. Este é o principal risco legal do projeto.

## Status de licença por módulo

| Pasta | Autor (declarado) | Versão | Licença encontrada | Redistribuir/vender? |
|-------|-------------------|--------|--------------------|----------------------|
| `Astrax` | t.me/BillyNutDemarco | v2-Eclipse | nenhuma | ❌ precisa de permissão |
| `AxVision_Hawk` | @ReiiEja | v1052-180926-S | nenhuma | ❌ precisa de permissão |
| `BEN_UNIVERSAL` | trhieuhoc | v4.6 | nenhuma | ❌ precisa de permissão |
| `CPU_GPU_Web_Panel_Itachi_Edition` | Jhonzxit | v5.0 | nenhuma | ❌ precisa de permissão |
| `Celestial-Game-Opt` | Kzyoo / kazuyoo-stuff | 3.4 | **GPL-3.0** | ⚠️ copyleft — manter licença + fonte |
| `Game_Scale` | Philip Nghia | v1.4.1 | nenhuma | ❌ precisa de permissão |
| `Gms_Tweaker` | ERINE 433 | 0.1 (alpha) | nenhuma | ❌ precisa de permissão |
| `Kang` | @illumi | 8.5.0 | **Apache-2.0** | ✅ permitido (com NOTICE) |
| `MOs_Premium_v15_Full-Stack_FPS_Engine` | jogominecraft1234 | v15.0 | nenhuma | ❌ precisa de permissão |
| `NOVA_TOUCH` | trhieuhoc | 1.0 | nenhuma | ❌ precisa de permissão |
| `NexaCore` | Enrique Brach | 2.0.0 | nenhuma | ❌ precisa de permissão |
| `Phoenix` | By_Rafael_System | v3.0 | nenhuma | ❌ precisa de permissão |
| `VOID_BATTERY` | VOID PERF | v9.1-fix2-safe | nenhuma | ❌ precisa de permissão |
| `VOID_TOUCH_Ultra` | VOID DEV | v5.1.0 | nenhuma | ❌ precisa de permissão |
| `VeuLexier` | @Reiieja | V1.7.6-DexOtSmt | nenhuma | ❌ precisa de permissão |
| `WS7_OFF7` | WS7_OFF7 | 6.0.0 | nenhuma | ❌ precisa de permissão |

## Como resolver (escolha uma via por módulo)

1. **Obter permissão escrita** do autor (e-mail/Telegram salvo em `modules/permissions.tsv`),
   declarando o uso comercial. Guarde a prova.
2. **Confirmar a licença** do projeto original (muitos são públicos no GitHub com
   Apache/MIT/GPL). Se for permissiva, inclua o texto da licença na pasta do módulo.
3. **Remover** o módulo do pacote pago (pode continuar apenas como link/recomendação).
4. **Substituir** por módulo próprio (autoral) com a mesma função.

## Módulos próprios (sem risco de terceiros)

Estes são de autoria do mantenedor e não dependem de licença de terceiros:

- `plugins/01-service-loop/` — Service Loop (AxManager)
- `plugins/02-webui-control/` — WebUI Control (AxManager)
- `scripts/`, `nivel-1-txt/`, `nivel-2-sh/` — o pack em si

## Verificação automatizada

```sh
sh scripts/check-licenses.sh          # lista pendências (não bloqueia dev)
STRICT_LICENSES=1 sh scripts/build-modules.sh   # empacota só módulos liberados
```

O workflow de release (`.github/workflows/build.yml`) usa o modo estrito, de modo que
**nenhum módulo sem licença é publicado em uma release**.

---

_Este arquivo não é parecer jurídico. Para uso comercial, consulte um advogado._
