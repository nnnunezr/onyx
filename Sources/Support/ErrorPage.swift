import Foundation

// MARK: - Load error page
/// Shown in place of a page that failed to load. Before this, a bad host, being offline or a
/// certificate error left the previous page (or a blank tab) with no explanation. Foundation-only
/// so tests/run.sh can check the escaping.
enum ErrorPage {
    struct Content: Equatable {
        let title: String
        let message: String
    }

    static func content(domain: String, code: Int, host: String, fallback: String) -> Content {
        let site = host.isEmpty ? "the site" : host
        if domain == NSURLErrorDomain {
            switch code {
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return Content(title: "Can't find \(site)", message: "Check the address for typos, or search for it instead.")
            case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff:
                return Content(title: "You're offline", message: "Onyx can't reach the internet. Check your Wi-Fi or network, then try again.")
            case NSURLErrorTimedOut:
                return Content(title: "\(site) took too long to respond", message: "The server may be busy or down. Try again in a moment.")
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
                return Content(title: "Can't connect to \(site)", message: "The server refused the connection or dropped it. Try again in a moment.")
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired:
                return Content(title: "Secure connection to \(site) failed", message: "Onyx can't verify this site's identity, so it did not open it. Someone could be impersonating it.")
            case NSURLErrorBadURL, NSURLErrorUnsupportedURL:
                return Content(title: "That address doesn't work", message: "Onyx can't open this kind of address.")
            default:
                break
            }
        }
        if domain == "WebKitErrorDomain" && code == 104 {
            return Content(title: "Blocked by Onyx", message: "This address matches one of Onyx's tracker-blocking rules.")
        }
        return Content(title: "Can't open \(site)", message: fallback)
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// No scripts: the page is loaded with the failed site's URL as its address.
    static func html(_ content: Content, failedURL: URL, searchURL: URL?) -> String {
        let retry = escape(failedURL.absoluteString)
        let search = searchURL.map { "<a class=\"btn\" href=\"\(escape($0.absoluteString))\">Search instead</a>" } ?? ""
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="color-scheme" content="dark">
        <title>\(escape(content.title))</title>
        <style>
        :root { --space-2: 8px; --space-3: 12px; --space-4: 16px; --space-6: 24px; --space-8: 32px; }
        *, *::before, *::after { box-sizing: border-box; }
        html, body { margin: 0; padding: 0; min-height: 100%; }
        body { background: #070709; color: #e4e4e7; font: 14px/1.5 -apple-system, BlinkMacSystemFont, sans-serif;
               display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: var(--space-6); }
        main { max-width: 480px; width: 100%; padding: var(--space-8); border-radius: 16px;
               background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.08); }
        h1 { margin: 0 0 var(--space-2); font-size: 20px; font-weight: 600; color: #fff; letter-spacing: -0.01em; overflow-wrap: anywhere; }
        p { margin: 0 0 var(--space-4); color: #a1a1aa; }
        code { display: block; margin: 0 0 var(--space-6); padding: var(--space-2) var(--space-3); border-radius: 8px;
               background: rgba(255,255,255,0.05); color: #71717a; font: 12px ui-monospace, Menlo, monospace; overflow-wrap: anywhere; }
        .actions { display: flex; gap: var(--space-2); flex-wrap: wrap; }
        .btn { display: inline-flex; align-items: center; height: 40px; padding: 0 var(--space-4); border-radius: 10px;
               text-decoration: none; font-weight: 600; color: #e4e4e7; background: rgba(255,255,255,0.08);
               border: 1px solid rgba(255,255,255,0.12); }
        .btn.primary { background: #fff; color: #070709; border-color: #fff; }
        .btn:focus-visible { outline: 2px solid #93c5fd; outline-offset: 2px; }
        </style></head>
        <body><main>
        <h1>\(escape(content.title))</h1>
        <p>\(escape(content.message))</p>
        <code>\(retry)</code>
        <div class="actions"><a class="btn primary" href="\(retry)">Try Again</a>\(search)</div>
        </main></body></html>
        """
    }
}
