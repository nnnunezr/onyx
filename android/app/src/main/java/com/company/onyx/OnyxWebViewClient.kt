package com.company.onyx

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient

class OnyxWebViewClient(
    private val activity: MainActivity,
    private val adBlockEngine: AdBlockEngine
) : WebViewClient() {

    var bridge: OnyxAndroidBridge? = null

    override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
        val url = request?.url?.toString() ?: return false
        if (url.startsWith("http://") || url.startsWith("https://") || url.startsWith(MainActivity.ASSET_PREFIX)) {
            return false
        }
        // Web content must not steer the WebView to other local files.
        if (url.startsWith("file:")) return true
        // External application schemes (mailto:, tel:, geo:, market:)
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            true
        }
    }

    override fun shouldInterceptRequest(
        view: WebView?,
        request: WebResourceRequest?
    ): WebResourceResponse? {
        val uri = request?.url
        if (adBlockEngine.shouldBlock(uri)) {
            return adBlockEngine.createEmptyResponse()
        }
        return super.shouldInterceptRequest(view, request)
    }

    override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
        // Only Onyx's bundled pages may drive the OnyxAndroid bridge.
        bridge?.trustedPageLoaded = url?.startsWith(MainActivity.ASSET_PREFIX) == true
        super.onPageStarted(view, url, favicon)
        activity.updateNavigationState()
        if (url != null && (url.contains("duckduckgo.com") || url.contains("duck.com") ||
            (url.contains("google.") && (url.contains("/search") || url.contains("q=") || url.contains("/imghp") || url.contains("tbm=") || url.contains("udm="))))) {
            injectOnyxSearchTheme(view)
        }
    }

    override fun onPageFinished(view: WebView?, url: String?) {
        super.onPageFinished(view, url)
        activity.updateNavigationState()

        // Inject YouTube AdBlocker
        if (url != null && (url.contains("youtube.com") || url.contains("youtu.be"))) {
            val script = adBlockEngine.getYouTubeAdBlockScript()
            view?.evaluateJavascript(script, null)
        }

        // Inject Onyx Search styling on DuckDuckGo and Google
        if (url != null && (url.contains("duckduckgo.com") || url.contains("duck.com") ||
            (url.contains("google.") && (url.contains("/search") || url.contains("q=") || url.contains("/imghp") || url.contains("tbm=") || url.contains("udm="))))) {
            injectOnyxSearchTheme(view)
        }
    }

    private fun injectOnyxSearchTheme(view: WebView?) {
        val css = """
            :root {
                --space-1: 4px !important;
                --space-2: 8px !important;
                --space-3: 12px !important;
                --space-4: 16px !important;
                --space-6: 24px !important;
                --onyx-bg: #070709 !important;
                --onyx-surface: rgba(255, 255, 255, 0.035) !important;
                --onyx-border: rgba(255, 255, 255, 0.08) !important;
            }
            *, *::before, *::after {
                box-sizing: border-box !important;
            }
            html, body, #app, .site-wrapper, .wrapper, .results-wrapper, main, .serp__body {
                background-color: #070709 !important;
                color: #ffffff !important;
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", Roboto, sans-serif !important;
                -webkit-font-smoothing: antialiased !important;
            }
            /* Scrub all DuckDuckGo logos, duck mascots, wordmarks, and globe icons */
            .header__logo-wrap, .header__logo, .header__logo__img, #header-logo-wrapper, #header-logo, #logo,
            [data-testid="header-logo"], [data-testid="logo"], [data-testid="logo-link"], [data-testid="logo_link"],
            a[aria-label*="DuckDuckGo home" i], a[aria-label*="DuckDuckGo" i], a[data-testid="logo-link"],
            a[data-testid="header-logo"], a[href="/"], header a[href="/"],
            #header a[href="/"], .header a[href="/"], .header-wrap a[href="/"], .site-wrapper header a[href="/"],
            [class*="HeaderLogo"], [class*="header_logo"], [class*="header__logo"],
            svg[class*="logo" i], svg[class*="Logo" i], svg[class*="duck" i],
            svg:has(path[fill="#F05F2B"]), svg:has(path[fill="#DE5833"]), svg:has(ellipse[fill="#F05F2B"]),
            .header__logo img, .header-wrap img[src*="duck"], #header-logo-wrapper img,
            a[aria-label*="DuckDuckGo home"] img, a[data-testid="logo-link"] img,
            img[alt*="DuckDuckGo" i], img[src*="duckduckgo" i], img[src*="duck" i],
            .header__tagline, .header__text, .header--aside, .header--aside__item, .header__button--menu,
            .js-side-menu-open, .feedback-btn, #footer-feedback-wrapper, .nav-menu--feedback,
            .react-feedback-prompt-mvc-wrapper, button[data-testid="feedback-button"],
            a[href*="assist=true"], li:has(> a[href*="assist=true"]),
            .badge--ad, [data-testid="ad"], [data-testid="ad-item"], .results--ads, .result--ad, .ads-wrapper,
            .ddg-extension-banner, .onboarding-ed, .js-onboarding-wrapper, .badge--privacy, .badge--protection,
            [data-testid="region-filter"] svg, .dropdown--region svg,
            button[aria-label*="Region" i] svg, button[aria-label*="region" i] svg,
            .footer, #footer, .footer__addons, .nav-menu, .nav-menu__item,
            .serp__top-right, .serp__bottom-right,
            #spacing_hidden_wrapper, #spacing_hidden, #bottom_spacing2, #z, #z2,
            .legacy-homepage__bottom {
                display: none !important;
                opacity: 0 !important;
                visibility: hidden !important;
                pointer-events: none !important;
                width: 0 !important;
                height: 0 !important;
                margin: 0 !important;
                padding: 0 !important;
                max-width: 0 !important;
                max-height: 0 !important;
                overflow: hidden !important;
            }
            html, html.is-not-mobile-device,
            body, body.is-not-mobile-device,
            .is-not-mobile-device, .site-wrapper,
            #web_content_wrapper, .content-wrap, #links_wrapper,
            #react-layout, [data-testid="mainline"], .results--main,
            #spacing_hidden_wrapper, #spacing_hidden, #bottom_spacing2, #z, #z2 {
                min-width: 0 !important;
                max-width: 100% !important;
                width: 100% !important;
                box-sizing: border-box !important;
                margin-left: 0 !important;
                margin-right: 0 !important;
            }
            html, body {
                overflow-x: hidden !important;
            }
            .header-wrap, #header_wrapper {
                background: #070709 !important;
                border: none !important;
                box-shadow: none !important;
                padding: 12px 16px 0 16px !important;
                width: 100% !important;
                max-width: 100% !important;
                box-sizing: border-box !important;
            }
            #header, .header.cw, #header-non-nav,
            .header__search-wrap, .header__content, .header__search,
            #react-search-form, #search_form {
                background: transparent !important;
                border: none !important;
                padding: 0 !important;
                margin: 0 !important;
                width: 100% !important;
                max-width: 100% !important;
                box-sizing: border-box !important;
                display: flex !important;
                flex-direction: column !important;
                align-items: flex-start !important;
            }
            /* Nuke edge gradient masks and cutoffs on mobile */
            nav::before, nav::after,
            [class*="ph1UFslrkUMqoYJEtp3t"]::before, [class*="ph1UFslrkUMqoYJEtp3t"]::after,
            [class*="hnKIeVb9Fi3YMCZAeQvR"]::before, [class*="hnKIeVb9Fi3YMCZAeQvR"]::after,
            [class*="DrcPyihFGyKMlg6lpwsa"]::before, [class*="DrcPyihFGyKMlg6lpwsa"]::after,
            [class*="W4_K5H4AqLL1ngRJt_pk"]::before, [class*="W4_K5H4AqLL1ngRJt_pk"]::after,
            .search-filters-wrap::before, .search-filters-wrap::after,
            .metabar__dropdowns-wrap::before, .metabar__dropdowns-wrap::after,
            .zcm__dropdowns::before, .zcm__dropdowns::after,
            [class*="XvPRmQVeIoCP5lQhICTv"]::before, [class*="XvPRmQVeIoCP5lQhICTv"]::after,
            .header-wrap::before, .header-wrap::after,
            #header::before, #header::after {
                display: none !important;
                content: none !important;
                background: transparent !important;
                background-image: none !important;
                opacity: 0 !important;
                visibility: hidden !important;
                width: 0 !important;
                height: 0 !important;
            }
            /* Filter buttons and dropdowns */
            nav[class*="ph1UFslrkUMqoYJEtp3t"] button,
            [class*="c1GwqC__eRoEs0cLTIfL"] button,
            .dropdown, .zcm__dropdown,
            [data-testid="privacy-reminder"],
            [data-testid="region-filter-label"],
            [data-testid="date-filter-trigger"] {
                background: rgba(255, 255, 255, 0.04) !important;
                border: 1px solid rgba(255, 255, 255, 0.08) !important;
                border-radius: 8px !important;
                color: #a1a1aa !important;
                font-size: 12px !important;
                padding: 4px 8px !important;
                display: inline-flex !important;
                align-items: center !important;
            }
            /* Dropdown menus */
            div[role="menu"], div[role="listbox"], .modal--dropdown {
                background: #121216 !important;
                border: 1px solid rgba(255, 255, 255, 0.12) !important;
                border-radius: 12px !important;
                box-shadow: 0 12px 40px rgba(0, 0, 0, 0.75) !important;
                color: #ffffff !important;
            }
            .search--header, .search--adv, .search-wrap,
            #search_form [class*="QsyijBlqupsaY11GFhnp"],
            #search_form [class*="T265XEcezvjUhK71U8pN"] {
                background: rgba(255, 255, 255, 0.04) !important;
                border: 1px solid rgba(255, 255, 255, 0.10) !important;
                border-radius: 24px !important;
                height: 44px !important;
                padding: 0 16px !important;
                box-shadow: 0 2px 10px rgba(0, 0, 0, 0.35) !important;
                width: 100% !important;
                max-width: 100% !important;
                box-sizing: border-box !important;
            }
            .search__input, #search_form_input, input[type="text"][name="q"] {
                color: #ffffff !important;
                font-size: 15px !important;
                background: transparent !important;
                border: none !important;
                outline: none !important;
                width: 100% !important;
            }
            #web_content_wrapper, .content-wrap, #react-layout {
                width: 100% !important;
                max-width: 100% !important;
                padding: 0 16px !important;
                margin: 0 !important;
                box-sizing: border-box !important;
            }
            [class*="qrc3T8W2"], [class*="FMPme3X9"],
            section[class*="At_VJ9M"], .At_VJ9MlrHsSjbfCtz2_ {
                width: 100% !important;
                max-width: 100% !important;
                margin: 0 !important;
                padding: 0 !important;
                box-sizing: border-box !important;
                flex-basis: 100% !important;
            }
            #links, #results, .results--main, .react-results--main {
                width: 100% !important;
                max-width: 100% !important;
                padding: 12px 0 48px 0 !important;
                margin: 0 !important;
                box-sizing: border-box !important;
                list-style: none !important;
            }
            .react-results--main > li, #links > div {
                width: 100% !important;
                max-width: 100% !important;
                margin: 0 !important;
                padding: 0 !important;
                box-sizing: border-box !important;
                list-style: none !important;
            }
            .result, .nrn-react-div, article[data-testid="result"], .result--default, article {
                width: 100% !important;
                max-width: 100% !important;
                background: rgba(255, 255, 255, 0.035) !important;
                border: 1px solid rgba(255, 255, 255, 0.08) !important;
                border-radius: 12px !important;
                padding: 16px 18px !important;
                margin-bottom: 12px !important;
                box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3) !important;
                box-sizing: border-box !important;
            }
            .result__title, [data-testid="result-title-a"], h2 {
                color: #ffffff !important;
                font-size: 16.5px !important;
                font-weight: 500 !important;
                line-height: 1.35 !important;
                margin-bottom: 4px !important;
            }
            .result__title a, [data-testid="result-title-a"] {
                color: #ffffff !important;
                text-decoration: none !important;
            }
            .result__url, [data-testid="result-extras-url-link"], cite {
                color: #71717a !important;
                font-size: 12px !important;
                text-decoration: none !important;
                margin-bottom: 4px !important;
            }
            .result__snippet, [data-testid="result-snippet"] {
                color: #d4d4d8 !important;
                font-size: 13.5px !important;
                line-height: 1.55 !important;
                margin-top: 6px !important;
            }
            b, strong, .highlight {
                color: #ffffff !important;
                background: rgba(255, 255, 255, 0.12) !important;
                padding: 1px 4px !important;
                border-radius: 4px !important;
            }
            /* Google Search Theme & Capsule */
            .RNNXgb, form[role="search"] .RNNXgb {
                background: rgba(255, 255, 255, 0.04) !important;
                border: 1px solid rgba(255, 255, 255, 0.10) !important;
                border-radius: 24px !important;
                height: 44px !important;
                padding: 0 16px !important;
                box-shadow: 0 2px 10px rgba(0, 0, 0, 0.35) !important;
                width: 100% !important;
                max-width: 100% !important;
                box-sizing: border-box !important;
            }
            .RNNXgb textarea, .RNNXgb input, textarea.gLFyf, input.gLFyf, #APjFqb {
                color: #ffffff !important;
                font-size: 15px !important;
                background: transparent !important;
                border: none !important;
                outline: none !important;
                -webkit-text-fill-color: #ffffff !important;
            }
            /* Scrub Google Header Clutter, 9-dot launcher, Share button, Account */
            #logo, .logo img, header svg.logo, a#logo, .logocont, #logocont,
            #gb, .gb_d, .gb_e, .gb_f, .gb_g, .gb_h, .gb_i, .gb_Ja, .gb_A, .gb_B,
            [aria-label*="Google apps" i], [aria-label*="Google app" i], [aria-label*="Google Account" i],
            a[href*="accounts.google.com"], a[href*="/preferences"], a[href*="/saves"],
            .Q3DXx, .Efnghe, .apFnFf, [aria-label*="Share" i], [aria-label*="Compartir" i], [data-share-url],
            svg:has(path[d*="M16 5l-1.42"]), svg:has(path[d*="M18 16.08c"]),
            #searchform button:not(#tsf button), header button:not(#tsf button), .sfbg button:not(#tsf button),
            #searchform > div:not(:has(#tsf)):not(#tsf),
            .zLSRge, .w2jn8d, .PwiNU, .m29tEd, .hdtb-ms, #hdtb-ms, hr, .HPvrce {
                display: none !important;
                opacity: 0 !important;
                visibility: hidden !important;
                pointer-events: none !important;
                width: 0 !important;
                height: 0 !important;
                margin: 0 !important;
                padding: 0 !important;
                overflow: hidden !important;
            }
            /* Google Category Tabs */
            .beZ0tf a, .rQTE8b a, a.C6AK7c, a.XVMlrc, .mOKdDc, #hdtb-tls {
                background: rgba(255, 255, 255, 0.04) !important;
                border: 1px solid rgba(255, 255, 255, 0.08) !important;
                border-radius: 20px !important;
                color: #a1a1aa !important;
                font-size: 13px !important;
                padding: 6px 14px !important;
                text-decoration: none !important;
            }
            .beZ0tf a.C6AK7c[disabled="true"], a.C6AK7c[disabled="true"],
            .beZ0tf a.C6AK7c[aria-disabled="true"], a.C6AK7c[aria-disabled="true"],
            .beZ0tf a.C6AK7c:has([aria-current="page"]), a.C6AK7c:has([aria-current="page"]),
            [role="tab"][aria-selected="true"] {
                background: rgba(255, 255, 255, 0.14) !important;
                border: 1px solid rgba(255, 255, 255, 0.28) !important;
                color: #ffffff !important;
                font-weight: 600 !important;
            }
            /* Obsidian Result Cards on Google */
            #center_col, #rso, .MjjYud, .g {
                width: 100% !important;
                max-width: 100% !important;
                box-sizing: border-box !important;
            }
            .g, .MjjYud:not(:has(.g)):not(:has([data-video-id])) {
                background: rgba(255, 255, 255, 0.035) !important;
                border: 1px solid rgba(255, 255, 255, 0.08) !important;
                border-radius: 14px !important;
                padding: 16px !important;
                margin-bottom: 12px !important;
            }
        """.trimIndent().replace("\n", " ")

        val js = """
            (function() {
                if (!document.getElementById('onyx-search-theme')) {
                    const style = document.createElement('style');
                    style.id = 'onyx-search-theme';
                    style.textContent = '$css';
                    (document.head || document.documentElement).appendChild(style);
                }
                if (document.title && document.title.includes('DuckDuckGo')) {
                    document.title = document.title.replace(/DuckDuckGo/g, '').replace(/ - /g, '').replace(/ — /g, '').trim();
                } else if (document.title && document.title.includes('Google Search')) {
                    document.title = document.title.replace(/ - Google Search/g, '').replace(/Google Search/g, '').trim();
                }
                const badSelectors = [
                    '.header__logo-wrap', '.header__logo', '.header__logo__img', '[data-testid="logo"]',
                    '#header-logo-wrapper', '#header-logo', '#logo', '[data-testid="header-logo"]',
                    '[data-testid="logo-link"]', '[data-testid="logo_link"]', 'a[aria-label*="DuckDuckGo home" i]',
                    'a[aria-label*="DuckDuckGo" i]', 'a#logo', 'a[data-testid="logo-link"]', 'a[data-testid="header-logo"]',
                    'a[href="/"]', 'header a[href="/"]', '#header a[href="/"]',
                    '.header a[href="/"]', '.header-wrap a[href="/"]', '.site-wrapper header a[href="/"]',
                    'svg[class*="logo" i]', 'svg[class*="Logo" i]', 'svg[class*="duck" i]',
                    'img[alt*="DuckDuckGo" i]', 'img[src*="duckduckgo" i]', 'img[src*="duck" i]',
                    '[data-testid="region-filter"] svg', '.dropdown--region svg',
                    'button[aria-label*="Region" i] svg', 'button[aria-label*="region" i] svg',
                    '.ddg-extension-banner', '.onboarding-ed', '.js-onboarding-wrapper', '.badge--ad',
                    '[data-testid="ad"]', '[data-testid="ad-item"]', '.results--ads', '.result--ad', '.ads-wrapper',
                    '.footer', '#footer', '.badge--privacy', '.badge--protection',
                    '#gb', '.gb_d', '.gb_Ja', '.gb_A', '.gb_B', '[aria-label*="Google apps" i]',
                    '[aria-label*="Google app" i]', '[aria-label*="Google Account" i]',
                    'a[href*="accounts.google.com"]', 'a[href*="/saves"]', 'a[href*="/preferences"]',
                    '.Q3DXx', '.Efnghe', '.apFnFf', '[aria-label*="Share" i]', '[aria-label*="Compartir" i]', '[data-share-url]'
                ];
                badSelectors.forEach(sel => {
                    try {
                        document.querySelectorAll(sel).forEach(e => {
                            e.style.setProperty('display', 'none', 'important');
                            e.style.setProperty('visibility', 'hidden', 'important');
                            e.remove();
                        });
                    } catch(err) {}
                });
            })();
        """.trimIndent()

        view?.evaluateJavascript(js, null)
    }
}
