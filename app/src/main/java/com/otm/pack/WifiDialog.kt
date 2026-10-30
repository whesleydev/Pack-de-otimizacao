package com.otm.pack

import android.content.Context
import android.text.InputType
import android.widget.EditText
import android.widget.LinearLayout
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/**
 * Diálogo de conexão por ADB Wi-Fi: pede SÓ o código de 6 números, como os apps
 * que mostram "digite o código". As portas e o endereço são descobertos sozinhos
 * pela rede (mDNS), então não há nada mais a preencher.
 *
 * Se a descoberta automática falhar (rede que bloqueia mDNS, ou o pareamento
 * recusado), o app avisa e oferece tentar de novo — em vez de exigir que o
 * usuário saiba IP e porta.
 */
object WifiDialog {

    fun show(activity: AppCompatActivity, context: Context, onConnected: (ShellRunner, String) -> Unit) {
        val adb = AdbRunner(context)
        val box = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 8, 48, 0)
        }
        val code = EditText(activity).apply {
            hint = "Código de 6 números"
            textSize = 22f
            gravity = android.view.Gravity.CENTER
            inputType = InputType.TYPE_CLASS_NUMBER
            letterSpacing = 0.25f
        }
        box.addView(code)

        fun toast(msg: String) =
            android.widget.Toast.makeText(context, msg, android.widget.Toast.LENGTH_LONG).show()

        val dialog = AlertDialog.Builder(activity)
            .setTitle("Depuração sem fio")
            .setMessage(
                "No aparelho: Opções do desenvolvedor → Depuração sem fio → " +
                    "\"Parear com código\".\n\nDigite aqui só o código de 6 números — " +
                    "o app acha o resto sozinho."
            )
            .setView(box)
            .setPositiveButton("Conectar", null)
            .setNegativeButton("Cancelar", null)
            .create()

        fun doWork() {
            val c = code.text.toString().trim()
            if (c.length != 6 || !c.all { it.isDigit() }) {
                toast("Digite o código de 6 números que aparece no aparelho.")
                return
            }
            dialog.dismiss()
            activity.lifecycleScope.launch {
                toast("Procurando o pareamento na rede…")
                var pr = adb.pairWithCode(c)
                // o mDNS pode perder a primeira resposta: uma segunda tentativa
                // resolve a maioria dos "não achei o serviço".
                if (!pr.ok) pr = adb.pairWithCode(c)
                if (!pr.ok) {
                    toast("Não pareou: " + (pr.stderr.ifBlank { pr.stdout }).trim())
                    return@launch
                }
                toast("Pareado. Conectando…")
                // `connectWireless` sozinho mentia: dizia "conectado" só porque o
                // socket abriu. Agora a conexão é testada de verdade e repetida,
                // porque o adbd leva um instante para publicar o serviço depois
                // do pareamento.
                val cr = adb.connectAndVerify()
                if (cr.ok) onConnected(adb, cr.stdout.ifBlank { "Conectado." })
                else toast("Pareou, mas não conectou: " + (cr.stderr.ifBlank { cr.stdout }).trim())
            }
        }

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { doWork() }
        }
        dialog.show()
    }
}
