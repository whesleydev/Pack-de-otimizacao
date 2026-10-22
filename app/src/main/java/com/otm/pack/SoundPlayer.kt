package com.otm.pack

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Toca os avisos de voz do pack (MP3 em `assets/audio`).
 *
 * Um som de cada vez: ao tocar um novo, o anterior para. Se o arquivo não
 * existir ou der erro, o app segue em silêncio (o som é só um enfeite), mas
 * registra o motivo no logcat com a tag "SoundPlayer".
 */
class SoundPlayer(private val context: Context) {

    var muted: Boolean = false

    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stop() }

    /**
     * Toca [file] (nome do arquivo em assets/audio). O som para quando terminar
     * ou depois de [maxMillis] — o que vier primeiro — para não travar o aparelho.
     */
    fun play(file: String, maxMillis: Long = 6000) {
        if (muted) return
        stop()
        try {
            val afd = context.assets.openFd("audio/$file")
            val mp = MediaPlayer().apply {
                // Mídia (e não sonificação): o canal de sonificação some em
                // muitos aparelhos mesmo com o volume de mídia alto.
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                setOnCompletionListener { stop() }
                setOnErrorListener { _, what, extra ->
                    Log.w("SoundPlayer", "erro ao tocar $file (what=$what extra=$extra)")
                    stop(); true
                }
                prepare()
                start()
            }
            afd.close()
            player = mp
            handler.removeCallbacks(autoStop)
            handler.postDelayed(autoStop, maxMillis)
        } catch (t: Throwable) {
            Log.w("SoundPlayer", "falha ao tocar $file", t)
            stop()
        }
    }

    fun stop() {
        handler.removeCallbacks(autoStop)
        try { player?.stop() } catch (_: Throwable) {}
        try { player?.release() } catch (_: Throwable) {}
        player = null
    }
}
