package com.company.onyx

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.webkit.JavascriptInterface

class OnyxAndroidBridge(
    private val activity: MainActivity,
    private val adBlockEngine: AdBlockEngine
) {

    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = activity.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            activity.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    @JavascriptInterface
    fun openUrl(url: String) {
        activity.runOnUiThread {
            activity.loadUrl(url)
        }
    }

    @JavascriptInterface
    fun switchWorkspace(id: String, url: String) {
        activity.runOnUiThread {
            activity.selectWorkspace(id, url)
        }
    }

    @JavascriptInterface
    fun openSettings() {
        activity.runOnUiThread {
            activity.loadUrl("file:///android_asset/settings.html")
        }
    }

    @JavascriptInterface
    fun closeSettings() {
        activity.runOnUiThread {
            activity.loadHome()
        }
    }

    @JavascriptInterface
    fun vibrate(durationMs: Long) {
        try {
            val ms = durationMs.coerceIn(5L, 200L)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(ms)
            }
        } catch (_: Exception) {}
    }

    @JavascriptInterface
    fun getAdBlockCount(): Int {
        return adBlockEngine.blockedCount.get()
    }

    @JavascriptInterface
    fun toggleAdBlock(): Boolean {
        adBlockEngine.isEnabled = !adBlockEngine.isEnabled
        return adBlockEngine.isEnabled
    }

    @JavascriptInterface
    fun isAdBlockEnabled(): Boolean {
        return adBlockEngine.isEnabled
    }

    @JavascriptInterface
    fun setSearchEngine(engine: String) {
        activity.runOnUiThread {
            activity.setSearchEngine(engine)
        }
    }

    @JavascriptInterface
    fun fetchSuggestions(query: String, reqId: String) {
        Thread {
            try {
                val encoded = java.net.URLEncoder.encode(query, "UTF-8")
                val url = java.net.URL("https://duckduckgo.com/ac/?q=$encoded&type=list")
                val conn = url.openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 1500
                conn.readTimeout = 1500
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; Mobile; Onyx)")
                val resp = conn.inputStream.bufferedReader().readText()
                activity.runOnUiThread {
                    activity.sendSuggestionsResponse(reqId, resp)
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    activity.sendSuggestionsResponse(reqId, "[]")
                }
            }
        }.start()
    }
}
