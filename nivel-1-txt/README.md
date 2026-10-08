# Nível 1 · Arquivos .txt (copiar e colar no Brevent)

O nível mais simples do pack. Cada arquivo é uma lista de comandos prontos — você abre,
copia tudo e cola no **Brevent** (ou no terminal `adb shell` no PC). Não precisa de root.

## Como usar

1. Instale e ative o **Brevent** (veja [`../docs/brevent.md`](../docs/brevent.md)).
2. Abra o `.txt` da área que você quer.
3. Selecione tudo, copie e cole na área de execução do Brevent.
4. Rode.
5. Se não gostar, cole o `99-restaurar-tudo.txt`.

## Os arquivos (22 arquivos)

| # | Arquivo | O que faz |
|---|---------|-----------|
| 00 | `00-aplicar-tudo.txt` | **aplica o pack inteiro** de uma vez (comece por aqui) |
| 01 | `01-performance-geral.txt` | ajuste de desempenho, cache de processos, renderizador |
| 02 | `02-velocidade-da-tela-animacoes.txt` | velocidade das animações (0 / 0.5 / 1) |
| 03 | `03-tela-display.txt` | refresh rate, tempo de tela, brilho, cor |
| 04 | `04-ram-memoria.txt` | limites de processos, libera RAM, zram |
| 05 | `05-bateria-economia.txt` | economia, Doze, app standby |
| 06 | `06-graficos-gpu.txt` | GPU forçada, hardware rendering, blur off |
| 07 | `07-rede-dns-latencia.txt` | DNS Cloudflare, buffers TCP, captive portal |
| 08 | `08-wifi-dados.txt` | Wi-Fi scan off, sleep policy, dados móveis |
| 09 | `09-jogo-game-mode.txt` | Game Mode, performance fixo, fecha apps |
| 10 | `10-free-fire.txt` | prepara e abre o Free Fire |
| 11 | `11-sensibilidade-touch.txt` | perfis de toque/mira (headshot, sniper, speed) |
| 12 | `12-congelar-apps.txt` | congela apps de fundo |
| 13 | `13-descongelar-apps.txt` | libera os apps congelados |
| 14 | `14-limpeza-cache-io.txt` | limpa cache, logs, trim do armazenamento |
| 15 | `15-notificacoes-dnd.txt` | silencia notificações (DND) |
| 16 | `16-bloat-privacidade.txt` | desativa apps inúteis (com aviso de cuidado) |
| 17 | `17-sistema-logs-debug.txt` | reduz logs e depuração em background |
| 18 | `18-fluidez.txt` | **fluidez**: animações 0, long/multi press, Hz máximo |
| 19 | `19-tuning-por-jogo.txt` | **só no jogo**: resolução (downscale), teto de FPS, engine |
| 20 | `20-otimizacoes-profundas.txt` | ANGLE/Vulkan por jogo + debloat real (appops/standby) |
| 99 | `99-restaurar-tudo.txt` | **desfaz tudo** e volta ao original |

## Ordem sugerida para jogar

1. `14-limpeza-cache-io.txt` (limpa)
2. `07-rede-dns-latencia.txt` (rede)
3. `09-jogo-game-mode.txt` (modo jogo)
4. `19-tuning-por-jogo.txt` (resolução/FPS do jogo)
5. `10-free-fire.txt` (abre o jogo)
6. Depois de jogar: `13-descongelar-apps.txt` e/ou `99-restaurar-tudo.txt`

## Avisos importantes

- **`setprop` não persiste após reiniciar.** Só os `settings put` ficam salvos. Os
  arquivos já avisam quando o comando é `setprop`.
- **Comandos específicos de aparelho** (refresh rate, zram, brilho, cor) estão marcados
  no arquivo. Descubra o valor do seu: `settings get system peak_refresh_rate`.
- **`16-bloat-privacidade.txt` exige cuidado**: desativar o app errado quebra o sistema.
  Desative um por vez.
- Sempre que puder, rode `sh scripts/snapshot.sh save` (nível 2) antes de mexer, para
  poder reverter com um comando.
