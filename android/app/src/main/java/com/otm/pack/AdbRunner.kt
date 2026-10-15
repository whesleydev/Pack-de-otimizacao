package com.otm.pack

import android.content.Context
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import io.github.muntashirakon.adb.AdbStream
import io.github.muntashirakon.adb.LocalServices
import java.io.File
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.concurrent.TimeUnit

/**
 * Conecta ao `adbd` do próprio aparelho por Wi-Fi (depuração sem fio) e executa
 * comandos com privilégio de shell.
 *
 * Primeiro é preciso parear (Android 11+): `pair(host, porta, código)`. Depois a
 * conexão normal em `host:porta` reaproveita a chave já autorizada.
 */
class AdbRunner(private val context: Context) : ShellRunner {

    override val label = "ADB (Wi-Fi)"

    private var manager: AbsAdbConnectionManager? = null
    private var connection: io.github.muntashirakon.adb.AdbConnection? = null

    val isConnected: Boolean get() = connection?.isConnectionEstablished == true

    /** Faz o pareamento por código (a porta é a que aparece em "Parear por código"). */
    suspend fun pair(host: String, port: Int, code: String): ExecResult = try {
        val mgr = mgr(host)
        val ok = mgr.pair(host, port, code)
        if (ok) ExecResult(0, "Pareado com $host:$port.", "") else ExecResult(1, "", "Pareamento recusado.")
    } catch (t: Throwable) {
        ExecResult(1, "", "Falha ao parear: ${t.message}")
    }

    /** Conecta em `host:porta` (a porta da tela "Depuração sem fio"). */
    suspend fun connect(host: String, port: Int): ExecResult = try {
        val mgr = mgr(host)
        val ok = mgr.connect(host, port)
        connection = mgr.adbConnection
        if (ok) ExecResult(0, "Conectado a $host:$port.", "")
        else ExecResult(1, "", "Não conectou. Confira a porta e se o Wi-Fi está na mesma rede.")
    } catch (t: Throwable) {
        ExecResult(1, "", "Falha ao conectar: ${t.message}")
    }

    override suspend fun exec(command: String, stdin: String?): ExecResult {
        val conn = connection ?: return ExecResult(1, "", "ADB não conectado.")
        return try {
            val stream: AdbStream = conn.open(LocalServices.SHELL, command)
            if (stdin != null) {
                try {
                    stream.openOutputStream().use { it.write(stdin.toByteArray(Charsets.UTF_8)); it.flush() }
                } catch (_: Throwable) {
                }
            }
            val stdout = stream.openInputStream().readAllText()
            try { stream.close() } catch (_: Throwable) {}
            ExecResult(0, stdout, "")
        } catch (t: Throwable) {
            ExecResult(1, "", "Erro no ADB: ${t.message}")
        }
    }

    override fun close() {
        try { connection?.close() } catch (_: Throwable) {}
        try { manager?.close() } catch (_: Throwable) {}
    }

    private fun mgr(host: String): AbsAdbConnectionManager {
        manager?.let { return it }
        val m = object : AbsAdbConnectionManager() {
            override fun getPrivateKey(): PrivateKey = keyPair.private
            override fun getCertificate(): Certificate = loadOrCreateCert(keyPair)
            override fun getDeviceName(): String = "00deUdia Pack Otimizacao"
        }
        m.setApi(android.os.Build.VERSION.SDK_INT)
        m.setTimeout(15, TimeUnit.SECONDS)
        m.hostAddress = host
        manager = m
        return m
    }

    // --- chave/certificado próprios, guardados nos arquivos do app ------------

    private val keyPair: KeyPair by lazy { loadOrCreateKeyPair() }

    private fun loadOrCreateKeyPair(): KeyPair {
        val f = File(context.filesDir, "adbkey.pk8")
        if (f.exists()) {
            val priv = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(f.readBytes()))
            return KeyPair(null, priv)
        }
        val gen = KeyPairGenerator.getInstance("RSA")
        gen.initialize(2048, SecureRandom())
        val kp = gen.generateKeyPair()
        f.writeBytes(kp.private.encoded)
        return kp
    }

    private fun loadOrCreateCert(kp: KeyPair): Certificate {
        val f = File(context.filesDir, "adbcert.pem")
        if (f.exists()) {
            return f.inputStream().use { CertificateFactory.getInstance("X.509").generateCertificate(it) }
        }
        // KeyPair(public=null) quando a chave veio do disco: gera um par novo junto.
        val pair = if (kp.public != null) kp else {
            val gen = KeyPairGenerator.getInstance("RSA")
            gen.initialize(2048, SecureRandom())
            gen.generateKeyPair().also { File(context.filesDir, "adbkey.pk8").writeBytes(it.private.encoded) }
        }
        val cert = SelfSignedCert.generate("CN=00deUdia Pack Otimizacao", pair)
        f.writeBytes(cert.encoded)
        return cert
    }
}
