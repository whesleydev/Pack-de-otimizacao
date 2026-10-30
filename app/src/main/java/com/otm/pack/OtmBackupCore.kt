package com.otm.pack

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Núcleo do backup criptografado — sem nada de Android de propósito.
 *
 * Fica separado do [OtmBackup] (que cuida de Keystore, pastas e do shell) para
 * poder ser exercitado num teste de verdade, fora do aparelho. É aqui que mora
 * a parte que não pode errar: o envelope e a cifra.
 *
 * Formato do arquivo (texto, para o usuário reconhecer o que é):
 *
 *     -----BEGIN TRIX BACKUP-----
 *     AES-256-GCM
 *     <base64 do IV(12 bytes) + texto cifrado + tag(16 bytes)>
 *     -----END TRIX BACKUP-----
 *
 * AES-256-GCM (AEAD) foi escolhido porque além de cifrar ele AUTENTICA: se
 * alguém editar o arquivo, a decifragem falha em vez de aplicar configuração
 * adulterada. O IV é sorteado a cada salvamento — repetir IV em GCM quebraria a
 * cifra, então nunca é reaproveitado.
 */
object OtmBackupCore {

    const val HEADER = "-----BEGIN TRIX BACKUP-----"
    const val FOOTER = "-----END TRIX BACKUP-----"
    private const val ALGO = "AES-256-GCM"
    private const val TRANSFORM = "AES/GCM/NoPadding"
    private const val IV_LEN = 12
    private const val TAG_BITS = 128
    const val KEY_LEN = 32

    /** Chave nova: 256 bits de aleatoriedade criptográfica. */
    fun newKey(): ByteArray = ByteArray(KEY_LEN).also { SecureRandom().nextBytes(it) }

    fun keyFrom(raw: ByteArray): SecretKey {
        require(raw.size == KEY_LEN) { "chave de backup com tamanho inválido" }
        return SecretKeySpec(raw, "AES")
    }

    /** Cifra [plain] e devolve o arquivo em texto, pronto para gravar. */
    fun seal(plain: String, key: SecretKey): String {
        val iv = ByteArray(IV_LEN).also { SecureRandom().nextBytes(it) }
        val c = Cipher.getInstance(TRANSFORM)
        c.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
        val ct = c.doFinal(plain.toByteArray(Charsets.UTF_8))
        val b64 = Base64.getEncoder().encodeToString(iv + ct)
        return buildString {
            append(HEADER).append('\n')
            append(ALGO).append('\n')
            append(b64).append('\n')
            append(FOOTER).append('\n')
        }
    }

    /** O arquivo é um backup nosso? (evita tratar arquivo alheio como backup) */
    fun isEnvelope(text: String): Boolean =
        text.lineSequence().firstOrNull { it.isNotBlank() }?.trim() == HEADER

    /**
     * Abre o arquivo. Lança exceção se o arquivo não for nosso, se a cifra não
     * for conhecida, se estiver adulterado ou se a chave não for a mesma —
     * nesses casos NADA é aplicado (melhor falhar do que restaurar lixo).
     */
    fun open(text: String, key: SecretKey): String {
        val lines = text.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.toList()
        require(lines.size >= 3 && lines[0] == HEADER) { "este arquivo não é um backup do Trix" }
        require(lines[1] == ALGO) { "criptografia não suportada: ${lines[1]}" }
        val raw = try {
            Base64.getDecoder().decode(lines[2])
        } catch (e: IllegalArgumentException) {
            throw IllegalArgumentException("arquivo de backup corrompido")
        }
        require(raw.size > IV_LEN) { "arquivo de backup corrompido" }
        val iv = raw.copyOfRange(0, IV_LEN)
        val ct = raw.copyOfRange(IV_LEN, raw.size)
        val c = Cipher.getInstance(TRANSFORM)
        c.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
        return try {
            String(c.doFinal(ct), Charsets.UTF_8)
        } catch (e: Exception) {
            // tag inválida = arquivo editado OU chave de outro aparelho/instalação
            throw IllegalStateException(
                "não consegui abrir o backup: ele foi alterado ou pertence a outra instalação do app"
            )
        }
    }
}
