package com.otm.pack

import android.content.pm.PackageManager
import android.os.RemoteException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
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

    /** Processo em execução agora (para o "parar" do Terminal). */
    @Volatile private var current: IRemoteProcess? = null

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

    /**
     * Modo ao vivo do Terminal: lê stdout e stderr em paralelo e entrega cada
     * pedaço assim que chega. Ler os dois ao mesmo tempo (em vez de um depois do
     * outro) evita o deadlock clássico do pipe cheio — um comando que escreve
     * muito no stderr travaria esperando alguém ler.
     */
    override suspend fun execStream(command: String, onChunk: (String) -> Unit): ExecResult {
        val svc = service ?: return ExecResult(1, "", "Shizuku indisponível (serviço não iniciado).")
        var process: IRemoteProcess? = null
        return try {
            val proc = svc.newProcess(arrayOf("/system/bin/sh", "-c", command), null, null)
            process = proc
            current = proc
            val all = StringBuilder()
            val lock = Any()
            fun emit(s: String) {
                if (s.isEmpty()) return
                synchronized(lock) { all.append(s) }
                onChunk(s)
            }
            coroutineScope {
                val out = async(Dispatchers.IO) { pump(proc.inputStream, ::emit) }
                val err = async(Dispatchers.IO) { pump(proc.errorStream, ::emit) }
                out.await(); err.await()
            }
            val code = try { proc.waitFor() } catch (t: Throwable) { -1 }
            ExecResult(code, all.toString(), "")
        } catch (e: RemoteException) {
            ExecResult(1, "", "Falha no Shizuku: ${e.message}")
        } catch (t: Throwable) {
            ExecResult(1, "", "Erro ao executar: ${t.message}")
        } finally {
            current = null
            try { process?.destroy() } catch (_: Throwable) {}
        }
    }

    override fun cancel() {
        try { current?.destroy() } catch (_: Throwable) {}
    }

    /** Lê um descritor do processo remoto em pedaços e manda para [sink]. */
    private fun pump(pfd: android.os.ParcelFileDescriptor, sink: (String) -> Unit) {
        try {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(pfd).use { ins ->
                val reader = java.io.InputStreamReader(ins, Charsets.UTF_8)
                val buf = CharArray(4096)
                while (true) {
                    val n = reader.read(buf)
                    if (n <= 0) break
                    sink(String(buf, 0, n))
                }
            }
        } catch (_: Throwable) {
        }
    }
}
