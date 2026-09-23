import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // Onyx Research Engine: Direct Comet-Style WebKit Integration
    func setupOnyxResearchBridge() {
        setupResearchBridge(for: sharedConfiguration)
    }
    
    func setupResearchBridge(for config: WKWebViewConfiguration) {
        // Native WebKit UserStyleSheet registration (Zero-FOUC, applied at WebCore parser level before DOM evaluation)
        if let userStyleSheetClass = NSClassFromString("_WKUserStyleSheet") as? NSObject.Type {
            let sel = NSSelectorFromString("initWithSource:forWKWebView:forMainFrameOnly:includeMatchPatternStrings:excludeMatchPatternStrings:baseURL:level:contentWorld:")
            typealias InitExt = @convention(c) (NSObject, Selector, NSString, WKWebView?, Bool, NSArray?, NSArray?, NSURL?, Int, WKContentWorld) -> NSObject
            let selAdd = NSSelectorFromString("_addUserStyleSheet:")
            typealias AddFunc = @convention(c) (WKUserContentController, Selector, NSObject) -> Void
            
            if userStyleSheetClass.instancesRespond(to: sel) && config.userContentController.responds(to: selAdd) {
                let searchPatterns = [
                    "*://*.google.com/*",
                    "*://google.com/*",
                    "*://*.google.ca/*",
                    "*://*.google.co.uk/*",
                    "*://*.google.de/*",
                    "*://*.google.fr/*",
                    "*://*.google.es/*",
                    "*://*.google.it/*",
                    "*://*.google.co.jp/*",
                    "*://*.duckduckgo.com/*",
                    "*://duckduckgo.com/*",
                    "*://*.duck.com/*",
                    "*://duck.com/*",
                    "*://*.brave.com/*"
                ] as NSArray
                
                let searchObj = userStyleSheetClass.init()
                let impInitSearch = searchObj.method(for: sel)
                let fnSearch = unsafeBitCast(impInitSearch, to: InitExt.self)
                let searchSheet = fnSearch(searchObj, sel, onyxSearchCSS as NSString, nil, true, searchPatterns, nil, nil, 1, WKContentWorld.page)
                
                let impAdd = config.userContentController.method(for: selAdd)
                let addFn = unsafeBitCast(impAdd, to: AddFunc.self)
                addFn(config.userContentController, selAdd, searchSheet)
                
                let researchPatterns = [
                    "*://duck.ai/*",
                    "*://*.duck.ai/*"
                ] as NSArray
                let researchObj = userStyleSheetClass.init()
                let impInitResearch = researchObj.method(for: sel)
                let fnResearch = unsafeBitCast(impInitResearch, to: InitExt.self)
                let researchSheet = fnResearch(researchObj, sel, onyxResearchCSS as NSString, nil, true, researchPatterns, nil, nil, 1, WKContentWorld.page)
                addFn(config.userContentController, selAdd, researchSheet)
            }
        }

        let escapedResearchCSS = onyxResearchCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        
        let escapedSearchCSS = onyxSearchCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let jsSourceStart = """
        (function() {
            const host = window.location.hostname || '';
            const href = window.location.href || '';
            const isDuck = host.includes('duck.ai') || host.includes('duckduckgo.com') || host.includes('duck.com');
            const isGoogle = host.includes('google.') && (href.includes('/search') || href.includes('q=') || href.includes('/imghp') || href.includes('tbm=') || href.includes('udm=') || host.startsWith('images.'));
            const isBrave = host.includes('brave.com') && href.includes('/search');
            const isSearch = isDuck || isGoogle || isBrave;
            if (!isSearch) return;

            try {
                document.documentElement.style.setProperty('background-color', '#070709', 'important');
                document.documentElement.style.setProperty('color-scheme', 'dark', 'important');
                document.documentElement.setAttribute('data-theme', 'dark');
                if (isGoogle) {
                    document.cookie = "PREF=f6=400; domain=.google.com; path=/; max-age=31536000";
                }
            } catch(e) {}

            function ensureBodyDark() {
                if (document.body) {
                    document.body.style.setProperty('background-color', '#070709', 'important');
                    document.body.style.setProperty('color', '#ffffff', 'important');
                }
            }
            ensureBodyDark();
            const bodyObs = new MutationObserver(() => {
                if (document.body) {
                    ensureBodyDark();
                    bodyObs.disconnect();
                }
            });
            try { bodyObs.observe(document.documentElement, { childList: true }); } catch(e) {}

            const isChat = host.includes('duck.ai') || href.includes('ia=chat');
            const css = isChat ? `\(escapedResearchCSS)` : `\(escapedSearchCSS)`;
            const styleId = isChat ? 'onyx-research-theme' : 'onyx-search-theme';

            let themeStyle = document.getElementById(styleId);
            if (!themeStyle) {
                themeStyle = document.createElement('style');
                themeStyle.id = styleId;
                themeStyle.textContent = css;
                (document.head || document.documentElement).appendChild(themeStyle);
            }

            function pinStyle() {
                const target = document.head || document.documentElement;
                if (!target) return;
                if (!document.getElementById(styleId)) {
                    target.appendChild(themeStyle);
                } else if (target.lastElementChild !== themeStyle) {
                    target.appendChild(themeStyle);
                }
            }

            // Keep stylesheet at very end of <head> during incremental HTML stream
            const headObserver = new MutationObserver(() => {
                pinStyle();
            });
            try {
                headObserver.observe(document.documentElement, { childList: true, subtree: true });
            } catch(e) {}

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', () => {
                    pinStyle();
                    setTimeout(() => { try { headObserver.disconnect(); } catch(e) {} }, 6000);
                });
            }

            // Capture-phase instant tab feedback when switching categories (All, Images, Videos, etc.)
            window.addEventListener('click', function(e) {
                const tab = e.target && e.target.closest && e.target.closest('a.C6AK7c, a.XVMlrc, .beZ0tf a, .rQTE8b a, .mOKdDc, #hdtb-tls');
                if (tab) {
                    const allTabs = document.querySelectorAll('.beZ0tf a, .rQTE8b a, a.C6AK7c, a.XVMlrc, .mOKdDc, #hdtb-tls');
                    allTabs.forEach(t => {
                        t.style.setProperty('background', 'rgba(255, 255, 255, 0.04)', 'important');
                        t.style.setProperty('border-color', 'rgba(255, 255, 255, 0.08)', 'important');
                        t.style.setProperty('color', '#a1a1aa', 'important');
                        t.style.setProperty('font-weight', '500', 'important');
                    });
                    tab.style.setProperty('background', 'rgba(255, 255, 255, 0.14)', 'important');
                    tab.style.setProperty('border-color', 'rgba(255, 255, 255, 0.28)', 'important');
                    tab.style.setProperty('color', '#ffffff', 'important');
                    tab.style.setProperty('font-weight', '600', 'important');
                }
            }, true);
        })();
        """

        let jsSource = """
        (function() {
            const host = window.location.hostname || '';
            const href = window.location.href || '';
            const isDuck = host.includes('duck.ai') || host.includes('duckduckgo.com') || host.includes('duck.com');
            const isGoogle = host.includes('google.') && (href.includes('/search') || href.includes('q=') || href.includes('/imghp') || href.includes('tbm=') || href.includes('udm=') || host.startsWith('images.'));
            const isBrave = host.includes('brave.com') && href.includes('/search');
            const isSearch = isDuck || isGoogle || isBrave;
            if (!isSearch) return;
            const isChat = host.includes('duck.ai') || href.includes('ia=chat');

            try {
                document.documentElement.style.colorScheme = 'dark';
                document.documentElement.setAttribute('data-theme', 'dark');
                let meta = document.querySelector('meta[name="color-scheme"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'color-scheme';
                    meta.content = 'dark';
                    (document.head || document.documentElement).appendChild(meta);
                }
                if (isGoogle) {
                    document.cookie = "PREF=f6=400; domain=.google.com; path=/; max-age=31536000";
                }
            } catch(e) {}

            function injectStyles() {
                if (isChat) {
                    if (!document.getElementById('onyx-research-theme')) {
                        const style = document.createElement('style');
                        style.id = 'onyx-research-theme';
                        style.textContent = `\(escapedResearchCSS)`;
                        (document.head || document.documentElement).appendChild(style);
                    }
                } else {
                    if (!document.getElementById('onyx-search-theme')) {
                        const style = document.createElement('style');
                        style.id = 'onyx-search-theme';
                        style.textContent = `\(escapedSearchCSS)`;
                        (document.head || document.documentElement).appendChild(style);
                    }
                }
            }

            function scrubTitle() {
                if (document.title && document.title.includes('DuckDuckGo')) {
                    document.title = document.title
                        .replace(/ at DuckDuckGo/g, '')
                        .replace(/ - DuckDuckGo/g, '')
                        .replace(/DuckDuckGo — /g, '');
                    if (!document.title.startsWith('✦ ')) {
                        document.title = '✦ ' + document.title + ' — Search';
                    }
                } else if (document.title && document.title.includes('Google Search')) {
                    document.title = document.title
                        .replace(/ - Google Search/g, '')
                        .replace(/Google Search/g, '')
                        .trim();
                    if (!document.title.startsWith('✦ ')) {
                        document.title = '✦ ' + document.title + ' — Search';
                    }
                }
            }

            function hideMascotsAndPromos() {
                if (document.querySelector('.anomaly-modal, [class*="anomaly-modal"], #anomaly-detected')) return;
                const badSelectors = [
                    '.header__logo-wrap', '.header__logo', '.header__logo__img', '[data-testid="logo"]',
                    '#header-logo-wrapper', '#header-logo', '#logo', '[data-testid="header-logo"]',
                    '[data-testid="logo-link"]', '[data-testid="logo_link"]', 'a[aria-label*="DuckDuckGo home" i]',
                    'a[aria-label*="DuckDuckGo" i]', 'a#logo', 'a[data-testid="logo-link"]', 'a[data-testid="header-logo"]',
                    'a[href="/"]', 'header a[href="/"]', '#header a[href="/"]',
                    '.header a[href="/"]', '.header-wrap a[href="/"]', '.site-wrapper header a[href="/"]',
                    '[class*="HeaderLogo"]', '[class*="header_logo"]', '[class*="header__logo"]',
                    'svg[class*="logo" i]', 'svg[class*="Logo" i]', 'svg[class*="duck" i]',
                    'img[alt*="DuckDuckGo" i]', 'img[src*="duckduckgo" i]', 'img[src*="duck" i]',
                    'a[href="/compare-privacy"]', 'a[href*="compare-privacy"]', 'a[href*="compare"]',
                    '.header__tagline', '.header__text', '.header--aside', '.header--aside__item',
                    '.header__button--menu', '.js-side-menu-open',
                    '.feedback-btn', 'button[data-testid="feedback-button"]',
                    '.js-feedback-btn-wrap', '[class*="TccjmKV6"]', '[class*="bYzmzE1m"]', '[class*="s_aX02AKO"]',
                    '#footer-feedback-wrapper', '.nav-menu--feedback', '.react-feedback-prompt-mvc-wrapper',
                    'a[href*="assist=true"]', 'li:has(> a[href*="assist=true"])',
                    'a[href*="ia=chat"]:not(.onyx-research-switch-btn)', 'li:has(> a[href*="ia=chat"]:not(.onyx-research-switch-btn))',
                    'li:has(> button[aria-label*="Search Settings"])',
                    'button[aria-label*="Search Settings"]',
                    '[data-testid="region-filter"] svg', '.dropdown--region svg',
                    'button[aria-label*="Region" i] svg', 'button[aria-label*="region" i] svg',
                    '.ddg-extension-banner', '.onboarding-ed', '.js-onboarding-wrapper', '.badge--ad',
                    '[data-testid="ad"]', '[data-testid="ad-item"]', '.results--ads', '.result--ad', '.ads-wrapper',
                    '.footer', '#footer', '.badge--privacy', '.badge--protection',
                    '.RM8cPgCF1NymxEVCc19D', '.y8qZjjhkSVTmBOORd3oQ', '.S1TV9gKXE9qTlJCKQyVA',
                    '[class*="extension-banner"]', '[class*="onboarding"]', '[class*="feedback"]', '[class*="Feedback"]',
                    '[class*="feedback-btn"]', '[class*="feedback-modal"]',
                    'a[href*="spread"]', 'a[href*="newsletter"]',
                    '#logo', '.logo img', 'header svg.logo', 'a#logo', '#fbar', '#footcnt', '#foot',
                    '.uEierd', '#tads', '#tadsb', '[data-text-ad]', '.appbar', '.cv2Vmc', '.LH92ce',
                    '.TQc1id', '.SJ1Kg', '.G57R0c', '#taw'
                ];
                badSelectors.forEach(sel => {
                    try {
                        document.querySelectorAll(sel).forEach(e => {
                            e.style.setProperty('display', 'none', 'important');
                            e.style.setProperty('visibility', 'hidden', 'important');
                            e.style.setProperty('opacity', '0', 'important');
                            e.style.setProperty('width', '0', 'important');
                            e.style.setProperty('height', '0', 'important');
                            e.style.setProperty('max-width', '0', 'important');
                            e.style.setProperty('max-height', '0', 'important');
                        });
                    } catch(err) {}
                });

                document.querySelectorAll('strong, span, p, a').forEach(el => {
                    if (el.children.length === 0 && el.innerText && el.innerText.includes('DuckDuckGo')) {
                        el.innerText = el.innerText.replace(/DuckDuckGo/g, 'Onyx Search');
                    }
                    if (el.children.length === 0 && el.innerText && el.innerText.trim() === 'Duck.ai') {
                        el.innerText = 'Onyx Research';
                    }
                });
            }

            function tagSearchPill() {
                const input = document.getElementById('search_form_input') || document.querySelector('input[name="q"]');
                if (input) {
                    const pill = input.closest('[class*="QsyijBlqupsaY11GFhnp"]') ||
                                 input.closest('[class*="T265XEcezvjUhK71U8pN"]') ||
                                 input.closest('[data-testid="search-form-input-wrapper"]') ||
                                 input.parentElement;
                    if (pill && !pill.classList.contains('onyx-search-pill')) {
                        pill.classList.add('onyx-search-pill');
                    }
                }
            }

            function updateActiveDuckbarTab() {
                const duckbar = document.getElementById('react-duckbar') || document.querySelector('[data-testid="duckbar"]');
                if (!duckbar) return;
                const ul = duckbar.querySelector('ul:first-child');
                if (!ul) return;
                const links = ul.querySelectorAll('a');
                if (!links || links.length === 0) return;

                const url = new URL(window.location.href);
                const ia = (url.searchParams.get('ia') || url.searchParams.get('iar') || '').toLowerCase();

                let activeLink = null;
                links.forEach(a => {
                    if (a.classList.contains('onyx-research-switch-btn')) return;
                    a.classList.add('onyx-duckbar-tab');
                    const text = (a.innerText || '').trim().toLowerCase();
                    const href = (a.getAttribute('href') || '').toLowerCase();

                    let isActive = false;
                    if (ia === 'images' && (text.includes('image') || href.includes('ia=images') || href.includes('iar=images'))) isActive = true;
                    else if (ia === 'videos' && (text.includes('video') || href.includes('ia=videos') || href.includes('iar=videos'))) isActive = true;
                    else if (ia === 'news' && (text.includes('news') || href.includes('ia=news') || href.includes('iar=news'))) isActive = true;
                    else if (ia === 'maps' && (text.includes('map') || href.includes('ia=maps') || href.includes('iar=maps'))) isActive = true;
                    else if ((!ia || ia === 'web') && (text === 'all' || a.querySelector('svg') || a.classList.contains('SnptgjT2zdOhGYfNng6g'))) isActive = true;

                    if (isActive) {
                        a.classList.add('onyx-tab-active');
                        a.classList.add('is-active');
                        activeLink = a;
                    } else {
                        a.classList.remove('onyx-tab-active');
                        a.classList.remove('is-active');
                        a.classList.remove('SnptgjT2zdOhGYfNng6g');
                    }
                });

                if (!activeLink && links.length > 0) {
                    links[0].classList.add('onyx-tab-active');
                    links[0].classList.add('is-active');
                    activeLink = links[0];
                }

                // Setup or fetch the single shared light glider
                let glider = document.getElementById('onyx-duckbar-glider');
                if (!glider) {
                    glider = document.createElement('div');
                    glider.id = 'onyx-duckbar-glider';
                    glider.className = 'onyx-duckbar-glider';
                    duckbar.appendChild(glider);
                }

                function positionGlider(targetTab, animate) {
                    if (!targetTab || !glider) return;
                    const duckbarRect = duckbar.getBoundingClientRect();
                    const tabRect = targetTab.getBoundingClientRect();
                    if (tabRect.width === 0) {
                        requestAnimationFrame(() => positionGlider(targetTab, animate));
                        return;
                    }
                    const left = Math.round(tabRect.left - duckbarRect.left);
                    const width = Math.min(Math.max(Math.round(tabRect.width), 30), 160);

                    if (!animate) {
                        glider.style.setProperty('transition', 'none', 'important');
                    } else {
                        glider.style.setProperty('transition', 'transform 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), width 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), opacity 0.2s ease', 'important');
                    }
                    glider.style.setProperty('transform', `translateX(${left}px)`, 'important');
                    glider.style.setProperty('width', `${width}px`, 'important');
                    glider.classList.add('is-ready');
                    if (!animate) {
                        void glider.offsetWidth;
                    }
                }

                // Bind click listeners for instant fluid light transfer between tabs
                links.forEach(a => {
                    if (a.classList.contains('onyx-research-switch-btn')) return;
                    if (a.dataset.gliderBound) return;
                    a.dataset.gliderBound = 'true';
                    a.addEventListener('click', () => {
                        const currentActive = ul.querySelector('a.onyx-tab-active') || links[0];
                        const duckbarRect = duckbar.getBoundingClientRect();
                        const curRect = currentActive ? currentActive.getBoundingClientRect() : null;
                        if (curRect && curRect.width > 0 && curRect.width < 200) {
                            try {
                                sessionStorage.setItem('onyx_glider_from_x', Math.round(curRect.left - duckbarRect.left).toString());
                                sessionStorage.setItem('onyx_glider_from_w', Math.min(Math.max(Math.round(curRect.width), 30), 160).toString());
                            } catch(e) {}
                        }
                        positionGlider(a, true);
                        links.forEach(l => {
                            if (l === a) {
                                l.classList.add('onyx-tab-active');
                                l.classList.add('is-active');
                            } else {
                                l.classList.remove('onyx-tab-active');
                                l.classList.remove('is-active');
                                l.classList.remove('SnptgjT2zdOhGYfNng6g');
                            }
                        });
                    });
                });

                if (!window._onyxDuckbarResizeBound) {
                    window._onyxDuckbarResizeBound = true;
                    window.addEventListener('resize', () => {
                        const current = document.querySelector('#react-duckbar ul:first-child a.onyx-tab-active') ||
                                        document.querySelector('[data-testid="duckbar"] ul:first-child a.onyx-tab-active');
                        if (current) positionGlider(current, false);
                    });
                }

                if (activeLink) {
                    let fromX = null;
                    let fromW = null;
                    try {
                        fromX = sessionStorage.getItem('onyx_glider_from_x');
                        fromW = sessionStorage.getItem('onyx_glider_from_w');
                        sessionStorage.removeItem('onyx_glider_from_x');
                        sessionStorage.removeItem('onyx_glider_from_w');
                    } catch(e) {}

                    const fw = parseFloat(fromW);
                    const fx = parseFloat(fromX);
                    if (!isNaN(fw) && !isNaN(fx) && fw >= 25 && fw <= 160 && fx >= 0 && fx <= 1200) {
                        const duckbarRect = duckbar.getBoundingClientRect();
                        const activeRect = activeLink.getBoundingClientRect();
                        const newLeft = Math.round(activeRect.left - duckbarRect.left);
                        if (Math.abs(fx - newLeft) > 5) {
                            glider.style.setProperty('transition', 'none', 'important');
                            glider.style.setProperty('transform', `translateX(${fx}px)`, 'important');
                            glider.style.setProperty('width', `${fw}px`, 'important');
                            glider.classList.add('is-ready');
                            void glider.offsetWidth;
                            requestAnimationFrame(() => {
                                requestAnimationFrame(() => {
                                    positionGlider(activeLink, true);
                                });
                            });
                            return;
                        }
                    }
                    positionGlider(activeLink, false);
                }
            }

            function injectOnyxSearchHeader() {
                if (isChat) return;
                const oldHeader = document.getElementById('onyx-brand-header');
                if (oldHeader) oldHeader.remove();

                const duckbar = document.getElementById('react-duckbar') || document.querySelector('[data-testid="duckbar"]');
                if (!duckbar) return;
                const ul = duckbar.querySelector('ul:first-child');
                if (!ul) return;

                const params = new URLSearchParams(window.location.search);
                const query = (params.get('q') || '').replace(/\\+/g, ' ');
                if (!query) return;

                let switchLi = document.getElementById('onyx-research-switch-li');
                if (!switchLi) {
                    switchLi = document.createElement('li');
                    switchLi.id = 'onyx-research-switch-li';
                    switchLi.style.cssText = 'margin-left: auto; display: inline-flex; align-items: center; padding: 0 0 2px 12px;';
                    switchLi.innerHTML = `
                        <a href="https://duckduckgo.com/?q=${encodeURIComponent(query)}&ia=chat" class="onyx-research-switch-btn" title="Open in Deep AI Research Mode">
                            <span>✦ Deep Research</span>
                        </a>
                    `;
                    ul.appendChild(switchLi);
                }
            }

            function injectAISynthesisCard() {
                if (isChat) return;
                const resultsContainer = document.querySelector('.react-results--main') ||
                                         document.querySelector('#links');
                if (!resultsContainer) return;

                const params = new URLSearchParams(window.location.search);
                const query = (params.get('q') || '').replace(/\\+/g, ' ');
                if (!query) return;

                let summaryText = '';
                const aboutSnippet = document.querySelector('[data-testid="about-snippet"]') ||
                                     document.querySelector('.module--wikipedia .module__body') ||
                                     document.querySelector('[data-testid="module--about"] .module__text') ||
                                     document.querySelector('.module__text');
                if (aboutSnippet && aboutSnippet.innerText && aboutSnippet.innerText.length > 50 && !aboutSnippet.innerText.includes('USD(%)') && !aboutSnippet.innerText.includes('1D5D')) {
                    summaryText = aboutSnippet.innerText.trim();
                } else {
                    const articles = document.querySelectorAll('article');
                    for (let i = 0; i < articles.length; i++) {
                        const art = articles[i];
                        const title = art.querySelector('h2') ? (art.querySelector('h2').innerText || '').trim() : '';
                        const lines = (art.innerText || '').split('\\n').map(s => s.trim()).filter(Boolean);
                        for (let j = 0; j < lines.length; j++) {
                            const line = lines[j];
                            if (title && (title === line || title.includes(line) || line.includes(title))) continue;
                            const cleaned = line.replace(/^[0-9]+\\s+(days?|hours?|mins?|weeks?|months?|years?)\\s+ago\\s*/i, '').trim();
                            if (cleaned.length >= 40 &&
                                !cleaned.includes('http') &&
                                !cleaned.includes('›') &&
                                !cleaned.includes('Only include') &&
                                !cleaned.includes('Redo search') &&
                                !cleaned.includes('Block this')) {
                                summaryText = cleaned;
                                break;
                            }
                        }
                        if (summaryText) break;
                    }
                }

                let card = document.getElementById('onyx-ai-synthesis-card');
                if (!card && summaryText && summaryText.trim().length > 20) {
                    card = document.createElement('div');
                    card.id = 'onyx-ai-synthesis-card';
                    card.innerHTML = `
                        <div class="onyx-ai-header">
                            <div class="onyx-ai-badge">
                                <span>✦</span>
                                <span>Onyx Synthetic Overview</span>
                            </div>
                            <span style="color: #71717a; font-size: 11px; font-weight: 500;">INSTANT OVERVIEW</span>
                        </div>
                        <div class="onyx-ai-content">
                            <p style="margin: 0; font-size: 14px; color: #e2e8f0; line-height: 1.65;">${summaryText}</p>
                        </div>
                    `;
                    const brandHeader = document.getElementById('onyx-brand-header');
                    if (brandHeader && brandHeader.parentElement === resultsContainer) {
                        if (brandHeader.nextSibling) {
                            resultsContainer.insertBefore(card, brandHeader.nextSibling);
                        } else {
                            resultsContainer.appendChild(card);
                        }
                    } else {
                        resultsContainer.insertBefore(card, resultsContainer.firstChild);
                    }
                } else if (card && card.parentElement !== resultsContainer) {
                    const brandHeader = document.getElementById('onyx-brand-header');
                    if (brandHeader && brandHeader.parentElement === resultsContainer && brandHeader.nextSibling) {
                        resultsContainer.insertBefore(card, brandHeader.nextSibling);
                    } else {
                        resultsContainer.insertBefore(card, resultsContainer.firstChild);
                    }
                }
            }

            function dismissOnboarding() {
                const buttons = Array.from(document.querySelectorAll('button'));
                for (const btn of buttons) {
                    const txt = (btn.textContent || '').trim().toLowerCase();
                    if (txt === 'got it' || txt === 'i agree' || txt === 'continue' || txt === 'accept') {
                        btn.click();
                    }
                }
            }

            let submitted = false;
            function autoSubmitIfReady() {
                if (!isChat || submitted) return;
                const params = new URLSearchParams(window.location.search);
                const query = params.get('q');
                if (!query) return;

                const textarea = document.querySelector('textarea[name="message"]') ||
                                 document.querySelector('textarea');
                const submitBtn = document.querySelector('form button[type="submit"]') ||
                                 Array.from(document.querySelectorAll('form button')).find(b => {
                                     let t = (b.innerText || '').trim().toLowerCase();
                                     let a = (b.getAttribute('aria-label') || '').toLowerCase();
                                     return t === 'ask' || t === 'send' || a === 'send';
                                 });

                if (textarea && submitBtn && !submitBtn.disabled) {
                    if (!textarea.value || textarea.value.trim() === '') {
                        const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, "value")?.set;
                        if (setter) {
                            setter.call(textarea, query);
                        } else {
                            textarea.value = query;
                        }
                        textarea.dispatchEvent(new Event('input', { bubbles: true }));
                        textarea.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                    submitted = true;
                    setTimeout(() => {
                        submitBtn.click();
                    }, 120);
                }
            }

            function injectThinkingOrbHUD() {
                if (!isChat) return;
                if (document.getElementById('onyx-orb-hud')) {
                    const txt = document.getElementById('onyx-orb-hud-text');
                    const hasMessage = document.querySelector('[data-testid="chat-message"]') || document.querySelector('.space-y-4');
                    const submitBtn = document.querySelector('form button[type="submit"]');
                    if (hasMessage && submitBtn && !submitBtn.disabled) {
                        if (txt && txt.textContent === 'Synthesizing') {
                            txt.textContent = 'Synthesized';
                            setTimeout(() => {
                                const h = document.getElementById('onyx-orb-hud');
                                if (h) h.style.opacity = '0.35';
                            }, 1800);
                        }
                    }
                    return;
                }
                if (!document.body) return;
                const hud = document.createElement('div');
                hud.id = 'onyx-orb-hud';
                hud.style.cssText = 'position: fixed; top: 14px; right: 20px; z-index: 999999; display: flex; align-items: center; gap: 8px; background: rgba(18, 18, 22, 0.75); border: 1px solid rgba(255, 255, 255, 0.10); border-radius: 20px; padding: 4px 12px 4px 6px; backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); box-shadow: 0 4px 16px rgba(0, 0, 0, 0.35); pointer-events: none; transition: opacity 300ms ease; cursor: pointer; pointer-events: auto;';
                hud.title = 'Switch Profile / Context';
                hud.innerHTML = '<canvas id="onyx-orb-hud-canvas" width="48" height="48" style="width: 24px; height: 24px; border-radius: 50%;"></canvas><span id="onyx-orb-hud-text" style="font-size: 11px; font-weight: 500; letter-spacing: -0.01em; color: #a1a1aa; font-family: -apple-system, BlinkMacSystemFont, sans-serif;">Synthesizing</span>';
                hud.onclick = () => {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openProfileManager) {
                        window.webkit.messageHandlers.openProfileManager.postMessage(null);
                    }
                };
                document.body.appendChild(hud);

                const cvs = document.getElementById('onyx-orb-hud-canvas');
                if (cvs) {
                    const ctx = cvs.getContext('2d');
                    const DPR = Math.min(2, window.devicePixelRatio || 1);
                    cvs.width = 24 * DPR;
                    cvs.height = 24 * DPR;
                    let t = 0;
                    function drawHUDOrb() {
                        ctx.clearRect(0, 0, cvs.width, cvs.height);
                        const cx = cvs.width / 2, cy = cvs.height / 2;
                        const R = (cvs.width / 2) * 0.75;
                        const latRings = 5, lonDensity = 10;
                        for (let ri = 0; ri <= latRings; ri++) {
                            const lat = -Math.PI / 2 + (ri / latRings) * Math.PI;
                            const cosLat = Math.cos(lat), sinLat = Math.sin(lat);
                            const w = 0.6 * Math.sin(t * 2.5 - ri * 0.6) + 0.4 * Math.sin(t * 1.5 + ri * 0.8);
                            const rr = R * (0.88 + 0.12 * w);
                            const lonCount = Math.max(1, Math.round(Math.abs(cosLat) * lonDensity));
                            for (let lj = 0; lj < lonCount; lj++) {
                                const lon = (lj / lonCount) * 2 * Math.PI;
                                const x = cosLat * Math.cos(lon) * rr;
                                const y = sinLat * rr;
                                const z = cosLat * Math.sin(lon) * rr;
                                const rad = 0.35;
                                const y2 = y * Math.cos(rad) - z * Math.sin(rad);
                                const z2 = y * Math.sin(rad) + z * Math.cos(rad);
                                const depth = (z2 / R + 1) / 2;
                                const alpha = 0.35 + 0.65 * depth;
                                ctx.beginPath();
                                ctx.arc(cx + x, cy + y2, (0.7 + 1.1 * depth) * DPR, 0, Math.PI * 2);
                                ctx.fillStyle = `rgba(255, 255, 255, ${alpha.toFixed(2)})`;
                                ctx.fill();
                            }
                        }
                        t += 0.04;
                        requestAnimationFrame(drawHUDOrb);
                    }
                    requestAnimationFrame(drawHUDOrb);
                }
            }

            function isAnomaly() {
                return !!(document.querySelector('.anomaly-modal, [class*="anomaly-modal"], #anomaly-detected'));
            }

            function injectBypassBanner() {
                const modal = document.querySelector('.anomaly-modal, [class*="anomaly-modal"], #anomaly-detected');
                if (!modal || document.getElementById('onyx-bypass-banner')) return;
                const banner = document.createElement('div');
                banner.id = 'onyx-bypass-banner';
                banner.className = 'onyx-bot-bypass-bar';
                const q = new URLSearchParams(window.location.search).get('q') || '';
                banner.innerHTML = `
                    <div style="display:flex; align-items:center; gap:8px;">
                        <span style="color:#ffffff; font-size:14px;">✦</span>
                        <span style="font-size:12.5px; font-weight:500; color:#e2e8f0;">Onyx Private Shield: Verification Challenge</span>
                    </div>
                    <button class="onyx-bot-bypass-btn" id="onyx-bypass-click">
                        Bypass Challenge ➔
                    </button>
                `;
                modal.insertBefore(banner, modal.firstChild);
                const btn = document.getElementById('onyx-bypass-click');
                if (btn) {
                    btn.onclick = (e) => {
                        e.preventDefault();
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bypassBotChallenge) {
                            window.webkit.messageHandlers.bypassBotChallenge.postMessage(q);
                        } else {
                            window.location.href = 'https://search.brave.com/search?q=' + encodeURIComponent(q);
                        }
                    };
                }
            }

            function cycle() {
                injectStyles();
                if (isAnomaly()) {
                    injectBypassBanner();
                    return;
                }
                scrubTitle();
                hideMascotsAndPromos();
                if (isChat) {
                    dismissOnboarding();
                    autoSubmitIfReady();
                    injectThinkingOrbHUD();
                } else {
                    tagSearchPill();
                    updateActiveDuckbarTab();
                    injectOnyxSearchHeader();
                    injectAISynthesisCard();
                }
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', cycle);
            } else {
                cycle();
            }

            let debounceTimer = null;
            function debouncedCycle() {
                if (debounceTimer) cancelAnimationFrame(debounceTimer);
                debounceTimer = requestAnimationFrame(() => {
                    cycle();
                });
            }

            // Observe dynamic results and SPA DOM transitions for Google, DDG, and Brave
            const observeTarget = document.getElementById('rso') ||
                                  document.getElementById('rcnt') ||
                                  document.getElementById('center_col') ||
                                  document.getElementById('links') ||
                                  document.querySelector('.react-results--main') ||
                                  document.body ||
                                  document.documentElement;
            if (observeTarget) {
                const observer = new MutationObserver(() => {
                    debouncedCycle();
                });
                try {
                    observer.observe(observeTarget, { childList: true, subtree: true });
                } catch(e) {}
            }

            // Hook HTML5 History API for SPA tab navigation
            const origPushState = history.pushState;
            history.pushState = function() {
                origPushState.apply(this, arguments);
                debouncedCycle();
            };
            const origReplaceState = history.replaceState;
            history.replaceState = function() {
                origReplaceState.apply(this, arguments);
                debouncedCycle();
            };
            window.addEventListener('popstate', debouncedCycle);
        })();
        """

        let userScriptStart = WKUserScript(source: jsSourceStart, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScriptStart)
        let userScriptEnd = WKUserScript(source: jsSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScriptEnd)
        config.userContentController.add(self, name: "bypassBotChallenge")
    }
    
    func injectOnyxResearchScript(into webView: WKWebView) {
        guard isResearchURL(webView.url) else { return }
        let escapedCSS = onyxResearchCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let script = """
        (function() {
            if (!document.getElementById("onyx-research-theme")) {
                let s = document.createElement("style");
                s.id = "onyx-research-theme";
                s.textContent = `\(escapedCSS)`;
                (document.head || document.documentElement).appendChild(s);
            }
            document.querySelectorAll('.RM8cPgCF1NymxEVCc19D, .y8qZjjhkSVTmBOORd3oQ, .S1TV9gKXE9qTlJCKQyVA').forEach(e => {
                e.style.display = 'none';
            });
            let brandTexts = Array.from(document.querySelectorAll("strong, span, div")).filter(e => e.innerText && e.innerText.trim() === "Duck.ai");
            brandTexts.forEach(b => {
                b.textContent = "Onyx Research";
            });
            // Safely dismiss promotional banner via its close button
            document.querySelectorAll('button').forEach(b => {
                const label = (b.getAttribute('aria-label') || '').toLowerCase();
                const pText = (b.parentElement?.textContent || '');
                if ((label.includes('close') || label.includes('dismiss')) && pText.includes('Duck.ai works best')) {
                    b.click();
                }
            });
            let submitBtn = document.querySelector('form button[type="submit"]') ||
                            Array.from(document.querySelectorAll('form button')).find(b => {
                                let t = (b.innerText || '').trim().toLowerCase();
                                let a = (b.getAttribute('aria-label') || '').toLowerCase();
                                return t === 'ask' || t === 'send' || a === 'send';
                            });
            if (submitBtn && !submitBtn.disabled) {
                submitBtn.click();
            }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    func isResearchURL(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        let str = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""
        return host.contains("duck.ai") || str.contains("ia=chat")
    }
    
    func isSearchURL(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        if isResearchURL(url) { return false }
        let host = url.host?.lowercased() ?? ""
        return host.contains("duckduckgo.com") || host.contains("duck.com") ||
               (host.contains("google.") && (url.path.contains("/search") || (url.query?.contains("q=") == true) || url.path.contains("/imghp") || host.hasPrefix("images.google."))) ||
               (host.contains("brave.com") && url.path.contains("/search")) ||
               (host.contains("kagi.com") && url.path.contains("/search")) ||
               (host.contains("bing.com") && url.path.contains("/search"))
    }
    
    func extractResearchQuery(from url: URL?) -> String {
        guard let url = url else { return "" }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let qItem = queryItems.first(where: { $0.name == "q" }),
           let value = qItem.value, !value.isEmpty {
            let decoded = value.removingPercentEncoding ?? value
            return decoded.replacingOccurrences(of: "+", with: " ")
        }
        return ""
    }

    func extractSearchQuery(from url: URL?) -> String {
        guard let url = url else { return "" }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            if let qItem = queryItems.first(where: { $0.name == "q" || $0.name == "search_query" }),
               let value = qItem.value, !value.isEmpty {
                let decoded = value.removingPercentEncoding ?? value
                return decoded.replacingOccurrences(of: "+", with: " ")
            }
        }
        return extractResearchQuery(from: url)
    }

    func injectOnyxSearchScript(into webView: WKWebView) {
        guard isSearchURL(webView.url) else { return }
        let escapedCSS = onyxSearchCSS
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let script = """
        (function() {
            if (document.querySelector('.anomaly-modal, [class*="anomaly-modal"], #anomaly-detected')) {
                return;
            }
            try {
                document.documentElement.style.colorScheme = 'dark';
                document.documentElement.setAttribute('data-theme', 'dark');
                let meta = document.querySelector('meta[name="color-scheme"]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'color-scheme';
                    meta.content = 'dark';
                    (document.head || document.documentElement).appendChild(meta);
                }
                if (window.location.hostname.includes('google.')) {
                    document.cookie = "PREF=f6=400; domain=.google.com; path=/; max-age=31536000";
                }
            } catch(e) {}

            let themeStyle = document.getElementById("onyx-search-theme");
            if (!themeStyle) {
                themeStyle = document.createElement("style");
                themeStyle.id = "onyx-search-theme";
            }
            themeStyle.textContent = `\(escapedCSS)`;
            const styleTarget = document.head || document.documentElement;
            if (styleTarget && (themeStyle.parentElement !== styleTarget || styleTarget.lastElementChild !== themeStyle)) {
                styleTarget.appendChild(themeStyle);
            }

            if (document.title && document.title.includes("DuckDuckGo")) {
                document.title = document.title
                    .replace(/ at DuckDuckGo/g, '')
                    .replace(/ - DuckDuckGo/g, '')
                    .replace(/DuckDuckGo — /g, '')
                    .replace(/DuckDuckGo/g, '')
                    .trim();
                if (!document.title.startsWith('✦ ')) {
                    document.title = '✦ ' + document.title + ' — Search';
                }
            } else if (document.title && document.title.includes("Google Search")) {
                document.title = document.title
                    .replace(/ - Google Search/g, '')
                    .replace(/Google Search/g, '')
                    .trim();
                if (!document.title.startsWith('✦ ')) {
                    document.title = '✦ ' + document.title + ' — Search';
                }
            }

            const badSelectors = [
                '.header__logo-wrap', '.header__logo', '.header__logo__img', '[data-testid="logo"]',
                '#header-logo-wrapper', '#header-logo', '#logo', '[data-testid="header-logo"]',
                '[data-testid="logo-link"]', '[data-testid="logo_link"]', 'a[aria-label*="DuckDuckGo home" i]',
                'a[aria-label*="DuckDuckGo" i]', 'a#logo', 'a[data-testid="logo-link"]', 'a[data-testid="header-logo"]',
                'a[href="/"]', 'header a[href="/"]', '#header a[href="/"]',
                '.header a[href="/"]', '.header-wrap a[href="/"]', '.site-wrapper header a[href="/"]',
                '[class*="HeaderLogo"]', '[class*="header_logo"]', '[class*="header__logo"]',
                'svg[class*="logo" i]', 'svg[class*="Logo" i]', 'svg[class*="duck" i]',
                'img[alt*="DuckDuckGo" i]', 'img[src*="duckduckgo" i]', 'img[src*="duck" i]',
                'a[href="/compare-privacy"]', 'a[href*="compare-privacy"]', 'a[href*="compare"]',
                '.header__tagline', '.header__text', '.header--aside', '.header--aside__item',
                '.header__button--menu', '.js-side-menu-open',
                '.feedback-btn', 'button[data-testid="feedback-button"]',
                '.js-feedback-btn-wrap', '[class*="TccjmKV6"]', '[class*="bYzmzE1m"]', '[class*="s_aX02AKO"]',
                '#footer-feedback-wrapper', '.nav-menu--feedback', '.react-feedback-prompt-mvc-wrapper',
                'a[href*="assist=true"]', 'li:has(> a[href*="assist=true"])',
                'a[href*="ia=chat"]:not(.onyx-research-switch-btn)', 'li:has(> a[href*="ia=chat"]:not(.onyx-research-switch-btn))',
                'li:has(> button[aria-label*="Search Settings"])',
                'button[aria-label*="Search Settings"]',
                '[data-testid="region-filter"] svg', '.dropdown--region svg',
                'button[aria-label*="Region" i] svg', 'button[aria-label*="region" i] svg',
                '.ddg-extension-banner', '.onboarding-ed', '.js-onboarding-wrapper', '.badge--ad',
                '[data-testid="ad"]', '[data-testid="ad-item"]', '.results--ads', '.result--ad', '.ads-wrapper',
                '.footer', '#footer', '.badge--privacy', '.badge--protection',
                '.RM8cPgCF1NymxEVCc19D', '.y8qZjjhkSVTmBOORd3oQ', '.S1TV9gKXE9qTlJCKQyVA',
                '[class*="extension-banner"]', '[class*="onboarding"]', '[class*="feedback"]', '[class*="Feedback"]',
                '[class*="feedback-btn"]', '[class*="feedback-modal"]',
                'a[href*="spread"]', 'a[href*="newsletter"]',
                '#logo', '.logo img', 'header svg.logo', 'a#logo', '#fbar', '#footcnt', '#foot',
                '.uEierd', '#tads', '#tadsb', '[data-text-ad]', '.appbar', '.cv2Vmc', '.LH92ce',
                '.TQc1id', '.SJ1Kg', '.G57R0c', '#taw',
                '#gb', '.gb_d', '.gb_Ja', '.gb_A', '.gb_B', '[aria-label*="Google apps" i]',
                '[aria-label*="Google app" i]', '[aria-label*="Google Account" i]',
                'a[href*="accounts.google.com"]', 'a[href*="/saves"]', 'a[href*="/preferences"]',
                '.HPvrce', '[class*="HPvrce"]', '.mTpL7c.HPvrce', '.u96bed.GTERze', '.Iy1nvd', '.SvoXfb',
                '.zLSRge', '.w2jn8d', '.PwiNU', '.m29tEd', '.hdtb-ms', '#hdtb-ms',
                '.Q3DXx', '.Efnghe', '.apFnFf', '[aria-label*="Share" i]', '[aria-label*="Compartir" i]', '[data-share-url]'
            ];
            badSelectors.forEach(sel => {
                try {
                    document.querySelectorAll(sel).forEach(e => {
                        e.style.setProperty('display', 'none', 'important');
                        e.style.setProperty('visibility', 'hidden', 'important');
                        e.style.setProperty('opacity', '0', 'important');
                        e.style.setProperty('width', '0', 'important');
                        e.style.setProperty('height', '0', 'important');
                        e.style.setProperty('max-width', '0', 'important');
                        e.style.setProperty('max-height', '0', 'important');
                    });
                } catch(err) {}
            });
            document.querySelectorAll('strong, span, p, a').forEach(el => {
                if (el.children.length === 0 && el.innerText && el.innerText.includes('DuckDuckGo')) {
                    el.innerText = el.innerText.replace(/DuckDuckGo/g, 'Onyx Search');
                }
                if (el.children.length === 0 && el.innerText && el.innerText.trim() === 'Duck.ai') {
                    el.innerText = 'Onyx Research';
                }
            });

            function tagSearchPill() {
                const input = document.getElementById('search_form_input') || document.querySelector('input[name="q"]');
                if (input) {
                    const pill = input.closest('[class*="QsyijBlqupsaY11GFhnp"]') ||
                                 input.closest('[class*="T265XEcezvjUhK71U8pN"]') ||
                                 input.closest('[data-testid="search-form-input-wrapper"]') ||
                                 input.parentElement;
                    if (pill && !pill.classList.contains('onyx-search-pill')) {
                        pill.classList.add('onyx-search-pill');
                    }
                }
            }

            function updateActiveDuckbarTab() {
                const duckbar = document.getElementById('react-duckbar') || document.querySelector('[data-testid="duckbar"]');
                if (!duckbar) return;
                const ul = duckbar.querySelector('ul:first-child');
                if (!ul) return;
                const links = ul.querySelectorAll('a');
                if (!links || links.length === 0) return;

                const url = new URL(window.location.href);
                const ia = (url.searchParams.get('ia') || url.searchParams.get('iar') || '').toLowerCase();

                let activeLink = null;
                links.forEach(a => {
                    if (a.classList.contains('onyx-research-switch-btn')) return;
                    a.classList.add('onyx-duckbar-tab');
                    const text = (a.innerText || '').trim().toLowerCase();
                    const href = (a.getAttribute('href') || '').toLowerCase();

                    let isActive = false;
                    if (ia === 'images' && (text.includes('image') || href.includes('ia=images') || href.includes('iar=images'))) isActive = true;
                    else if (ia === 'videos' && (text.includes('video') || href.includes('ia=videos') || href.includes('iar=videos'))) isActive = true;
                    else if (ia === 'news' && (text.includes('news') || href.includes('ia=news') || href.includes('iar=news'))) isActive = true;
                    else if (ia === 'maps' && (text.includes('map') || href.includes('ia=maps') || href.includes('iar=maps'))) isActive = true;
                    else if ((!ia || ia === 'web') && (text === 'all' || a.querySelector('svg') || a.classList.contains('SnptgjT2zdOhGYfNng6g'))) isActive = true;

                    if (isActive) {
                        a.classList.add('onyx-tab-active');
                        a.classList.add('is-active');
                        activeLink = a;
                    } else {
                        a.classList.remove('onyx-tab-active');
                        a.classList.remove('is-active');
                        a.classList.remove('SnptgjT2zdOhGYfNng6g');
                    }
                });

                if (!activeLink && links.length > 0) {
                    links[0].classList.add('onyx-tab-active');
                    links[0].classList.add('is-active');
                    activeLink = links[0];
                }

                // Setup or fetch the single shared light glider
                let glider = document.getElementById('onyx-duckbar-glider');
                if (!glider) {
                    glider = document.createElement('div');
                    glider.id = 'onyx-duckbar-glider';
                    glider.className = 'onyx-duckbar-glider';
                    duckbar.appendChild(glider);
                }

                function positionGlider(targetTab, animate) {
                    if (!targetTab || !glider) return;
                    const duckbarRect = duckbar.getBoundingClientRect();
                    const tabRect = targetTab.getBoundingClientRect();
                    if (tabRect.width === 0) {
                        requestAnimationFrame(() => positionGlider(targetTab, animate));
                        return;
                    }
                    const left = Math.round(tabRect.left - duckbarRect.left);
                    const width = Math.min(Math.max(Math.round(tabRect.width), 30), 160);

                    if (!animate) {
                        glider.style.setProperty('transition', 'none', 'important');
                    } else {
                        glider.style.setProperty('transition', 'transform 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), width 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), opacity 0.2s ease', 'important');
                    }
                    glider.style.setProperty('transform', `translateX(${left}px)`, 'important');
                    glider.style.setProperty('width', `${width}px`, 'important');
                    glider.classList.add('is-ready');
                    if (!animate) {
                        void glider.offsetWidth;
                    }
                }

                // Bind click listeners for instant fluid light transfer between tabs
                links.forEach(a => {
                    if (a.classList.contains('onyx-research-switch-btn')) return;
                    if (a.dataset.gliderBound) return;
                    a.dataset.gliderBound = 'true';
                    a.addEventListener('click', () => {
                        const currentActive = ul.querySelector('a.onyx-tab-active') || links[0];
                        const duckbarRect = duckbar.getBoundingClientRect();
                        const curRect = currentActive ? currentActive.getBoundingClientRect() : null;
                        if (curRect && curRect.width > 0 && curRect.width < 200) {
                            try {
                                sessionStorage.setItem('onyx_glider_from_x', Math.round(curRect.left - duckbarRect.left).toString());
                                sessionStorage.setItem('onyx_glider_from_w', Math.min(Math.max(Math.round(curRect.width), 30), 160).toString());
                            } catch(e) {}
                        }
                        positionGlider(a, true);
                        links.forEach(l => {
                            if (l === a) {
                                l.classList.add('onyx-tab-active');
                                l.classList.add('is-active');
                            } else {
                                l.classList.remove('onyx-tab-active');
                                l.classList.remove('is-active');
                                l.classList.remove('SnptgjT2zdOhGYfNng6g');
                            }
                        });
                    });
                });

                if (!window._onyxDuckbarResizeBound) {
                    window._onyxDuckbarResizeBound = true;
                    window.addEventListener('resize', () => {
                        const current = document.querySelector('#react-duckbar ul:first-child a.onyx-tab-active') ||
                                        document.querySelector('[data-testid="duckbar"] ul:first-child a.onyx-tab-active');
                        if (current) positionGlider(current, false);
                    });
                }

                if (activeLink) {
                    let fromX = null;
                    let fromW = null;
                    try {
                        fromX = sessionStorage.getItem('onyx_glider_from_x');
                        fromW = sessionStorage.getItem('onyx_glider_from_w');
                        sessionStorage.removeItem('onyx_glider_from_x');
                        sessionStorage.removeItem('onyx_glider_from_w');
                    } catch(e) {}

                    const fw = parseFloat(fromW);
                    const fx = parseFloat(fromX);
                    if (!isNaN(fw) && !isNaN(fx) && fw >= 25 && fw <= 160 && fx >= 0 && fx <= 1200) {
                        const duckbarRect = duckbar.getBoundingClientRect();
                        const activeRect = activeLink.getBoundingClientRect();
                        const newLeft = Math.round(activeRect.left - duckbarRect.left);
                        if (Math.abs(fx - newLeft) > 5) {
                            glider.style.setProperty('transition', 'none', 'important');
                            glider.style.setProperty('transform', `translateX(${fx}px)`, 'important');
                            glider.style.setProperty('width', `${fw}px`, 'important');
                            glider.classList.add('is-ready');
                            void glider.offsetWidth;
                            requestAnimationFrame(() => {
                                requestAnimationFrame(() => {
                                    positionGlider(activeLink, true);
                                });
                            });
                            return;
                        }
                    }
                    positionGlider(activeLink, false);
                }
            }

            tagSearchPill();
            updateActiveDuckbarTab();
            const resultsContainer = document.querySelector('.react-results--main') ||
                                     document.querySelector('#links');
            if (resultsContainer) {
                const params = new URLSearchParams(window.location.search);
                const query = (params.get('q') || '').replace(/\\+/g, ' ');

                let header = document.getElementById('onyx-brand-header');
                if (!header) {
                    header = document.createElement('div');
                    header.id = 'onyx-brand-header';
                    header.innerHTML = `
                        <div class="onyx-brand-title">
                            <span class="onyx-brand-dot"></span>
                            <span>✦ Onyx Search</span>
                            <span style="color: #71717a; font-weight: 400; font-size: 13px;">• Direct Web Index</span>
                        </div>
                        <div style="display: flex; gap: 8px; align-items: center;">
                            <a href="https://duckduckgo.com/?q=${encodeURIComponent(query)}&ia=chat" class="onyx-research-switch-btn" title="Open in Deep AI Research Mode">
                                <span>✦ Deep AI Research</span>
                            </a>
                        </div>
                    `;
                    resultsContainer.insertBefore(header, resultsContainer.firstChild);
                } else if (header.parentElement !== resultsContainer) {
                    resultsContainer.insertBefore(header, resultsContainer.firstChild);
                }

                let summaryText = '';
                const aboutSnippet = document.querySelector('[data-testid="about-snippet"]') ||
                                     document.querySelector('.module--wikipedia .module__body') ||
                                     document.querySelector('[data-testid="module--about"] .module__text') ||
                                     document.querySelector('.module__text');
                if (aboutSnippet && aboutSnippet.innerText && aboutSnippet.innerText.length > 50 && !aboutSnippet.innerText.includes('USD(%)') && !aboutSnippet.innerText.includes('1D5D')) {
                    summaryText = aboutSnippet.innerText.trim();
                } else {
                    const articles = document.querySelectorAll('article');
                    for (let i = 0; i < articles.length; i++) {
                        const art = articles[i];
                        const title = art.querySelector('h2') ? (art.querySelector('h2').innerText || '').trim() : '';
                        const lines = (art.innerText || '').split('\\n').map(s => s.trim()).filter(Boolean);
                        for (let j = 0; j < lines.length; j++) {
                            const line = lines[j];
                            if (title && (title === line || title.includes(line) || line.includes(title))) continue;
                            const cleaned = line.replace(/^[0-9]+\\s+(days?|hours?|mins?|weeks?|months?|years?)\\s+ago\\s*/i, '').trim();
                            if (cleaned.length >= 40 &&
                                !cleaned.includes('http') &&
                                !cleaned.includes('›') &&
                                !cleaned.includes('Only include') &&
                                !cleaned.includes('Redo search') &&
                                !cleaned.includes('Block this')) {
                                summaryText = cleaned;
                                break;
                            }
                        }
                        if (summaryText) break;
                    }
                }

                let card = document.getElementById('onyx-ai-synthesis-card');
                if (!card && summaryText && summaryText.trim().length > 20) {
                    card = document.createElement('div');
                    card.id = 'onyx-ai-synthesis-card';
                    card.innerHTML = `
                        <div class="onyx-ai-header">
                            <div class="onyx-ai-badge">
                                <span>✦</span>
                                <span>Onyx Synthetic Overview</span>
                            </div>
                            <span style="color: #71717a; font-size: 11px; font-weight: 500;">INSTANT OVERVIEW</span>
                        </div>
                        <div class="onyx-ai-content">
                            <p style="margin: 0; font-size: 14px; color: #e2e8f0; line-height: 1.65;">${summaryText}</p>
                        </div>
                    `;
                    if (header && header.parentElement === resultsContainer) {
                        if (header.nextSibling) {
                            resultsContainer.insertBefore(card, header.nextSibling);
                        } else {
                            resultsContainer.appendChild(card);
                        }
                    } else {
                        resultsContainer.insertBefore(card, resultsContainer.firstChild);
                    }
                } else if (card && card.parentElement !== resultsContainer) {
                    if (header && header.parentElement === resultsContainer && header.nextSibling) {
                        resultsContainer.insertBefore(card, header.nextSibling);
                    } else {
                        resultsContainer.insertBefore(card, resultsContainer.firstChild);
                    }
                }
            }
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}
