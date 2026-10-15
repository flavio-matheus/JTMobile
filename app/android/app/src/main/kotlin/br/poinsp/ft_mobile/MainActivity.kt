package br.poinsp.ft_mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Ponte nativa do JTMobile. Dois canais (ver docs/ARQUITETURA.md):
 *  - `br.poinsp.ft_mobile/net`   : `bindWifi` fixa o app na rede Wi-Fi do rádio;
 *  - `br.poinsp.ft_mobile/alert` : `playPcm` toca um alerta sonoro sintetizado no Dart e `vibrate` vibra.
 */
class MainActivity : FlutterActivity() {
    private var alertTrack: AudioTrack? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "br.poinsp.ft_mobile/net").setMethodCallHandler { call, result ->
            when (call.method) {
                "bindWifi" -> result.success(bindToWifi())
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "br.poinsp.ft_mobile/alert").setMethodCallHandler { call, result ->
            when (call.method) {
                "playPcm" -> {
                    val pcm = call.argument<ByteArray>("pcm")
                    val rate = call.argument<Int>("rate") ?: 22050
                    if (pcm != null) playPcm(pcm, rate)
                    result.success(null)
                }
                "vibrate" -> {
                    val pattern = call.argument<List<Int>>("pattern") ?: emptyList()
                    vibrate(pattern.map { it.toLong() }.toLongArray())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * O Wi-Fi do IC-705 não tem internet; por padrão o Android roteia o tráfego pela rede móvel.
     * Fixamos o processo na rede Wi-Fi para que os pacotes UDP cheguem ao rádio.
     */
    @Suppress("DEPRECATION")
    private fun bindToWifi(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        for (n in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(n) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                return cm.bindProcessToNetwork(n)
            }
        }
        return false
    }

    /**
     * Toca um som PCM 16 bit mono (sintetizado no Dart) no volume de **mídia**. Usa AudioTrack em
     * modo estático; o objeto anterior é liberado antes de tocar um novo alerta.
     */
    private fun playPcm(pcm: ByteArray, rate: Int) {
        try {
            alertTrack?.let {
                try {
                    it.stop()
                } catch (_: Exception) {
                }
                it.release()
            }
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val fmt = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(rate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val track = AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(fmt)
                .setBufferSizeInBytes(pcm.size)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
            track.write(pcm, 0, pcm.size)
            track.play()
            alertTrack = track
            val durationMs = (pcm.size / 2) * 1000L / rate
            handler.postDelayed({
                if (alertTrack === track) {
                    try {
                        track.release()
                    } catch (_: Exception) {
                    }
                    alertTrack = null
                }
            }, durationMs + 300)
        } catch (_: Exception) {
            // som é um recurso auxiliar: nunca deve derrubar o app
        }
    }

    /** Vibra seguindo [pattern] (ms: espera, vibra, espera, vibra...). */
    private fun vibrate(pattern: LongArray) {
        try {
            val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (!vibrator.hasVibrator() || pattern.isEmpty()) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, -1)
            }
        } catch (_: Exception) {
        }
    }
}
