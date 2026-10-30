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
    private val shizuku = ShizukuRunner()
    private val sound by lazy { SoundPlayer(applicationContext) }
    private var runner: ShellRunner? = null
    private var pendingAfterConnect: (() -> Unit)? = null

    /**
     * O binder do Shizuku chega depois do `onCreate`: o app pergunta ao
     * `ShizukuProvider` e a resposta volta por Binder. Se a gente checar
     * `hasPermission()` só no `onCreate`, a resposta ainda não chegou, o app
     * conclui "não autorizado" e pede a permissão de novo — toda vez que o app
     * é aberto, mesmo com a permissão já concedida. Por isso a conexão também
     * é tentada quando o binder chega (sticky) e quando ele morre (o serviço
     * do Shizuku reiniciou), que é o estado real do aparelho.
     */
    private val onBinderReceived = Shizuku.OnBinderReceivedListener { tryAutoConnectShizuku() }
    private val onBinderDead = Shizuku.OnBinderDeadListener {
        if (runner === shizuku) {
            runner = null
            OtmRunner.current = null
        }
    }
    private val onPermissionResult = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
        if (requestCode == REQ_SHIZUKU) {
            if (grantResult == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                activateShizuku()
            } else {
                toast("Permissão do Shizuku negada.")
                pendingAfterConnect = null
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.parseColor("#0D0C0A")

        val root = FrameLayout(this)
        web = WebView(this)
        root.addView(web, FrameLayout.LayoutParams(MATCH, MATCH))

        overlay = buildOverlay()
        root.addView(overlay, FrameLayout.LayoutParams(MATCH, MATCH))
        setContentView(root)

        // Registra os listeners ANTES de tentar conectar: o sticky entrega o
        // binder atual na hora se ele já existir, e avisa quando ele chegar.
        Shizuku.addBinderReceivedListenerSticky(onBinderReceived)
        Shizuku.addBinderDeadListener(onBinderDead)
        Shizuku.addRequestPermissionResultListener(onPermissionResult)
        tryAutoConnectShizuku()

        setupWeb()
        web.loadUrl("file:///android_asset/panel/login.html")
        Permissions.ensureChannel(applicationContext)
        Permissions.askOnce(this)
    }

    override fun onDestroy() {
        Shizuku.removeBinderReceivedListener(onBinderReceived)
        Shizuku.removeBinderDeadListener(onBinderDead)
        Shizuku.removeRequestPermissionResultListener(onPermissionResult)
        super.onDestroy()
    }

    /**
     * Volta do app do Shizuku (ou de qualquer tela do sistema) já conectado. O
     * listener sticky só avisa na chegada do binder; se ele já estava aqui e o
     * usuário liberou a permissão por fora, ninguém avisa o app — então a
     * checagem se repete a cada volta para a tela.
     */
    override fun onResume() {
        super.onResume()
        tryAutoConnectShizuku()
    }

    /**
     * Sem este retorno a permissão de descoberta era pedida e esquecida: o
     * diálogo de pareamento abria antes de o usuário responder, o mDNS falhava
     * em silêncio e a conexão nunca completava.
     */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != Permissions.REQ_MDNS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        Permissions.onMdnsResult(granted)
    }

    /**
     * Conecta sem perguntar nada SE o Shizuku já está rodando e a permissão já
     * foi concedida antes. Só nesse caso a capa some e o painel abre direto;
     * se falta a permissão, nada acontece aqui (o pedido é explícito, no botão).
     */
    private fun tryAutoConnectShizuku() {
        if (runner != null) return
        if (shizuku.isAvailable() && shizuku.hasPermission()) {
            runner = shizuku
            OtmRunner.current = shizuku
            overlay.visibility = View.GONE
            pendingAfterConnect?.invoke()
            pendingAfterConnect = null
        }
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

    /**
     * Garante os botões do app no cabeçalho do painel (após cada carga).
     *
     * O toque passa por [tapOnly]: um `onclick` puro disparava também quando o
     * dedo só PASSAVA pelo botão arrastando a página (o clique sintético que o
     * navegador emite no fim de um scroll). Era isso que abria o flutuante "sem
     * querer". Agora só vale o toque parado e curto.
     */
    private fun injectHeaderButtons(view: WebView) {
        val js = """
            (function(){
              var t = document.querySelector('header');
              if (!t) return;
              if (document.getElementById('otmFloat')) return;

              // Toque de verdade: dedo parado (pouca variação) e curto.
              //
              // Só o pointercancel não bastava: quando o dedo COMEÇA no botão e
              // arrasta a página, o WebView nem sempre emite o cancelamento, e o
              // clique sintético do fim do scroll abria o flutuante "sem querer".
              // Agora o arrasto é detectado por três vias: a variação do dedo, a
              // rolagem da página e o pointerleave.
              var OTM_TAP_PX = 14, OTM_TAP_MS = 600;
              function tapOnly(el, fn){
                var sx=0, sy=0, st=0, ok=false, pid=null;
                function cancel(){ ok=false; pid=null; }
                el.addEventListener('pointerdown', function(e){
                  if (e.pointerType === 'mouse' && e.button !== 0) { cancel(); return; }
                  sx=e.clientX; sy=e.clientY; st=Date.now(); ok=true; pid=e.pointerId;
                }, {passive:true});
                el.addEventListener('pointermove', function(e){
                  if(!ok || (pid !== null && e.pointerId !== pid)) return;
                  if (Math.abs(e.clientX-sx) > OTM_TAP_PX || Math.abs(e.clientY-sy) > OTM_TAP_PX) cancel();
                }, {passive:true});
                el.addEventListener('pointercancel', cancel, {passive:true});
                el.addEventListener('pointerleave', cancel, {passive:true});
                // se a página rolou durante o toque, o dedo estava arrastando
                window.addEventListener('scroll', cancel, {passive:true, capture:true});
                el.addEventListener('click', function(e){
                  if(!ok || Date.now()-st > OTM_TAP_MS){ e.preventDefault(); e.stopPropagation(); return; }
                  cancel(); fn(e);
                });
              }

              var f = document.createElement('button');
              f.className = 'iconbtn'; f.id = 'otmFloat'; f.type = 'button';
              f.title = 'Painel flutuante (sobre o jogo)';
              f.textContent = 'Flutuante';
              f.style.touchAction = 'manipulation';
              tapOnly(f, function(){ window.OTM.call('overlay','','c'); });
              t.appendChild(f);

              if (document.getElementById('otmConnect')) return;
              var b = document.createElement('button');
              b.className = 'iconbtn'; b.id = 'otmConnect'; b.type = 'button';
              b.title = 'Conectar (Shizuku/ADB)';
              b.textContent = 'Conectar';
              b.style.touchAction = 'manipulation';
              tapOnly(b, function(){ window.OTM.call('connect','','c'); });
              t.appendChild(b);
            })();
        """.trimIndent()
        view.evaluateJavascript(js, null)
    }

    private fun buildBridge() = PackBridge(
        context = applicationContext,
        runnerProvider = { runner },
        onConnect = { askConnect() },
        onOverlay = { askOverlay() },
        onSoundSet = { on ->
            sound.muted = !on
            if (on) sound.play("ativando.mp3")
            sound.muted
        },
        onLogin = { sound.play("login_feito_com_sucesso.mp3") },
        onLoginFail = { sound.play("credenciais_incorretas.mp3") },
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

    // ---- painel flutuante (overlay) ------------------------------------------

    /**
     * Liga/desliga o painel flutuante. Sem a permissão de sobreposição, manda o
     * usuário para a tela do sistema que libera "aparecer por cima de outros
     * apps" — é o único jeito de o Android deixar o painel ficar sobre o jogo.
     */
    private fun askOverlay() {
        if (OverlayService.canDraw(this)) {
            if (overlayRunning) {
                OverlayService.stop(this)
                overlayRunning = false
                toast("Painel flutuante desligado.")
            } else {
                OverlayService.start(this)
                overlayRunning = true
                toast("Painel flutuante ligado — ele fica sobre o jogo.")
            }
            return
        }
        androidx.appcompat.app.AlertDialog.Builder(this)
            .setTitle("Painel flutuante")
            .setMessage(
                "Para o painel aparecer por cima do jogo, o Android precisa da permissão " +
                    "\"aparecer por cima de outros apps\". Abra a tela, ligue a opção e volte aqui."
            )
            .setPositiveButton("Abrir") { _, _ ->
                try {
                    startActivity(
                        Intent(
                            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            android.net.Uri.parse("package:$packageName"),
                        )
                    )
                } catch (_: Throwable) {
                    toast("Não consegui abrir as permissões.")
                }
            }
            .setNegativeButton("Agora não", null)
            .show()
    }

    private var overlayRunning = false

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
                    1 -> {
                        // A permissão de descoberta PRECISA estar concedida antes
                        // do diálogo: sem ela a busca do serviço de pareamento é
                        // negada em silêncio e a conexão falha sempre.
                        Permissions.askMdnsThen(this) { granted ->
                            if (!granted) {
                                toast("Sem a permissão de \"Dispositivos próximos\" o app não acha o pareamento. Autorize e tente de novo.")
                                return@askMdnsThen
                            }
                            WifiDialog.show(this, applicationContext) { r, msg ->
                                runner = r
                                OtmRunner.current = r
                                toast(msg)
                                sound.play("pareamento_feito_com_sucesso.mp3")
                                pendingAfterConnect?.invoke(); pendingAfterConnect = null
                                web.reload()
                            }
                        }
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
            // o socket abrir não garante que o shell responde: testa antes de
            // anunciar "conectado" e deixar o usuário com ações falhando.
            val ok = r.ok && adb.verify().ok
            if (ok) {
                runner = adb
                OtmRunner.current = adb
                toast(r.stdout.ifBlank { "Conectado." })
                sound.play("pareamento_feito_com_sucesso.mp3")
                pendingAfterConnect?.invoke(); pendingAfterConnect = null
                web.reload()
            } else {
                adb.close()
                toast(r.stderr.ifBlank { "Não conectou. Ligue a depuração USB e aceite o aviso no celular." })
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
            if (!shizuku.requestPermission(REQ_SHIZUKU)) {
                toast("Shizuku ainda não respondeu. Tente de novo em um instante.")
            }
        }
    }

    private fun activateShizuku() {
        runner = shizuku
        OtmRunner.current = shizuku
        toast("Shizuku conectado.")
        sound.play("pareamento_feito_com_sucesso.mp3")
        pendingAfterConnect?.invoke()
        pendingAfterConnect = null
        web.reload()
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
