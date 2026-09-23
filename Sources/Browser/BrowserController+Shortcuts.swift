import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Shortcuts
    func setupShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            let isEditingText = (self.window?.firstResponder is NSTextView) || (self.window?.firstResponder is NSText)
            if !isEditingText, let hoveredBM = self.hoveredBookmarkButton {
                // Delete or Backspace key while hovering deletes this individual bookmark immediately
                if event.keyCode == 51 || event.keyCode == 117 {
                    self.deleteBookmark(id: hoveredBM.bookmark.id)
                    return nil
                }
                let key = event.charactersIgnoringModifiers?.lowercased()
                if key == "e" && (flags.isEmpty || flags == .command) {
                    self.showEditBookmarkModal(hoveredBM.bookmark)
                    return nil
                }
            }
            
            if flags.contains([.command, .shift]) {
                let key = event.charactersIgnoringModifiers?.lowercased()
                if key == "b" {
                    self.toggleBookmarksBar()
                    return nil
                } else if key == "s" {
                    self.showSuggestedTabsPopover()
                    return nil
                } else if event.charactersIgnoringModifiers == "]" {
                    self.selectTab(at: (self.activeTabIndex + 1) % self.tabs.count)
                    return nil
                } else if event.charactersIgnoringModifiers == "[" {
                    self.selectTab(at: (self.activeTabIndex - 1 + self.tabs.count) % self.tabs.count)
                    return nil
                }
            } else if flags.contains([.command, .option]) && !flags.contains(.shift) && !flags.contains(.control) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "1":
                    self.switchToProfileIndex(0)
                    return nil
                case "2":
                    self.switchToProfileIndex(1)
                    return nil
                case "3":
                    self.switchToProfileIndex(2)
                    return nil
                case "4":
                    self.switchToProfileIndex(3)
                    return nil
                case "p":
                    self.togglePasswordsPopover()
                    return nil
                case "n":
                    self.openAddPasswordModal()
                    return nil
                case "o":
                    self.showProfileManagerPopover()
                    return nil
                case "l":
                    self.toggleDownloadsPopover()
                    return nil
                default:
                    break
                }
            } else if flags.contains(.control) {
                if event.keyCode == 48 { // Tab
                    self.selectTab(at: (self.activeTabIndex + 1) % self.tabs.count)
                    return nil
                }
            } else if flags.contains(.command) && !flags.contains(.shift) && !flags.contains(.control) && !flags.contains(.option) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case ",":
                    self.openSettingsTab()
                    return nil
                case "b":
                    self.openBookmarkManagerModal()
                    return nil
                case "d":
                    self.addNewBookmarkPrompt()
                    return nil
                case "t":
                    self.createNewTab(url: self.startPageURL)
                    return nil
                case "w":
                    self.closeTab(at: self.activeTabIndex)
                    return nil
                case "o":
                    self.openLocalFile()
                    return nil
                case "j":
                    self.toggleDownloadsPopover()
                    return nil
                case "l", "k":
                    self.searchField.selectText(nil)
                    self.window?.makeFirstResponder(self.searchField)
                    return nil
                case "r":
                    self.reloadPage()
                    return nil
                case "[":
                    self.goBack()
                    return nil
                case "]":
                    self.goForward()
                    return nil
                case "1":
                    self.openBookmarkIndex(0)
                    return nil
                case "2":
                    self.openBookmarkIndex(1)
                    return nil
                case "3":
                    self.openBookmarkIndex(2)
                    return nil
                case "4":
                    self.openBookmarkIndex(3)
                    return nil
                case "5":
                    self.openBookmarkIndex(4)
                    return nil
                case "6":
                    self.openBookmarkIndex(5)
                    return nil
                case "+", "=":
                    self.activeWebView.pageZoom += 0.1
                    return nil
                case "-":
                    self.activeWebView.pageZoom = max(0.5, self.activeWebView.pageZoom - 0.1)
                    return nil
                case "0":
                    self.activeWebView.pageZoom = 1.0
                    return nil
                default:
                    break
                }
            } else if event.keyCode == 53 { // Escape
                self.window?.makeFirstResponder(self.activeWebView)
                return nil
            }
            return event
        }
    }
}
