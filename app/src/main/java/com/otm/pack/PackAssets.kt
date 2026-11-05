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

    /**
     * `HOME` dos scripts. Fica FORA de [EXEC_DIR], que é apagado inteiro quando
     * os scripts mudam: aqui moram os snapshots, a config e os ajustes salvos.
     */
    const val STATE_DIR = "/data/local/tmp/otm-state"

    private const val STAMP = ".extracted"

    /**
     * Pasta de estado que NÃO pode ser apagada.
     * O histórico (log.jsonl, term.jsonl) morava em `filesDir/pack/state`, e o
     * `pack` é reescrito do zero a cada mudança de assets. Resultado: instalar
     * uma versão nova apagava o histórico de tudo que o usuário tinha feito.
     * Aqui o estado fica fora da pasta extraída e sobrevive à atualização.
     */
    fun stateDir(context: Context): File = File(context.filesDir, "otm-state").apply { mkdirs() }

    fun ensureExtracted(context: Context): File = ensureExtracted(context, ASSET_ROOT)

    /** Extrai uma pasta de assets para filesDir/<nome> (uma vez por versão). */
    fun ensureExtracted(context: Context, assetRoot: String): File {
        val dest = File(context.filesDir, assetRoot)
        val stamp = File(dest, STAMP)
        val want = stampFor(context, assetRoot)
        if (stamp.exists() && stamp.readText() == want) return dest
        dest.deleteRecursively()
        dest.mkdirs()
        copyAssetDir(context, assetRoot, dest)
        stamp.writeText(want)
        return dest
    }

    private fun hex(bytes: ByteArray): String =
        bytes.joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }

    /**
     * Selo pelo CONTEÚDO dos assets, não pelo versionName. Dois APKs com a mesma
     * versão (o 2.30.0 republicado, por exemplo) tinham o mesmo selo e o app
     * achava que a cópia estava em dia — o aparelho seguia rodando script velho,
     * sem as ações novas. Com o hash, qualquer mudança força a recópia.
     */
    private fun stampFor(context: Context, assetRoot: String): String {
        val md = java.security.MessageDigest.getInstance("SHA-1")
        md.update(BuildConfig.VERSION_NAME.toByteArray())
        fun walk(path: String) {
            val children = context.assets.list(path).orEmpty().sorted()
            if (children.isEmpty()) {
                md.update(path.toByteArray())
                md.update(context.assets.open(path).use { it.readBytes() })
                return
            }
            for (child in children) walk("$path/$child")
        }
        walk(assetRoot)
        return hex(md.digest())
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
        val want = stampFor(context, "$ASSET_ROOT/scripts")
        kotlinx.coroutines.runBlocking {
            val stamp = r.exec("cat '$EXEC_DIR/$STAMP' 2>/dev/null")
            if (stamp.stdout.trim() == want) return@runBlocking

            // Antes de limpar: resgata o estado do usuário que morava aqui dentro
            // (o `rm -rf` abaixo apagaria snapshots e config junto com os scripts).
            migrarEstado(r)

            r.exec("rm -rf '$EXEC_DIR' && mkdir -p '$EXEC_DIR/scripts'")
            for (name in context.assets.list("$ASSET_ROOT/scripts").orEmpty()) {
                val content = context.assets.open("$ASSET_ROOT/scripts/$name")
                    .use { it.readBytes().toString(Charsets.UTF_8) }
                r.writeFile("$EXEC_DIR/scripts/$name", content)
            }
            val versionTxt = context.assets.open("$ASSET_ROOT/VERSION")
                .use { it.readBytes().toString(Charsets.UTF_8) }
            r.writeFile("$EXEC_DIR/VERSION", versionTxt)
            r.exec("chmod -R 755 '$EXEC_DIR' && printf '%s' '$want' > '$EXEC_DIR/$STAMP'")
        }
        return EXEC_DIR
    }

    /**
     * Traz o `.packotm` que morava dentro do [EXEC_DIR] (versões antigas) para a
     * pasta nova. Não sobrescreve: se já houver estado novo, o novo ganha.
     */
    private suspend fun migrarEstado(r: ShellRunner) {
        try {
            r.exec("mkdir -p '$STATE_DIR'")
            val tem = r.exec("ls -A '$STATE_DIR/.packotm' 2>/dev/null | head -1")
            if (tem.stdout.trim().isNotEmpty()) return
            val antigo = r.exec("ls -A '$EXEC_DIR/.packotm' 2>/dev/null | head -1")
            if (antigo.stdout.trim().isEmpty()) return
            r.exec("cp -a '$EXEC_DIR/.packotm' '$STATE_DIR/' 2>/dev/null")
        } catch (_: Throwable) {}
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
