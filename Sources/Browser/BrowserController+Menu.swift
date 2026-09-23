import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Menu Bar Actions
    @objc func menuNewTab() {
        createNewTab(url: startPageURL)
    }
    
    @objc func menuCloseTab() {
        closeTab(at: activeTabIndex)
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
        activeWebView.pageZoom += 0.1
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
        guard !tabs.isEmpty else { return }
        selectTab(at: (activeTabIndex + 1) % tabs.count)
    }
    
    @objc func menuPrevTab() {
        guard !tabs.isEmpty else { return }
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
    
    @objc func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "Onyx"
        alert.informativeText = "Version 1.0.0 (Native WebKit)\n\nUltra-low RAM browser engineered for instant search, tab management, and free Duck.ai research.\n\nPitch-black monochrome aesthetics."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Close")
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.runModal()
    }
}
