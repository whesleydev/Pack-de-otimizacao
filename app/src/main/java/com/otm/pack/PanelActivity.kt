package com.otm.pack

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import rikka.shizuku.Shizuku

/**
 * Tela principal do app: o painel 00deUdia Otimizações dentro de uma WebView.
 *
 * O painel é o mesmo do site (web/index.php), pré-renderizado em HTML estático
 * (assets/panel). Em vez de falar com `api.php`, ele chama o Android pela ponte
 * [PackBridge]. O acesso privilegiado (Shizuku) é pedido num diálogo nativo.
 */
class PanelActivity : AppCompatActivity() {

    private lateinit var web: WebView
    private lateinit var root: FrameLayout
    private lateinit var overlay: View
    private lateinit var keyInput: android.widget.EditText
    private lateinit var keyError: android.widget.TextView
    private var keySubmitBtn: Button? = null
    private val shizuku = ShizukuRunner()
    private val sound by lazy { SoundPlayer(applicationContext) }
    private var runner: ShellRunner? = null
    private var pendingAfterConnect: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.parseColor("#0D0C0A")

        val root = FrameLayout(this)
        this.root = root
        web = WebView(this)
        root.addView(web, FrameLayout.LayoutParams(MATCH, MATCH))

        // A capa inicial depende do estado: sem chave validada ela é a tela da
        // chave; com a chave já validada, é a tela do método de conexão.
        overlay = if (KeyGate.isUnlocked(this)) buildOverlay() else buildKeyOverlay()
        root.addView(overlay, FrameLayout.LayoutParams(MATCH, MATCH))
        setContentView(root)

        // Fluxo de entrada: primeiro a chave, depois o método de conexão.
        // A chave fica lembrada (SharedPreferences), então só pede na 1ª vez.
        if (KeyGate.isUnlocked(this)) {
            overlay.visibility = View.GONE
            // Já com a chave validada: se o Shizuku já está autorizado, conecta direto.
            if (shizuku.isAvailable() && shizuku.hasPermission()) {
                runner = shizuku
            } else {
                pendingAfterConnect = null
                askConnect()
            }
        } else {
            overlay.visibility = View.VISIBLE
        }

        Shizuku.addRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode == REQ_SHIZUKU) {
                if (grantResult == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                    activateShizuku()
                } else {
                    toast("Permissão do Shizuku negada.")
                    pendingAfterConnect = null
                }
            }
        }

        setupWeb()
        web.loadUrl("file:///android_asset/panel/index.html")
        Permissions.ensureChannel(applicationContext)
        Permissions.askOnce(this)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWeb() {
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            mediaPlaybackRequiresUserGesture = false
            cacheMode = WebSettings.LOAD_DEFAULT
        }
        web.setBackgroundColor(Color.parseColor("#0D0C0A"))
        web.addJavascriptInterface(buildBridge(), "OTM")
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, req: WebResourceRequest): Boolean {
                val u = req.url
                if (u.scheme == "file") return false
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, u))
                } catch (_: Throwable) {
                    toast("Não consegui abrir o link.")
                }
                return true
            }

            override fun onPageFinished(view: WebView, url: String) {
                injectHeaderButtons(view)
            }
        }
    }

    /** Garante os botões do app no cabeçalho do painel (após cada carga). */
    private fun injectHeaderButtons(view: WebView) {
        val js = """
            (function(){
              var t = document.querySelector('header');
              if (!t || document.getElementById('otmConnect')) return;
              var b = document.createElement('button');
              b.className = 'iconbtn'; b.id = 'otmConnect'; b.title = 'Conectar (Shizuku/ADB)';
              b.textContent = 'Conectar';
              b.onclick = function(){ window.OTM.call('connect','','c'); };
              t.appendChild(b);
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
    }

    private fun buildBridge() = PackBridge(
        context = applicationContext,
        runnerProvider = { runner },
        onConnect = { askConnect() },
        onSoundSet = { on ->
            sound.muted = !on
            if (on) sound.play("ativando.mp3")
            sound.muted
        },
        onActionSound = { file -> sound.play(file) },
        onRunDone = { group, ok ->
            val what = if (group.isBlank()) "Ação" else group
            Permissions.notify(
                applicationContext,
                if (ok) "$what concluído." else "$what terminou com avisos — veja o console.",
            )
        },
        deliver = { cbId, json ->
            runOnUiThread {
                val js = "window.__otmResolve(" + jsString(cbId) + "," + jsString(json) + ");"
                web.evaluateJavascript(js, null)
            }
        },
    )

    // ---- conexão (Shizuku / ADB) ---------------------------------------------

    private fun askConnect() {
        val options = arrayOf(
            "Shizuku (recomendado)",
            "ADB por Wi-Fi (só o código)",
            "Depuração USB (só autorizar)",
            "Cancelar",
        )
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Conectar")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> useShizuku()
                    1 -> WifiDialog.show(this, applicationContext) { r, msg ->
                        runner = r
                        toast(msg)
                        sound.play("pareamento_feito_com_sucesso.mp3")
                        pendingAfterConnect?.invoke(); pendingAfterConnect = null
                        web.reload()
                    }
                    2 -> useAdbLocal()
                }
            }
            .show()
    }

    /**
     * Conecta pelo `adbd` do próprio aparelho sem parear (depuração USB clássica):
     * acha o adbd no loopback (127.0.0.1:5555, de um `adb tcpip 5555`) ou pela rede
     * (mDNS). No celular aparece só o "Permitir depuração USB".
     */
    private fun useAdbLocal() {
        toast("Procurando o adbd… ligue a depuração USB e aceite o aviso no celular.")
        lifecycleScope.launch {
            val adb = AdbRunner(applicationContext)
            val r = adb.connectLocal()
            if (r.ok) {
                runner = adb
                toast(r.stdout.ifBlank { "Conectado." })
                sound.play("pareamento_feito_com_sucesso.mp3")
                pendingAfterConnect?.invoke(); pendingAfterConnect = null
                web.reload()
            } else {
                toast(r.stderr.ifBlank { "Não conectou." })
            }
        }
    }

    private fun useShizuku() {
        if (!shizuku.isAvailable()) {
            androidx.appcompat.app.AlertDialog.Builder(this)
                .setTitle("Shizuku não está rodando")
                .setMessage("Instale e abra o app Shizuku e inicie o serviço (por ADB ou root). Depois volte aqui.")
                .setPositiveButton("Ok", null)
                .show()
            return
        }
        if (shizuku.hasPermission()) {
            activateShizuku()
        } else {
            toast("Peça a permissão no diálogo do Shizuku…")
            shizuku.requestPermission(REQ_SHIZUKU)
        }
    }

    private fun activateShizuku() {
        runner = shizuku
        toast("Shizuku conectado.")
        sound.play("pareamento_feito_com_sucesso.mp3")
        pendingAfterConnect?.invoke()
        pendingAfterConnect = null
        web.reload()
    }

    // ---- sobreposição: chave de acesso ---------------------------------------

    /**
     * Primeira tela: pede a chave de acesso. Só depois de validar é que o app
     * segue para o método de conexão — é o mesmo acesso por chave do painel web,
     * com a validação feita aqui (hashes em `assets/panel/keys.json`).
     */
    private fun buildKeyOverlay(): View {
        val box = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0D0C0A"))
            setPadding(dp(28), dp(28), dp(28), dp(28))
        }
        box.addView(android.widget.TextView(this).apply {
            text = "00deUdia Otimizações"
            setTextColor(Color.parseColor("#FF6A2B"))
            textSize = 22f
            gravity = android.view.Gravity.CENTER
        })
        box.addView(android.widget.TextView(this).apply {
            text = "Digite a sua chave de acesso (00-XXXX-XXXX-XXXX)."
            setTextColor(Color.parseColor("#F3EFE7"))
            textSize = 14f
            gravity = android.view.Gravity.CENTER
            setPadding(0, dp(10), 0, dp(14))
        })
        keyInput = android.widget.EditText(this).apply {
            hint = "00-XXXX-XXXX-XXXX"
            setTextColor(Color.parseColor("#F3EFE7"))
            setHintTextColor(Color.parseColor("#A49D90"))
            inputType = android.text.InputType.TYPE_CLASS_TEXT or
                android.text.InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
            setSingleLine(true)
            setBackgroundColor(Color.parseColor("#1A1815"))
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        box.addView(
            keyInput,
            android.widget.LinearLayout.LayoutParams(
                MATCH, android.view.ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        keyError = android.widget.TextView(this).apply {
            setTextColor(Color.parseColor("#FF6B5E"))
            textSize = 12.5f
            visibility = View.GONE
            setPadding(0, dp(8), 0, 0)
        }
        box.addView(keyError)
        box.addView(android.widget.Space(this), lp(dp(14)))
        keySubmitBtn = Button(this).apply {
            text = "Validar chave"
            setOnClickListener { submitKey() }
        }
        box.addView(keySubmitBtn)
        box.addView(Button(this).apply {
            text = "Ver o painel sem conectar"
            setOnClickListener { this@PanelActivity.overlay.visibility = View.GONE }
        })
        return box
    }

    /**
     * Valida a chave digitada. A checagem fala com o painel (banco), então roda
     * fora da thread da tela — nada de travar o app esperando a rede. Acerta →
     * som de sucesso e vai para a conexão; erra → explica o motivo.
     */
    private fun submitKey() {
        val typed = keyInput.text.toString().trim()
        if (!KeyGate.wellFormed(typed)) {
            sound.play("credenciais_incorretas.mp3")
            keyError.text = "Formato inválido. Use 00-XXXX-XXXX-XXXX."
            keyError.visibility = View.VISIBLE
            return
        }

        keyError.visibility = View.GONE
        val btn = keySubmitBtn
        btn?.isEnabled = false
        btn?.text = "Validando…"

        lifecycleScope.launch {
            val res = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                KeyGate.check(this@PanelActivity, typed)
            }
            btn?.isEnabled = true
            btn?.text = "Validar chave"

            if (res.ok) {
                sound.play("key_validada_com_sucesso.mp3")
                // Em segundo plano, atualiza a lista de chaves para o modo offline.
                lifecycleScope.launch {
                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                        KeyGate.syncOffline(this@PanelActivity)
                    }
                }
                overlay.visibility = View.GONE
                askConnect()
            } else {
                sound.play("credenciais_incorretas.mp3")
                keyError.text = res.message
                keyError.visibility = View.VISIBLE
            }
        }
    }

    // ---- sobreposição: método de conexão -------------------------------------

    private fun buildOverlay(): View {
        val box = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0D0C0A"))
            setPadding(dp(28), dp(28), dp(28), dp(28))
        }
        box.addView(android.widget.TextView(this).apply {
            text = "Para o pack funcionar, o app precisa de um acesso privilegiado de shell.\n\n" +
                "Recomendado: Shizuku (sem root). No PC, use a depuração USB (cabo) — " +
                "basta aceitar \"Permitir depuração USB\" no celular."
            setTextColor(Color.parseColor("#F3EFE7"))
            textSize = 14f
            gravity = android.view.Gravity.CENTER
        })
        box.addView(android.widget.Space(this), lp(dp(16)))
        box.addView(Button(this).apply {
            text = "Conectar agora"
            setOnClickListener {
                pendingAfterConnect = { this@PanelActivity.overlay.visibility = View.GONE }
                askConnect()
            }
        })
        box.addView(Button(this).apply {
            text = "Ver o painel sem conectar"
            setOnClickListener { this@PanelActivity.overlay.visibility = View.GONE }
        })
        box.addView(Button(this).apply {
            text = "Trocar chave"
            setOnClickListener { showKeyScreen() }
        })
        return box
    }

    /** Volta para a tela da chave (para trocar a chave já validada). */
    private fun showKeyScreen() {
        KeyGate.lock(this)
        val nova = buildKeyOverlay()
        root.removeView(overlay)
        overlay = nova
        root.addView(overlay, FrameLayout.LayoutParams(MATCH, MATCH))
        overlay.visibility = View.VISIBLE
    }

    // ---- utilidades ----------------------------------------------------------

    private fun jsString(s: String): String {
        val sb = StringBuilder("\"")
        for (c in s) when (c) {
            '"' -> sb.append("\\\"")
            '\\' -> sb.append("\\\\")
            '\n' -> sb.append("\\n")
            '\r' -> sb.append("\\r")
            '\t' -> sb.append("\\t")
            '\u2028' -> sb.append("\\u2028")
            '\u2029' -> sb.append("\\u2029")
            else -> if (c < ' ') sb.append("\\u%04x".format(c.code)) else sb.append(c)
        }
        return sb.append("\"").toString()
    }

    private fun lp(top: Int) = android.widget.LinearLayout.LayoutParams(MATCH, top)

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()

    private companion object {
        const val MATCH = android.view.ViewGroup.LayoutParams.MATCH_PARENT
        const val REQ_SHIZUKU = 4211
    }
}
