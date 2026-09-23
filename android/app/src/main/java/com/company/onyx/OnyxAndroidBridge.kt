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

    /**
     * Set by OnyxWebViewClient on every main-frame navigation. addJavascriptInterface exposes this
     * object to every page (and iframe) the WebView loads, so privileged calls are only honored
     * while one of Onyx's bundled asset pages is showing.
     */
    @Volatile
    var trustedPageLoaded: Boolean = false

    /** Runs [action] on the UI thread only if the sender is (still) an Onyx asset page. */
    private fun ifTrusted(action: () -> Unit) {
        if (!trustedPageLoaded) return
        activity.runOnUiThread {
            if (activity.isShowingAssetPage()) action()
        }
    }

    @JavascriptInterface
    fun openUrl(url: String) {
        ifTrusted { activity.loadUrl(url) }
    }

    @JavascriptInterface
    fun switchWorkspace(id: String, url: String) {
        ifTrusted { activity.selectWorkspace(id, url) }
    }

    @JavascriptInterface
    fun openSettings() {
        ifTrusted { activity.loadUrl("file:///android_asset/settings.html") }
    }

    @JavascriptInterface
    fun closeSettings() {
        ifTrusted { activity.loadHome() }
    }

    @JavascriptInterface
    fun vibrate(durationMs: Long) {
        if (!trustedPageLoaded) return
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
        return if (trustedPageLoaded) adBlockEngine.blockedCount.get() else 0
    }

    @JavascriptInterface
    fun toggleAdBlock(): Boolean {
        if (!trustedPageLoaded) return adBlockEngine.isEnabled
        adBlockEngine.isEnabled = !adBlockEngine.isEnabled
        return adBlockEngine.isEnabled
    }

    @JavascriptInterface
    fun isAdBlockEnabled(): Boolean {
        return adBlockEngine.isEnabled
    }

    @JavascriptInterface
    fun setSearchEngine(engine: String) {
        ifTrusted { activity.setSearchEngine(engine) }
    }

    @JavascriptInterface
    fun fetchSuggestions(query: String, reqId: String) {
        if (!trustedPageLoaded) return
        Thread {
            val suggestions = org.json.JSONArray()
            try {
                val encoded = java.net.URLEncoder.encode(query, "UTF-8")
                val url = java.net.URL("https://duckduckgo.com/ac/?q=$encoded&type=list")
                val conn = url.openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 1500
                conn.readTimeout = 1500
                conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Android; Mobile; Onyx)")
                val resp = conn.inputStream.bufferedReader().readText()
                // DDG returns [query, [suggestion, ...]]; pass only the string list to the page.
                val list = org.json.JSONArray(resp).optJSONArray(1)
                if (list != null) {
                    for (i in 0 until list.length()) {
                        list.optString(i, null)?.let { suggestions.put(it) }
                    }
                }
            } catch (_: Exception) {}
            activity.runOnUiThread { activity.sendSuggestionsResponse(reqId, suggestions) }
        }.start()
    }

    /** Proxies allowlisted feeds (no CORS headers) for the start page. Mirrors the macOS onyxFetchFeed bridge. */
    @JavascriptInterface
    fun fetchFeed(url: String, reqId: String) {
        if (!trustedPageLoaded) return
        val uri = try { java.net.URI(url) } catch (_: Exception) { null }
        if (uri?.scheme != "https" || uri.host?.lowercase() !in FEED_HOSTS) {
            activity.runOnUiThread { activity.sendFeedResponse(reqId, null) }
            return
        }
        Thread {
            val text = try {
                val conn = uri.toURL().openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 4000
                conn.readTimeout = 4000
                conn.setRequestProperty("Accept", "application/json, text/xml, */*")
                if (conn.responseCode < 400) conn.inputStream.bufferedReader().readText() else null
            } catch (_: Exception) {
                null
            }
            activity.runOnUiThread { activity.sendFeedResponse(reqId, text) }
        }.start()
    }

    companion object {
        private val FEED_HOSTS = setOf("news.google.com", "hn.algolia.com")
    }
}
