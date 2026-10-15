package br.poinsp.ft_mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "br.poinsp.ft_mobile/net")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindWifi" -> result.success(bindToWifi())
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
}
