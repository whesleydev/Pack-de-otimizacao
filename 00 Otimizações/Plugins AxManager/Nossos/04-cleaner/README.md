# Pack OTM · Limpeza & Memória

Plugin AxManager (e KernelSU/APatch/Magisk) que roda **limpeza periódica** em segundo
plano: cache, logcat, fstrim e (opcional) fecha apps de fundo.

Não altera nenhuma configuração do sistema — **só limpa**, então não há o que reverter.

## O que faz
- `cmd activity trim-caches` + `pm trim-caches` a cada 15 min.
- Limpa o `logcat`.
- `fstrim` em `/data` e `/cache`.
- (Opcional) fecha apps de fundo pesados.

## Config — `/data/adb/packotm_cleaner/config`
```
CLEAN_INTERVAL=900
TRIM_CACHES=1
CLEAR_LOG=1
FSTRIM=1
KILL_BG=0
BG_APPS="com.instagram.android com.facebook.katana com.facebook.orca com.twitter.android"
```

## Instalar
```sh
sh scripts/build-plugins.sh
```
O botão de ação mostra RAM livre e log. `uninstall.sh` para o loop.
