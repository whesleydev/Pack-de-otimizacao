package com.otm.pack

import android.content.Context
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import io.github.muntashirakon.adb.AdbStream
import io.github.muntashirakon.adb.LocalServices
import io.github.muntashirakon.adb.android.AdbMdns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Conecta ao `adbd` do próprio aparelho por Wi-Fi (depuração sem fio) e executa
 * comandos com privilégio de shell.
 *
 * Há dois caminhos:
 *  - Depuração sem fio (Android 11+): é preciso parear antes. `pair(host, porta,
 *    código)`; depois a conexão normal em `host:porta` reaproveita a chave já
 *    autorizada.
 *  - Depuração USB clássica (adbd ouvindo em TCP, ex.: `adb tcpip 5555`): não
 *    pede pareamento, só o "Permitir depuração USB". [connectLocal] acha o `adbd`
 *    no próprio aparelho (loopback ou mDNS `_adb._tcp`) e conecta.
 */
class AdbRunner(private val context: Context) : ShellRunner {

    override val label = "ADB (Wi-Fi)"

    private var manager: AbsAdbConnectionManager? = null
    private var connection: io.github.muntashirakon.adb.AdbConnection? = null

    val isConnected: Boolean get() = connection?.isConnectionEstablished == true

    /** Faz o pareamento por código (a porta é a que aparece em "Parear por código"). */
    suspend fun pair(host: String, port: Int, code: String): ExecResult = try {
        val mgr = mgr(host)
        mgr.setTimeout(20, TimeUnit.SECONDS)
        val ok = mgr.pair(host, port, code)
        if (ok) ExecResult(0, "Pareado com $host:$port.", "") else ExecResult(1, "", "Pareamento recusado.")
    } catch (t: Throwable) {
        ExecResult(1, "", "Falha ao parear: ${t.message}")
    }

    /**
     * Pareia só com o código de 6 números: descobre sozinho o serviço de
     * pareamento (`_adb-tls-pairing._tcp`) pela rede, como os apps que mostram
     * "só digite o código". Devolve o endereço descoberto para a conexão seguinte.
     */
    suspend fun pairWithCode(code: String, timeoutMs: Long = 15000): ExecResult {
        val info = discover(AdbMdns.SERVICE_TYPE_TLS_PAIRING, timeoutMs)
            ?: return ExecResult(1, "", "Não achei o serviço de pareamento. Abra \"Depuração sem fio\" e toque em \"Parear com código\".")
        return try {
            val mgr = mgr(info.host)
            mgr.setTimeout(20, TimeUnit.SECONDS)
            val ok = mgr.pair(info.host, info.port, code)
            if (ok) ExecResult(0, "Pareado com ${info.host}:${info.port}.", "")
            else ExecResult(1, "", "Pareamento recusado. Confira o código.")
        } catch (t: Throwable) {
            ExecResult(1, "", "Falha ao parear: ${t.message}")
        }
    }

    /**
     * Conecta à depuração sem fio sem digitar porta: descobre o serviço
     * `_adb-tls-connect._tcp` (ou `_adb._tcp`) e conecta. Se não achar, tenta o
     * loopback (ADB em TCP no próprio aparelho).
     */
    suspend fun connectWireless(timeoutMs: Long = 15000): ExecResult {
        val info = discover(AdbMdns.SERVICE_TYPE_TLS_CONNECT, timeoutMs)
            ?: discover(AdbMdns.SERVICE_TYPE_ADB, 4000)
        if (info != null) {
            val r = connectTo(info.host, info.port, "Não conectou em ${info.host}:${info.port}.")
            if (r.ok) return r
        }
        return connectLocal()
    }

    /** Descobre um serviço mDNS e devolve host:porta (null se não achar). */
    private suspend fun discover(serviceType: String, timeoutMs: Long): HostPort? =
        withContext(Dispatchers.IO) {
            val ref = AtomicReference<HostPort?>(null)
            val latch = CountDownLatch(1)
            val mdns = AdbMdns(context, serviceType) { addr, port ->
                if (addr != null && port > 0) {
                    ref.set(HostPort(addr.hostAddress ?: "127.0.0.1", port))
                    latch.countDown()
                }
            }
            try {
                mdns.start()
                latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            } catch (_: Throwable) {
            } finally {
                try { mdns.stop() } catch (_: Throwable) {}
            }
            ref.get()
        }

    private data class HostPort(val host: String, val port: Int)

    /** Conecta em `host:porta` (a porta da tela "Depuração sem fio"). */
    suspend fun connect(host: String, port: Int): ExecResult =
        connectTo(host, port, "Não conectou. Confira a porta e se o Wi-Fi está na mesma rede.")

    /**
     * Conecta sem parear, no `adbd` do próprio aparelho: tenta o loopback
     * (127.0.0.1:5555, típico de `adb tcpip 5555`) e, se não houver, descobre a
     * porta pela rede (mDNS `_adb._tcp` / `_adb-tls-connect._tcp`). Só exige que a
     * depuração esteja ligada e o "Permitir depuração USB" aceito.
     */
    suspend fun connectLocal(): ExecResult {
        val m = mgr("127.0.0.1")
        // timeout curto por tentativa: são 3 portas + a descoberta mDNS
        m.setTimeout(5, TimeUnit.SECONDS)
        // 1) loopback (adbd em TCP no próprio aparelho)
        for (port in intArrayOf(5555, 5554, 5037)) {
            try {
                if (m.connect("127.0.0.1", port)) {
                    connection = m.adbConnection
                    return ExecResult(0, "Conectado (127.0.0.1:$port).", "")
                }
            } catch (_: Throwable) {
                // tenta o próximo
            }
        }
        // 2) descoberta pela rede (mDNS), ignorando o host fixo
        return try {
            val ok = m.autoConnect(context, 6000)
            connection = m.adbConnection
            if (ok) ExecResult(0, "Conectado (descoberto na rede).", "")
            else ExecResult(1, "", "Não achei o adbd. Ligue a depuração USB e aceite o aviso no celular.")
        } catch (t: Throwable) {
            ExecResult(1, "", "Não achei o adbd. Ligue a depuração USB e aceite o \"Permitir depuração USB\".")
        }
    }

    private suspend fun connectTo(host: String, port: Int, failMsg: String): ExecResult = try {
        val mgr = mgr(host)
        // timeout explícito: sem isso a lib espera para sempre e a UI parece travada
        mgr.setTimeout(15, TimeUnit.SECONDS)
        val ok = mgr.connect(host, port)
        connection = mgr.adbConnection
        if (ok) ExecResult(0, "Conectado a $host:$port.", "") else ExecResult(1, "", failMsg)
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
