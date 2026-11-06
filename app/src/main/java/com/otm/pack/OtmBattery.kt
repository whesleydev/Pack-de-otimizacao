package com.otm.pack

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import org.json.JSONObject

/**
 * Leitura de bateria pelo próprio Android (BatteryManager), sem shell.
 *
 * O card "Saúde do telefone" e o monitor dependiam só do `panel-stats.sh` (via
 * Shizuku/ADB). Sem shell, tudo virava "—" e o usuário achava que o card "não
 * funcionava". Aqui o app lê o que o Android expõe a qualquer app: nível,
 * temperatura, estado (carregando/descarregando) e a saúde declarada pela
 * bateria. É o mesmo número que a tela de bateria do sistema mostra.
 *
 * Só preenche o que o shell NÃO trouxe — o shell continua sendo a fonte
 * preferida quando existe, porque lê mais (ciclos, capacidade de fábrica).
 * Campo que o aparelho não expõe fica de fora: o painel mostra "—", nunca um
 * número inventado.
 */
object OtmBattery {

    /** Campos no MESMO formato do `panel-stats.sh`, só o que o Android entrega. */
    fun snapshot(context: Context): JSONObject {
        val o = JSONObject()
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val it: Intent? = try {
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        } catch (_: Throwable) {
            null
        }
        if (bm != null) {
            val lvl = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (lvl in 0..100) o.put("bat_level", lvl.toString())
        }
        if (it != null) {
            val raw = it.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            if (!o.has("bat_level") && raw in 0..100) o.put("bat_level", raw.toString())
            // temperatura vem em décimos de grau (ex.: 351 = 35.1 °C)
            val t = it.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            if (t != Int.MIN_VALUE && t > 0) {
                val c = String.format(java.util.Locale.US, "%.1f", t / 10.0)
                o.put("bat_temp_c", c)
            }
            val st = it.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            val label = when (st) {
                BatteryManager.BATTERY_STATUS_CHARGING -> "Carregando"
                BatteryManager.BATTERY_STATUS_DISCHARGING -> "Descarregando"
                BatteryManager.BATTERY_STATUS_FULL -> "Cheio"
                BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "Não carrega"
                BatteryManager.BATTERY_STATUS_UNKNOWN -> "Desconhecido"
                else -> ""
            }
            if (label.isNotEmpty()) o.put("bat_status", label)
            val h = it.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)
            val hlabel = when (h) {
                BatteryManager.BATTERY_HEALTH_GOOD -> "Boa"
                BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Superaquecida"
                BatteryManager.BATTERY_HEALTH_DEAD -> "Desgastada"
                BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Tensão alta"
                BatteryManager.BATTERY_HEALTH_COLD -> "Fria"
                BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "Falha"
                else -> ""
            }
            if (hlabel.isNotEmpty()) o.put("bat_health_label", hlabel)
        }
        return o
    }
}
