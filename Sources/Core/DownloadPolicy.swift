import Foundation

// MARK: - Download policy
/// Foundation-only so it can be unit-tested outside the app (tests/run.sh). Mirrors what Safari
/// does: the server's `Content-Disposition: attachment` and the page's `<a download>` always win,
/// and a main-frame response WebKit cannot render becomes a download instead of a silent no-op.
enum DownloadPolicy {
    enum Decision: Equatable { case allow, download, cancel }

    /// True for `attachment` and `attachment; filename=...` (any case, any whitespace).
    static func isAttachment(_ contentDisposition: String?) -> Bool {
        guard let value = contentDisposition?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return value == "attachment" || value.hasPrefix("attachment;") || value.hasPrefix("attachment ")
    }

    /// Web documents Onyx always renders unless the server says `attachment`.
    static func isWebDocument(_ mimeType: String?) -> Bool {
        let mime = (mimeType ?? "").split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return mime == "text/html" || mime == "application/xhtml+xml"
    }

    static func decideResponse(mimeType: String?, statusCode: Int?, contentDisposition: String?, isMainFrame: Bool, canShowMIMEType: Bool) -> Decision {
        // Redirects and empty responses carry no file, whatever their headers say.
        if let status = statusCode, (300...399).contains(status) || status == 204 || status == 205 {
            return .allow
        }
        // Gmail and Drive attachments are often PDFs or images sent with this header, and are
        // frequently fetched in a hidden iframe. Rendering them inline is the "download did
        // nothing" bug.
        if isAttachment(contentDisposition) {
            return .download
        }
        // A page is never saved as a file. WebKit can report canShowMIMEType == false for a
        // normal HTML page (seen on youtube.com in a signed-in workspace, likely a service-worker
        // response), which saved "www.youtube.com.html" instead of opening YouTube.
        if canShowMIMEType || isWebDocument(mimeType) {
            return .allow
        }
        // Allowing a type WebKit cannot show fails the load (WebKit error 102) and nothing
        // happens. Main frame: save it, as Safari does. Subframe without the header: drop it, so
        // ad iframes cannot start drive-by downloads.
        return isMainFrame ? .download : .cancel
    }
}
