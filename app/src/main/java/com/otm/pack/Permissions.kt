package com.otm.pack

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Permissões que o Android exige do próprio app (não do pack) para ele funcionar
 * bem: notificações (Android 13+) e ficar fora da otimização de bateria.
 *
 * Sem isso o sistema adormece o app, o som não toca e as ações em segundo plano
 * param sozinhas. As permissões que dependem de shell (Doze, segundo plano, Free
 * Fire) são aplicadas pelos scripts — aqui é só o que o app pode pedir sozinho.
 */
object Permissions {

    const val CHANNEL_ID = "otm_status"
    const val REQ_NOTIF = 4301
    const val REQ_MDNS = 4302

    /** Cria o canal de notificações (obrigatório no Android 8+). */
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(NotificationManager::class.java) ?: return
        if (mgr.getNotificationChannel(CHANNEL_ID) != null) return
        mgr.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Estado do pack",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Avisos do pack e andamento das ações." }
        )
    }

    fun hasNotif(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun askNotif(activity: AppCompatActivity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (hasNotif(activity)) return
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
    }

    /** Permissão que o Android pede para descobrir serviços na rede (mDNS). */
    private fun mdnsPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.NEARBY_WIFI_DEVICES
        else Manifest.permission.ACCESS_FINE_LOCATION

    fun hasMdns(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, mdnsPermission()) == PackageManager.PERMISSION_GRANTED

    /**
     * Pede a permissão da descoberta de rede antes de parear por Wi-Fi. Sem ela o
     * Android nega a busca do serviço de pareamento em silêncio.
     */
    fun askMdns(activity: AppCompatActivity) {
        if (hasMdns(activity)) return
        ActivityCompat.requestPermissions(activity, arrayOf(mdnsPermission()), REQ_MDNS)
    }

    /**
     * Pede a permissão da descoberta e SÓ chama [onResult] quando o usuário
     * responde. O diálogo do pareamento abria junto com o pedido de permissão:
     * o usuário digitava o código antes de a permissão existir e a busca mDNS
     * falhava em silêncio — era o "não conecta" mais comum.
     */
    fun askMdnsThen(activity: AppCompatActivity, onResult: (Boolean) -> Unit) {
        if (hasMdns(activity)) {
            onResult(true)
            return
        }
        pendingMdns = onResult
        ActivityCompat.requestPermissions(activity, arrayOf(mdnsPermission()), REQ_MDNS)
    }

    /** Guarda o que fazer quando a resposta da permissão de descoberta chegar. */
    private var pendingMdns: ((Boolean) -> Unit)? = null

    /** Chamado pelo [PanelActivity.onRequestPermissionsResult]. */
    fun onMdnsResult(granted: Boolean) {
        val cb = pendingMdns
        pendingMdns = null
        cb?.invoke(granted)
    }

    fun ignoringBattery(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * Pede para o app ficar fora da otimização de bateria. Usa o diálogo do
     * sistema (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS) e, se o aparelho não tiver
     * essa tela, cai na lista de otimização padrão.
     */
    fun askBattery(activity: AppCompatActivity) {
        if (ignoringBattery(activity)) return
        try {
            activity.startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:${activity.packageName}"))
            )
        } catch (_: Throwable) {
            try {
                activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Throwable) {
            }
        }
    }

    /** Mostra um aviso no canal do pack (se o usuário permitiu notificações). */
    fun notify(context: Context, text: String) {
        if (!hasNotif(context)) return
        ensureChannel(context)
        try {
            val n = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setContentTitle("Trix")
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(1, n)
        } catch (_: Throwable) {
        }
    }

    /**
     * Pede, uma vez por versão, as permissões do próprio app. Não bloqueia o
     * painel: se o usuário recusar, ele ainda consegue usar tudo (só perde som,
     * notificações e a garantia de rodar em segundo plano).
     */
    fun askOnce(activity: AppCompatActivity) {
        val prefs = activity.getSharedPreferences("otm-perms", Context.MODE_PRIVATE)
        val done = prefs.getBoolean("asked-${BuildConfig.VERSION_NAME}", false)
        if (done) return

        if (!hasNotif(activity)) {
            askNotif(activity)
        }
        if (!ignoringBattery(activity)) {
            AlertDialog.Builder(activity)
                .setTitle("Deixar o pack sempre ativo")
                .setMessage(
                    "Para as otimizações não pararem sozinhas, libere o app da economia " +
                        "de bateria. Você também pode fazer isso depois em Configurações."
                )
                .setPositiveButton("Liberar") { _, _ -> askBattery(activity) }
                .setNegativeButton("Agora não", null)
                .show()
        }
        // Acesso ao uso: é o que dá as métricas reais da Home (app em primeiro
        // plano e tempo de uso). Sem isso a Home ainda funciona pelo shell, só
        // fica sem esses dois números. O sistema exige que o usuário libere.
        if (!Usage.granted(activity)) {
            AlertDialog.Builder(activity)
                .setTitle("Ver o uso real do aparelho")
                .setMessage(
                    "Autorize o Acesso a dados de uso para o painel mostrar qual app está " +
                        "em primeiro plano e quanto você usou nas últimas 24 h — lido do " +
                        "próprio sistema. É opcional e pode ser desligado quando quiser."
                )
                .setPositiveButton("Autorizar") { _, _ -> Usage.openSettings(activity) }
                .setNegativeButton("Agora não", null)
                .show()
        }
        prefs.edit().putBoolean("asked-${BuildConfig.VERSION_NAME}", true).apply()
    }
}
