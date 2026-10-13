import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Shortcuts
    /// Most shortcuts live in the main menu (AppDelegate.setupMainMenu). Menu key equivalents reach
    /// a focused web page first, so Cmd+B (bold), Cmd+K (GitHub palette), Cmd+[ ] and Escape keep
    /// working inside web apps. This monitor handles only:
    ///  - the browser-reserved keys a page must never be able to block: Cmd+T, Cmd+Shift+T, Cmd+W, Cmd+Shift+W,
    ///    Cmd+Q (the same set Chrome reserves);
    ///  - Cmd+L and Cmd+R only while the page cannot take keys (crashed, or still a dead view),
    ///    otherwise a web app may use them and the menu handles them when it does not;
    ///  - Ctrl(+Shift)+Tab.
    /// It ignores other windows (open/save panels, alerts) but runs inside Onyx's popovers.
    func setupShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let win = self.window, let eventWindow = event.window else { return event }
            let isPopover = String(describing: type(of: eventWindow)).contains("Popover")
            guard eventWindow === win || isPopover else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = event.charactersIgnoringModifiers?.lowercased()
            
            // Ctrl+Tab / Ctrl+Shift+Tab cycle tabs.
            if flags.contains(.control) && !flags.contains(.command) && event.keyCode == 48 {
                guard !self.tabs.isEmpty, win.attachedSheet == nil else { return nil }
                let step = flags.contains(.shift) ? -1 : 1
                self.selectTab(at: (self.activeTabIndex + step + self.tabs.count) % self.tabs.count)
                return nil
            }
            
            // Reserved browser keys. Cmd+W goes through menuCloseTab, which knows about sheets.
            let onlyCommand = flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option)
            guard onlyCommand else { return event }
            if flags.contains(.shift) {
                if key == "w" { win.performClose(nil); return nil }
                if key == "t" { self.menuReopenClosedTab(); return nil }
                return event
            }
            switch key {
            case "w": self.menuCloseTab(); return nil
            case "t": self.menuNewTab(); return nil
            case "l", "r":
                // A WKWebView without a live process swallows key equivalents, so the menu would
                // never see these. Live pages get them first, like any other key.
                guard win.attachedSheet == nil, self.activeTab.needsReload || self.activeWebView.url == nil else { return event }
                if key == "l" { self.menuFocusAddressBar() } else { self.reloadPage() }
                return nil
            case "q": NSApp.terminate(nil); return nil
            default: return event
            }
        }
    }
}
