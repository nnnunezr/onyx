package com.company.onyx

import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.widget.FrameLayout
import android.widget.ProgressBar

class OnyxWebChromeClient(
    private val activity: MainActivity,
    private val progressBar: ProgressBar,
    private val fullscreenContainer: FrameLayout
) : WebChromeClient() {

    private var customView: View? = null
    private var customViewCallback: CustomViewCallback? = null

    override fun onProgressChanged(view: WebView?, newProgress: Int) {
        super.onProgressChanged(view, newProgress)
        if (newProgress < 100) {
            progressBar.visibility = View.VISIBLE
            progressBar.progress = newProgress
        } else {
            progressBar.visibility = View.GONE
        }
    }

    override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
        if (customView != null) {
            callback?.onCustomViewHidden()
            return
        }
        customView = view
        customViewCallback = callback
        fullscreenContainer.addView(view)
        fullscreenContainer.visibility = View.VISIBLE
    }

    override fun onHideCustomView() {
        if (customView == null) return
        fullscreenContainer.removeView(customView)
        fullscreenContainer.visibility = View.GONE
        customViewCallback?.onCustomViewHidden()
        customView = null
        customViewCallback = null
    }

    fun isFullscreen(): Boolean = customView != null
}
