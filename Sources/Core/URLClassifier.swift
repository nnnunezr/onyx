import Foundation

// MARK: - Exact host classification
/// Foundation-only so it can be unit-tested outside the app. Every "is this site X" decision goes
/// through exact host or registrable-suffix matching: substring checks let lookalike hosts such as
/// `google.tradesea.ai-login.io` or `tradesea.ai-secure.net` pass as trusted sites.
enum URLClassifier {
    /// Google search front-ends Onyx themes. Exact hosts only; `www.` variants are derived.
    static let googleSearchDomains: [String] = [
        "google.com", "google.com.do", "google.ca", "google.co.uk", "google.de", "google.fr",
        "google.es", "google.it", "google.co.jp", "google.com.mx"
    ]

    static func normalizedHost(_ url: URL?) -> String {
        guard var host = url?.host?.lowercased() else { return "" }
        if host.hasSuffix(".") { host.removeLast() }
        return host
    }

    /// True when `host` is `domain` itself or a subdomain of it.
    static func host(_ host: String, isOrIsSubdomainOf domain: String) -> Bool {
        let h = host.lowercased()
        let d = domain.lowercased()
        guard !h.isEmpty, !d.isEmpty else { return false }
        return h == d || h.hasSuffix("." + d)
    }

    static func isLoopback(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "localhost" || h.hasSuffix(".localhost") || h == "::1" || h == "[::1]" || h.hasPrefix("127.")
    }

    static func queryValue(_ url: URL?, _ name: String) -> String? {
        guard let url = url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return items.first(where: { $0.name == name })?.value
    }

    static func isDuckDuckGo(_ host: String) -> Bool {
        return self.host(host, isOrIsSubdomainOf: "duckduckgo.com") || self.host(host, isOrIsSubdomainOf: "duck.com")
    }

    static func isGoogleSearchHost(_ host: String) -> Bool {
        return googleSearchDomains.contains { host == $0 || host == "www." + $0 || host == "images." + $0 }
    }

    /// duck.ai, or DuckDuckGo's chat mode (`ia=chat` read from the query, on DuckDuckGo only).
    static func isResearch(_ url: URL?) -> Bool {
        let host = normalizedHost(url)
        if self.host(host, isOrIsSubdomainOf: "duck.ai") { return true }
        return isDuckDuckGo(host) && queryValue(url, "ia") == "chat"
    }

    static func isSearch(_ url: URL?) -> Bool {
        guard let url = url, !isResearch(url) else { return false }
        let host = normalizedHost(url)
        let path = url.path
        if isDuckDuckGo(host) { return true }
        if isGoogleSearchHost(host) {
            return path == "/search" || path.hasPrefix("/imghp") || host.hasPrefix("images.")
        }
        if host == "search.brave.com" { return path.hasPrefix("/search") }
        if host == "kagi.com" || host == "www.kagi.com" { return path.hasPrefix("/search") }
        if host == "bing.com" || host == "www.bing.com" { return path.hasPrefix("/search") }
        return false
    }

    /// Search pages that get the Onyx dark theme. Google is a search page (address bar, tab title)
    /// but is left to its native dark mode: the theme kept breaking its layout.
    static func isThemedSearch(_ url: URL?) -> Bool {
        return isSearch(url) && !isGoogleSearchHost(normalizedHost(url))
    }

    /// The same rules as JavaScript, for the injected search-theme scripts. Defines `host`, `href`,
    /// `isDuck`, `isGoogle`, `isBrave`, `isSearch`, `isThemedSearch` and `isChat` in the enclosing function scope.
    static var javaScriptClassifier: String {
        let googleList = googleSearchDomains.map { "'\($0)'" }.joined(separator: ", ")
        return """
            const host = (window.location.hostname || '').toLowerCase().replace(/\\.$/, '');
            const href = window.location.href || '';
            const onyxPath = window.location.pathname || '';
            const onyxHostIs = (d) => host === d || host.endsWith('.' + d);
            const onyxGoogle = [\(googleList)];
            const isDDG = onyxHostIs('duckduckgo.com') || onyxHostIs('duck.com');
            const isChat = onyxHostIs('duck.ai') || (isDDG && new URLSearchParams(window.location.search || '').get('ia') === 'chat');
            const isDuck = isDDG || onyxHostIs('duck.ai');
            const isGoogle = onyxGoogle.some(d => host === d || host === 'www.' + d || host === 'images.' + d) &&
                             (onyxPath === '/search' || onyxPath.startsWith('/imghp') || host.startsWith('images.'));
            const isBrave = host === 'search.brave.com' && onyxPath.startsWith('/search');
            const isSearch = isDuck || isGoogle || isBrave;
            const isBing = (host === 'bing.com' || host === 'www.bing.com') && onyxPath.startsWith('/search');
            const isKagi = (host === 'kagi.com' || host === 'www.kagi.com') && onyxPath.startsWith('/search');
            const isThemedSearch = isDuck || isBrave || isBing || isKagi;
        """
    }
}
