# Usando o pack pelo Termux + Shizuku (sem PC)

O **Shizuku** dá shell privilegiado ao Termux sem root, via `rish`. O `common.sh` detecta
o `rish` automaticamente.

## 1. Instalar o Shizuku

1. Instale o Shizuku (Play Store ou GitHub oficial).
2. Inicie o serviço (`adb` uma vez ou via root).
3. Abra o Shizuku → **Usar no Termux** → copie o `rish` para
   `/data/local/tmp/` ou deixe-o no `PATH`.

## 2. Preparar o Termux

```sh
pkg update && pkg upgrade
pkg install curl
# deixe o rish acessível:
cp /sdcard/rish ~/rish && chmod +x ~/rish   # se veio do gerenciador de arquivos
```

## 3. Rodar o pack

```sh
git clone https://github.com/whesleydev/Pack-de-otimizacao.git
cd Pack-de-otimizacao

# o menu detecta o rish e usa modo privilegiado
sh scripts/menu.sh

# ou direto
sh scripts/adb-tweaks.sh all
sh scripts/ff-touch.sh headshot
```

Se a detecção não pegar o `rish`, force:

```sh
OTM_MODE=rish sh scripts/menu.sh
```

## 4. Verificar

```sh
rish -c 'id -u'    # deve imprimir 0
```

## 5. Reverter

```sh
OTM_MODE=rish sh scripts/adb-tweaks.sh restore_all
```

## Observações

- O Shizuku cai quando o serviço é encerrado (wipe recentes, reboot). Reinicie-o.
- Sem root, alguns tweaks de `setprop` podem não permanecer após reboot.
- `freeze_apps` funciona bem pelo Shizuku, mas apps de sistema devem ficar fora da
  whitelist de congelamento (o script já pula uma lista).
