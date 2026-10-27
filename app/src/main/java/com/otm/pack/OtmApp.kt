package com.otm.pack

import android.app.Application
import android.content.Context
import android.os.Build
import io.github.muntashirakon.adb.PRNGFixes
import org.lsposed.hiddenapibypass.HiddenApiBypass

/**
 * Inicialização do app.
 *
 * O pareamento por Wi-Fi (libadb) fala TLS 1.3 com o `adbd` e, no Android 10+,
 * precisa de APIs internas do Conscrypt (`exportKeyingMaterial`) para amarrar a
 * senha do código ao canal TLS. Sem liberar as APIs ocultas o pareamento falha.
 * É o mesmo passo que o app de exemplo da própria biblioteca faz.
 */
class OtmApp : Application() {

    override fun onCreate() {
        super.onCreate()
        PRNGFixes.apply()
    }

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                HiddenApiBypass.addHiddenApiExemptions("L")
            } catch (_: Throwable) {
                // sem o bypass o resto do app continua funcionando; só o ADB Wi-Fi pode falhar
            }
        }
    }
}
