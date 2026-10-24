package com.otm.pack

import android.util.Base64
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Licença offline: lê e confere o bilhete assinado que o painel entrega.
 *
 * O bilhete ("OTM1.<payload>.<assinatura>") carrega a validade da chave e um
 * prazo de uso sem internet. A assinatura é **Ed25519**, feita com a chave
 * privada que só existe no servidor; aqui só mora a chave pública (embarcada no
 * build). Por isso ninguém consegue forjar uma licença só lendo o APK — e o app
 * consegue dizer "ainda vale" sem perguntar a ninguém.
 *
 * O relógio do aparelho não é confiável sozinho: quem guarda o bilhete também
 * guarda a hora que o servidor disse. Se o relógio andar para trás, a licença é
 * recusada (senão bastava voltar a data para nunca expirar).
 */
object License {

    private const val PREFIX = "OTM1"

    /** O que o bilhete diz. Datas em ISO UTC "yyyy-MM-dd HH:mm:ss". */
    data class Claims(
        val keyHash: String,
        val keyId: Int,
        val label: String,
        val deviceId: String,
        val expiresAt: String,     // "" = vitalícia
        val issuedAt: String,
        val offlineUntil: String,
        val graceDays: Int,
        val maxUses: Int,
        val usesCount: Int,
    )

    /** Chave pública embarcada no build (BuildConfig). Vazio = licença desligada. */
    fun publicKey(): String = BuildConfig.LICENSE_PUB.trim()

    /** A licença está ligada neste build? */
    fun isConfigured(): Boolean = publicKey().isNotEmpty()

    /**
     * Confere a assinatura e devolve as claims. Devolve null quando o bilhete
     * está malformado, foi adulterado ou a chave pública não confere.
     */
    fun verify(lease: String): Claims? {
        val pub = publicKey()
        if (pub.isEmpty()) return null

        val parts = lease.trim().split('.')
        if (parts.size != 3 || parts[0] != PREFIX) return null

        val payload = try {
            Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        } catch (_: Throwable) { return null }
        val sig = try {
            Base64.decode(parts[2], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        } catch (_: Throwable) { return null }

        val signed = "$PREFIX.${parts[1]}".toByteArray(Charsets.UTF_8)
        val pubKey = try {
            Ed25519PublicKeyParameters(Base64.decode(pub, Base64.DEFAULT), 0)
        } catch (_: Throwable) { return null }

        val ok = try {
            val signer = Ed25519Signer()
            signer.init(false, pubKey)
            signer.update(signed, 0, signed.size)
            signer.verifySignature(sig)
        } catch (_: Throwable) { false }
        if (!ok) return null

        return try {
            val j = JSONObject(String(payload, Charsets.UTF_8))
            Claims(
                keyHash      = j.optString("h", ""),
                keyId        = j.optInt("k", 0),
                label        = j.optString("l", ""),
                deviceId     = j.optString("d", ""),
                expiresAt    = j.optString("e", ""),
                issuedAt     = j.optString("i", ""),
                offlineUntil = j.optString("o", ""),
                graceDays    = j.optInt("g", 0),
                maxUses      = j.optInt("m", 0),
                usesCount    = j.optInt("u", 0),
            )
        } catch (_: Throwable) { null }
    }

    /** Converte "yyyy-MM-dd HH:mm:ss" (UTC) em epoch segundos. 0 se ilegível. */
    fun epoch(utc: String): Long {
        if (utc.isBlank()) return 0L
        return try {
            val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
            fmt.timeZone = TimeZone.getTimeZone("UTC")
            (fmt.parse(utc)?.time ?: 0L) / 1000L
        } catch (_: Throwable) { 0L }
    }

    /** Dias (inteiros, arredondando para cima) entre agora e uma data UTC. */
    fun daysUntil(utc: String, nowEpoch: Long): Int {
        val t = epoch(utc)
        if (t == 0L) return 0
        return Math.ceil((t - nowEpoch).toDouble() / 86400.0).toInt()
    }
}
