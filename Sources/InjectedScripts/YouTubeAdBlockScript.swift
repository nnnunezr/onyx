import Cocoa
import WebKit
import UniformTypeIdentifiers

let youTubeAdBlockerSource = #"""
    (function() {
        if (window.__onyx_yt_adblock_installed) return;
        window.__onyx_yt_adblock_installed = true;

        // 1. Permanent CSS rule hiding YouTube ad banners, promos, overlays, and enforcement dialogs
        var css = `
            #masthead-ad,
            #player-ads,
            ytd-ad-slot-renderer,
            ytd-in-feed-ad-layout-renderer,
            ytd-rich-item-renderer:has(ytd-ad-slot-renderer),
            ytd-promoted-sparkles-web-renderer,
            ytd-promoted-video-renderer,
            ytd-compact-promoted-video-renderer,
            ytd-banner-promo-renderer,
            ytd-statement-banner-renderer,
            ytd-action-companion-ad-renderer,
            ytd-merch-shelf-renderer,
            .ytd-merch-shelf-renderer,
            .ytp-ad-overlay-container,
            .ytp-ad-message-container,
            .ytp-ad-preview-container,
            .ytp-ad-image-overlay,
            .ytp-ad-text-overlay,
            .ytp-ad-player-overlay,
            .ytp-ad-player-overlay-flyout-cta,
            ytd-engagement-panel-section-list-renderer[target-id='engagement-panel-ads'],
            ytd-companion-slot-renderer,
            yt-mealbar-promo-renderer,
            ytd-mealbar-promo-renderer,
            ytd-enforcement-message-view-model {
                display: none !important;
                visibility: hidden !important;
                opacity: 0 !important;
                pointer-events: none !important;
                height: 0 !important;
                min-height: 0 !important;
            }
        `;

        function injectStyle() {
            if (!document.getElementById("onyx-yt-adblock-style")) {
                var style = document.createElement("style");
                style.id = "onyx-yt-adblock-style";
                style.textContent = css;
                (document.head || document.documentElement).appendChild(style);
            }
        }
        injectStyle();
        if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", injectStyle);
        }

        // 2. Data / JSON Pruning Engine (uBlock Origin & YoutubeAdblock pattern)
        // Strips ad configurations before player initializes or renders them
        function pruneAdProperties(obj) {
            if (!obj || typeof obj !== "object") return obj;
            try {
                if ("adPlacements" in obj) delete obj.adPlacements;
                if ("adSlots" in obj) delete obj.adSlots;
                if ("playerAds" in obj) delete obj.playerAds;
                if ("adBreakHeartbeatParams" in obj) delete obj.adBreakHeartbeatParams;
                if (obj.playerResponse && typeof obj.playerResponse === "object") {
                    pruneAdProperties(obj.playerResponse);
                }
                if (obj.auxiliaryUi && obj.auxiliaryUi.messageRenderers) {
                    delete obj.auxiliaryUi.messageRenderers.upsellDialogRenderer;
                    delete obj.auxiliaryUi.messageRenderers.enforcementMessageViewModel;
                }
                if (obj.playbackTracking) {
                    delete obj.playbackTracking.atrUrl;
                    delete obj.playbackTracking.qoeStatsUrl;
                    delete obj.playbackTracking.videostatsPlaybackUrl;
                }
            } catch (e) {}
            return obj;
        }

        // Intercept JSON.parse to sanitize any incoming InnerTube player payloads
        try {
            var origJSONParse = JSON.parse;
            JSON.parse = function() {
                var res = origJSONParse.apply(this, arguments);
                if (res && typeof res === "object") {
                    if (res.adPlacements || res.adSlots || res.playerAds || res.playerResponse) {
                        pruneAdProperties(res);
                    }
                }
                return res;
            };
        } catch(e) {}

        // Intercept Response.prototype.json
        try {
            if (window.Response && Response.prototype.json) {
                var origResponseJson = Response.prototype.json;
                Response.prototype.json = function() {
                    return origResponseJson.apply(this, arguments).then(function(data) {
                        if (data && typeof data === "object") {
                            if (data.adPlacements || data.adSlots || data.playerAds || data.playerResponse) {
                                pruneAdProperties(data);
                            }
                        }
                        return data;
                    });
                };
            }
        } catch(e) {}

        // Property trap on window.ytInitialPlayerResponse
        try {
            var _ytInitialPlayerResponse = window.ytInitialPlayerResponse;
            if (_ytInitialPlayerResponse) pruneAdProperties(_ytInitialPlayerResponse);
            Object.defineProperty(window, "ytInitialPlayerResponse", {
                get: function() { return _ytInitialPlayerResponse; },
                set: function(val) { _ytInitialPlayerResponse = pruneAdProperties(val); },
                configurable: true
            });
        } catch(e) {}

        // Intercept fetch to neutralize ad telemetry and ad break pings
        try {
            if (window.fetch) {
                var origFetch = window.fetch;
                window.fetch = function(input, init) {
                    var url = typeof input === "string" ? input : (input && input.url ? input.url : "");
                    if (url.indexOf("/api/stats/ads") !== -1 ||
                        url.indexOf("/pagead/") !== -1 ||
                        url.indexOf("/ptracking") !== -1 ||
                        url.indexOf("/youtubei/v1/player/ad_break") !== -1) {
                        return Promise.resolve(new Response(JSON.stringify({}), {
                            status: 200,
                            headers: { "Content-Type": "application/json" }
                        }));
                    }
                    return origFetch.apply(this, arguments);
                };
            }
        } catch(e) {}

        // 3. Anti-Adblock Modal Neutralizer
        // Automatically dismisses enforcement modals and resumes video playback ONLY if an enforcement modal was actively blocking
        function dismissAntiAdblockModal() {
            var dialogs = document.querySelectorAll("ytd-enforcement-message-view-model, tp-yt-paper-dialog:has(ytd-enforcement-message-view-model)");
            if (dialogs.length > 0) {
                dialogs.forEach(function(d) {
                    var wrapper = d.closest("tp-yt-paper-dialog") || d;
                    wrapper.remove();
                });

                var backdrops = document.querySelectorAll("tp-yt-iron-overlay-backdrop");
                backdrops.forEach(function(b) { b.remove(); });

                if (document.body && (document.body.style.overflow === "hidden" || document.body.style.overflowY === "hidden")) {
                    document.body.style.overflow = "auto";
                    document.body.style.overflowY = "auto";
                }

                var video = document.querySelector("video");
                var player = document.getElementById("movie_player") || document.querySelector(".html5-video-player");
                var isAdShowing = player && (player.classList.contains("ad-showing") || player.classList.contains("ad-interrupting"));
                if (video && video.paused && !video.ended && !isAdShowing) {
                    video.play().catch(function() {});
                }
            }
        }

        // 4. Real-time Video Ad Skipping & Playback State Restoration
        var savedState = null;
        var isHandlingAd = false;

        function handleVideoAds() {
            dismissAntiAdblockModal();

            var player = document.getElementById("movie_player") || document.querySelector(".html5-video-player");
            var video = document.querySelector("video");
            if (!player || !video) return;

            // Accurate ad detection strictly from player class attributes
            var isAdActive = player.classList.contains("ad-showing") || player.classList.contains("ad-interrupting");

            if (isAdActive) {
                if (!isHandlingAd) {
                    isHandlingAd = true;
                    // Preserve original user volume and playback rate
                    savedState = {
                        muted: video.muted,
                        playbackRate: (video.playbackRate > 0 && video.playbackRate <= 4) ? video.playbackRate : 1.0
                    };
                }

                // Mute ad audio instantly
                if (!video.muted) {
                    video.muted = true;
                }

                // Speed up playback to fast-forward through ad frames
                if (video.playbackRate < 16) {
                    video.playbackRate = 16.0;
                }

                // Seek straight to video duration if finite
                if (isFinite(video.duration) && video.duration > 0) {
                    video.currentTime = video.duration;
                }

                // Click skip button immediately
                var skipSelectors = [
                    ".ytp-ad-skip-button",
                    ".ytp-ad-skip-button-modern",
                    ".ytp-skip-ad-button",
                    "button.ytp-ad-skip-button-modern",
                    ".ytp-ad-skip-button-container button",
                    "[id^='skip-button'] button",
                    ".videoAdUiSkipButton",
                    ".ytp-ad-skip-button-slot button"
                ];
                for (var i = 0; i < skipSelectors.length; i++) {
                    var btn = document.querySelector(skipSelectors[i]);
                    if (btn) {
                        btn.click();
                        break;
                    }
                }

                // Click overlay close buttons if present
                var closeBtn = document.querySelector(".ytp-ad-overlay-close-button, .ytp-ad-overlay-close-container button");
                if (closeBtn) {
                    closeBtn.click();
                }
            } else {
                // Normal video is active
                if (isHandlingAd) {
                    isHandlingAd = false;
                    // Restore user's original playback rate & audio mute
                    if (savedState) {
                        video.playbackRate = savedState.playbackRate || 1.0;
                        video.muted = savedState.muted;
                        savedState = null;
                    } else {
                        if (video.playbackRate > 4) {
                            video.playbackRate = 1.0;
                        }
                    }
                } else {
                    // Failsafe: if video is at ad speed for any reason, reset to 1.0
                    if (video.playbackRate > 4) {
                        video.playbackRate = 1.0;
                    }
                }
            }
        }

        // 5. Event Listeners & Observer Setup
        function attachVideoListeners() {
            var video = document.querySelector("video");
            if (video && !video.__onyx_ad_monitored) {
                video.__onyx_ad_monitored = true;
                video.addEventListener("timeupdate", handleVideoAds);
                video.addEventListener("play", handleVideoAds);
                video.addEventListener("playing", handleVideoAds);
                video.addEventListener("ratechange", function() {
                    var player = document.getElementById("movie_player") || document.querySelector(".html5-video-player");
                    if (player && (player.classList.contains("ad-showing") || player.classList.contains("ad-interrupting"))) {
                        if (video.playbackRate < 16) {
                            video.playbackRate = 16.0;
                        }
                    }
                });
            }
        }

        attachVideoListeners();

        // High-frequency watchdog interval (runs every 150ms)
        setInterval(function() {
            injectStyle();
            attachVideoListeners();
            handleVideoAds();
        }, 150);

        // MutationObserver to catch dynamic DOM additions immediately
        var observer = new MutationObserver(function() {
            injectStyle();
            attachVideoListeners();
            handleVideoAds();
        });

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ["class", "style"]
        });

        // YouTube SPA navigation events
        window.addEventListener("yt-navigate-start", handleVideoAds);
        window.addEventListener("yt-navigate-finish", function() {
            injectStyle();
            attachVideoListeners();
            handleVideoAds();
        });
        window.addEventListener("yt-page-data-updated", function() {
            if (window.ytInitialPlayerResponse) {
                pruneAdProperties(window.ytInitialPlayerResponse);
            }
            handleVideoAds();
        });
    })();
    """#
