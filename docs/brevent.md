# Usando o pack pelo Brevent (sem PC)

O **Brevent** executa comandos privilegiados de shell no próprio celular, então dá para
usar quase tudo deste pack sem computador.

## 1. Ativar o Brevent

1. Instale o Brevent (Play Store ou APK oficial).
2. Siga o assistente e conceda a permissão via **ADB sem fio** uma vez.
3. Confirme que aparece "Brevent está ativo" na tela inicial.

## 2. Rodar os comandos

O Brevent tem uma área para executar comandos. Copie os comandos de
`scripts/adb-tweaks.sh` **sem o transporte** (`adb shell` / `rish -c` / `su -c`).

Exemplos:

```sh
# performance
settings put global window_animation_scale 0.5
settings put global transition_animation_scale 0.5
settings put global animator_duration_scale 0.5
settings put global force_gpu_rendering 1

# congelamento de apps em cache (freezer)
settings put global cached_apps_freezer enabled

# DNS
settings put global private_dns_mode hostname
settings put global private_dns_specifier dns.cloudflare.com
```

## 3. Congelar e descongelar no Brevent

O Brevent já faz freeze/unfreeze nativo pela interface. Os comandos equivalentes são:

```sh
# congelar um app
pm suspend --user 0 com.exemplo.app

# descongelar / reativar
pm unsuspend --user 0 com.exemplo.app
pm enable --user 0 com.exemplo.app

# listar apps de terceiros
pm list packages -3
pm list packages -u -3
```

## 4. Reverter

Para desfazer os tweaks:

```sh
settings delete global window_animation_scale
settings delete global transition_animation_scale
settings delete global animator_duration_scale
settings put global force_gpu_rendering 0
settings put global cached_apps_freezer disabled
settings put global private_dns_mode opportunistic
```

> Dica: se um app sumir da lista após `pm suspend`, rode `pm unsuspend --user 0 <pacote>`
> e `pm enable --user 0 <pacote>`.

## 5. Observações

- `setprop` (buffers TCP, touch boost) pode não persistir após reiniciar.
- Alguns comandos `cmd game` exigem Android 12+.
- O congelamento via `pm suspend` é mais agressivo que o do Brevent; use com cuidado.
