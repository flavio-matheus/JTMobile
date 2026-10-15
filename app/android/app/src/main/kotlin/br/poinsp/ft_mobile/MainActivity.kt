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
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Ponte nativa do JTMobile. Dois canais (ver docs/ARQUITETURA.md):
 *  - `br.poinsp.ft_mobile/net`   : `bindWifi` fixa o app na rede Wi-Fi do rádio;
  - `br.poinsp.ft_mobile/alert` : `playPcm` toca um alerta sonoro sintetizado no Dart e `vibrate` vibra;
 *  - `br.poinsp.ft_mobile/monitor`: `start`/`write`/`volume`/`stop` reproduzem o áudio recebido do rádio
 *    no alto-falante do celular (monitor do "assobio" dos modos digitais).
 */
class MainActivity : FlutterActivity() {
    private var alertTrack: AudioTrack? = null
    private val handler = Handler(Looper.getMainLooper())

    // Monitor de áudio (AudioTrack em modo stream; as escritas bloqueantes rodam em uma thread própria)
    private var monTrack: AudioTrack? = null
    private var monExecutor: ExecutorService? = null
    private val monPending = AtomicInteger(0)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "br.poinsp.ft_mobile/net").setMethodCallHandler { call, result ->
            when (call.method) {
                "bindWifi" -> result.success(bindToWifi())
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "br.poinsp.ft_mobile/monitor").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    monitorStart(call.argument<Int>("rate") ?: 48000, (call.argument<Double>("volume") ?: 0.8).toFloat())
                    result.success(null)
                }
                "write" -> {
                    call.argument<ByteArray>("pcm")?.let { monitorWrite(it) }
                    result.success(null)
                }
                "volume" -> {
                    monTrack?.setVolume((call.argument<Double>("volume") ?: 0.8).toFloat())
                    result.success(null)
                }
                "stop" -> {
                    monitorStop()
                    result.success(null)
                }
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
    /**
     * Liga o monitor: AudioTrack mono 16 bit em modo stream, volume de mídia x [volume].
     * Buffer de ~200 ms: suficiente contra pequenas oscilações sem acumular atraso perceptível.
     */
    private fun monitorStart(rate: Int, volume: Float) {
        monitorStop()
        try {
            val minBuf = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
            val bufSize = maxOf(minBuf, rate * 2 / 5)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val fmt = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(rate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val track = AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(fmt)
                .setBufferSizeInBytes(bufSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
            track.setVolume(volume)
            track.play()
            monTrack = track
            monExecutor = Executors.newSingleThreadExecutor()
        } catch (_: Exception) {
            monitorStop()
        }
    }

    /**
     * Enfileira um pacote de áudio. Se a fila crescer (dispositivo lento), descarta pacotes para o
     * monitor nunca ficar atrasado em relação ao rádio.
     */
    private fun monitorWrite(pcm: ByteArray) {
        val ex = monExecutor ?: return
        val track = monTrack ?: return
        if (monPending.get() > 12) return
        monPending.incrementAndGet()
        try {
            ex.execute {
                try {
                    track.write(pcm, 0, pcm.size)
                } catch (_: Exception) {
                } finally {
                    monPending.decrementAndGet()
                }
            }
        } catch (_: Exception) {
            monPending.decrementAndGet()
        }
    }

    private fun monitorStop() {
        monExecutor?.shutdownNow()
        monExecutor = null
        monTrack?.let {
            try {
                it.stop()
            } catch (_: Exception) {
            }
            try {
                it.release()
            } catch (_: Exception) {
            }
        }
        monTrack = null
        monPending.set(0)
    }

    override fun onDestroy() {
        monitorStop()
        super.onDestroy()
    }
}
