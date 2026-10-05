# Nível 1 · Arquivos .txt (copiar e colar no Brevent)

O nível mais simples do pack. Cada arquivo é uma lista de comandos prontos — você abre,
copia tudo e cola no **Brevent** (ou no terminal `adb shell` no PC). Não precisa de root.

## Como usar

1. Instale e ative o **Brevent** (veja [`../docs/brevent.md`](../docs/brevent.md)).
2. Abra o `.txt` da área que você quer.
3. Selecione tudo, copie e cole na área de execução do Brevent.
4. Rode.

## Arquivos

| Arquivo | O que faz |
|---------|-----------|
| `01-performance.txt` | animações rápidas, GPU, sem blur (mais FPS) |
| `02-rede-dns.txt` | DNS Cloudflare e buffers TCP (menos ping) |
| `03-bateria-doze.txt` | economia de bateria e Doze |
| `04-jogo-freefire.txt` | prepara e abre o Free Fire |
| `05-congelar-apps.txt` | congela apps de fundo (Brevent) |
| `06-descongelar-apps.txt` | libera os apps congelados |
| `07-touch-sensibilidade.txt` | perfil de toque/mira headshot |
| `08-tela-refresh.txt` | refresh alto e tela sempre ligada |
| `09-notificacoes-dnd.txt` | silencia notificações |
| `10-limpeza-cache.txt` | limpa cache/dexopt |
| `99-restaurar.txt` | **desfaz tudo** e volta ao original |

> Dica: os arquivos `setprop` (rede/touch) não persistem após reiniciar. Os `settings put`
> persistem.

## Ordem sugerida para jogar

1. `10-limpeza-cache.txt` (limpa)
2. `02-rede-dns.txt` (rede)
3. `04-jogo-freefire.txt` (prepara + abre o jogo)
4. Depois de jogar: `06-descongelar-apps.txt` e/ou `99-restaurar.txt`
