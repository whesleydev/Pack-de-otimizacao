package com.otm.pack

import android.content.Context
import android.net.wifi.WifiManager
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import io.github.muntashirakon.adb.AdbStream
import io.github.muntashirakon.adb.LocalServices
import io.github.muntashirakon.adb.android.AdbMdns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.DatagramPacket
import java.net.InetAddress
import java.net.MulticastSocket
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.security.interfaces.RSAPrivateCrtKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.RSAPublicKeySpec
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
    private var multicastLock: WifiManager.MulticastLock? = null

    val isConnected: Boolean get() = connection?.isConnectionEstablished == true

    /** Faz o pareamento por código (a porta é a que aparece em "Parear por código"). */
    suspend fun pair(host: String, port: Int, code: String): ExecResult = try {
        val mgr = mgr(host)
        mgr.setTimeout(20, TimeUnit.SECONDS)
        val ok = mgr.pair(host, port, code)
        if (ok) ExecResult(0, "Pareado com $host:$port.", "") else ExecResult(1, "", "Pareamento recusado.")
    } catch (t: Throwable) {
        ExecResult(1, "", "Falha ao parear: ${describe(t)}")
    }

    /**
     * Pareia só com o código de 6 números: descobre sozinho o serviço de
     * pareamento (`_adb-tls-pairing._tcp`) pela rede, como os apps que mostram
     * "só digite o código".
     */
    suspend fun pairWithCode(code: String, timeoutMs: Long = 15000): ExecResult {
        val info = discover(AdbMdns.SERVICE_TYPE_TLS_PAIRING, timeoutMs)
            ?: return ExecResult(1, "", noServiceMsg("pareamento"))
        // o serviço de pareamento roda no próprio aparelho: o IP descoberto pela
        // rede pode estar bloqueado, então o loopback é o plano B.
        var last = ""
        for (host in candidates(info)) {
            val r = try {
                val mgr = mgr(host)
                mgr.setTimeout(20, TimeUnit.SECONDS)
                if (mgr.pair(host, info.port, code)) ExecResult(0, "Pareado com $host:${info.port}.", "")
                else ExecResult(1, "", "Pareamento recusado. Confira o código.")
            } catch (t: Throwable) {
                ExecResult(1, "", "Falha ao parear: ${describe(t)}")
            }
            if (r.ok) return r
            last = r.stderr
        }
        return ExecResult(1, "", last.ifBlank { "Pareamento recusado. Confira o código." })
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
            for (host in candidates(info)) {
                val r = connectTo(host, info.port, "Não conectou em $host:${info.port}.")
                if (r.ok) return r
            }
        }
        return connectLocal()
    }

    /**
     * Confirma que a conexão é REAL: `connect()` devolver `true` só diz que o
     * socket abriu, não que o shell responde. Sem esta checagem o painel dizia
     * "conectado" e toda ação falhava depois. Se o comando de teste não voltar,
     * a conexão é descartada em vez de ficar pela metade.
     */
    suspend fun verify(timeoutMs: Long = 8000): ExecResult {
        if (!isConnected) return ExecResult(1, "", "ADB não conectado.")
        return try {
            val r = withTimeoutOrNull(timeoutMs) { exec("echo otm-ok") }
                ?: return ExecResult(1, "", "O aparelho não respondeu ao teste (pareamento incompleto).")
            if (r.ok && r.stdout.contains("otm-ok")) ExecResult(0, "Shell respondendo.", "")
            else ExecResult(1, "", "O shell não respondeu ao teste.")
        } catch (t: Throwable) {
            ExecResult(1, "", "Falha no teste da conexão: ${describe(t)}")
        }
    }

    /** Igual a [verify], mas reconecta antes: o adbd demora a publicar o serviço após parear. */
    suspend fun connectAndVerify(attempts: Int = 3, waitMs: Long = 1500): ExecResult {
        var last = ExecResult(1, "", "não tentou conectar")
        for (i in 0 until attempts) {
            if (i > 0) delay(waitMs)
            val c = connectWireless()
            if (!c.ok) { last = c; continue }
            val v = verify()
            if (v.ok) return c
            last = v
            close()
        }
        return last
    }

    /** Descobre um serviço mDNS e devolve host:porta (null se não achar). */
    private suspend fun discover(serviceType: String, timeoutMs: Long): HostPort? =
        discoverViaNsd(serviceType, timeoutMs) ?: discoverViaMulticast(serviceType, timeoutMs)

    /**
     * Descobre pelo NsdManager do sistema. A lib cria o NsdManager e usa os
     * callbacks do serviço de descoberta: como o NsdManager entrega os eventos no
     * Looper de quem o criou, isto PRECISA rodar na thread principal (o
     * `Dispatchers.IO` de antes deixava a descoberta muda).
     */
    private suspend fun discoverViaNsd(serviceType: String, timeoutMs: Long): HostPort? =
        withContext(Dispatchers.Main) {
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
                withContext(Dispatchers.IO) { latch.await(timeoutMs, TimeUnit.MILLISECONDS) }
            } catch (_: Throwable) {
            } finally {
                try { mdns.stop() } catch (_: Throwable) {}
            }
            ref.get()
        }

    /**
     * Plano B: consulta mDNS própria. O NsdManager do sistema falha em algumas
     * redes/aparelhos (e a lib ignora o erro em silêncio), então aqui a consulta
     * multicast é enviada e a resposta é lida na mão.
     */
    private suspend fun discoverViaMulticast(serviceType: String, timeoutMs: Long): HostPort? =
        withContext(Dispatchers.IO) {
            val query = buildMdnsQuery("_$serviceType._tcp.local")
            val group = try { InetAddress.getByName("224.0.0.251") } catch (_: Throwable) { return@withContext null }
            val socket = try { MulticastSocket() } catch (_: Throwable) { return@withContext null }
            holdMulticast(true)
            try {
                socket.reuseAddress = true
                socket.soTimeout = 700
                socket.joinGroup(group)
                socket.send(DatagramPacket(query, query.size, group, 5353))
                val deadline = System.currentTimeMillis() + timeoutMs
                val buf = ByteArray(4096)
                while (System.currentTimeMillis() < deadline) {
                    val pkt = DatagramPacket(buf, buf.size)
                    val ok = try { socket.receive(pkt); true } catch (_: Throwable) { false }
                    if (!ok) continue
                    val answer = parseMdnsAnswer(pkt.data.copyOf(pkt.length))
                    if (answer != null) return@withContext answer
                }
                null
            } catch (_: Throwable) {
                null
            } finally {
                try { socket.leaveGroup(group) } catch (_: Throwable) {}
                try { socket.close() } catch (_: Throwable) {}
                holdMulticast(false)
            }
        }

    /**
     * O multicast mDNS só chega ao app com o Wi-Fi Multicast "segurado"; sem isso
     * o Android filtra os pacotes e nenhum serviço aparece.
     */
    private fun holdMulticast(hold: Boolean) {
        try {
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
            if (hold) {
                if (multicastLock == null) {
                    multicastLock = wifi.createMulticastLock("otm-mdns").apply { setReferenceCounted(false) }
                }
                multicastLock?.takeIf { !it.isHeld }?.acquire()
            } else {
                multicastLock?.takeIf { it.isHeld }?.release()
            }
        } catch (_: Throwable) {
        }
    }

    private fun candidates(info: HostPort): List<String> {
        val out = LinkedHashSet<String>()
        if (info.host.isNotBlank()) out.add(info.host)
        out.add("127.0.0.1")
        return out.toList()
    }

    private fun noServiceMsg(what: String): String = if (hasNearbyPermission()) {
        "Não achei o serviço de $what. Abra \"Depuração sem fio\", toque em \"Parear com código\" e deixe a tela aberta."
    } else {
        "Falta a permissão de \"Dispositivos próximos\". Toque em \"Conectar\" e permita quando o Android pedir."
    }

    /** Android 13+ pede NEARBY_WIFI_DEVICES para a descoberta de serviços. */
    private fun hasNearbyPermission(): Boolean {
        val perm = if (android.os.Build.VERSION.SDK_INT >= 33) "android.permission.NEARBY_WIFI_DEVICES"
        else "android.permission.ACCESS_FINE_LOCATION"
        return context.checkSelfPermission(perm) == android.content.pm.PackageManager.PERMISSION_GRANTED
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
        ExecResult(1, "", "Falha ao conectar: ${describe(t)}")
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
            ExecResult(1, "", "Erro no ADB: ${describe(t)}")
        }
    }

    override fun close() {
        holdMulticast(false)
        try { connection?.close() } catch (_: Throwable) {}
        try { manager?.close() } catch (_: Throwable) {}
    }

    /** Traduz o erro cru numa dica útil (o TLS do pareamento é o que mais falha). */
    private fun describe(t: Throwable): String {
        val msg = t.message.orEmpty()
        return when {
            t is java.security.SignatureException ||
                msg.contains("exportKeyingMaterial", true) ||
                msg.contains("Conscrypt", true) ->
                "o TLS do pareamento falhou neste aparelho. Tente de novo; se repetir, use o Shizuku."
            else -> msg.ifBlank { t.javaClass.simpleName }
        }
    }

    private fun mgr(host: String): AbsAdbConnectionManager {
        // O endereço é reaplicado a cada chamada: o plano B (loopback) e o plano A
        // (host descoberto) compartilham o mesmo objeto, e antes o segundo ficava
        // com o endereço do primeiro — a conexão "caía" sempre no mesmo lugar.
        manager?.let { it.hostAddress = host; return it }
        val m = object : AbsAdbConnectionManager() {
            override fun getPrivateKey(): PrivateKey = adbKeyPair.private
            override fun getCertificate(): Certificate = adbCertificate
            override fun getDeviceName(): String = "00deUdia Pack Otimizacao"
        }
        m.setApi(android.os.Build.VERSION.SDK_INT)
        m.setTimeout(15, TimeUnit.SECONDS)
        m.hostAddress = host
        manager = m
        return m
    }

    // --- chave/certificado próprios, guardados nos arquivos do app ------------
    //
    // A chave privada e o certificado precisam ser SEMPRE do mesmo par: o TLS do
    // pareamento assina com a privada e apresenta o certificado. Se os dois não
    // casarem, o handshake morre com SignatureException e o pareamento nunca
    // completa. Por isso o certificado é derivado da MESMA privada lida do disco
    // (e não de um par novo, como acontecia antes quando o .pem faltava).

    private val adbKeyPair: KeyPair by lazy { loadOrCreateKeyPair() }

    private fun loadOrCreateKeyPair(): KeyPair {
        val f = File(context.filesDir, "adbkey.pk8")
        val priv = if (f.exists()) {
            try {
                KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(f.readBytes()))
            } catch (_: Throwable) {
                null
            }
        } else {
            null
        }
        if (priv != null) return KeyPair(publicFrom(priv), priv)

        val gen = KeyPairGenerator.getInstance("RSA")
        gen.initialize(2048, SecureRandom())
        val kp = gen.generateKeyPair()
        f.writeBytes(kp.private.encoded)
        return kp
    }

    /** Reconstrói a pública a partir da privada (o PKCS#8 guardado não traz a pública). */
    private fun publicFrom(priv: PrivateKey): java.security.PublicKey? = try {
        val crt = priv as RSAPrivateCrtKey
        KeyFactory.getInstance("RSA").generatePublic(RSAPublicKeySpec(crt.modulus, crt.publicExponent))
    } catch (_: Throwable) {
        null
    }

    private val adbCertificate: Certificate by lazy {
        val f = File(context.filesDir, "adbcert.pem")
        if (f.exists()) {
            val cert = try {
                f.inputStream().use { CertificateFactory.getInstance("X.509").generateCertificate(it) }
            } catch (_: Throwable) {
                null
            }
            // certificado de um par antigo: joga fora e refaz a partir da chave atual
            if (cert != null && cert.publicKey == adbKeyPair.public) return@lazy cert
        }
        val cert = SelfSignedCert.generate("CN=00deUdia Pack Otimizacao", adbKeyPair)
        f.writeBytes(cert.encoded)
        cert
    }

    // --- mDNS na mão (plano B do NsdManager) ---------------------------------

    private fun buildMdnsQuery(name: String): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0))
        for (label in name.split('.')) {
            if (label.isEmpty()) continue
            val b = label.toByteArray(Charsets.UTF_8)
            out.write(b.size)
            out.write(b)
        }
        out.write(0)
        out.write(byteArrayOf(0, 12, 0, 1)) // QTYPE=PTR, QCLASS=IN
        return out.toByteArray()
    }

    /** Lê a resposta mDNS e devolve host:porta do primeiro SRV com registro A. */
    private fun parseMdnsAnswer(data: ByteArray): HostPort? {
        if (data.size < 12) return null
        fun u8(i: Int) = data[i].toInt() and 0xFF
        fun u16(i: Int) = (u8(i) shl 8) or u8(i + 1)

        val questions = u16(4)
        val records = u16(6) + u16(8) + u16(10)
        var pos = 12
        repeat(questions) {
            pos = skipName(data, pos)
            pos += 4
        }
        var port = -1
        var host: String? = null
        var i = 0
        while (i < records && pos >= 0 && pos + 10 <= data.size) {
            pos = skipName(data, pos)
            if (pos < 0 || pos + 10 > data.size) break
            val type = u16(pos)
            val len = u16(pos + 8)
            val rd = pos + 10
            if (rd + len > data.size) break
            when (type) {
                // SRV: prioridade(2) + peso(2) + porta(2) + alvo
                0x21 -> if (len >= 6) port = u16(rd + 4)
                // A: endereço IPv4
                0x01 -> if (len == 4) host = "${u8(rd)}.${u8(rd + 1)}.${u8(rd + 2)}.${u8(rd + 3)}"
            }
            pos = rd + len
            i++
        }
        if (port <= 0) return null
        // sem registro A na resposta, o serviço é do próprio aparelho
        return HostPort(host ?: "127.0.0.1", port)
    }

    private fun skipName(data: ByteArray, start: Int): Int {
        var p = start
        while (p < data.size) {
            val len = data[p].toInt() and 0xFF
            if (len == 0) return p + 1
            if (len and 0xC0 == 0xC0) return p + 2
            p += len + 1
        }
        return -1
    }
}
