# Compatibilidade por aparelho

Caminhos de `sysfs` mudam entre kernels e fabricantes. Por isso o pack **detecta** e
**avisa** em vez de prometer. Use `sh scripts/device-profile.sh` para ver o que tende a
funcionar no seu aparelho.

> ⚠️ **Honestidade:** o pack foi validado em ambiente controlado (testes com stubs), mas
> **não** foi testado em todos os modelos abaixo. A coluna "status" é preenchida por
> quem testar de verdade. Não afirme compatibilidade que não foi medida.

## O que depende do aparelho

| Recurso | Depende de | Funciona em |
|---------|-----------|-------------|
| `angle` (ANGLE/Vulkan por jogo) | Android 10+ com ANGLE no sistema | quase todos |
| `debloat` (appops/standby) | Android 9+ | quase todos |
| `net` (BBR/fq_codel) | kernel com BBR compilado | maioria dos kernels ≥ 4.9 |
| `mem` (MGLRU/KSM/zRAM) | kernel com MGLRU (≥ 5.1) e KSM | varia muito |
| `io` (scheduler/fstrim) | caminhos de bloco (UFS/eMMC) | maioria |
| `latency` (SurfaceFlinger/vsync) | props do framework | maioria |
| `freq` (trava de frequência) | cpufreq por cluster | Snapdragon quase sempre; MTK/Exynos varia |
| `thermal` (afrouxar limite) | trip points em `thermal_zone*` | Snapdragon; MTK/Exynos raro |

## Módulos por família de SoC (recomendação, não garantia)

| Família | Seguros | Evitar / testar |
|---------|---------|-----------------|
| Snapdragon | angle, debloat, net, io, mem, latency, freq, thermal | — |
| Dimensity (MTK) | angle, debloat, net, io, mem, latency | freq, thermal (caminhos mudam) |
| Exynos | angle, debloat, net, mem, latency | freq, thermal (exigem kernel custom) |
| Tensor | angle, debloat, net, mem | thermal (térmico agressivo de fábrica) |
| Kirin | angle, debloat, net | freq, thermal |

## Aparelhos testados

Preencha conforme for testando. Formato sugerido:

| Modelo | SoC | Android | ROM/kernel | Módulos OK | Observações |
|--------|-----|---------|------------|------------|-------------|
| _exemplo_ | SD 8 Gen 2 | 14 | stock | angle, debloat, net, freq | thermal +5 °C estável |
|  |  |  |  |  |  |

## Como testar um aparelho novo

```sh
sh scripts/device-profile.sh save          # perfil + detecção em ~/.packotm/perfil.txt
sh scripts/bench.sh save antes             # linha de base
sh scripts/deep-tune.sh gaming on <pkg>    # aplica o pacote (confirma o térmico)
# jogue ~20 min
sh scripts/bench.sh run depois
sh scripts/bench.sh report antes depois    # compare os números
sh scripts/deep-tune.sh restore            # reverta e confirme que voltou ao normal
```

Se algum módulo não aplicar (o script avisa "nada aplicado"), ele **não** quebra o
aparelho — apenas é ignorado. Reporte o modelo no repositório para entrar na tabela.
