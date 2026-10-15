package com.otm.pack

import android.content.Context
import android.text.InputType
import android.widget.EditText
import android.widget.LinearLayout
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/** Diálogo de conexão por ADB Wi-Fi (pareamento por código + conexão). */
object WifiDialog {

    fun show(activity: AppCompatActivity, context: Context, onConnected: (ShellRunner, String) -> Unit) {
        val adb = AdbRunner(context)
        val box = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 12, 48, 12)
        }
        val host = field(activity, box, "Endereço (ex.: 192.168.0.10)", "127.0.0.1")
        val port = field(activity, box, "Porta da depuração sem fio (ex.: 37000)", "", numeric = true)
        val pairPort = field(activity, box, "Porta de pareamento (só no primeiro uso)", "", numeric = true)
        val code = field(activity, box, "Código de pareamento (só no primeiro uso)", "", numeric = true)

        AlertDialog.Builder(activity)
            .setTitle("Wi-Fi (ADB)")
            .setMessage("No aparelho: Opções do desenvolvedor → Depuração sem fio. Use os números que aparecem lá.")
            .setView(box)
            .setPositiveButton("Conectar") { _, _ ->
                val h = host.text.toString().trim().ifEmpty { "127.0.0.1" }
                val p = port.text.toString().trim().toIntOrNull() ?: 5555
                val pp = pairPort.text.toString().trim().toIntOrNull()
                val pc = code.text.toString().trim()
                activity.lifecycleScope.launch {
                    if (pp != null && pc.isNotEmpty()) adb.pair(h, pp, pc)
                    val r = adb.connect(h, p)
                    if (r.ok) onConnected(adb, "ADB conectado em $h:$p.")
                    else android.widget.Toast.makeText(context, "Não conectou: ${r.stderr}", android.widget.Toast.LENGTH_LONG).show()
                }
            }
            .setNegativeButton("Cancelar", null)
            .show()
    }

    private fun field(
        activity: AppCompatActivity, parent: LinearLayout, hint: String, initial: String, numeric: Boolean = false,
    ): EditText = EditText(activity).apply {
        this.hint = hint
        setText(initial)
        textSize = 13f
        if (numeric) inputType = InputType.TYPE_CLASS_NUMBER
        parent.addView(this)
    }
}
