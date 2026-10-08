# 🔍 Guia de Auditoria Técnica

Este documento existe para que **qualquer auditor (humano ou IA)** consiga avaliar o pack
com contexto completo: o que cada módulo faz, **comando exato**, requisito de privilégio,
risco, ganho esperado e como reverter.

> **Princípio do pack:** nada de placebo escondido. Onde um comando é duvidoso ou
> dependente de aparelho, está marcado aqui. Onde há risco, está marcado com ⚠️.

---

## Como testar

```sh
# 1) o script roda em 4 modos; force um deles para testar sem celular:
OTM_MODE=local sh scripts/deep-tune.sh status

# 2) veja o que o aparelho suporta (roda em qualquer celular):
sh scripts/deep-tune.sh detect

# 3) aplique um módulo e veja o backup gerado (reversão real):
sh scripts/deep-tune.sh angle add com.dts.freefireth
cat ~/.packotm/deep/off.sh        # cada linha = <tag> TAB <comando de reversão>

# 4) reverte só aquele módulo:
sh scripts/deep-tune.sh angle reset
```

**Verificação de sintaxe** (roda em qualquer PC/container):

```sh
for f in $(find scripts nivel-2-sh plugins -name '*.sh'); do sh -n "$f" || echo "ERRO $f"; done
```

---

## Classificação dos módulos profundos (`scripts/deep-tune.sh`)

| Módulo | Privilégio | Mecanismo | Ganho esperado | Risco | Reversão |
|--------|-----------|-----------|----------------|-------|----------|
| `angle` | **sem root** | `settings global angle_gl_driver_selection_*` | alto em jogos GLES | baixo (alguns jogos quebram) | `angle reset` |
| `debloat` | **sem root** | `cmd appops` + `am set-standby-bucket` | médio (RAM/bateria) | baixo | `debloat off` |
| `freq` | root | `/sys/.../cpufreq/scaling_governor` + `min_freq`; GPU `min_pwrlevel` | alto | médio (calor/bateria) | `freq off` |
| `thermal` | root | `/sys/class/thermal/thermal_zone*/trip_point_*_temp` (+5 °C) | **muito alto** (FPS sustentado) | ⚠️ **alto** (aquecimento) | `thermal off` |
| `io` | root | `queue/scheduler=none`, `read_ahead_kb`, `sm fstrim` | médio | baixo | `io off` |
| `mem` | root | `/sys/kernel/mm/lru_gen` (MGLRU), KSM, `vm.swappiness`, zRAM | médio-alto | baixo | `mem off` |
| `net` | root | `sysctl tcp_congestion_control=bbr`, `fq_codel` | médio (latência) | baixo | `net off` |
| `latency` | root | `setprop debug.sf.latch_unsignaled` etc. | médio | baixo | `latency off` |
| `gaming` | root | liga freq+io+mem+net+latency+debloat+angle+thermal | máximo | ⚠️ alto (herda térmico) | `gaming off` |

---

## Detalhe de cada módulo (o que o auditor deve checar)

### `angle` — ANGLE / Vulkan por jogo (sem root) ★
- **Comandos:** `settings put global angle_gl_driver_selection_pkgs <pkgs>` e
  `..._values angle,angle`.
- **O que é:** o Android 10+ pode renderizar jogos GLES via **ANGLE** (camada que traduz
  OpenGL ES para Vulkan). Em muitos aparelhos isso reduz overhead de driver.
- **Ganho:** varia por jogo/GPU. **Não é garantido.**
- **Risco:** alguns jogos não abrem ou ficam instáveis com ANGLE. Reversível na hora.
- **Limitação:** só afeta jogos que usam OpenGL ES (não os que já são Vulkan nativo).
- **Checagem:** `settings get global angle_gl_driver_selection_pkgs`.

### `freq` — frequência de CPU/GPU (root)
- **Comandos:** `echo performance > scaling_governor`; `scaling_min_freq = cpuinfo_max_freq`;
  GPU Adreno `min_pwrlevel=0` / devfreq `governor=performance`.
- **Ganho:** imediato e perceptível em jogos pesados.
- **Risco:** mais calor e consumo. **Recomendado só durante o jogo.**
- **Limitação:** caminhos de GPU variam (Adreno × Mali). O script detecta, mas pode não
  achar em ROMs muito customizadas.

### `thermal` — afrouxar limite térmico (root) ⚠️
- **Comando:** eleva `trip_point_*_temp` em +5 °C nas zonas `cpu/gpu/soc/skin`.
- **Por que existe:** o **throttling térmico é a maior causa** de queda de FPS depois de
  alguns minutos. Sem isso, os outros ajustes são cosméticos.
- **Risco:** ⚠️ **aquecimento, consumo e desgaste**. Nunca use carregando e sem ventilação.
- **Limitação:** depende de o kernel expor os trip points como graváveis. Muitos não
  permitem — o script avisa e não faz nada em vez de mentir.

### `io` — I/O (root)
- `scheduler=none` (para UFS/NVMe), `read_ahead_kb=4096`, `nr_requests=128`, `sm fstrim`.

### `mem` — memória (root)
- **MGLRU** (`/sys/kernel/mm/lru_gen/enabled=1`) — gerenciador de páginas do kernel 6.1+.
- **KSM** (`ksm/run=1`), `vm.swappiness=100`, `dirty_ratio`, zRAM `disksize`.

### `net` — rede (root)
- **BBR** (`tcp_congestion_control`), `tcp_fastopen=3`, buffers, `tc qdisc fq_codel`.
- **Limitação:** se o kernel não tiver BBR, o script avisa (não força).

### `latency` — latência de toque→tela (root)
- `debug.sf.latch_unsignaled=1`, `debug.sf.enable_gl_backpressure=1`.
- **Nota:** `debug.sf.vsync_phase_offset_ns` é device-specific; **não** aplicamos por
  padrão para não introduzir tearing.

### `debloat` — debloat real (sem root)
- `cmd appops set <pkg> RUN_IN_BACKGROUND ignore` + `RUN_ANY_IN_BACKGROUND ignore` +
  `am set-standby-bucket <pkg> restricted`.
- **Por que é melhor que force-stop:** restrição de política persistente, reversível, sem
  matar processo à força (o app só perde permissão de rodar sozinho).

---

## Placebos removidos / marcados

Estes comandos são comuns em "packs" de internet mas **não têm efeito em Android moderno**.
Foram removidos ou marcados como legado para não vender placebo:

| Comando | Situação |
|---------|----------|
| `debug.performance.tuning` | no-op em Android 8+ — **marcado como legado** |
| `debug.egl.hw` / `debug.sf.hw` | no-op desde Android 8 |
| `debug.hwui.renderer.disable_partial_updates` | efeito duvidoso |

> Se o auditor discordar de algum item desta lista, é só apontar — a intenção é manter
> o pack **honesto**, não "cheio de comando".

---

## Integração nos plugins (níveis 3 e 4)

Os plugins reaplicam os tweaks em loop/serviço, então a reversão tem um cuidado extra:

- **`plugins/01-service-loop`** — `apply_deep()` (em `lib.sh`) espelha os módulos
  profundos. Liga/desliga por chaves no `config`: `ENABLE_ANGLE`, `ENABLE_DEBLOAT`,
  `ENABLE_DEEP`, `ENABLE_THERMAL`. `uninstall.sh` chama `revert_deep`.
- **`plugins/02-webui-control`** — `apply.sh` ganhou `m_angle`, `m_debloat`,
  `m_deep`, `m_thermal` e `revert_deep`; a UI expõe `CFG_ANGLE`, `CFG_DEBLOAT`,
  `CFG_DEEP`, `CFG_THERMAL` e `CFG_ANGLE_PKGS`.

**Ponto crítico que o auditor deve verificar:** como o loop reaplica a cada ciclo, o
backup do estado original (`<STATE>/deep_off.sh`) é gravado **uma única vez**, marcado
por `<STATE>/deep_mark`. Sem esse marcador, cada reaplicação duplicaria as linhas de
reversão e o `off.sh` cresceria sem parar. Teste sugerido:

```sh
# no aparelho (ou com stubs de settings/cmd/am/setprop):
sh apply.sh apply; sh apply.sh apply; sh apply.sh apply
wc -l /data/adb/packotm/deep_off.sh   # deve permanecer estável (não triplica)
```

> O plugin 01 não expõe UI; a config é editada em `/data/adb/packotm/config`.

---

## Como reproduzir a avaliação

1. `git clone https://github.com/whesleydev/Pack-de-otimizacao` e `cd` nele.
2. `sh tests/run.sh` — suíte automatizada (stubs de `settings`/`cmd`/`am`/`getprop`),
   cobre sintaxe, apply→restore, reversão por tag e o marcador `deep_mark`. Deve dar
   **0 falhas**.
3. `sh scripts/check-secrets.sh` — não pode achar credencial (sai com 1 se achar).
4. `OTM_MODE=local sh scripts/deep-tune.sh detect` — não deve tocar em nada (modo local).
5. Aplicar/reverter um módulo e conferir `~/.packotm/deep/off.sh` (tag por módulo).
6. `sh scripts/build-plugins.sh` — empacota só os plugins do pack (nada de terceiros).
7. `sh scripts/bench.sh save antes && ... && sh scripts/bench.sh report antes depois`.

---

## Limitações conhecidas (declaradas)

1. **Caminhos de sysfs variam** por fabricante/kernel. O script detecta e degrada com
   segurança (avisa em vez de falhar). Ver `docs/COMPATIBILIDADE.md`.
2. **`setprop` não persiste** após reiniciar. Os módulos profundos são "ligar quando jogar".
3. **Thermal/root** exige confiança do usuário — daí a confirmação explícita, a trava
   automática (`THERMAL_MAX_C`, padrão 45 °C; `THERMAL_STOP_CHARGING`) e o aviso.
4. **Ganho não é garantido** por aparelho. O pack promete *menos queda de FPS e menos
   travada*, **não** um número fixo de FPS. Meça com `scripts/bench.sh`.
5. **Sem módulos de terceiros** — o repositório só contém conteúdo próprio (MIT); os
   plugins são empacotados por `scripts/build-plugins.sh`.

---

## Segurança (o que o auditor deve conferir)

1. `scripts/check-secrets.sh` roda no CI e bloqueia commit com credencial.
2. O incidente do `apps_otm.zip` (dumps de conversa com token) está documentado em
   `docs/SEGURANCA.md` — arquivo removido do versionamento; histórico ainda **não** purgado.
3. A trava térmica (`thermal_watch`) reverte o módulo sozinha; teste com
   `THERMAL_MAX_C=0 THERMAL_OK=1 deep-tune.sh thermal on` e veja `~/.packotm/deep/thermal.log`.

---

## Estrutura de reversão (como o auditor confere)

- `~/.packotm/off.sh` — reversão dos `settings` (nível 2).
- `~/.packotm/deep/off.sh` — reversão das otimizações profundas, com **tag por módulo**
  (formato `<tag>\t<comando>`). `deep-tune.sh <módulo> off` reverte só aquele módulo.
- `~/.packotm/deep/thermal.pid` + `thermal.log` — trava de segurança térmica.
- `nivel-1-txt/99-restaurar-tudo.txt` — reversão manual (Brevent).

---

_Última atualização: pack v1.1.0 (otimizações profundas, benchmark, testes, CI, trava térmica)._
