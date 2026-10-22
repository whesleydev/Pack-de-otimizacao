package com.otm.pack

import android.content.Context
import java.io.File

/**
 * Prepara o pack para execução.
 *
 * O app roda os scripts com privilégio de shell (Shizuku/ADB), que executa como
 * o usuário `shell` (uid 2000). Esse usuário NÃO consegue ler nem executar nada
 * dentro de `/data/user/0/com.otm.pack` (modo 0700). Por isso os scripts vão
 * para `/data/local/tmp/otm-pack`, que existe justamente para isso e é acessível
 * ao shell. Os `.txt` do nível 1 continuam numa cópia local (o app lê e manda os
 * comandos prontos, sem precisar que o shell enxergue o arquivo).
 */
object PackAssets {

    private const val ASSET_ROOT = "pack"

    /** Onde os scripts rodam (visível ao usuário `shell` do Shizuku/ADB). */
    const val EXEC_DIR = "/data/local/tmp/otm-pack"

    private const val STAMP = ".extracted"

    /** Extrai assets/pack para filesDir/pack (uso local do app: .txt do nível 1). */
    fun ensureExtracted(context: Context): File = ensureExtracted(context, ASSET_ROOT)

    /** Extrai uma pasta de assets para filesDir/<nome> (uma vez por versão). */
    fun ensureExtracted(context: Context, assetRoot: String): File {
        val dest = File(context.filesDir, assetRoot)
        val stamp = File(dest, STAMP)
        if (stamp.exists()) return dest
        dest.deleteRecursively()
        dest.mkdirs()
        copyAssetDir(context, assetRoot, dest)
        stamp.writeText("ok")
        return dest
    }

    /**
     * Copia `assets/pack/scripts` + `VERSION` para [EXEC_DIR], uma vez por versão,
     * e devolve o caminho. Retorna null se não houver runner (sem acesso).
     *
     * A checagem do selo é feita pelo próprio shell, então repetir é barato: só
     * recopia quando o selo não bate (primeira vez, atualização ou reboot).
     */
    fun ensureShellCopy(context: Context, runner: ShellRunner?): String? {
        val r = runner ?: return null
        val version = BuildConfig.VERSION_NAME
        kotlinx.coroutines.runBlocking {
            val stamp = r.exec("cat '$EXEC_DIR/$STAMP' 2>/dev/null")
            if (stamp.stdout.trim() == version) return@runBlocking

            r.exec("rm -rf '$EXEC_DIR' && mkdir -p '$EXEC_DIR/scripts'")
            for (name in context.assets.list("$ASSET_ROOT/scripts").orEmpty()) {
                val content = context.assets.open("$ASSET_ROOT/scripts/$name")
                    .use { it.readBytes().toString(Charsets.UTF_8) }
                r.writeFile("$EXEC_DIR/scripts/$name", content)
            }
            val versionTxt = context.assets.open("$ASSET_ROOT/VERSION")
                .use { it.readBytes().toString(Charsets.UTF_8) }
            r.writeFile("$EXEC_DIR/VERSION", versionTxt)
            r.exec("chmod -R 755 '$EXEC_DIR' && printf '%s' '$version' > '$EXEC_DIR/$STAMP'")
        }
        return EXEC_DIR
    }

    private fun copyAssetDir(context: Context, assetPath: String, dest: File) {
        val children = context.assets.list(assetPath).orEmpty()
        if (children.isEmpty()) {
            dest.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input -> dest.outputStream().use { input.copyTo(it) } }
            dest.setExecutable(true, false)
            return
        }
        dest.mkdirs()
        for (child in children) copyAssetDir(context, "$assetPath/$child", File(dest, child))
    }

    /**
     * Monta o comando de shell para a ação. [packDir] é a pasta extraída.
     * Retorna null para ações informativas (níveis 3/4).
     */
    fun commandFor(action: PackAction, packDir: File): String? {
        if (action.infoOnly) return null
        action.inline?.let { return it.replace("\$PACK", packDir.absolutePath) }
        action.assetFile?.let { rel ->
            val f = File(packDir, rel)
            return commandsFromTextFile(f)
        }
        return null
    }

    /** Extrai os comandos executáveis de um arquivo `.txt` do Brevent. */
    fun commandsFromTextFile(file: File): String {
        val cmds = file.readLines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
        return cmds.joinToString("\n")
    }
}
