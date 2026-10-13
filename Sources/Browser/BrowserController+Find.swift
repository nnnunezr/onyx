import Cocoa
import WebKit

// MARK: - Find in Page (⌘F, ⌘G, ⇧⌘G)
extension BrowserController {
    @objc func menuFind() {
        showFindBar()
    }

    @objc func menuFindNext() {
        guard let bar = findBar else { return showFindBar() }
        performFind(bar.field.stringValue, backwards: false, isNewQuery: false)
    }

    @objc func menuFindPrevious() {
        guard let bar = findBar else { return showFindBar() }
        performFind(bar.field.stringValue, backwards: true, isNewQuery: false)
    }

    func showFindBar() {
        if let bar = findBar {
            window?.makeFirstResponder(bar.field)
            bar.field.currentEditor()?.selectAll(nil)
            return
        }
        guard let content = window?.contentView else { return }
        let bar = OnyxFindBar()
        // Hosted in the content view, not webContainerView: tab switches clear that container.
        content.addSubview(bar, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: webContainerView.topAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: webContainerView.trailingAnchor, constant: -16)
        ])
        bar.onSearch = { [weak self] text, backwards, isNew in
            self?.performFind(text, backwards: backwards, isNewQuery: isNew)
        }
        bar.onClose = { [weak self] in self?.hideFindBar() }
        findBar = bar
        bar.field.stringValue = lastFindQuery
        window?.makeFirstResponder(bar.field)
        bar.field.currentEditor()?.selectAll(nil)
        if !lastFindQuery.isEmpty {
            performFind(lastFindQuery, backwards: false, isNewQuery: true)
        }
    }

    func hideFindBar(restoreFocus: Bool = true) {
        guard let bar = findBar else { return }
        bar.removeFromSuperview()
        findBar = nil
        findMatchIndex = 0
        findMatchCount = 0
        if restoreFocus {
            window?.makeFirstResponder(activeWebView)
        }
    }

    func performFind(_ text: String, backwards: Bool, isNewQuery: Bool) {
        lastFindQuery = text
        let webView = activeWebView
        guard !text.isEmpty else {
            findBar?.setStatus("", notFound: false)
            webView.evaluateJavaScript("window.getSelection().removeAllRanges()", in: nil, in: .defaultClient, completionHandler: nil)
            return
        }

        // Count matches in the page text (Onyx's own content world, so the page can't interfere).
        // WebKit's find API reports only found / not found.
        let countJS = """
        (function(q) {
            const t = (document.body ? document.body.innerText : '').toLowerCase();
            q = q.toLowerCase();
            let n = 0, i = 0;
            while ((i = t.indexOf(q, i)) !== -1) { n++; i += q.length; }
            if (\(isNewQuery)) { window.getSelection().removeAllRanges(); }
            return n;
        })(\(JS.string(text)))
        """
        webView.evaluateJavaScript(countJS, in: nil, in: .defaultClient) { [weak self] result in
            guard let self = self else { return }
            let count = (try? result.get()) as? Int ?? 0
            let config = WKFindConfiguration()
            config.backwards = backwards
            config.caseSensitive = false
            config.wraps = true
            webView.find(text, configuration: config) { [weak self] found in
                guard let self = self, let bar = self.findBar, bar.field.stringValue == text else { return }
                guard found.matchFound else {
                    self.findMatchIndex = 0
                    self.findMatchCount = 0
                    bar.setStatus("Not found", notFound: true)
                    return
                }
                if isNewQuery || count != self.findMatchCount || self.findMatchIndex == 0 {
                    self.findMatchIndex = backwards ? count : 1
                } else if backwards {
                    self.findMatchIndex = self.findMatchIndex <= 1 ? count : self.findMatchIndex - 1
                } else {
                    self.findMatchIndex = self.findMatchIndex >= count ? 1 : self.findMatchIndex + 1
                }
                self.findMatchCount = count
                // Matches inside frames are found but not counted.
                bar.setStatus(count > 0 ? "\(self.findMatchIndex) of \(count)" : "Found", notFound: false)
            }
        }
    }
}
