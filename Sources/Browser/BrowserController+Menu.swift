import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Menu Bar Actions
    /// Tab-changing menu actions must not act on the tab under an open sheet
    /// (e.g. Cmd+W while the Edit Bookmark sheet is up).
    var isShowingSheet: Bool {
        return window?.attachedSheet != nil
    }
    
    @objc func menuNewTab() {
        guard !isShowingSheet else { return }
        createNewTab(url: startPageURL)
    }
    
    @objc func menuCloseTab() {
        if let win = window, let sheet = win.attachedSheet {
            // Onyx's own sheets (edit bookmark, password editor) block Cmd+W. A page's
            // alert()/confirm()/prompt() sheet does not: cancel it and close the page, which is
            // the only keyboard way out of an alert loop.
            guard sheet === activeJSDialogSheet else { return }
            let dialogWebView = activeJSDialogWebView
            win.endSheet(sheet, returnCode: .alertSecondButtonReturn)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let wv = dialogWebView, let tab = self.tabs.first(where: { $0.webView == wv }) {
                    self.closeTab(tab: tab)
                } else {
                    self.closeTab(at: self.activeTabIndex)
                }
            }
            return
        }
        closeTab(at: activeTabIndex)
    }
    
    @objc func menuFocusAddressBar() {
        guard !isShowingSheet else { return }
        searchField.selectText(nil)
        window?.makeFirstResponder(searchField)
    }
    
    @objc func menuOpenBookmarkSlot(_ sender: NSMenuItem) {
        guard !isShowingSheet else { return }
        openBookmarkIndex(sender.tag)
    }
    
    @objc func menuReload() {
        reloadPage()
    }
    
    @objc func menuToggleBookmarks() {
        toggleBookmarksBar()
    }
    
    @objc func menuToggleDownloads() {
        toggleDownloadsPopover()
    }
    
    @objc func menuTogglePasswords() {
        togglePasswordsPopover()
    }
    
    @objc func menuToggleExtensions() {
        toggleExtensionsPopover()
    }
    
    @objc func menuImportPasswords() {
        importPasswordsPrompt()
    }
    
    @objc func menuExportPasswords() {
        exportPasswordsPrompt()
    }
    
    @objc func menuZoomIn() {
        activeWebView.pageZoom = min(3.0, activeWebView.pageZoom + 0.1)
    }
    
    @objc func menuZoomOut() {
        activeWebView.pageZoom = max(0.5, activeWebView.pageZoom - 0.1)
    }
    
    @objc func menuZoomReset() {
        activeWebView.pageZoom = 1.0
    }
    
    @objc func menuGoBack() {
        goBack()
    }
    
    @objc func menuGoForward() {
        goForward()
    }
    
    @objc func menuGoHome() {
        loadTabURL(tab: activeTab, url: startPageURL)
    }
    
    @objc func menuNextTab() {
        guard !tabs.isEmpty, !isShowingSheet else { return }
        selectTab(at: (activeTabIndex + 1) % tabs.count)
    }
    
    @objc func menuPrevTab() {
        guard !tabs.isEmpty, !isShowingSheet else { return }
        selectTab(at: (activeTabIndex - 1 + tabs.count) % tabs.count)
    }
    
    @objc func menuSwitchProfile1() { switchToProfileIndex(0) }
    @objc func menuSwitchProfile2() { switchToProfileIndex(1) }
    @objc func menuSwitchProfile3() { switchToProfileIndex(2) }
    @objc func menuSwitchProfile4() { switchToProfileIndex(3) }
    @objc func menuManageProfiles() { showProfileManagerPopover() }
    
    @objc func showPrivacyReport() {
        let alert = NSAlert()
        alert.messageText = "Onyx Shield"
        alert.informativeText = "Active Content Blocker: Active\nEngine: Native WebKit + YouTube Ad Shield (~30 MB RAM)\n\n• Global Web Ad & Tracker Blocking: Enabled\n• YouTube Video Ad Skipping & Popup Elimination: Active\n• Anti-Adblock Enforcement Neutralizer: Active\n\nOnyx prevents tracking beacons, video pre-rolls/mid-rolls, and intrusive banners with zero layout shift."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Done")
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.runModal()
    }
    
    /// App menu > "Make Onyx Default Browser…". macOS shows its own confirmation dialog.
    @objc func menuMakeDefaultBrowser() {
        requestDefaultBrowser()
    }

    func requestDefaultBrowser() {
        if DefaultBrowser.isDefault {
            showVaultToastHUD(icon: "checkmark.circle.fill", title: "ALREADY DEFAULT", message: "Links from other apps already open in Onyx")
            return
        }
        DefaultBrowser.request { [weak self] isDefault, error in
            guard let self = self else { return }
            if isDefault {
                self.showVaultToastHUD(icon: "checkmark.circle.fill", title: "DEFAULT BROWSER", message: "Links from other apps now open in Onyx")
            } else if error == nil {
                // The user dismissed the system dialog; nothing to report.
                OnyxLog.security.notice("default browser request was not approved")
            } else {
                self.showVaultToastHUD(icon: "exclamationmark.triangle.fill", title: "COULD NOT SET DEFAULT", message: "Choose Onyx under System Settings > Desktop & Dock > Default web browser")
            }
            if let webView = self.tabs.first(where: { self.isSettingsURL($0.url) })?.webView {
                self.sendSettingsPayload(to: webView)
            }
        }
    }

    @objc func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "Onyx"
        alert.informativeText = "Version 1.2.0 (Native WebKit)\n\nUltra-low RAM browser engineered for instant search, tab management, and free Duck.ai research.\n\nPitch-black monochrome aesthetics."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Close")
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.runModal()
    }
}

// MARK: - Bookmarks menu titles (⌘1-⌘9 follow the bookmarks bar order)
extension BrowserController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Bookmarks" else { return }
        for item in menu.items where item.action == #selector(menuOpenBookmarkSlot(_:)) {
            if item.tag < bookmarks.count {
                item.title = bookmarks[item.tag].title
                item.isHidden = false
            } else {
                item.title = "Bookmark \(item.tag + 1)"
                item.isHidden = true
            }
        }
    }
}

// MARK: - Print & Save
extension BrowserController {
    @objc func menuPrintPage() {
        guard let window = window, window.attachedSheet == nil else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        let op = activeWebView.printOperation(with: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        // WKWebView's print view needs a frame or it prints blank pages.
        op.view?.frame = activeWebView.bounds
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func suggestedPageFileName(_ ext: String) -> String {
        let raw = activeWebView.title?.isEmpty == false ? activeWebView.title! : (activeWebView.url?.host ?? "Page")
        let cleaned = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(80)) + "." + ext
    }

    private func savePage(ext: String, type: UTType, produce: @escaping (@escaping (Result<Data, Error>) -> Void) -> Void) {
        guard let window = window, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedPageFileName(ext)
        panel.allowedContentTypes = [type]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            produce { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: url, options: .atomic)
                            self?.showVaultToastHUD(icon: "checkmark.circle.fill", title: "SAVED", message: url.lastPathComponent)
                        } catch {
                            self?.showVaultToastHUD(icon: "exclamationmark.triangle.fill", title: "COULDN'T SAVE", message: error.localizedDescription)
                        }
                    case .failure(let error):
                        self?.showVaultToastHUD(icon: "exclamationmark.triangle.fill", title: "COULDN'T SAVE", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    /// Web Archive, like Safari's File > Save As: page plus its images and styles, opens offline.
    @objc func menuSavePageAs() {
        let webView = activeWebView
        savePage(ext: "webarchive", type: UTType(filenameExtension: "webarchive") ?? .data) { done in
            webView.createWebArchiveData { done($0) }
        }
    }

    @objc func menuExportPDF() {
        let webView = activeWebView
        savePage(ext: "pdf", type: .pdf) { done in
            webView.createPDF(configuration: WKPDFConfiguration()) { done($0) }
        }
    }
}
