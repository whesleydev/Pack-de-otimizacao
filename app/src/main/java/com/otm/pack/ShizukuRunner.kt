package com.otm.pack

import android.content.pm.PackageManager
import android.os.RemoteException
import moe.shizuku.server.IRemoteProcess
import moe.shizuku.server.IShizukuService
import rikka.shizuku.Shizuku

/**
 * Executa comandos com privilégio de shell (uid 2000) usando o Shizuku.
 *
 * O Shizuku roda um serviço em `shell` (via ADB ou root) e o app pede permissão
 * a ele. Falamos com esse serviço por Binder: `newProcess` cria um processo
 * remoto e devolve três descritores (entrada, saída, erros). O AIDL fica em
 * `src/main/aidl/moe/shizuku/server/` (contrato público do Shizuku, Apache-2.0).
 */
class ShizukuRunner : ShellRunner {

    override val label = "Shizuku"

    private val service: IShizukuService?
        get() = try {
            val binder = Shizuku.getBinder()
            if (binder == null || !binder.pingBinder()) null
            else IShizukuService.Stub.asInterface(binder)
        } catch (t: Throwable) {
            null
        }

    fun isAvailable(): Boolean = service != null

    /** Já temos permissão concedida? */
    fun hasPermission(): Boolean = try {
        Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (t: Throwable) {
        false
    }

    /**
     * Pede a permissão do Shizuku (mostra o diálogo do próprio Shizuku).
     *
     * Devolve `false` quando o binder ainda não chegou: o
     * `Shizuku.requestPermission` lança nesse caso, e pedir permissão antes do
     * binder existir é o que fazia o diálogo reaparecer a cada abertura do app.
     */
    fun requestPermission(requestCode: Int): Boolean = try {
        if (!isAvailable()) false
        else {
            Shizuku.requestPermission(requestCode)
            true
        }
    } catch (t: Throwable) {
        false
    }

    override suspend fun exec(command: String, stdin: String?): ExecResult {
        val svc = service ?: return ExecResult(1, "", "Shizuku indisponível (serviço não iniciado).")
        var process: IRemoteProcess? = null
        return try {
            process = svc.newProcess(arrayOf("/system/bin/sh", "-c", command), null, null)
            if (stdin != null) {
                try {
                    android.os.ParcelFileDescriptor.AutoCloseOutputStream(process.outputStream).use {
                        it.write(stdin.toByteArray(Charsets.UTF_8))
                        it.flush()
                    }
                } catch (_: Throwable) {
                }
            }
            val stdout = android.os.ParcelFileDescriptor.AutoCloseInputStream(process.inputStream).readAllText()
            val stderr = android.os.ParcelFileDescriptor.AutoCloseInputStream(process.errorStream).readAllText()
            val code = try { process.waitFor() } catch (t: Throwable) { -1 }
            ExecResult(code, stdout, stderr)
        } catch (e: RemoteException) {
            ExecResult(1, "", "Falha no Shizuku: ${e.message}")
        } catch (t: Throwable) {
            ExecResult(1, "", "Erro ao executar: ${t.message}")
        } finally {
            try { process?.destroy() } catch (_: Throwable) {}
        }
    }
}
