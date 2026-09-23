import Cocoa
import WebKit
import UniformTypeIdentifiers

let onyxResearchCSS = """
    :root {
        --bg: #070709 !important;
        --surface: rgba(255, 255, 255, 0.04) !important;
        --border: rgba(255, 255, 255, 0.08) !important;
        --text: #ffffff !important;
        --text-muted: #a1a1aa !important;
    }

    html, body {
        background-color: #070709 !important;
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", sans-serif !important;
        -webkit-font-smoothing: antialiased !important;
    }

    #app, main, section, [role="main"] {
        background-color: #070709 !important;
        color: #ffffff !important;
    }

    /* Force opacity on responses */
    [class*="ulhFW"],
    .space-y-4 {
        opacity: 1 !important;
    }

    /* Hide Duck mascot SVGs, watermarks, center hero */
    svg:has(path[fill="#F05F2B"]),
    svg:has(path[fill="#DE5833"]),
    svg:has(path[fill="#9E2B08"]),
    .sk-lockup,
    .RM8cPgCF1NymxEVCc19D,
    .y8qZjjhkSVTmBOORd3oQ,
    .S1TV9gKXE9qTlJCKQyVA,
    .uOlVBqdhDvmtfhIycAG0,
    .O5Ra8A7Sorua0Mko8MYQ,
    .BXf8VCyyOfjab0CgSDlg,
    .n4vrMGwaSPo1WZT89efg {
        display: none !important;
    }

    /* Hide top privacy banner & disclaimer */
    .iP4HH3Eq_DvgejuvS05a,
    .zCVUKvnxAtTkzWbiEROp {
        display: none !important;
    }

    /* Left sidebar styled as macOS native source list */
    main > section:first-child {
        background-color: #0a0a0d !important;
        border-right: 1px solid rgba(255, 255, 255, 0.06) !important;
    }

    /* Chat messages text styling */
    p, li {
        color: #ffffff !important;
        font-size: 15px !important;
        line-height: 1.65 !important;
        letter-spacing: -0.01em !important;
    }

    /* Prompt Form (Apple 24px capsule) */
    form {
        border-radius: 24px !important;
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        backdrop-filter: blur(24px) !important;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5) !important;
    }

    textarea {
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 14px !important;
    }

    /* Submit button */
    button[type="submit"],
    button[aria-label="Send"] {
        background: #ffffff !important;
        border-radius: 50% !important;
    }
    button[type="submit"] svg,
    button[aria-label="Send"] svg {
        fill: #000000 !important;
    }
    button[type="submit"] path,
    button[aria-label="Send"] path {
        fill: #000000 !important;
    }
    """

let onyxSearchCSS = """
    :root {
        --space-1: 4px !important;
        --space-2: 8px !important;
        --space-3: 12px !important;
        --space-4: 16px !important;
        --space-5: 20px !important;
        --space-6: 24px !important;
        --space-8: 32px !important;
        --space-10: 40px !important;
        --space-12: 48px !important;

        --onyx-bg: #070709 !important;
        --onyx-surface: rgba(255, 255, 255, 0.035) !important;
        --onyx-surface-hover: rgba(255, 255, 255, 0.065) !important;
        --onyx-surface-active: rgba(255, 255, 255, 0.10) !important;
        --onyx-border: rgba(255, 255, 255, 0.08) !important;
        --onyx-border-hover: rgba(255, 255, 255, 0.18) !important;
        --onyx-border-focus: rgba(255, 255, 255, 0.35) !important;
        --onyx-text: #ffffff !important;
        --onyx-text-muted: #a1a1aa !important;
        --onyx-text-subtle: #71717a !important;
        --onyx-link-hover: #93c5fd !important;
        --onyx-link-visited: #c7d2fe !important;
        --onyx-ease: cubic-bezier(0.16, 1, 0.3, 1) !important;
        
        --theme-bg-color: #070709 !important;
        --theme-text-color: #ffffff !important;
        color-scheme: dark !important;
    }

    *, *::before, *::after {
        box-sizing: border-box !important;
    }

    /* Force Onyx Obsidian Dark Background on whole viewport for all engines */
    html, body, #app, .site-wrapper, .wrapper, .results-wrapper, main, .serp__body,
    #main, #cnt, #rcnt, #center_col, #rhs, .appbar, #hdtb, #top_nav, .minidiv, .sfbg, #searchform, .mw,
    #searchform > div, .srp, #botstuff, #rso {
        background-color: #070709 !important;
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", sans-serif !important;
        -webkit-font-smoothing: antialiased !important;
    }

    /* 1. Complete Scrubbing of DuckDuckGo Branding, Mascots, Ads, and Noise */
    .header__logo-wrap,
    .header__logo,
    .header__logo__img,
    #header-logo-wrapper,
    #header-logo,
    #logo,
    [data-testid="header-logo"],
    [data-testid="logo"],
    [data-testid="logo-link"],
    [data-testid="logo_link"],
    a[aria-label*="DuckDuckGo home" i],
    a[aria-label*="DuckDuckGo" i],
    a[data-testid="logo-link"],
    a[data-testid="header-logo"],
    a[href="/"],
    header a[href="/"],
    #header a[href="/"],
    .header a[href="/"],
    .header-wrap a[href="/"],
    .site-wrapper header a[href="/"],
    [class*="HeaderLogo"],
    [class*="header_logo"],
    [class*="header__logo"],
    svg[class*="logo" i],
    svg[class*="Logo" i],
    svg[class*="duck" i],
    svg:has(path[fill="#F05F2B"]),
    svg:has(path[fill="#DE5833"]),
    svg:has(ellipse[fill="#F05F2B"]),
    .header__logo img,
    .header-wrap img[src*="duck"],
    #header-logo-wrapper img,
    a[aria-label*="DuckDuckGo home"] img,
    a[data-testid="logo-link"] img,
    img[alt*="DuckDuckGo" i],
    img[src*="duckduckgo" i],
    img[src*="duck" i],
    a[href="/compare-privacy"],
    a[href*="compare-privacy"],
    a[href*="compare"],
    .header__tagline,
    .header__text,
    .header--aside,
    .header--aside__item,
    .header__button--menu,
    .js-side-menu-open,
    .feedback-btn,
    #footer-feedback-wrapper,
    .nav-menu--feedback,
    .react-feedback-prompt-mvc-wrapper,
    button[data-testid="feedback-button"],
    a[href*="assist=true"],
    li:has(> a[href*="assist=true"]),
    a[href*="ia=chat"]:not(.onyx-research-switch-btn),
    li:has(> a[href*="ia=chat"]),
    #react-duckbar li:has(button),
    [data-testid="duckbar"] li:has(button),
    #react-duckbar button,
    [data-testid="duckbar"] button,
    li:has(> button[aria-label*="Search Settings"]),
    button[aria-label*="Search Settings"],
    .badge--ad,
    [data-testid="ad"],
    [data-testid="ad-item"],
    .results--ads,
    .result--ad,
    .ads-wrapper,
    .onboarding-ed,
    .js-onboarding-wrapper,
    .ddg-extension-banner,
    .badge--privacy,
    .badge--protection,
    .modal--feedback,
    [class*="feedback"],
    [class*="Feedback"],
    .js-feedback-btn-wrap,
    [class*="TccjmKV6"],
    [class*="bYzmzE1m"],
    [class*="s_aX02AKO"],
    #react-duckbar a:not(.onyx-tab-active):not(.is-active)::after,
    [data-testid="duckbar"] a:not(.onyx-tab-active):not(.is-active)::after,
    [class*="feedback-btn"],
    [class*="feedback-modal"],
    .newsletter,
    [class*="newsletter"],
    [class*="promo"],
    /* Hide all globe icons from region filter & dropdowns */
    [data-testid="region-filter"] svg,
    .dropdown--region svg,
    button[aria-label*="Region" i] svg,
    button[aria-label*="region" i] svg,
    .footer,
    #footer,
    .footer__addons,
    .nav-menu,
    .nav-menu__item,
    .nav-menu--theme,
    .nav-menu--feedback,
    .serp__top-right,
    .serp__bottom-right,
    #spacing_hidden_wrapper,
    #spacing_hidden,
    #bottom_spacing2,
    #z,
    #z2,
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

    /* 1b. Absolute Full-Width Reset: Override invasive hardcoded DDG min-widths (980px, 1000px, 1072px) */
    html, html.is-not-mobile-device,
    body, body.is-not-mobile-device,
    .is-not-mobile-device,
    .site-wrapper,
    #web_content_wrapper,
    .content-wrap,
    #links_wrapper,
    #react-layout,
    [data-testid="mainline"],
    .results--main,
    #spacing_hidden_wrapper,
    #spacing_hidden,
    #bottom_spacing2,
    #z,
    #z2 {
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

    /* 1b. Anomaly / Bot Challenge Obsidian UI */
    .anomaly-modal,
    [class*="anomaly-modal"],
    .modal--popout.anomaly-modal__modal,
    #anomaly-detected {
        display: block !important;
        visibility: visible !important;
        opacity: 1 !important;
        pointer-events: auto !important;
        position: fixed !important;
        top: 50% !important;
        left: 50% !important;
        transform: translate(-50%, -50%) !important;
        background: #121216 !important;
        border: 1px solid rgba(255, 255, 255, 0.16) !important;
        border-radius: 16px !important;
        box-shadow: 0 24px 80px rgba(0, 0, 0, 0.9) !important;
        max-width: 520px !important;
        width: 90% !important;
        padding: 24px !important;
        box-sizing: border-box !important;
        z-index: 999999 !important;
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }

    .anomaly-modal *,
    [class*="anomaly-modal"] *,
    #anomaly-detected * {
        visibility: visible !important;
        opacity: 1 !important;
        box-sizing: border-box !important;
    }

    .anomaly-modal__title,
    [class*="anomaly-modal__title"] {
        color: #ffffff !important;
        font-size: 18px !important;
        font-weight: 600 !important;
        letter-spacing: -0.01em !important;
        margin-bottom: 8px !important;
        text-align: center !important;
        display: block !important;
    }

    .anomaly-modal__description,
    [class*="anomaly-modal__description"] {
        color: #a1a1aa !important;
        font-size: 13.5px !important;
        line-height: 1.5 !important;
        margin-bottom: 16px !important;
        text-align: center !important;
        display: block !important;
    }

    .anomaly-modal img,
    [class*="anomaly-modal"] img {
        display: block !important;
        visibility: visible !important;
        opacity: 1 !important;
        border-radius: 8px !important;
        border: 2px solid transparent !important;
        cursor: pointer !important;
        transition: all 0.15s ease !important;
    }
    .anomaly-modal img:hover,
    [class*="anomaly-modal"] img:hover {
        transform: scale(1.03) !important;
        border-color: #ffffff !important;
    }

    .anomaly-modal button,
    [class*="anomaly-modal"] button,
    [class*="anomaly-modal"] input[type="submit"] {
        display: inline-flex !important;
        visibility: visible !important;
        opacity: 1 !important;
        align-items: center !important;
        justify-content: center !important;
        background: #ffffff !important;
        color: #0a0a0e !important;
        border: none !important;
        border-radius: 8px !important;
        padding: 9px 22px !important;
        font-size: 13.5px !important;
        font-weight: 600 !important;
        cursor: pointer !important;
        margin: 14px auto 0 auto !important;
        box-shadow: 0 4px 14px rgba(0, 0, 0, 0.5) !important;
    }
    .anomaly-modal button:hover,
    [class*="anomaly-modal"] button:hover {
        background: #e4e4e7 !important;
    }

    .onyx-bot-bypass-bar {
        display: flex !important;
        align-items: center !important;
        justify-content: space-between !important;
        background: rgba(255, 255, 255, 0.06) !important;
        border: 1px solid rgba(255, 255, 255, 0.16) !important;
        border-radius: 10px !important;
        padding: 10px 14px !important;
        margin-bottom: 16px !important;
    }
    .onyx-bot-bypass-btn {
        background: #ffffff !important;
        color: #0a0a0e !important;
        font-size: 12px !important;
        font-weight: 600 !important;
        padding: 6px 14px !important;
        border-radius: 6px !important;
        text-decoration: none !important;
        border: none !important;
        cursor: pointer !important;
        display: inline-flex !important;
        align-items: center !important;
        gap: 6px !important;
    }

    /* 2. Top Header Bar & Search Pill: Clean, Left Blank Where Logo Was */
    .header-wrap, #header_wrapper {
        background: #070709 !important;
        border: none !important;
        box-shadow: none !important;
        padding: var(--space-4) var(--space-6) 0 var(--space-6) !important;
        margin: 0 !important;
        width: 100% !important;
        max-width: 100% !important;
        box-sizing: border-box !important;
        display: flex !important;
        flex-direction: column !important;
        align-items: center !important;
        position: relative !important;
    }

    #header, .header, .header.cw, .header-wrap > div, #header-non-nav {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 auto !important;
        box-sizing: border-box !important;
        max-width: 1100px !important;
        width: 100% !important;
        display: flex !important;
        flex-direction: column !important;
        align-items: flex-start !important;
    }

    /* Nuke all edge gradients, cutoff boxes, and mask pseudo-elements in header and filter bars */
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

    .header__search-wrap,
    .header__content,
    .header__search,
    #react-search-form,
    #search_form {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        border-radius: 0 !important;
        max-width: 680px !important;
        width: 100% !important;
        padding: 0 !important;
        margin: 0 !important;
        box-sizing: border-box !important;
    }

    #search_form > div,
    #search_form form,
    #search_form [class*="jnfopIud3XnBlXjNFBlD"],
    #search_form [class*="qbeSJGurtw4wF0FqAJqF"] {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        border-radius: 0 !important;
        padding: 0 !important;
        margin: 0 !important;
        width: 100% !important;
        max-width: 680px !important;
    }

    /* The ONE and ONLY Search Input Capsule */
    .onyx-search-pill,
    #search_form [class*="QsyijBlqupsaY11GFhnp"],
    #search_form [class*="T265XEcezvjUhK71U8pN"],
    .search--header,
    .search--adv,
    .search-wrap {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.10) !important;
        border-radius: 24px !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.35) !important;
        max-width: 680px !important;
        width: 100% !important;
        box-sizing: border-box !important;
        height: 44px !important;
        display: flex !important;
        align-items: center !important;
        padding: 0 var(--space-4) !important;
        transition: background 0.16s var(--onyx-ease), border-color 0.16s var(--onyx-ease), box-shadow 0.16s var(--onyx-ease) !important;
    }

    .onyx-search-pill:focus-within,
    #search_form [class*="QsyijBlqupsaY11GFhnp"]:focus-within,
    #search_form [class*="T265XEcezvjUhK71U8pN"]:focus-within,
    .search--header:focus-within,
    .search-wrap:focus-within {
        background: rgba(255, 255, 255, 0.07) !important;
        border-color: rgba(255, 255, 255, 0.32) !important;
        box-shadow: 0 0 0 3px rgba(255, 255, 255, 0.08), 0 4px 16px rgba(0, 0, 0, 0.45) !important;
    }

    .search__input, #search_form_input, input[type="text"][name="q"] {
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 15px !important;
        background: transparent !important;
        border: none !important;
        outline: none !important;
        box-shadow: none !important;
        width: 100% !important;
    }
    .search__button, #search_button, button[aria-label="Search"], button[type="submit"] {
        color: #a1a1aa !important;
        background: transparent !important;
        border: none !important;
        cursor: pointer !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        transition: color 0.15s ease !important;
    }
    .search__button:hover, #search_button:hover {
        color: #ffffff !important;
    }

    /* 3. Category Navigation Tabs ("All", "Images", "News", "Videos", "Maps") */
    #react-duckbar, [data-testid="duckbar"], .zcm {
        background: transparent !important;
        border: none !important;
        border-bottom: none !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: var(--space-3) auto 0 auto !important;
        width: 100% !important;
        max-width: 1100px !important;
        display: block !important;
        box-sizing: border-box !important;
        position: relative !important;
    }

    #react-duckbar > div:not(.onyx-duckbar-glider), #react-duckbar section, [data-testid="duckbar"] > div:not(.onyx-duckbar-glider) {
        margin: 0 !important;
        padding: 0 !important;
        width: 100% !important;
        overflow: visible !important;
        border: none !important;
        border-bottom: none !important;
    }

    #react-duckbar nav, [data-testid="duckbar"] nav, .zcm__items {
        display: flex !important;
        align-items: flex-end !important;
        position: relative !important;
        z-index: 2 !important;
        background: transparent !important;
        padding: 0 !important;
        margin: 0 !important;
        box-sizing: border-box !important;
        border: none !important;
        border-bottom: none !important;
        width: 100% !important;
        max-width: 680px !important;
        overflow: visible !important;
    }

    #react-duckbar ul:first-child, [data-testid="duckbar"] ul:first-child {
        display: flex !important;
        align-items: flex-end !important;
        gap: var(--space-2) !important;
        list-style: none !important;
        padding: 0 !important;
        margin: 0 !important;
        overflow: visible !important;
        width: auto !important;
        height: auto !important;
        border: none !important;
        border-bottom: none !important;
    }

    #react-duckbar ul:last-child,
    [data-testid="duckbar"] ul:last-child,
    #react-duckbar [class*="ofDl_"],
    .header--aside,
    .js-header-aside {
        display: none !important;
        visibility: hidden !important;
        pointer-events: none !important;
    }

    #react-duckbar ul:first-child li, [data-testid="duckbar"] ul:first-child li {
        display: inline-flex !important;
        align-items: flex-end !important;
        padding: 0 !important;
        margin: 0 !important;
        list-style: none !important;
        overflow: visible !important;
        border: none !important;
        border-bottom: none !important;
    }

    #react-duckbar ul:first-child a::before,
    #react-duckbar ul:first-child a::after,
    [data-testid="duckbar"] ul:first-child a::before,
    [data-testid="duckbar"] ul:first-child a::after,
    .onyx-duckbar-tab::before,
    .onyx-duckbar-tab::after {
        display: none !important;
        content: none !important;
        opacity: 0 !important;
        background: transparent !important;
    }

    #react-duckbar ul:first-child a,
    [data-testid="duckbar"] ul:first-child a,
    .onyx-duckbar-tab,
    #react-duckbar a.kFFXe30DOpq5j1hbWU1q,
    #react-duckbar .kFFXe30DOpq5j1hbWU1q.kFFXe30DOpq5j1hbWU1q.kFFXe30DOpq5j1hbWU1q,
    .zcm__item,
    .zcm__link {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        gap: var(--space-2) !important;
        position: relative !important;
        z-index: 2 !important;
        bottom: 0 !important;
        height: 38px !important;
        box-sizing: border-box !important;
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
        outline: none !important;
        padding: 0 var(--space-3) !important;
        margin: 0 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 13.5px !important;
        font-weight: 500 !important;
        text-decoration: none !important;
        color: rgba(255, 255, 255, 0.45) !important;
        opacity: 0.75 !important;
        cursor: pointer !important;
        transition: color 0.2s var(--onyx-ease), opacity 0.2s var(--onyx-ease) !important;
    }

    #react-duckbar ul:first-child a strong,
    [data-testid="duckbar"] ul:first-child a strong,
    .onyx-duckbar-tab strong,
    #react-duckbar ul:first-child a span,
    [data-testid="duckbar"] ul:first-child a span,
    .onyx-duckbar-tab span {
        font-weight: inherit !important;
        color: inherit !important;
        display: inline-flex !important;
        align-items: center !important;
        gap: var(--space-2) !important;
        position: relative !important;
        z-index: 2 !important;
        background: transparent !important;
    }

    #react-duckbar ul:first-child a svg,
    [data-testid="duckbar"] ul:first-child a svg,
    .onyx-duckbar-tab svg {
        color: inherit !important;
        fill: currentColor !important;
        opacity: 0.75 !important;
        position: relative !important;
        z-index: 2 !important;
        transition: all 0.25s ease !important;
    }

    #react-duckbar ul:first-child a:hover,
    [data-testid="duckbar"] ul:first-child a:hover,
    .onyx-duckbar-tab:hover {
        color: rgba(255, 255, 255, 0.90) !important;
        opacity: 1 !important;
        background: transparent !important;
        border: none !important;
    }

    #react-duckbar ul:first-child a:hover svg,
    [data-testid="duckbar"] ul:first-child a:hover svg,
    .onyx-duckbar-tab:hover svg {
        opacity: 1 !important;
        color: rgba(255, 255, 255, 0.90) !important;
    }

    #react-duckbar ul:first-child a.SnptgjT2zdOhGYfNng6g,
    #react-duckbar ul:first-child a[class*="SnptgjT"],
    #react-duckbar ul:first-child a.onyx-tab-active,
    #react-duckbar ul:first-child a.is-active,
    [data-testid="duckbar"] ul:first-child a.onyx-tab-active,
    [data-testid="duckbar"] ul:first-child a.is-active,
    .onyx-duckbar-tab.onyx-tab-active,
    .onyx-duckbar-tab.is-active {
        background: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        color: #ffffff !important;
        opacity: 1 !important;
        font-weight: 600 !important;
        text-shadow: 0 0 8px rgba(255, 255, 255, 0.25) !important;
    }

    #react-duckbar ul:first-child a.SnptgjT2zdOhGYfNng6g svg,
    #react-duckbar ul:first-child a[class*="SnptgjT"] svg,
    #react-duckbar ul:first-child a.onyx-tab-active svg,
    .onyx-duckbar-tab.onyx-tab-active svg {
        color: #ffffff !important;
        fill: #ffffff !important;
        opacity: 1 !important;
    }

    .onyx-duckbar-glider {
        position: absolute !important;
        bottom: 0 !important;
        left: 0 !important;
        height: 38px !important;
        max-width: 180px !important;
        pointer-events: none !important;
        z-index: 1 !important;
        transition: transform 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), width 0.32s cubic-bezier(0.2, 0.8, 0.2, 1), opacity 0.2s ease !important;
        will-change: transform, width !important;
        opacity: 0;
    }
    .onyx-duckbar-glider.is-ready {
        opacity: 1 !important;
    }
    .onyx-duckbar-glider::after {
        content: "" !important;
        display: block !important;
        position: absolute !important;
        bottom: 0 !important;
        left: 8px !important;
        right: 8px !important;
        height: 2.5px !important;
        background: #ffffff !important;
        border-radius: 2px !important;
        box-shadow: 0 0 8px rgba(255, 255, 255, 0.6) !important;
        pointer-events: none !important;
        z-index: 2 !important;
    }

    /* Filter dropdown containers: completely transparent, zero borders */
    .dropdown,
    .zcm__dropdown,
    .search-filters-wrap,
    .metabar__dropdowns-wrap,
    [class*="c1GwqC__eRoEs0cLTIfL"],
    [data-testid="privacy-reminder"],
    [data-testid="region-filter"],
    [data-testid="date-filter"] {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 !important;
    }

    /* Single, clean Apple Obsidian Pill Button */
    .dropdown > button,
    .dropdown__button,
    [data-testid="privacy-reminder"] button,
    [data-testid="date-filter-trigger"],
    [data-testid="region-filter-label"],
    nav[class*="ph1UFslrkUMqoYJEtp3t"] button,
    [class*="c1GwqC__eRoEs0cLTIfL"] button,
    .zcm__dropdown > button,
    .zcm__dropdown > a {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        gap: 6px !important;
        height: 28px !important;
        padding: 0 12px !important;
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 14px !important;
        color: #a1a1aa !important;
        font-size: 12px !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-weight: 500 !important;
        line-height: 1 !important;
        cursor: pointer !important;
        box-shadow: none !important;
        transition: all 160ms var(--onyx-ease) !important;
        white-space: nowrap !important;
    }

    .dropdown > button:hover,
    .dropdown__button:hover,
    [data-testid="privacy-reminder"] button:hover,
    [data-testid="date-filter-trigger"]:hover,
    [data-testid="region-filter-label"]:hover,
    nav[class*="ph1UFslrkUMqoYJEtp3t"] button:hover,
    [class*="c1GwqC__eRoEs0cLTIfL"] button:hover {
        background: rgba(255, 255, 255, 0.08) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        color: #ffffff !important;
        transform: translateY(-1px) !important;
    }

    .dropdown > button:active,
    .dropdown__button:active,
    [data-testid="privacy-reminder"] button:active,
    [data-testid="date-filter-trigger"] active {
        transform: scale(0.97) !important;
    }

    /* Total annihilation of nested button-in-button borders or backgrounds */
    .dropdown button *,
    .dropdown__button *,
    [data-testid="privacy-reminder"] button *,
    [data-testid="date-filter-trigger"] *,
    [data-testid="region-filter-label"] *,
    nav[class*="ph1UFslrkUMqoYJEtp3t"] button * {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
    }

    /* Dropdown popover menus */
    div[role="menu"],
    div[role="listbox"],
    .modal--dropdown,
    [class*="modal--dropdown"],
    [class*="KveNZ4T8UTSkbUIN7OIu"],
    [class*="BdZVYXbdg6Rx9Lrm5wzC"] {
        background: #121216 !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 12px !important;
        box-shadow: 0 12px 40px rgba(0, 0, 0, 0.75) !important;
        backdrop-filter: blur(20px) !important;
        -webkit-backdrop-filter: blur(20px) !important;
        padding: 6px !important;
        color: #ffffff !important;
    }

    div[role="menuitem"],
    div[role="menuitemradio"],
    div[role="option"],
    [class*="QuHfab2kCueVYIcnymfA"] {
        border-radius: 8px !important;
        padding: 8px 12px !important;
        color: #d4d4d8 !important;
        font-size: 13px !important;
        transition: all 0.12s ease !important;
    }

    div[role="menuitem"]:hover,
    div[role="menuitemradio"]:hover,
    div[role="option"]:hover,
    div[role="menuitem"][data-focused="true"],
    div[role="menuitemradio"][data-focused="true"],
    [class*="QuHfab2kCueVYIcnymfA"]:hover {
        background: rgba(255, 255, 255, 0.08) !important;
        color: #ffffff !important;
    }

    div[role="menuitemradio"][aria-checked="true"],
    div[role="option"][aria-selected="true"],
    [class*="DDNpARtK93vNnTDLVKBA"] {
        background: rgba(255, 255, 255, 0.12) !important;
        color: #ffffff !important;
        font-weight: 600 !important;
    }

    /* 4. Unified Search Results Container & Mainline Column */
    #web_content_wrapper, .content-wrap, #react-layout {
        width: 100% !important;
        max-width: 1100px !important;
        margin: 0 auto !important;
        padding: 0 var(--space-6) !important;
        box-sizing: border-box !important;
    }

    [class*="qrc3T8W2"], .qrc3T8W2PIYg9L63oA06 {
        width: 100% !important;
        max-width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
    }

    [class*="FMPme3X9"], .FMPme3X940xAt4SKPFuw {
        width: 100% !important;
        max-width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
        display: flex !important;
        flex-wrap: wrap !important;
        gap: var(--space-6) !important;
    }

    /* Main Results Section */
    section[class*="At_VJ9M"], .At_VJ9MlrHsSjbfCtz2_ {
        flex: 1 1 680px !important;
        max-width: 680px !important;
        min-width: 0 !important;
        width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
    }

    /* Knowledge Sidebar Section */
    [class*="FMPme3X9"] > aside,
    [class*="FMPme3X9"] > section:nth-child(2),
    .results--sidebar, .react-results--sidebar {
        flex: 0 1 340px !important;
        max-width: 380px !important;
        min-width: 0 !important;
        margin: 0 !important;
        box-sizing: border-box !important;
    }

    #links, #results, .results--main, .react-results--main {
        width: 100% !important;
        max-width: 100% !important;
        padding: var(--space-4) 0 var(--space-12) 0 !important;
        margin: 0 !important;
        box-sizing: border-box !important;
        list-style: none !important;
    }
    .results--main:empty {
        display: none !important;
    }

    .react-results--main > li, #links > div {
        width: 100% !important;
        max-width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
        list-style: none !important;
    }

    /* Individual Card: Apple Obsidian Aesthetic */
    .result, .nrn-react-div, article[data-testid="result"], .result--default, article {
        width: 100% !important;
        max-width: 100% !important;
        background: rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 12px !important;
        padding: 18px 22px !important;
        margin-bottom: var(--space-3) !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
        transition: transform 0.16s var(--onyx-ease), background 0.16s ease, border-color 0.16s ease, box-shadow 0.16s ease !important;
        position: relative !important;
        box-sizing: border-box !important;
    }
    .result:hover, .nrn-react-div:hover, article[data-testid="result"]:hover {
        background: rgba(255, 255, 255, 0.065) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        transform: translateY(-1.5px) !important;
        box-shadow: 0 6px 22px rgba(0, 0, 0, 0.5) !important;
    }

    /* Result Title */
    .result__title, [data-testid="result-title-a"], h2, h3, h3.LC20lb, .yuRUbf h3, a h3 {
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif !important;
        font-size: 17px !important;
        font-weight: 500 !important;
        letter-spacing: -0.015em !important;
        line-height: 1.35 !important;
        margin: 0 0 var(--space-1) 0 !important;
        transition: color 140ms ease !important;
    }
    .result__title a, [data-testid="result-title-a"], a:has(h3), .yuRUbf a {
        color: #ffffff !important;
        text-decoration: none !important;
    }
    .result__title a:hover, [data-testid="result-title-a"]:hover, a:has(h3):hover h3, .yuRUbf a:hover h3, h3:hover, a:hover h3 {
        color: #93c5fd !important;
        text-decoration: underline !important;
    }
    a:visited h3, .yuRUbf a:visited h3, .result__title a:visited {
        color: #c7d2fe !important;
    }

    /* Domain / URL Breadcrumb */
    .result__url, [data-testid="result-extras-url-link"], cite {
        color: #71717a !important;
        font-size: 12px !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        display: inline-flex !important;
        align-items: center !important;
        gap: var(--space-2) !important;
        text-decoration: none !important;
        margin-bottom: var(--space-1) !important;
    }
    .result__icon, [data-testid="result-favicon"] {
        border-radius: 4px !important;
    }

    /* Result Snippet */
    .result__snippet, [data-testid="result-snippet"] {
        color: #d4d4d8 !important;
        font-size: 14px !important;
        line-height: 1.6 !important;
        margin-top: var(--space-2) !important;
    }

    /* Keyword highlight pill */
    b, strong, .highlight {
        color: #ffffff !important;
        background: rgba(255, 255, 255, 0.12) !important;
        padding: 1px 4px !important;
        border-radius: 4px !important;
        font-weight: 600 !important;
    }

    /* Sublinks / Sitelinks inside cards */
    .result__sitelinks, .result__sublinks {
        margin-top: var(--space-3) !important;
        border-top: 1px solid rgba(255, 255, 255, 0.06) !important;
        padding-top: var(--space-2) !important;
    }
    .result__sitelinks a, .result__sublinks a {
        color: #e4e4e7 !important;
        font-size: 13px !important;
        text-decoration: none !important;
    }
    .result__sitelinks a:hover, .result__sublinks a:hover {
        text-decoration: underline !important;
    }

    /* 5. Knowledge Panel & Instant Modules (Stocks, Weather, Calculator, About, Wikipedia) */
    .results--sidebar, .module, [class*="ia-module"], .module--about, [data-testid="module--about"], .js-about-module {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 16px !important;
        padding: var(--space-6) !important;
        backdrop-filter: blur(20px) !important;
        -webkit-backdrop-filter: blur(20px) !important;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4) !important;
        color: #ffffff !important;
        margin-bottom: var(--space-4) !important;
    }
    .module *, [class*="ia-module"] * {
        color: #ffffff !important;
    }
    .module__title, .module__heading, .stocks-module__header .module__title {
        color: #ffffff !important;
        font-size: 22px !important;
        font-weight: 600 !important;
        letter-spacing: -0.02em !important;
        margin-bottom: var(--space-2) !important;
    }
    .stocks-module__latestUpdate, .stocks-module__exchange, .module__more-at {
        color: #71717a !important;
        font-size: 12px !important;
    }
    .stocks-module__currentPrice {
        color: #ffffff !important;
        font-size: 32px !important;
        font-weight: 700 !important;
        letter-spacing: -0.03em !important;
    }
    .stocks-module__currency {
        color: #a1a1aa !important;
        font-size: 14px !important;
        font-weight: 500 !important;
        margin-left: 6px !important;
    }
    .stocks-module__timePeriod {
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 6px !important;
        color: #a1a1aa !important;
        padding: 4px 10px !important;
        font-size: 12px !important;
        font-weight: 500 !important;
        margin-right: 4px !important;
    }
    .stocks-module__timePeriod.selected, .stocks-module__timePeriod:hover {
        background: rgba(255, 255, 255, 0.15) !important;
        color: #ffffff !important;
        border-color: rgba(255, 255, 255, 0.25) !important;
    }
    .module svg text, svg text {
        fill: #a1a1aa !important;
    }
    .module svg line, svg line, svg path[stroke*="#"] {
        stroke: rgba(255, 255, 255, 0.15) !important;
    }
    .module__text, .module__content {
        color: #d4d4d8 !important;
        font-size: 14px !important;
        line-height: 1.6 !important;
    }

    /* 6. Clean Deep Research Switch Button */
    .onyx-research-switch-btn {
        display: inline-flex !important;
        align-items: center !important;
        gap: 6px !important;
        background: rgba(255, 255, 255, 0.06) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 8px !important;
        color: #ffffff !important;
        font-size: 12px !important;
        font-weight: 500 !important;
        padding: 6px 14px !important;
        cursor: pointer !important;
        text-decoration: none !important;
        transition: all 0.15s ease !important;
    }
    .onyx-research-switch-btn:hover {
        background: rgba(255, 255, 255, 0.14) !important;
        border-color: rgba(255, 255, 255, 0.25) !important;
        color: #ffffff !important;
    }

    /* Onyx AI Overview Card */
    #onyx-ai-synthesis-card {
        display: block !important;
        width: 100% !important;
        box-sizing: border-box !important;
        background: linear-gradient(135deg, rgba(30, 41, 59, 0.35) 0%, rgba(15, 23, 42, 0.35) 100%), rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 12px !important;
        padding: 16px 20px !important;
        margin-bottom: var(--space-4) !important;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.35) !important;
        position: relative !important;
        list-style: none !important;
    }
    .onyx-ai-header {
        display: flex !important;
        align-items: center !important;
        justify-content: space-between !important;
        margin-bottom: 8px !important;
    }
    .onyx-ai-badge {
        display: inline-flex !important;
        align-items: center !important;
        gap: 6px !important;
        color: #ffffff !important;
        font-size: 12px !important;
        font-weight: 600 !important;
        letter-spacing: 0.03em !important;
    }
    .onyx-ai-content {
        color: #e2e8f0 !important;
        font-size: 14px !important;
        line-height: 1.6 !important;
    }

    /* Pagination / Next Page Button */
    .result--more, .btn--more, [data-testid="more-results"] {
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid rgba(255, 255, 255, 0.10) !important;
        border-radius: 10px !important;
        color: #ffffff !important;
        font-size: 13.5px !important;
        font-weight: 500 !important;
        padding: 12px 28px !important;
        margin: var(--space-6) auto !important;
        max-width: 240px !important;
        cursor: pointer !important;
        transition: all 0.16s var(--onyx-ease) !important;
    }
    .result--more:hover, .btn--more:hover, [data-testid="more-results"]:hover {
        background: rgba(255, 255, 255, 0.10) !important;
        border-color: rgba(255, 255, 255, 0.22) !important;
    }

    /* =========================================================
       7. GOOGLE SEARCH OBSIDIAN GLASS THEME
       ========================================================= */

    /* Google Header & Search Capsule - ONLY the outer capsule gets the border */
    .RNNXgb, form[role="search"] .RNNXgb, .minidiv .RNNXgb {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.10) !important;
        border-radius: 24px !important;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.45), inset 0 1px 0 rgba(255, 255, 255, 0.06) !important;
        height: 48px !important;
        box-sizing: border-box !important;
        color: #ffffff !important;
        max-width: 680px !important;
        width: 100% !important;
        margin: 0 !important;
        transition: background 160ms var(--onyx-ease), border-color 160ms var(--onyx-ease), box-shadow 160ms var(--onyx-ease) !important;
    }

    .RNNXgb:focus-within, form[role="search"] .RNNXgb:focus-within {
        background: rgba(255, 255, 255, 0.07) !important;
        border-color: rgba(255, 255, 255, 0.35) !important;
        box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.35), 0 8px 32px rgba(0, 0, 0, 0.6) !important;
    }

    /* Neutralize all inner containers to avoid double border / crescent artifact */
    .iblpc, .SDkEP, .A8SBwf, form[role="search"] .A8SBwf, .oxmBfd, .emcav, .emcav .emc, .RNNXgb > div {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
    }

    /* Eliminate Google 136px logo offset so input aligns with tabs */
    .A8SBwf, .aypyie, form[role="search"] .A8SBwf, #tsf .A8SBwf, .RNNXgb, #tsf .RNNXgb, .NDnoQ, .NDnoQ .RNNXgb {
        margin-left: 0 !important;
    }

    .RNNXgb textarea, .RNNXgb input, textarea.gLFyf, input.gLFyf, #APjFqb {
        color: #ffffff !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 15px !important;
        background: transparent !important;
        border: none !important;
        outline: none !important;
        box-shadow: none !important;
        -webkit-text-fill-color: #ffffff !important;
    }

    .RNNXgb svg, .iblpc svg, .ExCKkf svg, .XDyW0e svg, .nDcEnd svg, .G43f7e svg, .dRYYxd svg,
    button[aria-label*="Search" i] svg, button[aria-label*="Clear" i] svg {
        fill: rgba(255, 255, 255, 0.65) !important;
        stroke: rgba(255, 255, 255, 0.65) !important;
        color: rgba(255, 255, 255, 0.65) !important;
    }

    /* Complete scrub of Google App Launcher (9-dot grid), Google Account, Share, and Header Clutter */
    #logo, .logo img, header svg.logo, [aria-label*="Google" i] img, a#logo, .logocont, #logocont,
    #gb, .gb_d, .gb_e, .gb_f, .gb_g, .gb_h, .gb_i, .gb_v, .gb_w, .gb_x, .gb_y, .gb_z,
    .gb_A, .gb_B, .gb_C, .gb_Ja, .gb_1, .gb_X, [aria-label*="Google apps" i],
    [aria-label*="Google app" i], [aria-label*="Google Account" i],
    a[href*="accounts.google.com"], a[href*="/preferences"], a[href*="google.com/save"], a[href*="/saves"],
    .G57R0c, .LH92ce, .TQc1id, .SJ1Kg, div[data-async-context*="share"], div[jscontroller*="share"],
    .Q3DXx, .Efnghe, .apFnFf, [aria-label*="Share" i], [aria-label*="share" i], [aria-label*="Compartir" i],
    [title*="Share" i], [title*="share" i], [data-share-url],
    svg:has(path[d*="M16 5l-1.42"]), svg:has(path[d*="M18 16.08c"]),
    #searchform button:not(#tsf button), header button:not(#tsf button), .sfbg button:not(#tsf button),
    #searchform > div:not(:has(#tsf)):not(#tsf) {
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

    /* Google Category Navigation Bar ("All", "Images", "Videos", "Short videos", "Forums", "News", "More", "Tools") */
    #top_nav, .crJ18e, .hdtb-mfa, .hdtb, #hdtb, .z80RDc, .O8QBhe, [role="navigation"],
    .EDblX, .h5JSWd, .rQTE8b, .beZ0tf, .O1uzAe {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        max-width: 100% !important;
        width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        box-sizing: border-box !important;
    }

    .rQTE8b {
        display: flex !important;
        align-items: center !important;
        justify-content: flex-start !important;
        gap: 8px !important;
        max-width: 100% !important;
        width: 100% !important;
        margin: 10px 0 16px 0 !important;
        padding: 0 !important;
    }

    .beZ0tf {
        display: flex !important;
        align-items: center !important;
        flex-wrap: nowrap !important;
        gap: 6px !important;
        padding: 0 !important;
        margin: 0 !important;
        overflow-x: auto !important;
        scrollbar-width: none !important;
    }
    .beZ0tf::-webkit-scrollbar, .rQTE8b::-webkit-scrollbar {
        display: none !important;
    }

    .yeKjxb {
        display: inline-flex !important;
        align-items: center !important;
        margin-left: auto !important;
        padding: 0 !important;
        flex-shrink: 0 !important;
    }

    /* Total annihilation of Google's horizontal hairline divider, scroll circles, and tab ghost artifacts */
    .zLSRge, .w2jn8d, .PwiNU, .m29tEd, .hdtb-ms, #hdtb-ms, .E4ffZe,
    .e9EfHf::before, .e9EfHf::after, #cnt::before, #cnt::after, #sfcnt::after, hr {
        display: none !important;
        height: 0 !important;
        border: none !important;
        border-bottom: none !important;
        visibility: hidden !important;
        opacity: 0 !important;
    }

    /* Eradicate dark circular carousel scroll buttons and edge fade masks */
    .u96bed, .GTERze, .zwVERd, .yFyxRc, .l7Wnjd, .tGYVp,
    .Iy1nvd, .vezEod, .SvoXfb, .F9Idpe,
    button.Iy1nvd, button.vezEod,
    .A66hff button, .zp6Lyf button,
    button[jsname="ggE0ke"], [class*="Iy1nvd"], [class*="vezEod"], [class*="SvoXfb"], [class*="F9Idpe"],
    .mXZJrb button, .p7eiqf, .oIdq8b, .sz3HNe, .b3puKe, .GHMsie, .TQc1id,
    .HPvrce, [class*="HPvrce"], .mTpL7c.HPvrce, .mTpL7c:empty {
        display: none !important;
        width: 0 !important;
        height: 0 !important;
        opacity: 0 !important;
        pointer-events: none !important;
        visibility: hidden !important;
    }

    .mXwfNd::before, .mXwfNd::after,
    .C6AK7c::before, .C6AK7c::after,
    .XVMlrc::before, .XVMlrc::after,
    .beZ0tf::before, .beZ0tf::after,
    .rQTE8b::before, .rQTE8b::after,
    .EDblX::before, .EDblX::after,
    .h5JSWd::before, .h5JSWd::after,
    .olrp5b::before, .olrp5b::after,
    .mVH5Fc::before, .mVH5Fc::after,
    .crJ18e::before, .crJ18e::after,
    .hdtb-mfa::before, .hdtb-mfa::after {
        display: none !important;
        content: none !important;
        background: transparent !important;
        background-image: none !important;
        border: none !important;
        box-shadow: none !important;
        width: 0 !important;
        height: 0 !important;
        opacity: 0 !important;
    }

    /* Sub-filter suggestion strip container in Google Images & Videos */
    .rfiSsc, .YNk70c, .sBbkle, .xhjkHe, .TrmO7, .ZeeOc, .bqHHPb, .fMHynf, .PHj8of, .Xx7Mif, .zp6Lyf, .A66hff {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
    }

    .IUOThf {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
        display: flex !important;
        align-items: center !important;
        gap: 8px !important;
        padding: 4px 0 14px 0 !important;
        overflow-x: auto !important;
        scrollbar-width: none !important;
    }
    .IUOThf::-webkit-scrollbar {
        display: none !important;
    }

    .A66hff a.nPDzT,
    .IUOThf a.nPDzT,
    a.nPDzT {
        text-decoration: none !important;
        display: inline-flex !important;
        align-items: center !important;
        border: none !important;
        background: transparent !important;
    }

    /* Sub-filter chips: Apple Obsidian frosted pills */
    .GKS7s {
        display: inline-flex !important;
        align-items: center !important;
        height: 34px !important;
        padding: 0 14px 0 5px !important;
        gap: 8px !important;
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 17px !important;
        box-shadow: none !important;
        transition: all 160ms var(--onyx-ease) !important;
        cursor: pointer !important;
        box-sizing: border-box !important;
    }

    .GKS7s:hover,
    a.nPDzT:hover .GKS7s {
        background: rgba(255, 255, 255, 0.08) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        transform: translateY(-1px) !important;
    }

    .EENbod, .iAatCe, .q1MG4e {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
    }

    .iAatCe {
        width: 24px !important;
        height: 24px !important;
        border-radius: 12px !important;
        overflow: hidden !important;
        background: rgba(255, 255, 255, 0.08) !important;
    }

    .iAatCe img, .q1MG4e img {
        width: 24px !important;
        height: 24px !important;
        object-fit: cover !important;
        border-radius: 12px !important;
    }

    .FMKtTb, .FMKtTb * {
        color: #e2e8f0 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 13px !important;
        font-weight: 500 !important;
        line-height: 1 !important;
        white-space: nowrap !important;
    }

    .GKS7s:hover .FMKtTb {
        color: #ffffff !important;
    }

    .GKS7s::before, .GKS7s::after,
    .EENbod::before, .EENbod::after,
    .nPDzT::before, .nPDzT::after,
    .iAatCe::before, .iAatCe::after {
        display: none !important;
        content: none !important;
    }

    /* Neutralize all ghost background rectangles from tab wrappers except actual pill controls */
    .beZ0tf div:not(.mTpL7c):not(.mOKdDc):not(#hdtb-tls),
    .rQTE8b div:not(.mTpL7c):not(.mOKdDc):not(#hdtb-tls),
    .olrp5b,
    .crJ18e div, .hdtb-mfa div, .O8QBhe div, .z80RDc div,
    .crJ18e [role="listitem"], .hdtb-mfa [role="listitem"],
    .beZ0tf [role="listitem"], .rQTE8b [role="listitem"],
    .crJ18e [role="list"], .hdtb-mfa [role="list"] {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        box-shadow: none !important;
    }

    /* Google Search Category Pills: Unified Apple Obsidian Capsules */
    .beZ0tf a.C6AK7c,
    .beZ0tf a.XVMlrc,
    a.C6AK7c,
    a.XVMlrc,
    .crJ18e a,
    .hdtb-mfa a,
    .IUOThf a,
    .hdtb-imb a,
    .hdtb-mfa div[role="tab"],
    .z80RDc a,
    .O8QBhe a,
    .beZ0tf .mTpL7c,
    .rQTE8b .mTpL7c,
    .yeKjxb .mTpL7c,
    .mOKdDc,
    #hdtb-tls {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        height: 32px !important;
        padding: 0 14px !important;
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 16px !important;
        color: #a1a1aa !important;
        font-size: 13px !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-weight: 500 !important;
        line-height: 1 !important;
        text-decoration: none !important;
        cursor: pointer !important;
        box-shadow: none !important;
        transition: all 160ms var(--onyx-ease) !important;
        white-space: nowrap !important;
        box-sizing: border-box !important;
    }

    .beZ0tf a.C6AK7c:hover,
    .beZ0tf a.XVMlrc:hover,
    a.C6AK7c:hover,
    a.XVMlrc:hover,
    .crJ18e a:hover,
    .hdtb-mfa a:hover,
    .IUOThf a:hover,
    .z80RDc a:hover,
    .beZ0tf .mTpL7c:hover,
    .rQTE8b .mTpL7c:hover,
    .yeKjxb .mTpL7c:hover,
    .mOKdDc:hover,
    #hdtb-tls:hover {
        background: rgba(255, 255, 255, 0.08) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        color: #ffffff !important;
        transform: translateY(-1px) !important;
    }

    /* Active Tab */
    .beZ0tf a.C6AK7c:has([aria-current="page"]),
    .beZ0tf a.C6AK7c:has([selected]),
    a.C6AK7c:has([aria-current="page"]),
    a.C6AK7c:has([selected]),
    .beZ0tf a.C6AK7c[aria-disabled="true"],
    a.C6AK7c[aria-disabled="true"],
    .beZ0tf a.C6AK7c.onyx-tab-active,
    a.C6AK7c.onyx-tab-active,
    .crJ18e a.YmvwI,
    .hdtb-mfa a.YmvwI,
    .hdtb-mfa .selected,
    .crJ18e [aria-selected="true"],
    .IUOThf [aria-selected="true"],
    .z80RDc .selected,
    [role="tab"][aria-selected="true"] {
        background: rgba(255, 255, 255, 0.14) !important;
        border: 1px solid rgba(255, 255, 255, 0.28) !important;
        color: #ffffff !important;
        font-weight: 600 !important;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35) !important;
    }

    /* AI Mode Tab: Frosted Obsidian with Violet Glow Accent */
    a.XVMlrc, .olrp5b a {
        background: linear-gradient(135deg, rgba(99, 102, 241, 0.12) 0%, rgba(168, 85, 247, 0.12) 100%), rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(168, 85, 247, 0.25) !important;
        color: #e0e7ff !important;
    }
    a.XVMlrc:hover, .olrp5b a:hover {
        background: linear-gradient(135deg, rgba(99, 102, 241, 0.22) 0%, rgba(168, 85, 247, 0.22) 100%), rgba(255, 255, 255, 0.08) !important;
        border-color: rgba(168, 85, 247, 0.45) !important;
        color: #ffffff !important;
    }

    /* Tab internal layout & vertical centering */
    .mXwfNd, .mVH5Fc {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        height: 100% !important;
        padding: 0 !important;
        margin: 0 !important;
        border: none !important;
        border-bottom: none !important;
        background: transparent !important;
        box-shadow: none !important;
    }
    .R1QWuf {
        display: inline-flex !important;
        align-items: center !important;
        line-height: 1 !important;
        margin: 0 !important;
        padding: 0 !important;
        border-bottom: none !important;
        color: inherit !important;
        font-size: 13px !important;
        font-weight: inherit !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }
    .C6AK7c, .C6AK7c *, .XVMlrc, .XVMlrc * {
        border-bottom: none !important;
        text-decoration: none !important;
    }
    .mTpL7c svg, .mOKdDc svg, .beZ0tf svg, .yeKjxb svg, #hdtb-tls svg {
        fill: currentColor !important;
        width: 14px !important;
        height: 14px !important;
        margin-left: 4px !important;
    }

    /* More dropdown menu popover */
    .vH6rvf, .FJCJfd, .R0DW9c, .bsmXxe {
        background: #121216 !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 12px !important;
        box-shadow: 0 12px 40px rgba(0, 0, 0, 0.75) !important;
        backdrop-filter: blur(20px) !important;
        padding: 6px !important;
    }
    .vH6rvf a, .FJCJfd a, .bsmXxe a {
        border-radius: 8px !important;
        padding: 8px 12px !important;
        color: #d4d4d8 !important;
        font-size: 13px !important;
        transition: all 0.12s ease !important;
    }
    .vH6rvf a:hover, .FJCJfd a:hover, .bsmXxe a:hover {
        background: rgba(255, 255, 255, 0.08) !important;
        color: #ffffff !important;
    }

    /* Google AI Overview & Total Nuke of the Blinding White Gradient Block */
    .ULSxyf, .cUnQKe, .Ww4FFb, .yG4QQe, .L3eUgb, .w8qArf, .b3id4d, .ob912b, .exp-c, .xpdopen,
    [jsname="j1fyvd"], div[data-attrid="wa:/description"], div[data-asoch-targets],
    .hlcw0c, .xpd, .UD9u0, .gJ5Zne {
        background: transparent !important;
        background-color: transparent !important;
        background-image: none !important;
        box-shadow: none !important;
    }

    .ULSxyf::before, .ULSxyf::after,
    .cUnQKe::before, .cUnQKe::after,
    .Ww4FFb::before, .Ww4FFb::after,
    .yG4QQe::before, .yG4QQe::after,
    .L3eUgb::before, .L3eUgb::after,
    .w8qArf::before, .w8qArf::after,
    .b3id4d::before, .b3id4d::after,
    .ob912b::before, .ob912b::after,
    .exp-c::before, .exp-c::after,
    .xpdopen::before, .xpdopen::after,
    [jsname="j1fyvd"]::before, [jsname="j1fyvd"]::after,
    div[data-attrid="wa:/description"]::before, div[data-attrid="wa:/description"]::after,
    .UD9u0::before, .UD9u0::after {
        display: none !important;
        content: none !important;
        background: transparent !important;
        background-image: none !important;
        opacity: 0 !important;
        visibility: hidden !important;
        width: 0 !important;
        height: 0 !important;
    }

    /* AI Overview Card Container */
    .Ww4FFb, div[data-attrid="wa:/description"] {
        background: linear-gradient(135deg, rgba(30, 41, 59, 0.35) 0%, rgba(15, 23, 42, 0.35) 100%), rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 16px !important;
        padding: 20px !important;
        margin-bottom: 24px !important;
        box-shadow: 0 4px 24px rgba(0, 0, 0, 0.45) !important;
        box-sizing: border-box !important;
    }

    .Ww4FFb, .Ww4FFb *,
    div[data-attrid="wa:/description"], div[data-attrid="wa:/description"] *,
    .w8qArf, .w8qArf *,
    .b3id4d, .b3id4d *,
    .fP1Qef, .fP1Qef * {
        color: #e2e8f0 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }

    /* AI Overview Topic / Suggestion Pills - strictly scoped inside AI Overview */
    .Ww4FFb [role="listitem"] button,
    .Ww4FFb [role="listitem"] a,
    div[data-attrid="wa:/description"] [role="listitem"] button,
    div[data-attrid="wa:/description"] [role="listitem"] a,
    .dg0Ffc, .gL95fc, .Z1Vzce, .K20v3e, .v5yQqb, .Z1Vzce button {
        background: rgba(255, 255, 255, 0.06) !important;
        border: 1px solid rgba(255, 255, 255, 0.12) !important;
        border-radius: 16px !important;
        color: #ffffff !important;
        font-size: 12.5px !important;
        font-weight: 500 !important;
        padding: 6px 14px !important;
        cursor: pointer !important;
        transition: all 160ms var(--onyx-ease) !important;
    }
    .Ww4FFb [role="listitem"] button:hover,
    .dg0Ffc:hover, .gL95fc:hover, .Z1Vzce:hover {
        background: rgba(255, 255, 255, 0.12) !important;
        border-color: rgba(255, 255, 255, 0.25) !important;
        color: #ffffff !important;
        transform: translateY(-1px) !important;
    }

    /* AI Overview Preview References (Side cards) */
    .I6TXqe, .dnXCYb, .xYnFwe, .k6P01c, .uVAGfe {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 12px !important;
        color: #ffffff !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
    }
    .I6TXqe *, .dnXCYb *, .xYnFwe * {
        color: #d4d4d8 !important;
    }

    /* Google "Show more ∨" / "Show less ∧" Expander Button */
    [role="button"][jsname="j1fyvd"],
    button[jsname="j1fyvd"],
    .w8qArf [role="button"][jsname="j1fyvd"],
    .cUnQKe [role="button"][jsname="j1fyvd"],
    .exp-c [role="button"],
    .exp-c button {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        gap: 8px !important;
        height: 38px !important;
        padding: 0 24px !important;
        background: rgba(255, 255, 255, 0.06) !important;
        border: 1px solid rgba(255, 255, 255, 0.16) !important;
        border-radius: 19px !important;
        color: #ffffff !important;
        font-size: 13px !important;
        font-weight: 500 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        cursor: pointer !important;
        box-shadow: 0 4px 16px rgba(0, 0, 0, 0.45) !important;
        margin: 16px auto !important;
        transition: all 160ms var(--onyx-ease) !important;
    }

    [role="button"][jsname="j1fyvd"]:hover,
    button[jsname="j1fyvd"]:hover,
    .exp-c [role="button"]:hover,
    .exp-c button:hover {
        background: rgba(255, 255, 255, 0.12) !important;
        border-color: rgba(255, 255, 255, 0.30) !important;
        color: #ffffff !important;
        transform: translateY(-1px) !important;
        box-shadow: 0 6px 20px rgba(0, 0, 0, 0.6) !important;
    }

    [role="button"][jsname="j1fyvd"]:active,
    button[jsname="j1fyvd"]:active {
        transform: scale(0.97) !important;
    }

    [role="button"][jsname="j1fyvd"] *,
    button[jsname="j1fyvd"] *,
    .w8qArf [role="button"][jsname="j1fyvd"] *,
    .cUnQKe [role="button"][jsname="j1fyvd"] *,
    .exp-c [role="button"] *,
    .exp-c button * {
        color: #ffffff !important;
        fill: #ffffff !important;
        stroke: #ffffff !important;
        background: transparent !important;
        border: none !important;
    }

    /* Google Organic Search Results: Single clean Apple Obsidian Card per result */
    .MjjYud, .g:not(.MjjYud .g) {
        background: rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 14px !important;
        padding: 18px 22px !important;
        margin-bottom: 12px !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
        transition: transform 160ms var(--onyx-ease),
                    background 160ms ease,
                    border-color 160ms ease,
                    box-shadow 160ms ease !important;
        box-sizing: border-box !important;
        position: relative !important;
        max-width: 680px !important;
        width: 100% !important;
    }

    .MjjYud:hover, .g:not(.MjjYud .g):hover {
        background: rgba(255, 255, 255, 0.065) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        transform: translateY(-1.5px) !important;
        box-shadow: 0 6px 24px rgba(0, 0, 0, 0.5) !important;
    }

    /* Sitelinks cluster within organic result card */
    .hlcw0c {
        display: flex !important;
        flex-direction: column !important;
        gap: 8px !important;
    }
    .hlcw0c .g {
        background: transparent !important;
        border: none !important;
        border-top: 1px solid rgba(255, 255, 255, 0.06) !important;
        border-radius: 0 !important;
        padding: 10px 0 0 0 !important;
        margin: 6px 0 0 0 !important;
        box-shadow: none !important;
    }
    .hlcw0c .g:first-child {
        border-top: none !important;
        padding-top: 0 !important;
        margin-top: 0 !important;
    }

    /* Video search results & thumbnails */
    .d3F79b, [data-video-id], .MjjYud:has(video) {
        border-radius: 12px !important;
    }
    .d3F79b img, [data-video-id] img, .ct3b9e img {
        border-radius: 8px !important;
    }

    /* When .MjjYud is a group container holding multiple results, unbox it and style children individually */
    .MjjYud:has(.g ~ .g),
    .MjjYud:has(.Ww4FFb ~ .Ww4FFb),
    .MjjYud:has(.d3F79b ~ .d3F79b),
    .MjjYud:has([data-video-id] ~ [data-video-id]) {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 !important;
        transform: none !important;
    }
    .MjjYud:has(.g ~ .g):hover,
    .MjjYud:has(.Ww4FFb ~ .Ww4FFb):hover,
    .MjjYud:has(.d3F79b ~ .d3F79b):hover,
    .MjjYud:has([data-video-id] ~ [data-video-id]):hover {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        transform: none !important;
    }

    .MjjYud:has(.g ~ .g) .g,
    .MjjYud:has(.Ww4FFb ~ .Ww4FFb) .Ww4FFb,
    .MjjYud:has(.d3F79b ~ .d3F79b) .d3F79b,
    .MjjYud:has([data-video-id] ~ [data-video-id]) [data-video-id] {
        background: rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 14px !important;
        padding: 16px 20px !important;
        margin-bottom: 12px !important;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.3) !important;
        transition: transform 160ms var(--onyx-ease),
                    background 160ms ease,
                    border-color 160ms ease,
                    box-shadow 160ms ease !important;
        box-sizing: border-box !important;
    }

    .MjjYud:has(.g ~ .g) .g:hover,
    .MjjYud:has(.Ww4FFb ~ .Ww4FFb) .Ww4FFb:hover,
    .MjjYud:has(.d3F79b ~ .d3F79b) .d3F79b:hover,
    .MjjYud:has([data-video-id] ~ [data-video-id]) [data-video-id]:hover {
        background: rgba(255, 255, 255, 0.065) !important;
        border-color: rgba(255, 255, 255, 0.18) !important;
        transform: translateY(-1.5px) !important;
        box-shadow: 0 6px 24px rgba(0, 0, 0, 0.5) !important;
    }

    /* Google Images Grid Container: Never box the entire image results grid into a card */
    .MjjYud:has(.VKHL9c),
    .MjjYud:has(.DeNS1c),
    .MjjYud:has([data-ri]),
    .MjjYud:has(#islrg),
    .MjjYud:has(.islrc),
    .MjjYud:has(.srKDX),
    .VKHL9c,
    .srKDX,
    #rso:has(.VKHL9c),
    #rso:has(.DeNS1c),
    #center_col:has(.VKHL9c),
    #center_col:has(.DeNS1c),
    #rcnt:has(.VKHL9c),
    #rcnt:has(.DeNS1c) {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 !important;
        max-width: 100% !important;
        width: 100% !important;
        transform: none !important;
    }
    .MjjYud:has(.VKHL9c):hover,
    .MjjYud:has(.DeNS1c):hover,
    .MjjYud:has([data-ri]):hover,
    .MjjYud:has(#islrg):hover,
    .MjjYud:has(.islrc):hover,
    .MjjYud:has(.srKDX):hover {
        background: transparent !important;
        border: none !important;
        transform: none !important;
        box-shadow: none !important;
    }

    /* Google Image Result Items: Individual Apple Obsidian Cards */
    .kb0PBd.cvP2Ce,
    div[data-ri],
    .isv-r,
    .isv-r .isv-r,
    .islrc > div {
        background: rgba(255, 255, 255, 0.035) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 14px !important;
        padding: 8px !important;
        box-sizing: border-box !important;
        transition: transform 160ms var(--onyx-ease),
                    border-color 160ms ease,
                    background 160ms ease,
                    box-shadow 160ms ease !important;
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35) !important;
    }

    .kb0PBd.cvP2Ce:hover,
    div[data-ri]:hover,
    .isv-r:hover,
    .islrc > div:hover {
        transform: translateY(-2px) !important;
        background: rgba(255, 255, 255, 0.07) !important;
        border-color: rgba(255, 255, 255, 0.22) !important;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6) !important;
    }

    .kb0PBd.cvP2Ce img,
    .DeNS1c img,
    .bFtXbb img,
    .uhHOwf img,
    .isv-r img {
        border-radius: 10px !important;
        object-fit: cover !important;
    }

    .VifEQd, .VifEQd * {
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
    }
    .VifEQd a, .VifEQd h3 {
        color: #e2e8f0 !important;
        font-size: 12.5px !important;
        line-height: 1.4 !important;
    }
    .VifEQd a:hover {
        color: #ffffff !important;
    }

    /* Eliminate double-nesting: all descendants inside .MjjYud must be borderless and transparent */
    .MjjYud .g,
    .MjjYud .tF2Cxc,
    .MjjYud .kvH3mc,
    .MjjYud .jGGUs,
    .MjjYud .Z26q7c,
    .MjjYud .Ww4FFb,
    .MjjYud .hlcw0c,
    .MjjYud .MjjYud {
        background: transparent !important;
        background-color: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
        padding: 0 !important;
        margin: 0 !important;
        transform: none !important;
    }

    /* Google Snippets & Highlights */
    .VwiC3b, .yXK7lf, .MUxGbd, .lEBKkf, div[data-sncf], .VwiC3b * {
        color: #d4d4d8 !important;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
        font-size: 14px !important;
        line-height: 1.6 !important;
    }

    .VwiC3b em, .VwiC3b b, em, b, strong {
        color: #ffffff !important;
        font-weight: 600 !important;
        background: rgba(255, 255, 255, 0.10) !important;
        padding: 1px 4px !important;
        border-radius: 4px !important;
    }

    .usJj9c, .MSLpAb, .StTgjd {
        border-top: 1px solid rgba(255, 255, 255, 0.06) !important;
        padding-top: 8px !important;
        margin-top: 12px !important;
    }
    .usJj9c a, .MSLpAb a {
        color: #93c5fd !important;
        text-decoration: none !important;
        font-size: 13px !important;
    }
    .usJj9c a:hover, .MSLpAb a:hover {
        text-decoration: underline !important;
    }

    hr, .Ww4FFb hr, .g hr, .hlcw0c {
        display: none !important;
        border: none !important;
    }

    /* Google Accordions ("People Also Ask") */
    .related-question-pair, .cbphWd, .g.kno-result, .csDO3b, [jsname="yEVEwb"] {
        background: rgba(255, 255, 255, 0.03) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 10px !important;
        padding: 12px 16px !important;
        margin-bottom: 8px !important;
        color: #ffffff !important;
    }
    .related-question-pair [role="button"], .cbphWd [role="button"] {
        background: transparent !important;
        border: none !important;
        color: #ffffff !important;
        font-weight: 500 !important;
        font-size: 14px !important;
        padding: 0 !important;
    }
    .related-question-pair svg, .cbphWd svg {
        fill: #a1a1aa !important;
    }

    /* Google Knowledge Panel (Sidebar #rhs) */
    #rhs, .kp-blk, .I6TXqe, .wp-ms, .osrp-blk {
        background: rgba(255, 255, 255, 0.04) !important;
        border: 1px solid rgba(255, 255, 255, 0.08) !important;
        border-radius: 16px !important;
        padding: 20px !important;
        backdrop-filter: blur(20px) !important;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.45) !important;
        color: #ffffff !important;
    }
    .kp-blk *, .I6TXqe *, .wp-ms * {
        color: #ffffff !important;
    }
    .kno-ecr-pt {
        font-size: 22px !important;
        font-weight: 600 !important;
        letter-spacing: -0.02em !important;
        color: #ffffff !important;
    }

    /* Google Footer, Ads, and Noise Removal */
    #fbar, #footcnt, #foot,
    .uEierd, #tads, #tadsb, [data-text-ad],
    .appbar, .cv2Vmc, .LH92ce, .TQc1id,
    .SJ1Kg, .G57R0c, #taw {
        display: none !important;
        visibility: hidden !important;
        opacity: 0 !important;
        pointer-events: none !important;
        height: 0 !important;
    }

    /* Google Pagination */
    #botstuff, #navcnt, table.AaVjTc {
        background: transparent !important;
        border: none !important;
    }
    table.AaVjTc td a {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        min-width: 36px !important;
        height: 36px !important;
        padding: 0 12px !important;
        background: rgba(255, 255, 255, 0.05) !important;
        border: 1px solid rgba(255, 255, 255, 0.10) !important;
        border-radius: 10px !important;
        color: #ffffff !important;
        font-size: 13px !important;
        font-weight: 500 !important;
        text-decoration: none !important;
        transition: all 160ms ease !important;
    }
    table.AaVjTc td a:hover {
        background: rgba(255, 255, 255, 0.12) !important;
        border-color: rgba(255, 255, 255, 0.24) !important;
    }
    table.AaVjTc td.cur {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        min-width: 36px !important;
        height: 36px !important;
        background: #ffffff !important;
        color: #070709 !important;
        font-weight: 600 !important;
        border-radius: 10px !important;
    }

    /* Universal Content Container Alignment - Eliminate Google 180px logo offset */
    #center_col, .mw #center_col, #rcnt #center_col {
        margin-left: 0 !important;
        margin-right: 0 !important;
        padding-left: 0 !important;
        padding-right: 0 !important;
        max-width: 680px !important;
        width: 100% !important;
        float: none !important;
    }

    #rcnt {
        display: flex !important;
        flex-wrap: wrap !important;
        gap: var(--space-6) !important;
        max-width: 1100px !important;
        margin: 0 auto !important;
        padding: 0 var(--space-6) !important;
        width: 100% !important;
        box-sizing: border-box !important;
    }

    #searchform, .sfbg, .minidiv {
        max-width: 1100px !important;
        margin: 0 auto !important;
        padding: 0 var(--space-6) !important;
        box-sizing: border-box !important;
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
    }

    #searchform > div, #searchform form, #tsf {
        max-width: 680px !important;
        width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
    }

    #main, #cnt {
        max-width: 1100px !important;
        margin: 0 auto !important;
        width: 100% !important;
        box-sizing: border-box !important;
        padding: 0 var(--space-6) !important;
    }

    /* On Google Images search or wide grid modes, allow full content width up to 1440px */
    #rcnt #center_col:has(.VKHL9c),
    #rcnt #center_col:has(.srKDX),
    #rcnt #center_col:has(.DeNS1c),
    #rcnt #center_col:has([data-ri]),
    #rcnt #center_col:has(#islrg),
    #center_col:has(.VKHL9c),
    #center_col:has(.srKDX),
    #center_col:has(.DeNS1c),
    #center_col:has([data-ri]),
    body:has(.VKHL9c) #rcnt #center_col,
    body:has(.srKDX) #rcnt #center_col,
    body:has(#islmp) #rcnt #center_col,
    body:has(.DeNS1c) #rcnt #center_col,
    body:has([data-ri]) #rcnt #center_col,
    body:has(#islmp) #center_col,
    body:has(.VKHL9c) #center_col,
    body:has(#islmp) #rcnt,
    body:has(.VKHL9c) #rcnt,
    body:has(.srKDX) #rcnt,
    body:has(#islmp) #main,
    body:has(.VKHL9c) #main,
    body:has(.srKDX) #main,
    body:has(#islmp) #cnt,
    body:has(.VKHL9c) #cnt,
    body:has(.srKDX) #cnt,
    body:has(#islmp) #searchform,
    body:has(.VKHL9c) #searchform,
    body:has(.srKDX) #searchform,
    body:has(#islmp) #searchform > div,
    body:has(.VKHL9c) #searchform > div,
    body:has(#islmp) #tsf,
    body:has(.VKHL9c) #tsf {
        max-width: 1440px !important;
        width: 100% !important;
    }

    #rhs {
        max-width: 380px !important;
        box-sizing: border-box !important;
    }

    @media (max-width: 768px) {
        .header-wrap, #header_wrapper, #main, #cnt, #rcnt {
            padding-left: var(--space-4) !important;
            padding-right: var(--space-4) !important;
        }
        #web_content_wrapper, .content-wrap, #react-layout {
            padding-left: var(--space-4) !important;
            padding-right: var(--space-4) !important;
        }
        .search--header, .search--adv, .search-wrap,
        #search_form [class*="QsyijBlqupsaY11GFhnp"],
        #search_form [class*="T265XEcezvjUhK71U8pN"],
        #react-duckbar, [data-testid="duckbar"],
        #react-duckbar nav, [data-testid="duckbar"] nav,
        section[class*="At_VJ9M"], .At_VJ9MlrHsSjbfCtz2_,
        [class*="FMPme3X9"] > aside,
        [class*="FMPme3X9"] > section:nth-child(2),
        #center_col, #rhs {
            max-width: 100% !important;
            flex-basis: 100% !important;
        }
    }
    """
