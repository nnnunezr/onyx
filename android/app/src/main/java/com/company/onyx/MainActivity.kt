package com.company.onyx

import android.annotation.SuppressLint
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Bundle
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.webkit.WebSettings
import android.webkit.WebView
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.google.android.material.bottomsheet.BottomSheetDialog
import kotlin.math.abs

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private lateinit var progressBar: ProgressBar
    private lateinit var fullscreenContainer: FrameLayout

    private val adBlockEngine = AdBlockEngine()
    private lateinit var chromeClient: OnyxWebChromeClient
    private lateinit var gestureDetector: GestureDetector

    private var currentWorkspaceId: String = "ai"

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            // Edge-to-edge transparent system bars
            WindowCompat.setDecorFitsSystemWindows(window, false)
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
        } catch (_: Exception) {}

        setContentView(R.layout.activity_main)

        initViews()
        setupSystemWindowInsets()
        setupWebView()
        setupNavigationGestures()
        setupBackPressed()

        loadHome()
    }

    private fun initViews() {
        webView = findViewById(R.id.web_view)
        swipeRefresh = findViewById(R.id.swipe_refresh)
        progressBar = findViewById(R.id.progress_bar)
        fullscreenContainer = findViewById(R.id.fullscreen_container)

        swipeRefresh.setColorSchemeColors(Color.WHITE, Color.GRAY)
        swipeRefresh.setProgressBackgroundColorSchemeColor(Color.parseColor("#141419"))
        swipeRefresh.setOnRefreshListener {
            webView.reload()
            swipeRefresh.isRefreshing = false
        }
    }

    private fun setupSystemWindowInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.root_layout)) { _, insets ->
            val statusBars = insets.getInsets(WindowInsetsCompat.Type.statusBars())
            progressBar.updatePadding(top = statusBars.top)
            insets
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupWebView() {
        chromeClient = OnyxWebChromeClient(this, progressBar, fullscreenContainer)
        webView.webChromeClient = chromeClient
        webView.webViewClient = OnyxWebViewClient(this, adBlockEngine)

        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(true)
            builtInZoomControls = true
            displayZoomControls = false
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            cacheMode = WebSettings.LOAD_DEFAULT
            mediaPlaybackRequiresUserGesture = false
            allowFileAccess = true
            allowContentAccess = true
            allowFileAccessFromFileURLs = true
            allowUniversalAccessFromFileURLs = true
        }

        val bridge = OnyxAndroidBridge(this, adBlockEngine)
        webView.addJavascriptInterface(bridge, "OnyxAndroid")
    }

    private fun setupNavigationGestures() {
        gestureDetector = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            private val swipeThreshold = 120
            private val swipeVelocityThreshold = 100

            override fun onFling(
                e1: MotionEvent?,
                e2: MotionEvent,
                velocityX: Float,
                velocityY: Float
            ): Boolean {
                if (e1 == null) return false
                val diffX = e2.x - e1.x
                val diffY = e2.y - e1.y

                if (abs(diffX) > abs(diffY) &&
                    abs(diffX) > swipeThreshold &&
                    abs(velocityX) > swipeVelocityThreshold
                ) {
                    if (diffX > 0 && e1.x < 80) {
                        // Edge swipe right -> Back
                        if (webView.canGoBack()) {
                            webView.goBack()
                            return true
                        }
                    } else if (diffX < 0 && e1.x > (window.decorView.width - 80)) {
                        // Edge swipe left -> Forward
                        if (webView.canGoForward()) {
                            webView.goForward()
                            return true
                        }
                    }
                }
                return false
            }
        })

        webView.setOnTouchListener { _, event ->
            try {
                gestureDetector.onTouchEvent(event)
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun setupBackPressed() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (chromeClient.isFullscreen()) {
                    chromeClient.onHideCustomView()
                } else if (webView.canGoBack()) {
                    webView.goBack()
                } else {
                    finish()
                }
            }
        })
    }

    fun loadHome() {
        webView.loadUrl("file:///android_asset/startpage.html")
    }

    fun loadUrl(url: String) {
        val trimmed = url.trim()
        val target = when {
            trimmed.startsWith("!r ") || trimmed.startsWith("!ai ") || trimmed.startsWith("!d ") -> {
                val q = java.net.URLEncoder.encode(trimmed.substring(3).trim(), "UTF-8")
                "https://duckduckgo.com/?q=$q&ia=chat"
            }
            trimmed.startsWith("!p ") -> {
                val q = java.net.URLEncoder.encode(trimmed.substring(3).trim(), "UTF-8")
                "https://www.perplexity.ai/search?q=$q"
            }
            trimmed.startsWith("!g ") -> {
                val q = java.net.URLEncoder.encode(trimmed.substring(3).trim(), "UTF-8")
                "https://www.google.com/search?q=$q"
            }
            trimmed.startsWith("!yt ") -> {
                val q = java.net.URLEncoder.encode(trimmed.substring(4).trim(), "UTF-8")
                "https://www.youtube.com/results?search_query=$q"
            }
            trimmed.startsWith("!gh ") -> {
                val q = java.net.URLEncoder.encode(trimmed.substring(4).trim(), "UTF-8")
                "https://github.com/search?q=$q"
            }
            trimmed.startsWith("!w ") -> {
                val q = java.net.URLEncoder.encode(trimmed.substring(3).trim(), "UTF-8")
                "https://en.wikipedia.org/wiki/Special:Search?search=$q"
            }
            trimmed.startsWith("!k ") -> {
                val q = java.net.URLEncoder.encode(trimmed.substring(3).trim(), "UTF-8")
                "https://kagi.com/search?q=$q"
            }
            trimmed.startsWith("http://") || trimmed.startsWith("https://") || trimmed.startsWith("file:///") -> trimmed
            trimmed.contains(".") && !trimmed.contains(" ") -> "https://$trimmed"
            else -> {
                val q = java.net.URLEncoder.encode(trimmed, "UTF-8")
                val defaultEngine = getSharedPreferences("onyx_prefs", MODE_PRIVATE).getString("search_engine", "duckduckgo") ?: "duckduckgo"
                when (defaultEngine.lowercase()) {
                    "google" -> "https://www.google.com/search?q=$q"
                    "brave" -> "https://search.brave.com/search?q=$q"
                    "perplexity" -> "https://www.perplexity.ai/search?q=$q"
                    "kagi" -> "https://kagi.com/search?q=$q"
                    "bing" -> "https://www.bing.com/search?q=$q"
                    else -> "https://duckduckgo.com/?q=$q"
                }
            }
        }
        webView.loadUrl(target)
    }

    fun sendSuggestionsResponse(reqId: String, json: String) {
        webView.evaluateJavascript("window.onOnyxSuggestionsReceived && window.onOnyxSuggestionsReceived('$reqId', $json);", null)
    }

    fun setSearchEngine(engine: String) {
        val prefs = getSharedPreferences("onyx_prefs", MODE_PRIVATE)
        prefs.edit().putString("search_engine", engine.lowercase()).apply()
        webView.evaluateJavascript("""
            window.postMessage({ type: 'onyx-search-engine-changed', engine: '${engine.lowercase()}' }, '*');
            if (typeof window.onOnyxSearchEngineChanged === 'function') {
                window.onOnyxSearchEngineChanged('${engine.lowercase()}');
            }
            if (typeof window.setSearchEngine === 'function') {
                window.setSearchEngine('${engine.lowercase()}');
            }
        """.trimIndent(), null)
    }

    fun selectWorkspace(id: String, url: String) {
        currentWorkspaceId = id
        loadUrl(url)
    }

    fun updateNavigationState() {
        // Navigation state updated dynamically via webview and gesture back stack
    }

    fun toggleShield() {
        adBlockEngine.isEnabled = !adBlockEngine.isEnabled
        val isEnabled = adBlockEngine.isEnabled
        val count = adBlockEngine.blockedCount.get()
        val msg = if (isEnabled) "Shield Active ($count trackers blocked)" else "Shield Paused"
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
    }

    private fun showWorkspacesSheet() {
        try {
            val dialog = BottomSheetDialog(this)
            val sheetView = layoutInflater.inflate(R.layout.bottom_sheet_workspaces, null)

            val btnClose = sheetView.findViewById<View>(R.id.btn_close_sheet)
            val wsAi = sheetView.findViewById<View>(R.id.ws_ai)
            val wsTrading = sheetView.findViewById<View>(R.id.ws_trading)
            val wsUnapec = sheetView.findViewById<View>(R.id.ws_unapec)

            btnClose?.setOnClickListener { dialog.dismiss() }

            wsAi?.setOnClickListener {
                selectWorkspace("ai", "https://duckduckgo.com/?q=&ia=chat")
                dialog.dismiss()
            }

            wsTrading?.setOnClickListener {
                selectWorkspace("trading", "https://web.ninjatrader.com/trading-mode")
                dialog.dismiss()
            }

            wsUnapec?.setOnClickListener {
                selectWorkspace("unapec", "https://canvas.unapec.edu.do/")
                dialog.dismiss()
            }

            dialog.setContentView(sheetView)
            dialog.show()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
