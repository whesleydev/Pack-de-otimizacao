# Plugins AxManager

Plugins no formato de módulo do **AxManager** (também rodam em KernelSU, APatch e Magisk).
São zips com `module.prop` + scripts (`customize.sh`, `service.sh`, `action.sh`,
`uninstall.sh`).

## Organização

```
Plugins AxManager/
├── Nossos/                  ← feitos por nós (whesleydev)
│   ├── 01-service-loop/     aplica o pack e mantém ativo (loop)
│   ├── 02-webui-control/    configurável por WebUI
│   ├── 03-battery-thermal/  economia + trava térmica (45°C)
│   ├── 04-cleaner/          limpeza de cache/log/RAM
│   └── 05-fps-refresh/      refresh máximo + modo de jogo
└── Terceiros-open-source/   ← de outros autores (só licença permissiva)
    ├── Stellar-Tweaks/      Apache-2.0 (zip instalável incluído)
    ├── Kang/                Apache-2.0
    ├── Sakoiire/            Apache-2.0
    └── Aapt-for-Plugin/     Apache-2.0
```

Créditos e licenças dos terceiros em
[`Terceiros-open-source/CREDITS.md`](Terceiros-open-source/CREDITS.md).

## Empacotar
```sh
sh scripts/build-plugins.sh   # gera releases/*.zip de cada plugin
```

## Instalar
1. Empacote (ou pegue o zip em `releases/`).
2. No AxManager: **Plugins → instalar** e escolha o zip.
3. O botão de ação mostra o status; o `uninstall.sh` reverte.
