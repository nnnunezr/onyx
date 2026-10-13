import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var browserController: BrowserController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        // Force-load high-resolution celestial thinking-orb AppIcon into macOS Dock runtime
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let iconImg = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = iconImg
        } else if let localIcon = NSImage(contentsOf: BrowserController.devResourceURL("AppIcon.icns")) {
            NSApp.applicationIconImage = localIcon
        }

        browserController = BrowserController()
        setupMainMenu()
        browserController?.showWindow(nil)
        browserController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        if CommandLine.arguments.count > 1 {
            let arg = CommandLine.arguments[1]
            // resolveQuery handles http(s), file://, onyx:// aliases, bare domains and search text.
            if !arg.hasPrefix("-"), let resolved = browserController?.resolveQuery(arg) {
                browserController?.openLaunchURL(resolved)
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if browserController == nil {
                browserController = BrowserController()
            }
            browserController?.showWindow(nil)
            browserController?.window?.makeKeyAndOrderFront(nil)
        }
        return true
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            browserController?.createNewTab(url: url)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        browserController?.saveSession()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func setupMainMenu() {
        let mainMenu = NSMenu()
        guard let controller = browserController else { return }
        
        // 1. App Menu (Onyx)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Onyx")
        let aboutItem = NSMenuItem(title: "About Onyx", action: #selector(BrowserController.showAboutPanel), keyEquivalent: "")
        aboutItem.target = controller
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(BrowserController.menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = controller
        let passwordsItem = NSMenuItem(title: "Passwords & Vault...", action: #selector(BrowserController.menuTogglePasswords), keyEquivalent: "p")
        passwordsItem.keyEquivalentModifierMask = [.command, .shift]
        passwordsItem.target = controller
        let extensionsItem = NSMenuItem(title: "Extensions & Tools...", action: #selector(BrowserController.menuToggleExtensions), keyEquivalent: "e")
        extensionsItem.keyEquivalentModifierMask = [.command, .option]
        extensionsItem.target = controller
        let hideItem = NSMenuItem(title: "Hide Onyx", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit Onyx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        appMenu.addItem(aboutItem)
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(passwordsItem)
        appMenu.addItem(extensionsItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(hideItem)
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(showAllItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(BrowserController.menuNewTab), keyEquivalent: "t")
        newTabItem.target = controller
        let openFileItem = NSMenuItem(title: "Open File...", action: #selector(BrowserController.openLocalFile), keyEquivalent: "o")
        openFileItem.target = controller
        let openLocationItem = NSMenuItem(title: "Open Location...", action: #selector(BrowserController.menuFocusAddressBar), keyEquivalent: "l")
        openLocationItem.target = controller
        let searchItem = NSMenuItem(title: "Search...", action: #selector(BrowserController.menuFocusAddressBar), keyEquivalent: "k")
        searchItem.target = controller
        let newLoginItem = NSMenuItem(title: "New Login...", action: #selector(BrowserController.openAddPasswordModal), keyEquivalent: "n")
        newLoginItem.keyEquivalentModifierMask = [.command, .option]
        newLoginItem.target = controller
        let importPasswordsItem = NSMenuItem(title: "Import Passwords...", action: #selector(BrowserController.menuImportPasswords), keyEquivalent: "")
        importPasswordsItem.target = controller
        let exportPasswordsItem = NSMenuItem(title: "Export Passwords...", action: #selector(BrowserController.menuExportPasswords), keyEquivalent: "")
        exportPasswordsItem.target = controller
        let closeTabItem = NSMenuItem(title: "Close Tab", action: #selector(BrowserController.menuCloseTab), keyEquivalent: "w")
        closeTabItem.target = controller
        let closeWindowItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "W")
        
        fileMenu.addItem(newTabItem)
        fileMenu.addItem(openLocationItem)
        fileMenu.addItem(searchItem)
        fileMenu.addItem(openFileItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(newLoginItem)
        fileMenu.addItem(importPasswordsItem)
        fileMenu.addItem(exportPasswordsItem)
        fileMenu.addItem(NSMenuItem.separator())
        let reopenSessionItem = NSMenuItem(title: "Reopen Last Session", action: #selector(BrowserController.menuReopenLastSession), keyEquivalent: "")
        reopenSessionItem.target = controller
        let reopenClosedItem = NSMenuItem(title: "Reopen Closed Tab", action: #selector(BrowserController.menuReopenClosedTab), keyEquivalent: "T")
        reopenClosedItem.target = controller
        fileMenu.addItem(reopenClosedItem)
        fileMenu.addItem(reopenSessionItem)
        fileMenu.addItem(NSMenuItem.separator())
        let savePageItem = NSMenuItem(title: "Save Page As…", action: #selector(BrowserController.menuSavePageAs), keyEquivalent: "s")
        savePageItem.target = controller
        let exportPDFItem = NSMenuItem(title: "Export as PDF…", action: #selector(BrowserController.menuExportPDF), keyEquivalent: "")
        exportPDFItem.target = controller
        let printItem = NSMenuItem(title: "Print…", action: #selector(BrowserController.menuPrintPage), keyEquivalent: "p")
        printItem.target = controller
        fileMenu.addItem(savePageItem)
        fileMenu.addItem(exportPDFItem)
        fileMenu.addItem(printItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(closeTabItem)
        fileMenu.addItem(closeWindowItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)
        
        // 3. Edit Menu (Standard OS Undo, Cut, Copy, Paste, Select All)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        editMenu.addItem(undoItem)
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(cutItem)
        editMenu.addItem(copyItem)
        editMenu.addItem(pasteItem)
        editMenu.addItem(selectAllItem)
        editMenu.addItem(NSMenuItem.separator())
        let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        let findItem = NSMenuItem(title: "Find…", action: #selector(BrowserController.menuFind), keyEquivalent: "f")
        findItem.target = controller
        let findNextItem = NSMenuItem(title: "Find Next", action: #selector(BrowserController.menuFindNext), keyEquivalent: "g")
        findNextItem.target = controller
        let findPrevItem = NSMenuItem(title: "Find Previous", action: #selector(BrowserController.menuFindPrevious), keyEquivalent: "G")
        findPrevItem.target = controller
        findMenu.addItem(findItem)
        findMenu.addItem(findNextItem)
        findMenu.addItem(findPrevItem)
        findMenuItem.submenu = findMenu
        editMenu.addItem(findMenuItem)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let reloadItem = NSMenuItem(title: "Reload Page", action: #selector(BrowserController.menuReload), keyEquivalent: "r")
        reloadItem.target = controller
        let toggleBookmarksItem = NSMenuItem(title: "Toggle Bookmarks Bar", action: #selector(BrowserController.menuToggleBookmarks), keyEquivalent: "B")
        toggleBookmarksItem.target = controller
        let downloadsItem = NSMenuItem(title: "Downloads", action: #selector(BrowserController.menuToggleDownloads), keyEquivalent: "j")
        downloadsItem.target = controller
        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(BrowserController.menuZoomIn), keyEquivalent: "+")
        zoomInItem.target = controller
        // Cmd+= (no Shift) is what most people press for zoom in.
        let zoomInEqualsItem = NSMenuItem(title: "Zoom In", action: #selector(BrowserController.menuZoomIn), keyEquivalent: "=")
        zoomInEqualsItem.target = controller
        zoomInEqualsItem.isHidden = true
        zoomInEqualsItem.allowsKeyEquivalentWhenHidden = true
        let downloadsAltItem = NSMenuItem(title: "Downloads", action: #selector(BrowserController.menuToggleDownloads), keyEquivalent: "l")
        downloadsAltItem.keyEquivalentModifierMask = [.command, .option]
        downloadsAltItem.target = controller
        downloadsAltItem.isHidden = true
        downloadsAltItem.allowsKeyEquivalentWhenHidden = true
        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(BrowserController.menuZoomOut), keyEquivalent: "-")
        zoomOutItem.target = controller
        let zoomResetItem = NSMenuItem(title: "Actual Size", action: #selector(BrowserController.menuZoomReset), keyEquivalent: "0")
        zoomResetItem.target = controller
        let fullScreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        
        viewMenu.addItem(reloadItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(toggleBookmarksItem)
        viewMenu.addItem(downloadsItem)
        viewMenu.addItem(downloadsAltItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(zoomInItem)
        viewMenu.addItem(zoomInEqualsItem)
        viewMenu.addItem(zoomOutItem)
        viewMenu.addItem(zoomResetItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(fullScreenItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        
        // 5. History Menu
        let historyMenuItem = NSMenuItem()
        let historyMenu = NSMenu(title: "History")
        let backItem = NSMenuItem(title: "Back", action: #selector(BrowserController.menuGoBack), keyEquivalent: "[")
        backItem.target = controller
        let forwardItem = NSMenuItem(title: "Forward", action: #selector(BrowserController.menuGoForward), keyEquivalent: "]")
        forwardItem.target = controller
        let homeItem = NSMenuItem(title: "Home", action: #selector(BrowserController.menuGoHome), keyEquivalent: "H")
        homeItem.target = controller
        
        historyMenu.addItem(backItem)
        historyMenu.addItem(forwardItem)
        historyMenu.addItem(homeItem)
        historyMenuItem.submenu = historyMenu
        mainMenu.addItem(historyMenuItem)
        
        // 5b. Bookmarks Menu (menu key equivalents let a focused page claim ⌘B/⌘D/⌘1-9 first)
        let bookmarksMenuItem = NSMenuItem()
        let bookmarksMenu = NSMenu(title: "Bookmarks")
        bookmarksMenu.delegate = controller
        let addBookmarkItem = NSMenuItem(title: "Add Bookmark...", action: #selector(BrowserController.menuAddBookmark), keyEquivalent: "d")
        addBookmarkItem.target = controller
        let manageBookmarksItem = NSMenuItem(title: "Manage Bookmarks...", action: #selector(BrowserController.menuOpenManager), keyEquivalent: "b")
        manageBookmarksItem.target = controller
        bookmarksMenu.addItem(addBookmarkItem)
        bookmarksMenu.addItem(manageBookmarksItem)
        bookmarksMenu.addItem(NSMenuItem.separator())
        for slot in 0..<9 {
            let item = NSMenuItem(title: "Bookmark \(slot + 1)", action: #selector(BrowserController.menuOpenBookmarkSlot(_:)), keyEquivalent: "\(slot + 1)")
            item.tag = slot
            item.target = controller
            bookmarksMenu.addItem(item)
        }
        bookmarksMenuItem.submenu = bookmarksMenu
        mainMenu.addItem(bookmarksMenuItem)
        
        // 6. Profiles Menu
        let profilesMenuItem = NSMenuItem()
        let profilesMenu = NSMenu(title: "Profiles")
        let p1 = NSMenuItem(title: "Personal", action: #selector(BrowserController.menuSwitchProfile1), keyEquivalent: "1")
        p1.keyEquivalentModifierMask = [.command, .option]
        p1.target = controller
        let p2 = NSMenuItem(title: "Research & AI", action: #selector(BrowserController.menuSwitchProfile2), keyEquivalent: "2")
        p2.keyEquivalentModifierMask = [.command, .option]
        p2.target = controller
        let p3 = NSMenuItem(title: "Markets & Trading", action: #selector(BrowserController.menuSwitchProfile3), keyEquivalent: "3")
        p3.keyEquivalentModifierMask = [.command, .option]
        p3.target = controller
        let p4 = NSMenuItem(title: "Campus / Academic", action: #selector(BrowserController.menuSwitchProfile4), keyEquivalent: "4")
        p4.keyEquivalentModifierMask = [.command, .option]
        p4.target = controller
        let manageP = NSMenuItem(title: "Manage Profiles...", action: #selector(BrowserController.menuManageProfiles), keyEquivalent: "o")
        manageP.keyEquivalentModifierMask = [.command, .option]
        manageP.target = controller
        
        profilesMenu.addItem(p1)
        profilesMenu.addItem(p2)
        profilesMenu.addItem(p3)
        profilesMenu.addItem(p4)
        profilesMenu.addItem(NSMenuItem.separator())
        profilesMenu.addItem(manageP)
        profilesMenuItem.submenu = profilesMenu
        mainMenu.addItem(profilesMenuItem)
        
        // 7. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let minimizeItem = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let zoomItem = NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let nextTabItem = NSMenuItem(title: "Show Next Tab", action: #selector(BrowserController.menuNextTab), keyEquivalent: "}")
        nextTabItem.target = controller
        let prevTabItem = NSMenuItem(title: "Show Previous Tab", action: #selector(BrowserController.menuPrevTab), keyEquivalent: "{")
        prevTabItem.target = controller
        
        let suggestedItem = NSMenuItem(title: "Workspaces...", action: #selector(BrowserController.showSuggestedTabsPopover), keyEquivalent: "S")
        suggestedItem.keyEquivalentModifierMask = [.command, .shift]
        suggestedItem.target = controller
        
        windowMenu.addItem(minimizeItem)
        windowMenu.addItem(zoomItem)
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(nextTabItem)
        windowMenu.addItem(prevTabItem)
        windowMenu.addItem(suggestedItem)
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
}
