package com.otm.pack

/**
 * Ponte para o núcleo nativo (C, via NDK) do pack.
 *
 * Por que existe: a telemetria do monitor (RAM, temperatura, frequência, carga da
 * CPU) vinha do `panel-stats.sh`, que abre um processo a cada ciclo. Em C a mesma
 * leitura é uma leitura de arquivo — dá para medir mais e com menos gasto.
 *
 * Contrato: cada função devolve -1 quando o dado não existe/não é legível (o
 * mesmo "nunca inventar" dos scripts). Se a lib não carregar, [available] é
 * falso e quem chama usa o caminho de shell — o app nunca quebra por causa disto.
 */
object OtmNative {

    /** true quando a biblioteca nativa carregou neste aparelho. */
    val available: Boolean = try {
        System.loadLibrary("otmcore")
        true
    } catch (t: Throwable) {
        false
    }

    /** RAM disponível em kB (MemAvailable), ou -1. */
    external fun ramAvailableKb(): Long

    /** RAM total em kB (MemTotal), ou -1. */
    external fun ramTotalKb(): Long

    /** Maior temperatura das zonas térmicas, em mili-graus Celsius, ou -1. */
    external fun maxThermalMilliC(): Long

    /** Frequência atual do núcleo mais rápido, em kHz, ou -1. */
    external fun currentCpuFreqKhz(): Long

    /**
     * Carga da CPU em % (0..100), medida entre duas chamadas seguidas.
     * A PRIMEIRA chamada devolve -1 (não há base de comparação).
     */
    external fun cpuUsagePercent(): Int

    /** Tempo ligado, em segundos, ou -1. */
    external fun uptimeSeconds(): Long

    /** Número de núcleos, ou -1. */
    external fun cpuCores(): Int

    /** Temperatura em °C, ou null quando não deu para ler. */
    fun thermalC(): Double? {
        if (!available) return null
        val m = maxThermalMilliC()
        return if (m <= 0) null else m / 1000.0
    }

    /** RAM disponível em MB, ou null. */
    fun ramAvailableMb(): Long? {
        if (!available) return null
        val kb = ramAvailableKb()
        return if (kb < 0) null else kb / 1024
    }

    /** Frequência atual em MHz, ou null. */
    fun cpuFreqMhz(): Long? {
        if (!available) return null
        val khz = currentCpuFreqKhz()
        return if (khz <= 0) null else khz / 1000
    }

    /** Carga da CPU em % (ou null na primeira leitura). */
    fun cpuPct(): Int? {
        if (!available) return null
        val p = cpuUsagePercent()
        return if (p < 0) null else p
    }

    /** "0.0" quando a lib não está disponível (para o rodapé do painel). */
    fun versionTag(): String = if (available) "c-ndk" else "shell"
}
