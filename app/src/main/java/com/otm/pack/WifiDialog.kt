package com.otm.pack

import android.content.Context
import android.text.InputType
import android.view.View
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/**
 * Diálogo de conexão por ADB Wi-Fi no estilo dos apps que pedem só o código de
 * 6 números: as portas são descobertas sozinhas pela rede (mDNS), então o usuário
 * só digita o código que aparece em "Depuração sem fio → Parear com código".
 *
 * O bloco "Avançado" (opcional) permite informar IP e portas na mão, para redes
 * que bloqueiam a descoberta (mDNS) ou para o ADB por TCP clássico.
 */
object WifiDialog {

    fun show(activity: AppCompatActivity, context: Context, onConnected: (ShellRunner, String) -> Unit) {
        val adb = AdbRunner(context)
        val box = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 12, 48, 12)
        }
        val code = field(activity, box, "Código de pareamento (6 números)", "", numeric = true)

        val adv = CheckBox(activity).apply { text = "Avançado (informar IP e portas)" }
        box.addView(adv)
        val advBox = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
        }
        val host = field(activity, advBox, "Endereço (ex.: 192.168.0.10)", "")
        val port = field(activity, advBox, "Porta de conexão", "", numeric = true)
        val pairPort = field(activity, advBox, "Porta de pareamento", "", numeric = true)
        box.addView(advBox)
        adv.setOnCheckedChangeListener { _, on ->
            advBox.visibility = if (on) View.VISIBLE else View.GONE
        }

        fun toast(msg: String) =
            android.widget.Toast.makeText(context, msg, android.widget.Toast.LENGTH_LONG).show()

        fun finish(r: ExecResult) {
            if (r.ok) onConnected(adb, r.stdout.ifBlank { "Conectado." })
            else toast("Não conectou: " + (r.stderr.ifBlank { r.stdout }).trim())
        }

        val dialog = AlertDialog.Builder(activity)
            .setTitle("Wi-Fi (ADB)")
            .setMessage(
                "No aparelho: Opções do desenvolvedor → Depuração sem fio → " +
                    "\"Parear com código\". Digite aqui só o código de 6 números."
            )
            .setView(box)
            .setPositiveButton("Parear e conectar", null)
            .setNeutralButton("Só conectar", null)
            .setNegativeButton("Cancelar", null)
            .create()

        fun doWork(pair: Boolean) {
            dialog.dismiss()
            activity.lifecycleScope.launch {
                val manual = adv.isChecked && host.text.toString().trim().isNotEmpty()
                if (manual) {
                    val h = host.text.toString().trim()
                    val p = port.text.toString().trim().toIntOrNull() ?: 5555
                    val pp = pairPort.text.toString().trim().toIntOrNull()
                    val pc = code.text.toString().trim()
                    if (pair && pp != null && pc.isNotEmpty()) adb.pair(h, pp, pc)
                    finish(adb.connect(h, p))
                    return@launch
                }
                if (pair) {
                    val c = code.text.toString().trim()
                    if (c.isEmpty()) {
                        toast("Digite o código de 6 números.")
                        return@launch
                    }
                    toast("Procurando o serviço de pareamento na rede…")
                    val pr = adb.pairWithCode(c)
                    if (!pr.ok) {
                        finish(pr)
                        return@launch
                    }
                }
                toast("Conectando…")
                finish(adb.connectWireless())
            }
        }

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { doWork(pair = true) }
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener { doWork(pair = false) }
        }
        dialog.show()
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
