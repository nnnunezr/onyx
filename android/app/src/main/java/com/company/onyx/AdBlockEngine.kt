package com.company.onyx

import android.net.Uri
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import java.util.concurrent.atomic.AtomicInteger

class AdBlockEngine {

    var isEnabled: Boolean = true
    val blockedCount = AtomicInteger(0)

    private val blockedHosts = hashSetOf(
        "doubleclick.net",
        "google-analytics.com",
        "googlesyndication.com",
        "adservice.google.com",
        "pagead2.googlesyndication.com",
        "ads.youtube.com",
        "adnxs.com",
        "advertising.com",
        "taboola.com",
        "outbrain.com",
        "criteo.com",
        "scorecardresearch.com",
        "quantserve.com",
        "connect.facebook.net/en_US/fbevents.js",
        "analytics.tiktok.com",
        "adroll.com"
    )

    fun shouldBlock(uri: Uri?): Boolean {
        if (!isEnabled || uri == null) return false
        val host = uri.host?.lowercase() ?: return false
        val path = uri.path ?: ""
        for (blocked in blockedHosts) {
            // Entries may be "host" or "host/path-prefix" (e.g. a single tracking script).
            val slash = blocked.indexOf('/')
            val ruleHost = if (slash >= 0) blocked.substring(0, slash) else blocked
            val rulePath = if (slash >= 0) blocked.substring(slash) else ""
            val hostMatches = host == ruleHost || host.endsWith(".$ruleHost")
            if (hostMatches && (rulePath.isEmpty() || path.startsWith(rulePath))) {
                blockedCount.incrementAndGet()
                return true
            }
        }
        return false
    }

    fun createEmptyResponse(): WebResourceResponse {
        return WebResourceResponse(
            "text/plain",
            "UTF-8",
            200,
            "OK",
            emptyMap(),
            ByteArrayInputStream(ByteArray(0))
        )
    }

    fun getYouTubeAdBlockScript(): String {
        return """
            (function() {
                if (window._onyxYTBlockerInjected) return;
                window._onyxYTBlockerInjected = true;

                function skipAds() {
                    // Click skip button immediately
                    var skipButtons = document.querySelectorAll(
                        '.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, button.ytp-ad-skip-button-icon, .ytp-ad-overlay-close-button'
                    );
                    skipButtons.forEach(function(btn) {
                        if (btn) btn.click();
                    });

                    // Fast forward video ads to the end
                    var video = document.querySelector('video');
                    var adContainer = document.querySelector('.ad-showing, .ad-interrupting, .ytp-ad-player-overlay');
                    if (video && adContainer) {
                        video.muted = true;
                        video.playbackRate = 16.0;
                        if (video.duration && !isNaN(video.duration)) {
                            video.currentTime = video.duration - 0.1;
                        }
                    }

                    // Hide banner ads and promoted content
                    var adElements = document.querySelectorAll(
                        '.ytp-ad-overlay-container, .ytp-ad-message-container, ytd-promoted-video-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer, #player-ads, .video-ads, .ytp-ad-module'
                    );
                    adElements.forEach(function(el) {
                        if (el) el.style.display = 'none';
                    });
                }

                setInterval(skipAds, 400);
            })();
        """.trimIndent()
    }
}
