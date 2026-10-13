import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Bookmarks Management & Actions
    @objc func bookmarkButtonClicked(_ sender: BookmarkButton) {
        if let url = URL(string: sender.bookmark.urlString) {
            loadURL(url)
        }
    }
    
    func openBookmarkIndex(_ idx: Int) {
        guard idx < bookmarks.count else { return }
        if let url = URL(string: bookmarks[idx].urlString) {
            loadURL(url)
        }
    }
    
    @objc func toggleBookmarksBar() {
        let isVisible = bookmarksBarHeightConstraint.constant > 0
        setBookmarksBarVisible(!isVisible)
    }
    
    func setBookmarksBarVisible(_ show: Bool) {
        let currentlyVisible = bookmarksBarHeightConstraint.constant > 0
        guard show != currentlyVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            Motion.prepare(ctx)
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.bookmarksBarHeightConstraint.animator().constant = show ? 28 : 0
            self.bookmarksBar.animator().alphaValue = show ? 1.0 : 0.0
        }
        UserDefaults.standard.set(show, forKey: "OnyxShowBookmarksBar")
    }
    
    @objc func manageBookmarksButtonClicked(_ sender: NSButton) {
        let point = NSPoint(x: sender.bounds.minX, y: sender.bounds.minY)
        showBookmarksBarMenu(at: point, in: sender)
    }
    
    func loadSavedBookmarks() {
        let result = Persistence.loadList(BookmarkItem.self, key: "OnyxBookmarks")
        if let problem = result.problem {
            // Raw data is already in Onyx/recovery. Show what survived (or the defaults); nothing is
            // written back until the user edits bookmarks.
            startupNotices.append(problem.userMessage)
            bookmarks = result.items.isEmpty ? BrowserController.defaultBookmarks : result.items
        } else if UserDefaults.standard.data(forKey: "OnyxBookmarks") == nil {
            bookmarks = BrowserController.defaultBookmarks
        } else {
            bookmarks = result.items
        }
    }
    
    func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "OnyxBookmarks")
        }
    }
    
    func loadBrowsingHistory() {
        let result = Persistence.loadList(BrowsingHistoryItem.self, key: "OnyxBrowsingHistory")
        browsingHistory = result.items
        if let problem = result.problem {
            startupNotices.append(problem.userMessage)
            // History autosaves on every page load. Only allow that to replace the unreadable value
            // once its raw bytes are safely in Onyx/recovery.
            historySavingBlocked = problem.backupURL == nil
        }
    }
    
    func saveBrowsingHistory() {
        guard !historySavingBlocked else { return }
        if let data = try? JSONEncoder().encode(browsingHistory) {
            UserDefaults.standard.set(data, forKey: "OnyxBrowsingHistory")
        }
    }
    
    func addBrowsingHistory(title: String, url: URL) {
        let urlStr = url.absoluteString
        guard !urlStr.isEmpty, !url.isFileURL, !urlStr.contains("startpage.html"), !urlStr.contains("settings.html"), url.scheme == "http" || url.scheme == "https" else { return }
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (url.host ?? urlStr) : title
        browsingHistory.removeAll { $0.urlString == urlStr }
        browsingHistory.insert(BrowsingHistoryItem(title: displayTitle, urlString: urlStr, timestamp: Date()), at: 0)
        if browsingHistory.count > 300 {
            browsingHistory = Array(browsingHistory.prefix(300))
        }
        saveBrowsingHistory()
    }
    
    func renderBookmarks() {
        guard bookmarksStack != nil else { return }
        
        for view in bookmarksStack.arrangedSubviews {
            bookmarksStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        bookmarkButtons.removeAll()
        
        for (index, bm) in bookmarks.enumerated() {
            var updatedBM = bm
            if index < 9 {
                updatedBM.shortcut = "⌘\(index + 1)"
            } else {
                updatedBM.shortcut = ""
            }
            
            let btn = BookmarkButton(bookmark: updatedBM, target: self, action: #selector(bookmarkButtonClicked(_:)))
            btn.onOpenInNewTab = { [weak self] item in
                if let url = URL(string: item.urlString) {
                    self?.createNewTab(url: url)
                }
            }
            btn.onCopyURL = { item in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.urlString, forType: .string)
            }
            btn.onEdit = { [weak self] item in
                self?.showEditBookmarkModal(item)
            }
            btn.onDelete = { [weak self] item in
                self?.deleteBookmark(id: item.id)
            }
            btn.onAddBookmark = { [weak self] in
                self?.addNewBookmarkPrompt()
            }
            btn.onOpenManager = { [weak self] in
                self?.openBookmarkManagerModal()
            }
            btn.onHoverChanged = { [weak self] button, isHovered in
                guard let self = self else { return }
                if isHovered {
                    self.hoveredBookmarkButton = button
                    for other in self.bookmarkButtons where other !== button {
                        other.setHovered(false)
                    }
                } else if self.hoveredBookmarkButton === button {
                    self.hoveredBookmarkButton = nil
                }
            }
            
            bookmarkButtons.append(btn)
            bookmarksStack.addArrangedSubview(btn)
        }
        
        updateActiveBookmarkHighlight()
    }
    
    func deleteBookmark(id: String) {
        hoveredBookmarkButton = nil
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
        renderBookmarks()
        refreshBookmarkManagerList()
    }
    
    func deleteBookmark(at index: Int) {
        hoveredBookmarkButton = nil
        guard index >= 0 && index < bookmarks.count else { return }
        bookmarks.remove(at: index)
        saveBookmarks()
        renderBookmarks()
        refreshBookmarkManagerList()
    }
    
    func showBookmarksBarMenu(at point: NSPoint, in view: NSView) {
        let menu = createBookmarksBarMenu(at: point)
        menu.popUp(positioning: nil, at: point, in: view)
    }
    
    func createBookmarksBarMenu(at point: NSPoint) -> NSMenu {
        let menu = NSMenu(title: "Bookmarks")
        
        let addItem = NSMenuItem(title: "Add Bookmark...", action: #selector(menuAddBookmark), keyEquivalent: "d")
        if let img = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            addItem.image = img.withSymbolConfiguration(cfg)
        }
        addItem.target = self
        menu.addItem(addItem)
        
        let addCurrentItem = NSMenuItem(title: "Add Current Page", action: #selector(menuAddCurrentPage), keyEquivalent: "")
        if let img = NSImage(systemSymbolName: "star", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            addCurrentItem.image = img.withSymbolConfiguration(cfg)
        }
        addCurrentItem.target = self
        menu.addItem(addCurrentItem)
        
        let managerItem = NSMenuItem(title: "Bookmark Manager...", action: #selector(menuOpenManager), keyEquivalent: "b")
        if let img = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            managerItem.image = img.withSymbolConfiguration(cfg)
        }
        managerItem.target = self
        menu.addItem(managerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Delete Bookmark Submenu
        let deleteSubmenu = NSMenu(title: "Delete Bookmark")
        if bookmarks.isEmpty {
            let emptyItem = NSMenuItem(title: "No Bookmarks to Delete", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            deleteSubmenu.addItem(emptyItem)
        } else {
            for (index, bm) in bookmarks.enumerated() {
                let item = NSMenuItem(title: bm.title, action: #selector(menuDeleteSpecificBookmark(_:)), keyEquivalent: "")
                if let img = NSImage(systemSymbolName: bm.iconName, accessibilityDescription: nil) {
                    let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                    item.image = img.withSymbolConfiguration(cfg)
                }
                item.target = self
                item.tag = index
                item.toolTip = "Delete \(bm.title) (\(bm.urlString))"
                deleteSubmenu.addItem(item)
            }
            deleteSubmenu.addItem(NSMenuItem.separator())
            let delAllItem = NSMenuItem(title: "Delete All Bookmarks...", action: #selector(menuDeleteAllBookmarks), keyEquivalent: "")
            if let img = NSImage(systemSymbolName: "trash", accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                delAllItem.image = img.withSymbolConfiguration(cfg)
            }
            delAllItem.target = self
            deleteSubmenu.addItem(delAllItem)
        }
        
        let deleteMenuItem = NSMenuItem(title: "Delete Bookmark", action: nil, keyEquivalent: "")
        if let img = NSImage(systemSymbolName: "trash", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            deleteMenuItem.image = img.withSymbolConfiguration(cfg)
        }
        deleteMenuItem.submenu = deleteSubmenu
        menu.addItem(deleteMenuItem)
        
        // Edit Bookmark Submenu
        let editSubmenu = NSMenu(title: "Edit Bookmark")
        if bookmarks.isEmpty {
            let emptyItem = NSMenuItem(title: "No Bookmarks to Edit", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            editSubmenu.addItem(emptyItem)
        } else {
            for (index, bm) in bookmarks.enumerated() {
                let item = NSMenuItem(title: bm.title, action: #selector(menuEditSpecificBookmark(_:)), keyEquivalent: "")
                if let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil) {
                    let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                    item.image = img.withSymbolConfiguration(cfg)
                }
                item.target = self
                item.tag = index
                item.toolTip = "Edit \(bm.title)"
                editSubmenu.addItem(item)
            }
        }
        let editMenuItem = NSMenuItem(title: "Edit Bookmark", action: nil, keyEquivalent: "")
        if let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            editMenuItem.image = img.withSymbolConfiguration(cfg)
        }
        editMenuItem.submenu = editSubmenu
        menu.addItem(editMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let resetItem = NSMenuItem(title: "Reset to Default Bookmarks", action: #selector(menuResetDefaults), keyEquivalent: "")
        if let img = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            resetItem.image = img.withSymbolConfiguration(cfg)
        }
        resetItem.target = self
        menu.addItem(resetItem)
        
        let isVisible = bookmarksBarHeightConstraint.constant > 0
        let hideItem = NSMenuItem(title: isVisible ? "Hide Bookmarks Bar" : "Show Bookmarks Bar", action: #selector(toggleBookmarksBar), keyEquivalent: "")
        if let img = NSImage(systemSymbolName: isVisible ? "eye.slash" : "eye", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            hideItem.image = img.withSymbolConfiguration(cfg)
        }
        hideItem.target = self
        menu.addItem(hideItem)
        
        return menu
    }
    
    @objc func menuAddBookmark() {
        addNewBookmarkPrompt()
    }
    
    @objc func menuAddCurrentPage() {
        let currentURL = activeTab.url
        var title = activeTab.title
        if title.isEmpty || title == "New Tab" {
            title = currentURL.host ?? "Bookmark"
        }
        let urlStr = currentURL.absoluteString
        let icon = iconNameForURL(urlStr)
        let item = BookmarkItem(title: title, urlString: urlStr, iconName: icon)
        bookmarks.append(item)
        saveBookmarks()
        renderBookmarks()
    }
    
    @objc func menuOpenManager() {
        openBookmarkManagerModal()
    }
    
    @objc func menuDeleteSpecificBookmark(_ sender: NSMenuItem) {
        deleteBookmark(at: sender.tag)
    }
    
    @objc func menuEditSpecificBookmark(_ sender: NSMenuItem) {
        guard sender.tag >= 0 && sender.tag < bookmarks.count else { return }
        showEditBookmarkModal(bookmarks[sender.tag])
    }
    
    @objc func menuDeleteAllBookmarks() {
        let alert = NSAlert()
        alert.messageText = "Delete All Bookmarks?"
        alert.informativeText = "Are you sure you want to remove all bookmarks? This cannot be undone."
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical
        if let win = self.window {
            alert.beginSheetModal(for: win) { [weak self] resp in
                if resp == .alertFirstButtonReturn {
                    self?.bookmarks.removeAll()
                    self?.saveBookmarks()
                    self?.renderBookmarks()
                    self?.refreshBookmarkManagerList()
                }
            }
        }
    }
    
    @objc func menuResetDefaults() {
        bookmarks = BrowserController.defaultBookmarks
        saveBookmarks()
        renderBookmarks()
        refreshBookmarkManagerList()
    }
    
    func addNewBookmarkPrompt() {
        let alert = NSAlert()
        alert.messageText = "Add Bookmark"
        alert.informativeText = "Enter the title and URL for the new bookmark:"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
        
        let titleInput = NSTextField(frame: NSRect(x: 0, y: 36, width: 320, height: 24))
        titleInput.placeholderString = "Title (e.g. Google)"
        titleInput.stringValue = (activeTab.title != "New Tab" && !activeTab.title.isEmpty) ? activeTab.title : ""
        
        let urlInput = NSTextField(frame: NSRect(x: 0, y: 4, width: 320, height: 24))
        urlInput.placeholderString = "URL (e.g. https://google.com)"
        let activeURLStr = activeTab.url.absoluteString
        urlInput.stringValue = (!activeURLStr.contains("startpage.html") && !activeURLStr.isEmpty) ? activeURLStr : "https://"
        
        container.addSubview(titleInput)
        container.addSubview(urlInput)
        alert.accessoryView = container
        
        if let win = self.window {
            alert.beginSheetModal(for: win) { [weak self] resp in
                guard let self = self, resp == .alertFirstButtonReturn else { return }
                var t = titleInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                var u = urlInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { t = u }
                if !u.lowercased().hasPrefix("http://") && !u.lowercased().hasPrefix("https://") {
                    u = "https://" + u
                }
                let icon = self.iconNameForURL(u)
                let newItem = BookmarkItem(title: t, urlString: u, iconName: icon)
                self.bookmarks.append(newItem)
                self.saveBookmarks()
                self.renderBookmarks()
                self.refreshBookmarkManagerList()
            }
        }
    }
    
    func showEditBookmarkModal(_ item: BookmarkItem) {
        let alert = NSAlert()
        alert.messageText = "Edit Bookmark"
        alert.informativeText = "Modify the title or destination URL:"
        alert.addButton(withTitle: "Save")
        let cancelBtn = alert.addButton(withTitle: "Cancel")
        cancelBtn.keyEquivalent = "\u{1b}"
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
        
        let titleInput = NSTextField(frame: NSRect(x: 0, y: 36, width: 320, height: 24))
        titleInput.stringValue = item.title
        titleInput.placeholderString = "Bookmark Title"
        
        let urlInput = NSTextField(frame: NSRect(x: 0, y: 4, width: 320, height: 24))
        urlInput.stringValue = item.urlString
        urlInput.placeholderString = "https://..."
        
        container.addSubview(titleInput)
        container.addSubview(urlInput)
        alert.accessoryView = container
        
        if let win = self.window {
            alert.window.initialFirstResponder = titleInput
            DispatchQueue.main.async {
                titleInput.selectText(nil)
            }
            alert.beginSheetModal(for: win) { [weak self] resp in
                guard let self = self, resp == .alertFirstButtonReturn else { return }
                guard let idx = self.bookmarks.firstIndex(where: { $0.id == item.id }) else { return }
                var t = titleInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                var u = urlInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { t = item.title }
                if !u.lowercased().hasPrefix("http://") && !u.lowercased().hasPrefix("https://") {
                    u = "https://" + u
                }
                self.bookmarks[idx].title = t
                self.bookmarks[idx].urlString = u
                if let h = URL(string: u)?.host {
                    self.bookmarks[idx].domain = h
                }
                self.bookmarks[idx].iconName = self.iconNameForURL(u)
                self.saveBookmarks()
                self.renderBookmarks()
                self.refreshBookmarkManagerList()
            }
        }
    }
    
    func openBookmarkManagerModal() {
        if let pop = bookmarkManagerPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let contentWidth: CGFloat = 380
        let totalHeight: CGFloat = 400
        let headerHeight: CGFloat = 48
        let footerHeight: CGFloat = 44
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: totalHeight))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // Header View
        let headerView = NSView(frame: NSRect(x: 0, y: totalHeight - headerHeight, width: contentWidth, height: headerHeight))
        let titleLabel = NSTextField(labelWithString: "Bookmarks")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        headerView.addSubview(titleLabel)
        
        let countBadge = NSTextField(labelWithString: "\(bookmarks.count) items")
        countBadge.translatesAutoresizingMaskIntoConstraints = false
        countBadge.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        countBadge.textColor = NSColor(white: 0.55, alpha: 1.0)
        headerView.addSubview(countBadge)
        self.bookmarkManagerCountLabel = countBadge
        
        let addBtn = NSButton(frame: .zero)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.bezelStyle = .regularSquare
        addBtn.isBordered = false
        addBtn.wantsLayer = true
        addBtn.layer?.cornerRadius = 5
        addBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        addBtn.setMonochromeTitle("＋ Add Bookmark", color: .white, font: NSFont.systemFont(ofSize: 11, weight: .medium))
        addBtn.target = self
        addBtn.action = #selector(managerAddClicked)
        headerView.addSubview(addBtn)
        container.addSubview(headerView)
        
        let headerSep = NSBox(frame: NSRect(x: 0, y: totalHeight - headerHeight, width: contentWidth, height: 1))
        headerSep.boxType = .custom
        headerSep.borderWidth = 0
        headerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(headerSep)
        
        // ScrollView & Stack
        let scrollY = footerHeight
        let scrollHeight = totalHeight - headerHeight - footerHeight
        let scrollView = NSScrollView(frame: NSRect(x: 6, y: scrollY, width: contentWidth - 12, height: scrollHeight))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        
        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.spacing = 4
        rowsStack.alignment = .leading
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        self.bookmarkManagerStack = rowsStack
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = rowsStack
        scrollView.contentView = clipView
        container.addSubview(scrollView)
        
        let footerSep = NSBox(frame: NSRect(x: 0, y: footerHeight, width: contentWidth, height: 1))
        footerSep.boxType = .custom
        footerSep.borderWidth = 0
        footerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(footerSep)
        
        // Footer View
        let footerView = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: footerHeight))
        let resetBtn = NSButton(frame: .zero)
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        resetBtn.bezelStyle = .regularSquare
        resetBtn.isBordered = false
        resetBtn.wantsLayer = true
        resetBtn.layer?.cornerRadius = 4
        resetBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        resetBtn.setMonochromeTitle("Reset Defaults", color: NSColor(white: 0.70, alpha: 1.0), font: NSFont.systemFont(ofSize: 11, weight: .regular))
        resetBtn.target = self
        resetBtn.action = #selector(managerResetClicked)
        footerView.addSubview(resetBtn)
        
        let doneBtn = NSButton(frame: .zero)
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.bezelStyle = .regularSquare
        doneBtn.isBordered = false
        doneBtn.wantsLayer = true
        doneBtn.layer?.cornerRadius = 5
        doneBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        doneBtn.setMonochromeTitle("Done", color: .white, font: NSFont.systemFont(ofSize: 11, weight: .semibold))
        doneBtn.target = self
        doneBtn.action = #selector(managerDoneClicked)
        footerView.addSubview(doneBtn)
        container.addSubview(footerView)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            countBadge.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countBadge.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            addBtn.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14),
            addBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 104),
            addBtn.heightAnchor.constraint(equalToConstant: 24),
            
            resetBtn.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 14),
            resetBtn.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            resetBtn.widthAnchor.constraint(equalToConstant: 96),
            resetBtn.heightAnchor.constraint(equalToConstant: 24),
            
            doneBtn.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -14),
            doneBtn.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            doneBtn.widthAnchor.constraint(equalToConstant: 58),
            doneBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        refreshBookmarkManagerList()
        
        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        self.bookmarkManagerPopover = popover
        
        if let btn = manageBookmarksBtn {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .maxY)
        } else {
            popover.show(relativeTo: bookmarksBar.bounds, of: bookmarksBar, preferredEdge: .maxY)
        }
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
    }
    
    func refreshBookmarkManagerList() {
        guard let stack = bookmarkManagerStack else { return }
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        bookmarkManagerCountLabel?.stringValue = "\(bookmarks.count) items"
        
        if bookmarks.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No bookmarks yet. Click ＋ Add Bookmark to create one.")
            emptyLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            emptyLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
            stack.addArrangedSubview(emptyLabel)
            return
        }
        
        for bm in bookmarks {
            let row = BookmarkManagerRowView(bookmark: bm)
            row.widthAnchor.constraint(equalToConstant: 356).isActive = true
            row.onDelete = { [weak self] in
                self?.deleteBookmark(id: bm.id)
            }
            row.onEdit = { [weak self] in
                self?.showEditBookmarkModal(bm)
            }
            row.onOpen = { [weak self] in
                if let url = URL(string: bm.urlString) {
                    self?.loadURL(url)
                    self?.bookmarkManagerPopover?.performClose(nil)
                }
            }
            stack.addArrangedSubview(row)
        }
    }
    
    @objc func managerAddClicked() {
        addNewBookmarkPrompt()
    }
    
    @objc func managerResetClicked() {
        menuResetDefaults()
    }
    
    @objc func managerDoneClicked() {
        bookmarkManagerPopover?.performClose(nil)
    }
    
    func iconNameForURL(_ urlString: String) -> String {
        let lower = urlString.lowercased()
        if lower.contains("github") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("ninjatrader") || lower.contains("tradesea") || lower.contains("trade") || lower.contains("chart") || lower.contains("market") || lower.contains("stock") { return "chart.xyaxis.line" }
        if lower.contains("canvas") || lower.contains("unapec") || lower.contains("edu") || lower.contains("school") || lower.contains("college") { return "graduationcap" }
        if lower.contains("conflictly") || lower.contains("chat") || lower.contains("slack") || lower.contains("discord") { return "bubble.left.and.bubble.right" }
        if lower.contains("finviz") || lower.contains("crypto") || lower.contains("finance") { return "waveform.path.ecg" }
        if lower.contains("mail") || lower.contains("inbox") { return "envelope" }
        if lower.contains("news") || lower.contains("ycombinator") || lower.contains("article") { return "newspaper" }
        if lower.contains("youtube") || lower.contains("video") { return "play.rectangle" }
        if lower.contains("spotify") || lower.contains("music") { return "music.note" }
        return "globe"
    }
}
