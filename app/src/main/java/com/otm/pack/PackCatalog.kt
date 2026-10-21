package com.otm.pack

/** Uma ação do pack que o app sabe executar. */
data class PackAction(
    val id: String,
    val group: String,
    val label: String,
    val desc: String,
    /** safe | careful | root */
    val risk: String,
    /** 1 = Brevent (.txt), 2 = scripts sh (Shizuku/ADB), 3/4 = plugins (AxManager) */
    val level: String,
    /** Arquivo em assets/pack, quando for um .txt do nível 1. */
    val assetFile: String? = null,
    /** Comando pronto (nível 2). Usa $PACK para a pasta extraída. */
    val inline: String? = null,
    /** Só informativo (níveis 3/4): não executa, mostra a explicação. */
    val infoOnly: Boolean = false,
    val needsParam: Boolean = false,
    /** Arquivo de áudio em assets/audio tocado antes de executar (opcional). */
    val actionSound: String? = null,
)

/** Créditos do criador, exibidos e usados no botão do Discord. */
object Credits {
    const val CREATOR = "00deUdia"
    const val DISCORD_USER = "cute_axolotl_51194"
    const val DISCORD_URL = "https://discord.com/users/cute_axolotl_51194"
    const val SERVER_URL = "https://discord.gg/w9hFBeVKw8"
}

/**
 * Catálogo de ações. Espelha os 4 níveis do pack:
 *  - nível 1: comandos Brevent (`.txt`), colados/executados linha a linha;
 *  - nível 2: scripts `sh` do pack (Shizuku/ADB), com estado e reversão;
 *  - níveis 3/4: plugins e módulos do AxManager (informativo no app).
 */
object PackCatalog {

    private fun txt(
        id: String, group: String, label: String, desc: String, risk: String, file: String,
        sound: String = SND_SYSTEM,
    ) = PackAction(id, group, label, desc, risk, "1", assetFile = "comandos/$file", actionSound = sound)

    const val SND_SYSTEM = "otimizando-o-sistema.mp3"
    const val SND_RAM = "liberando-memoria-ram.mp3"
    const val SND_DNS = "configurando-dns.mp3"
    const val SND_ACTIVATE = "ativando.mp3"
    const val SND_CONFIGURE = "configurando.mp3"

    val actions: List<PackAction> = listOf(
        // ---- Rápido ----------------------------------------------------------
        txt("apply_all", "Rápido", "Aplicar TUDO (nível 1)", "Roda o conjunto recomendado de comandos seguros de uma vez.", "careful", "00-aplicar-tudo.txt"),
        txt("restore_all_txt", "Rápido", "Restaurar tudo (nível 1)", "Desfaz os comandos aplicados pelo arquivo de restaurar.", "safe", "99-restaurar-tudo.txt", SND_CONFIGURE),

        // ---- Performance -----------------------------------------------------
        txt("perf", "Performance", "Performance geral", "Mais processos em cache, UI mais rápida e sem travas de erro.", "safe", "01-performance-geral.txt"),
        txt("anim", "Performance", "Velocidade da tela (animações)", "Zera as animações do sistema para abrir apps na hora.", "safe", "02-velocidade-da-tela-animacoes.txt"),
        txt("display", "Performance", "Tela / display", "Ajustes de taxa de atualização e resposta da tela.", "careful", "03-tela-display.txt"),
        txt("fluidez", "Performance", "Fluidez geral", "Reduz engasgos e deixa a rolagem mais lisa.", "safe", "18-fluidez.txt"),
        txt("tuning_game", "Performance", "Tuning por jogo", "Aplica um modo de performance para jogos instalados.", "careful", "19-tuning-por-jogo.txt"),
        txt("debloat_txt", "Performance", "Debloat (bloatware)", "Desativa apps de fábrica que atrapalham. Reversível.", "careful", "21-debloat-bloatware.txt"),
        txt("deep_txt", "Performance", "Otimizações profundas (root)", "Mexe em kernel e sistema. Só com root.", "root", "20-otimizacoes-profundas.txt"),

        // ---- RAM / limpeza ---------------------------------------------------
        txt("ram", "RAM / Limpeza", "RAM / memória", "Ajusta o gerenciamento de memória do Android.", "safe", "04-ram-memoria.txt", SND_RAM),
        txt("freeze", "RAM / Limpeza", "Congelar apps", "Congela apps em segundo plano para liberar RAM.", "careful", "12-congelar-apps.txt", SND_RAM),
        txt("unfreeze", "RAM / Limpeza", "Descongelar apps", "Traz de volta os apps que você congelou.", "safe", "13-descongelar-apps.txt", SND_RAM),
        txt("cache", "RAM / Limpeza", "Limpar cache e I/O", "Limpa caches e melhora a leitura/escrita.", "safe", "14-limpeza-cache-io.txt", SND_RAM),

        // ---- Renderizador / GPU ---------------------------------------------
        txt("gpu", "Renderizador", "Gráficos / GPU", "Troca o renderizador e força aceleração por GPU.", "careful", "06-graficos-gpu.txt", SND_ACTIVATE),

        // ---- Rede / DNS ------------------------------------------------------
        txt("dns", "Wi-Fi e rede", "Rede / DNS / latência", "Reduz latência e melhora a resolução de nomes.", "safe", "07-rede-dns-latencia.txt", SND_DNS),
        txt("wifi", "Wi-Fi e rede", "Wi-Fi e dados", "Ajustes de Wi-Fi e rede móvel.", "safe", "08-wifi-dados.txt", SND_DNS),

        // ---- Jogo / Free Fire ------------------------------------------------
        txt("game_mode", "Jogo / Free Fire", "Modo jogo (game mode)", "Ativa o modo jogo do Android antes de abrir o Free Fire.", "safe", "09-jogo-game-mode.txt", SND_ACTIVATE),
        txt("ff", "Jogo / Free Fire", "Free Fire: preparar e abrir", "Prioriza o jogo, limpa RAM e abre o Free Fire.", "careful", "10-free-fire.txt", SND_ACTIVATE),

        // ---- Touch / Free Fire ----------------------------------------------
        txt("touch", "Touch / Free Fire", "Sensibilidade / touch", "Perfil de toque e resposta para jogos de tiro.", "careful", "11-sensibilidade-touch.txt", SND_CONFIGURE),

        // ---- Bateria / notificações / privacidade ---------------------------
        txt("battery", "Bateria", "Bateria e economia", "Ajusta economia de energia sem derrubar o desempenho.", "safe", "05-bateria-economia.txt"),
        txt("dnd", "Notificações", "Notificações / Não perturbe", "Silencia interrupções enquanto você joga.", "safe", "15-notificacoes-dnd.txt"),
        txt("privacy", "Privacidade", "Bloat / privacidade", "Reduz telemetria e apps indesejados.", "safe", "16-bloat-privacidade.txt"),
        txt("logs", "Privacidade", "Logs e depuração", "Desliga logs e rastros de depuração.", "safe", "17-sistema-logs-debug.txt"),

        // ---- Nível 2: scripts do pack ---------------------------------------
        PackAction("sh_status", "Scripts (nível 2)", "Status do pack", "Mostra o estado do aparelho e o que já foi aplicado.", "safe", "2",
            inline = "sh \"\$PACK/scripts/pack.sh\" status", actionSound = SND_CONFIGURE),
        PackAction("sh_apply", "Scripts (nível 2)", "Aplicar pack recomendado", "Aplica o conjunto recomendado (com estado e snapshot).", "careful", "2",
            inline = "sh \"\$PACK/scripts/pack.sh\" apply", actionSound = SND_SYSTEM),
        PackAction("sh_restore", "Scripts (nível 2)", "Reverter tudo", "Restaura o aparelho ao estado anterior.", "safe", "2",
            inline = "sh \"\$PACK/scripts/pack.sh\" restore", actionSound = SND_CONFIGURE),
        PackAction("sh_snapshot", "Scripts (nível 2)", "Salvar snapshot", "Guarda o estado atual para poder voltar depois.", "safe", "2",
            inline = "sh \"\$PACK/scripts/pack.sh\" snapshot save", actionSound = SND_CONFIGURE),
        PackAction("sh_device", "Scripts (nível 2)", "Detectar aparelho", "Mostra o perfil do aparelho (SoC, Android, etc.).", "safe", "2",
            inline = "sh \"\$PACK/scripts/pack.sh\" device", actionSound = SND_CONFIGURE),
        PackAction("sh_bench", "Scripts (nível 2)", "Benchmark", "Mede o desempenho atual do aparelho.", "safe", "2",
            inline = "sh \"\$PACK/scripts/pack.sh\" bench", actionSound = SND_SYSTEM),
        PackAction("sh_debloat", "Scripts (nível 2)", "Debloat por perfil", "Desativa bloatware por perfil (leve, médio, pesado).", "careful", "2",
            inline = "sh \"\$PACK/scripts/pack.sh\" debloat menu"),
        PackAction("sh_touch", "Scripts (nível 2)", "Touch: menu de perfis", "Abre os perfis de sensibilidade do pack.", "careful", "2",
            inline = "sh \"\$PACK/scripts/pack.sh\" touch menu", actionSound = SND_CONFIGURE),

        // ---- Níveis 3/4: informativo ----------------------------------------
        PackAction("ax_plugins", "Plugins (nível 3)", "Plugins do AxManager", "Os 5 plugins do pack rodam em loop no AxManager (nível 3). Baixe na release.", "safe", "3",
            infoOnly = true),
        PackAction("ax_webui", "Plugins (nível 4)", "Plugin com WebUI", "O plugin com interface web roda no AxManager (nível 4). Baixe na release.", "safe", "4",
            infoOnly = true),
    )

    val groups: List<String> = actions.map { it.group }.distinct()
}
