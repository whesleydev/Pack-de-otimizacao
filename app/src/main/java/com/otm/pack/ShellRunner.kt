package com.otm.pack

import java.io.InputStream

/** Resultado de um comando executado no aparelho. */
data class ExecResult(val code: Int, val stdout: String, val stderr: String) {
    val ok: Boolean get() = code == 0
}

/**
 * Executa comandos shell no aparelho por um transporte privilegiado
 * (Shizuku ou ADB por Wi-Fi). As duas implementações expõem a mesma interface.
 */
interface ShellRunner {
    /** Nome do transporte, para mostrar na interface. */
    val label: String

    /** Roda [command] (interpretado por `sh -c`). [stdin] é opcional. */
    suspend fun exec(command: String, stdin: String? = null): ExecResult

    /** Escreve [content] em [path] no aparelho (cria a pasta se preciso). */
    suspend fun writeFile(path: String, content: String): ExecResult {
        val dir = path.substringBeforeLast('/', "/data/local/tmp")
        exec("mkdir -p '$dir'").let { if (!it.ok && it.code != 0) return it }
        return exec("cat > '$path' && chmod 700 '$path'", stdin = content)
    }

    fun close() {}
}

/** Lê um InputStream inteiro para String (UTF-8). */
internal fun InputStream.readAllText(): String = use { it.readBytes().toString(Charsets.UTF_8) }

/** Junta stdout e stderr num texto só, cortando excesso. */
internal fun joinOutput(stdout: String, stderr: String, limit: Int = 40_000): String {
    val out = buildString {
        if (stdout.isNotBlank()) append(stdout.trimEnd())
        if (stderr.isNotBlank()) {
            if (isNotEmpty()) append("\n\n")
            append("— erros —\n").append(stderr.trimEnd())
        }
    }.ifBlank { "(sem saída)" }
    return if (out.length > limit) out.take(limit) + "\n… (saída cortada)" else out
}
