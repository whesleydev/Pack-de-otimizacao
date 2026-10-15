package com.otm.pack

import android.content.Context
import java.io.File

/**
 * Extrai o conteúdo do pack (comandos Brevent e scripts) dos assets para uma
 * pasta de trabalho do app e monta os comandos a executar.
 *
 * Os `.txt` do nível 1 são arquivos de comandos: cada linha não vazia e que não
 * seja comentário (`#`) vira um comando. Os scripts do nível 2 rodam inteiros.
 */
object PackAssets {

    private const val ASSET_ROOT = "pack"

    /** Extrai assets/pack para filesDir/pack (uma vez por versão). */
    fun ensureExtracted(context: Context): File = ensureExtracted(context, ASSET_ROOT)

    /** Extrai uma pasta de assets para filesDir/<nome> (uma vez por versão). */
    fun ensureExtracted(context: Context, assetRoot: String): File {
        val dest = File(context.filesDir, assetRoot)
        val stamp = File(dest, ".extracted")
        if (stamp.exists()) return dest
        dest.deleteRecursively()
        dest.mkdirs()
        copyAssetDir(context, assetRoot, dest)
        stamp.writeText("ok")
        return dest
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
