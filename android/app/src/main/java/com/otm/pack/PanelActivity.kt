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
    private lateinit var overlay: View
    private lateinit var overlayText: android.widget.TextView
    private val shizuku = ShizukuRunner()
    private val sound by lazy { SoundPlayer(applicationContext) }
    private var runner: ShellRunner? = null
    private var pendingAfterConnect: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.parseColor("#0D0C0A")

        val root = FrameLayout(this)
        web = WebView(this)
        root.addView(web, FrameLayout.LayoutParams(MATCH, MATCH))

        overlay = buildOverlay()
        root.addView(overlay, FrameLayout.LayoutParams(MATCH, MATCH))
        setContentView(root)

        // Se o Shizuku já está autorizado, conecta direto e esconde a capa.
        if (shizuku.isAvailable() && shizuku.hasPermission()) {
            runner = shizuku
            overlay.visibility = View.GONE
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

    /** Insere "Conectar" e "Som" no cabeçalho do painel (após cada carga). */
    private fun injectHeaderButtons(view: WebView) {
        val js = """
            (function(){
              var t = document.querySelector('header') || document.body;
              if (!t || document.getElementById('otmConnect')) return;
              var mk = function(id, label, act){
                var b = document.createElement('button');
                b.className = 'iconbtn'; b.id = id; b.textContent = label;
                b.onclick = act; return b;
              };
              t.appendChild(mk('otmConnect','Conectar', function(){ window.OTM.call('connect','','c'); }));
              var mb = mk('otmSound','🔊', function(){
                window.__otmMuted = !window.__otmMuted;
                window.OTM.call('sound','','s');
                this.textContent = window.__otmMuted ? '🔇' : '🔊';
              });
              t.appendChild(mb);
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
    }

    private fun buildBridge() = PackBridge(
        context = applicationContext,
        runnerProvider = { runner },
        onConnect = { askConnect() },
        onSoundToggle = {
            sound.muted = !sound.muted
            sound.muted
        },
        onActionSound = { file -> sound.play(file) },
        deliver = { cbId, json ->
            runOnUiThread {
                val js = "window.__otmResolve(" + jsString(cbId) + "," + jsString(json) + ");"
                web.evaluateJavascript(js, null)
            }
        },
    )

    // ---- conexão (Shizuku / ADB) ---------------------------------------------

    private fun askConnect() {
        val options = arrayOf("Shizuku (recomendado)", "ADB por Wi-Fi", "Cancelar")
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Conectar")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> useShizuku()
                    1 -> WifiDialog.show(this, applicationContext) { r, msg ->
                        runner = r
                        toast(msg)
                        sound.play("login_feito_com_sucesso.mp3")
                        pendingAfterConnect?.invoke(); pendingAfterConnect = null
                        web.reload()
                    }
                }
            }
            .show()
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
        sound.play("login_feito_com_sucesso.mp3")
        pendingAfterConnect?.invoke()
        pendingAfterConnect = null
        web.reload()
    }

    // ---- sobreposição (primeira abertura) ------------------------------------

    private fun buildOverlay(): View {
        val box = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0D0C0A"))
            setPadding(dp(28), dp(28), dp(28), dp(28))
        }
        overlayText = android.widget.TextView(this).apply {
            text = "Para o pack funcionar, o app precisa de um acesso privilegiado de shell.\n\n" +
                "Recomendado: Shizuku (sem root)."
            setTextColor(Color.parseColor("#F3EFE7"))
            textSize = 14f
            gravity = android.view.Gravity.CENTER
        }
        box.addView(overlayText)
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
        return box
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
