package com.otm.pack

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * Backup das configurações num arquivo criptografado, na pasta do app.
 *
 * Fluxo:
 *   salvar  -> roda `backup.sh collect` (o estado vira texto), cifra com AES-GCM
 *              e grava o arquivo na pasta do app no armazenamento compartilhado;
 *   voltar  -> lê o arquivo, decifra e manda o texto de volta ao aparelho, onde
 *              `backup.sh restore` devolve as configurações.
 *
 * A chave é gerada AQUI e vive no Android Keystore (não sai do aparelho, não vai
 * para o arquivo). É por isso que o backup é seguro em repouso: sem a chave do
 * Keystore, o conteúdo do arquivo não é legível — e o GCM ainda garante que
 * ninguém conseguiu editar o arquivo sem ser notado.
 *
 * O texto trafega pelo stdout do script (não por arquivo compartilhado), porque
 * o usuário `shell` do Shizuku/ADB não lê a pasta privada do app — e a pasta
 * compartilhada do app (Android/data) é restrita no Android 11+. Na volta, o
 * texto é escrito em /data/local/tmp (que o shell lê) só durante a restauração.
 */
object OtmBackup {

    private const val KEY_ALIAS = "trix-backup-key"
    private const val KEYSTORE = "AndroidKeyStore"
    private const val DIR_NAME = "Trix"
    private const val STAGE = "/data/local/tmp/trix-restore.txt"

    /** Pasta do app no armazenamento do telefone (sem precisar de permissão). */
    fun dir(context: Context): File =
        File(context.getExternalFilesDir(null) ?: context.filesDir, DIR_NAME)

    // ---- chave ---------------------------------------------------------------

    /**
     * Chave do Keystore, criada na primeira vez. Fica presa ao aparelho: o backup
     * feito aqui só abre aqui (o que também protege o arquivo se ele vazar).
     */
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        gen.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(OtmBackupCore.KEY_LEN * 8)
                .build()
        )
        return gen.generateKey()
    }

    // ---- salvar --------------------------------------------------------------

    /** Lê o estado atual pelo script, cifra e grava o arquivo. */
    fun export(context: Context, runner: ShellRunner?): String {
        val res = OtmExec.run(context, runner, "backup.sh", listOf("collect"))
        val plano = res.stdout.trim()
        if (!plano.startsWith("#TRIX-BACKUP-V1")) {
            val erro = listOf(res.stderr, res.stdout).joinToString(" ").trim()
            return err("não consegui ler as configurações do aparelho" +
                (if (erro.isNotBlank()) ": " + erro.lineSequence().last().trim() else ""))
        }

        val d = dir(context)
        if (!d.isDirectory && !d.mkdirs()) return err("não consegui criar a pasta ${d.absolutePath}")

        val nome = "trix-config-" + java.text.SimpleDateFormat("yyyy-MM-dd_HHmmss", java.util.Locale.US)
            .format(java.util.Date()) + ".txt"
        val f = File(d, nome)
        return try {
            f.writeText(OtmBackupCore.seal(plano, key()))
            // o arquivo tem de ser do usuário: legível quando ele copiar para o PC
            f.setReadable(true, false)
            val n = plano.lineSequence().count { it.startsWith("global ") || it.startsWith("system ") || it.startsWith("setprop ") }
            JSONObject().put("ok", true)
                .put("file", f.absolutePath)
                .put("name", nome)
                .put("keys", n)
                .put("out", "configurações salvas em $nome ($n chaves).\n\n" +
                    "Arquivo: ${f.absolutePath}\n" +
                    "Guardado criptografado (AES-256-GCM). Para voltar depois, use \"Restaurar configurações\".")
                .toString()
        } catch (t: Throwable) {
            err("não consegui gravar o arquivo: ${t.message}")
        }
    }

    // ---- voltar --------------------------------------------------------------

    /**
     * Decifra o arquivo mais recente e devolve as configurações. Se houver mais
     * de um, usa o último — é o que o usuário espera ("volta ao que salvei").
     */
    fun import(context: Context, runner: ShellRunner?): String {
        val arquivos = listFiles(context)
        val f = arquivos.maxByOrNull { it.lastModified() }
            ?: return err("nenhum arquivo de configuração salvo. Use \"Salvar configurações\" antes.")

        val texto = try { f.readText() } catch (t: Throwable) {
            return err("não consegui ler ${f.name}: ${t.message}")
        }
        if (!OtmBackupCore.isEnvelope(texto)) {
            return err("${f.name} não é um backup do Trix — não vou aplicar.")
        }

        val plano = try {
            OtmBackupCore.open(texto, key())
        } catch (t: Throwable) {
            return err(t.message ?: "não consegui abrir o backup")
        }
        if (!plano.startsWith("#TRIX-BACKUP-V1")) return err("o conteúdo do backup está vazio ou inválido")

        val r = runner ?: return err("sem acesso (conecte o Shizuku ou o ADB) para aplicar as configurações")

        // o shell precisa enxergar o texto; a pasta privada do app ele não lê
        val w = runBlocking { r.writeFile(STAGE, plano) }
        if (!w.ok) return err("não consegui preparar o arquivo para o aparelho: ${w.stderr.trim()}")

        val res = OtmExec.run(context, runner, "backup.sh", listOf("restore", STAGE))
        runBlocking { r.exec("rm -f '$STAGE'") }   // não deixa o texto claro para trás

        val saida = joinOutput(res.stdout, res.stderr)
        val ok = res.ok && saida.contains("restaur")
        return JSONObject()
            .put("ok", ok)
            .put("file", f.absolutePath)
            .put("name", f.name)
            .put("out", (if (ok) "configurações restauradas de ${f.name}.\n\n" else "falhou ao restaurar.\n\n") + saida)
            .toString()
    }

    // ---- listar --------------------------------------------------------------

    private fun listFiles(context: Context): List<File> =
        dir(context).listFiles { f -> f.isFile && f.name.endsWith(".txt") }?.toList() ?: emptyList()

    fun list(context: Context): String {
        val arr = JSONArray()
        val arquivos = listFiles(context).sortedByDescending { it.lastModified() }
        for (f in arquivos) {
            arr.put(
                JSONObject()
                    .put("name", f.name)
                    .put("bytes", f.length())
                    .put("date", java.text.SimpleDateFormat("dd/MM/yyyy HH:mm", java.util.Locale.US)
                        .format(java.util.Date(f.lastModified())))
                    .put("path", f.absolutePath)
            )
        }
        val txt = if (arquivos.isEmpty())
            "Nenhum arquivo salvo ainda. Toque em \"Salvar configurações\" para criar o primeiro."
        else
            arquivos.joinToString("\n") { "• ${it.name}  (${it.length()} bytes)" } +
                "\n\nPasta: ${dir(context).absolutePath}"
        return JSONObject().put("ok", true).put("files", arr).put("out", txt).toString()
    }

    private fun err(msg: String): String = JSONObject().put("ok", false).put("out", msg).toString()
}
