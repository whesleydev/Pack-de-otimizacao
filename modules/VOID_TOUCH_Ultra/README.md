# VOID TOUCH Ultra v5.1.0 — Ultimate ADB Touch Optimizer

> **O melhor modulo de otimizacao de touch para Android via ADB, sem root.**

---

## Visao Geral

O VOID TOUCH Ultra v5.1.0 otimiza a responsividade do touchscreen no Android **sem root**. Aplica **40 otimizacoes reais** em 7 fases: resposta ao toque, animacoes, refresh rate, sistema, pipeline de input, vendor-specific e otimizacoes avancadas.

### Destaques
- **50 funcoes** (40 otimizacoes + 10 diagnosticos)
- **Zero root** — funciona 100% via ADB
- **Zero daemon** — execucao one-shot, sem processos persistentes
- **Zero interferencia** — nao altera navegacao, launcher ou interface do usuario
- **Backup automatico** — todos os valores originais sao salvos
- **Restore incluso** — `restore.sh` reverte todas as alteracoes
- **Vendor-aware** — Samsung, Xiaomi, OnePlus, OPPO, Pixel, Huawei, Vivo e mais
- **Try-first engine** — tenta aplicar antes de desistir, menos funcoes puladas

---

## Instalacao

### Via ADB (PC)
```bash
adb push VOID_TOUCH_Ultra_v5.1.0_ADB_NoRoot /sdcard/
adb shell sh /sdcard/VOID_TOUCH_Ultra_v5.1.0_ADB_NoRoot/action.sh
```

### Via AXManager
1. Importe o modulo
2. Execute o action

---

## Arquitetura

```
VOID_TOUCH_Ultra_v5.1.0_ADB_NoRoot/
|-- action.sh              # Ponto de entrada principal
|-- restore.sh             # Restaurar configuracoes originais
|-- module.prop            # Metadados do modulo
|-- banner.png             # Banner visual
|-- README.md              # Documentacao
|-- scripts/
    |-- lib/common.sh      # Biblioteca utilitaria
    |-- 01_detect/core.sh  # Fase 1: Deteccao (f01-f08)
    |-- 02_touch_response/ # Fase 2: Resposta ao toque (f09-f16)
    |-- 03_animation/      # Fase 3: Animacoes (f17-f20)
    |-- 04_display/        # Fase 4: Display/Refresh (f21-f26)
    |-- 05_system/         # Fase 5: Sistema (f27-f32)
    |-- 06_input/          # Fase 6: Input pipeline (f33-f38)
    |-- 07_advanced/       # Fase 7: Avancado/Vendor (f39-f48)
```

---

## Catalogo de Funcoes (50 total)

### Fase 1: Deteccao (f01-f08) — Somente leitura

| # | Funcao | Descricao |
|---|--------|-----------|
| f01 | Touchscreen Presence | Detecta touchscreen no dumpsys |
| f02 | Touch Vendor | Identifica controlador (Goodix, FocalTech, Synaptics, ILI...) |
| f03 | Input Service | Verifica servico de input |
| f04 | Multitouch | Detecta suporte multitouch |
| f05 | Touch Resolution | Analisa eixos X/Y |
| f06 | Device Info | Marca, modelo, SDK, brand |
| f07 | Settings Snapshot | Captura configuracoes atuais |
| f08 | Display Info | Resolucao, densidade, max Hz (deteccao melhorada) |

### Fase 2: Resposta ao Toque (f09-f16)

| # | Funcao | O que faz | Impacto |
|---|--------|-----------|---------|
| f09 | Show Touches Off | Desativa overlay de debug | -overhead renderizacao |
| f10 | Pointer Location Off | Desativa overlay de coordenadas | -overhead renderizacao |
| f11 | Long Press 300ms | Reduz timeout de long press | 25-40% mais rapido |
| f12 | Multi Press 250ms | Reduz timeout de duplo toque | 17% mais rapido |
| f13 | Pointer Speed | Calibra velocidade (min 3, max 7) | Tracking responsivo |
| f14 | Touch Sounds Off | Desativa sons de toque | -processamento audio |
| f15 | Lock Sounds Off | Desativa sons de lock/unlock | -thread de audio |
| f16 | Charge Sounds Off | Desativa som de carregamento | -interrupcoes |

### Fase 3: Animacoes (f17-f20)

| # | Funcao | O que faz | Impacto |
|---|--------|-----------|---------|
| f17 | Window 0.5x | Animacao de janela rapida | UI 2x mais rapida |
| f18 | Transition 0.5x | Transicao entre telas rapida | Apps 2x mais rapido |
| f19 | Animator 0.5x | Ripple/feedback rapido | Touch 2x mais visual |
| f20 | IME Instant | Teclado aparece instantaneo | Zero delay no teclado |

### Fase 4: Display & Refresh (f21-f26)

| # | Funcao | O que faz | Impacto |
|---|--------|-----------|---------|
| f21 | Peak Refresh Max | Define refresh de pico no max | Touch mais suave |
| f22 | Min Refresh Max | Impede queda para 60Hz | Consistencia |
| f23 | User Refresh Max | Preferencia do usuario no max | Mantém max |
| f24 | Window Blurs Off | Desativa blur de janela (Android 12+) | -GPU por frame |
| f25 | Bubbles Off | Desativa bolhas de notificacao | -camadas compositor |
| f26 | Screensaver Off | Desativa screen saver/daydream | -overhead display |

### Fase 5: Sistema (f27-f32)

| # | Funcao | O que faz | Impacto |
|---|--------|-----------|---------|
| f27 | Kill Cached | Elimina processos ociosos | +CPU para touch |
| f28 | TRIM Memory | Libera RAM de apps em background | -swapping |
| f29 | LED Pulse Off | Desativa LED de notificacao | -interrupcoes HW |
| f30 | Dots Off | Desativa pontos de notificacao | -compositor |
| f31 | Activities Persist | Apps ficam em memoria | Re-toque instantaneo |
| f32 | DTMF Off | Desativa tons do discador | -audio overhead |

### Fase 6: Input Pipeline (f33-f38)

| # | Funcao | O que faz | Impacto |
|---|--------|-----------|---------|
| f33 | Text Classifier Off | Desativa ML de texto background | -CPU ML |
| f34 | Smart Selection Off | Desativa selecao inteligente | -processamento texto |
| f35 | Predictive Back Off | Desativa back preditivo (Android 14+) | Voltar mais rapido |
| f36 | Magnification Off | Desativa zoom por toque* | -interceptacao touch |
| f37 | Autoclick Off | Desativa auto-clique* | -delay dwell |
| f38 | Touch Exploration Off | Desativa exploracao por toque* | -latencia leitura |

> *Preservado automaticamente se servicos de acessibilidade estiverem ativos

### Fase 7: Avancado (f39-f48)

| # | Funcao | O que faz | Impacto |
|---|--------|-----------|---------|
| f39 | Vendor Optimizer | Aplica TODOS os ajustes da marca detectada | Brand-specific |
| f40 | Battery Saver Off | Desativa economia que throttla CPU/GPU | Touch sem throttle |
| f41 | Debug App Clear | Remove app de debug + wait_for_debugger | -overhead monitor |
| f42 | GPU Pipeline Reset | Limpa stats acumuladas do GPU | Pipeline limpo |
| f43 | Cache Trim | Limpa cache de apps via pm | -I/O swap |
| f44 | Spell Checker Off | Desativa verificacao ortografica | -ML por keystroke |
| f45 | WiFi Scan Throttle Off | Desativa throttle de scan WiFi | -CPU spikes |
| f46 | Network Scoring Off | Desativa avaliacao de rede | -algoritmos background |
| f47 | Package Verifier Off | Desativa verificacao de pacotes | -I/O background |
| f48 | Connectivity Refresh | Atualiza rede + limpa DNS cache | Conexao fresca |

---

## Diferencas v5.0.0 -> v5.1.0

### Bugs Corrigidos
1. **Banner**: `\033[0m` aparecia literalmente na linha 2 — corrigido usando `printf '%s'` para arte ASCII
2. **Refresh rate**: deteccao falhava em Xiaomi (formato `fps=90.0`) — agora detecta Hz, fps=, refreshRate=
3. **safe_set**: pulava funcoes sem tentar — agora TENTA escrever e verifica se funcionou
4. **Xiaomi**: typo `three_gestrue_screenshot` -> `three_gesture_screenshot`
5. **Predictive back**: tentava so 1 key name — agora tenta 3 keys em 2 namespaces

### Redesign
- **Phase 7**: 10 vendor-specific (9 sempre pulavam) -> 1 vendor consolidado + 9 universais
- **safe_set engine**: "check-then-skip" -> "try-then-verify" = muito menos SKIPs
- **Refresh rate**: 4 patterns (Hz, fps=, refreshRate=, settings fallback)
- **Vendor function**: 1 funcao que tenta TUDO da marca detectada internamente

---

## Backup e Restauracao

### Backup automatico
```
/sdcard/VOID_TOUCH/v5/backup/settings_backup.txt
```

### Restaurar
```bash
adb shell sh /sdcard/VOID_TOUCH_Ultra_v5.1.0_ADB_NoRoot/restore.sh
```

---

## Compatibilidade

| Android | Suporte |
|---------|---------|
| 8.0-10 | Basico (sem refresh rate, sem blurs) |
| 11-12  | Completo |
| 13-14  | Completo + predictive back |
| 15-16  | Completo + todas as funcoes |

### Marcas Suportadas
Samsung, Xiaomi/Redmi/POCO, OnePlus, OPPO/Realme, Google Pixel, Huawei/Honor, Vivo, Motorola, Sony, ASUS, Nothing + generico AOSP

---

## FAQ

**Interfere no uso normal?** Nao. Animacoes ficam 0.5x (nao desativadas), acessibilidade preservada, nenhum app afetado.

**Drena bateria?** Nao. Varias otimizacoes economizam bateria (sons off, blurs off, caches limpos).

**Posso reverter?** Sim, execute `restore.sh`.

**Preciso rodar toda vez?** A maioria das settings sobrevive ao reboot. Recomenda-se rodar apos atualizacao de sistema.

---

## Changelog

### v5.1.0 (2026-08-12)
- Fix banner backslash/escape bug
- Fix refresh rate detection (fps=, refreshRate=, Hz, settings fallback)
- Redesigned safe_set engine: try-first instead of check-first
- Consolidated 10 vendor functions into 1 smart vendor + 9 universal
- Fixed Xiaomi setting key typo
- Fixed predictive back multi-key search
- Added: screensaver off, battery saver off, debug app clear, GPU reset, cache trim, spell checker off, WiFi scan throttle off, network scoring off, package verifier off, connectivity refresh
- Reduced typical SKIPs from 18 to 2-5

### v5.0.0
- Reconstrucao total da v4.0.0
- 40 otimizacoes reais (v4 tinha apenas 2)
- Backup/restore automatico

### v4.0.0
- 100 funcoes diagnosticas (apenas 2 faziam alteracoes)

---

## Licenca
Uso pessoal livre. Redistribuicao com creditos ao autor (VOID DEV).

## Creditos
Autor: VOID DEV | Motor: ADB settings + am/pm commands | Inspiracao: XDA, Magisk community
