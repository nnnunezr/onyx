import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Password Manager & Vault Actions
    @objc func togglePasswordsPopover() {
        if let pop = passwordsPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        showPasswordsPopover()
    }
    
    func showPasswordsPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let width: CGFloat = 420
        let height: CGFloat = 480
        popover.contentSize = NSSize(width: width, height: height)
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.25).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        
        // 1. Header (48px)
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        
        let headerIcon = NSImageView()
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Passwords Vault") {
            headerIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            headerIcon.contentTintColor = .white
        }
        header.addSubview(headerIcon)
        
        let titleLabel = NSTextField(labelWithString: "PASSWORDS & VAULT")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = .white
        header.addSubview(titleLabel)
        
        let countLabel = NSTextField(labelWithString: "")
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        header.addSubview(countLabel)
        self.passwordCountLabel = countLabel
        
        let headerActions = NSStackView()
        headerActions.translatesAutoresizingMaskIntoConstraints = false
        headerActions.orientation = .horizontal
        headerActions.spacing = 4
        headerActions.alignment = .centerY
        header.addSubview(headerActions)
        
        let exportBtn = NavIconButton(iconName: "square.and.arrow.up", tooltip: "Export Passwords to CSV", target: self, action: #selector(exportPasswordsPrompt), size: 24)
        headerActions.addArrangedSubview(exportBtn)
        
        let importBtn = NavIconButton(iconName: "square.and.arrow.down", tooltip: "Import Passwords (CSV, JSON, Chrome, Safari, Bitwarden...)", target: self, action: #selector(importPasswordsPrompt), size: 24)
        headerActions.addArrangedSubview(importBtn)
        
        let addBtn = NavIconButton(iconName: "plus", tooltip: "Add New Login (⌘N)", target: self, action: #selector(openAddPasswordModal), size: 24)
        headerActions.addArrangedSubview(addBtn)
        
        let headerSep = NSBox()
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerSep.boxType = .custom
        headerSep.borderWidth = 0
        headerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        header.addSubview(headerSep)
        
        // 2. Search Container (40px)
        let searchBox = NSView()
        searchBox.translatesAutoresizingMaskIntoConstraints = false
        searchBox.wantsLayer = true
        searchBox.layer?.cornerRadius = 8
        searchBox.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        searchBox.layer?.borderWidth = 1
        searchBox.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        container.addSubview(searchBox)
        
        let searchIcon = NSImageView()
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") {
            searchIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
            searchIcon.contentTintColor = NSColor(white: 0.45, alpha: 1.0)
        }
        searchBox.addSubview(searchIcon)
        
        let searchInput = NSTextField()
        searchInput.translatesAutoresizingMaskIntoConstraints = false
        searchInput.isBordered = false
        searchInput.drawsBackground = false
        searchInput.focusRingType = .none
        searchInput.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        searchInput.textColor = .white
        searchInput.placeholderAttributedString = NSAttributedString(
            string: "Search passwords, usernames, domains...",
            attributes: [
                .foregroundColor: NSColor(white: 0.45, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .regular)
            ]
        )
        searchInput.target = self
        searchInput.action = #selector(passwordSearchChanged(_:))
        searchInput.delegate = self
        searchBox.addSubview(searchInput)
        self.passwordSearchField = searchInput
        
        // 3. Scrollable Stack for Password Rows
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        container.addSubview(scrollView)
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        
        let rowsStack = NSStackView()
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        rowsStack.orientation = .vertical
        rowsStack.spacing = 4
        rowsStack.alignment = .leading
        documentView.addSubview(rowsStack)
        self.passwordRowsStack = rowsStack
        
        // 4. Footer (36px)
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(footer)
        
        let footerSep = NSBox()
        footerSep.translatesAutoresizingMaskIntoConstraints = false
        footerSep.boxType = .custom
        footerSep.borderWidth = 0
        footerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        footer.addSubview(footerSep)
        
        let statusStack = NSStackView()
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusStack.orientation = .horizontal
        statusStack.spacing = 5
        statusStack.alignment = .centerY
        footer.addSubview(statusStack)
        
        let statusIcon = NSImageView()
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Encrypted Vault") {
            statusIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium))
            statusIcon.contentTintColor = NSColor(white: 0.50, alpha: 1.0)
        }
        statusStack.addArrangedSubview(statusIcon)
        
        let footerStatus = NSTextField(labelWithString: "AES-256 • Keychain Vault")
        footerStatus.translatesAutoresizingMaskIntoConstraints = false
        footerStatus.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        footerStatus.textColor = NSColor(white: 0.50, alpha: 1.0)
        statusStack.addArrangedSubview(footerStatus)
        
        let generateBtn = NSButton()
        generateBtn.translatesAutoresizingMaskIntoConstraints = false
        generateBtn.bezelStyle = .regularSquare
        generateBtn.isBordered = false
        generateBtn.wantsLayer = true
        generateBtn.layer?.cornerRadius = 5
        generateBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        generateBtn.imagePosition = .imageLeading
        if let img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Generate") {
            generateBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
            generateBtn.contentTintColor = NSColor(white: 0.85, alpha: 1.0)
        }
        generateBtn.setMonochromeTitle(" Generate Password", color: NSColor(white: 0.90, alpha: 1.0), font: NSFont.systemFont(ofSize: 10.5, weight: .medium))
        generateBtn.target = self
        generateBtn.action = #selector(generateQuickPasswordAction)
        footer.addSubview(generateBtn)
        
        // Layout Constraints (Strictly aligned to 8px base grid / 4px increments)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),
            container.heightAnchor.constraint(equalToConstant: height),
            
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),
            
            headerIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            headerIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerIcon.widthAnchor.constraint(equalToConstant: 18),
            headerIcon.heightAnchor.constraint(equalToConstant: 18),
            
            titleLabel.leadingAnchor.constraint(equalTo: headerIcon.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            headerActions.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            headerActions.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            headerSep.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerSep.heightAnchor.constraint(equalToConstant: 1),
            
            searchBox.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            searchBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            searchBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            searchBox.heightAnchor.constraint(equalToConstant: 32),
            
            searchIcon.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 8),
            searchIcon.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 14),
            searchIcon.heightAnchor.constraint(equalToConstant: 14),
            
            searchInput.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchInput.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -8),
            searchInput.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            
            scrollView.topAnchor.constraint(equalTo: searchBox.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            
            documentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            documentView.bottomAnchor.constraint(equalTo: rowsStack.bottomAnchor, constant: 8),
            
            rowsStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 4),
            rowsStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 4),
            rowsStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -4),
            
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 36),
            
            footerSep.topAnchor.constraint(equalTo: footer.topAnchor),
            footerSep.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            footerSep.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            footerSep.heightAnchor.constraint(equalToConstant: 1),
            
            statusStack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            statusStack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            
            generateBtn.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            generateBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            generateBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        self.passwordsPopover = popover
        
        refreshPasswordManagerList(query: "")
        let anchor = (passwordsButton.isHidden || passwordsButton.window == nil) ? extensionsButton! : passwordsButton!
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
        DispatchQueue.main.async {
            searchInput.window?.makeFirstResponder(searchInput)
        }
    }
    
    func refreshPasswordManagerList(query: String = "") {
        guard let stack = passwordRowsStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let allEntries = passwordStore.allEntries()
        let filtered = passwordStore.filteredEntries(query: query)
        
        let activeHost = activeWebView.url?.host ?? ""
        let activeMatches = filtered.filter { $0.matches(host: activeHost) }
        let otherEntries = filtered.filter { !$0.matches(host: activeHost) }
            .sorted(by: { $0.title.lowercased() < $1.title.lowercased() })
        
        if query.isEmpty {
            passwordCountLabel?.stringValue = "\(allEntries.count) Logins"
        } else {
            passwordCountLabel?.stringValue = "\(filtered.count) of \(allEntries.count)"
        }
        
        if filtered.isEmpty {
            let emptyView = NSView()
            emptyView.translatesAutoresizingMaskIntoConstraints = false
            emptyView.heightAnchor.constraint(equalToConstant: 220).isActive = true
            emptyView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            if let img = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil) {
                icon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 36, weight: .light))
                icon.contentTintColor = NSColor(white: 1.0, alpha: 0.2)
            }
            emptyView.addSubview(icon)
            
            let label = NSTextField(labelWithString: query.isEmpty ? "No Saved Passwords" : "No Matches Found")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            label.textColor = NSColor(white: 0.7, alpha: 1.0)
            emptyView.addSubview(label)
            
            let sub = NSTextField(labelWithString: query.isEmpty ? "Import from Chrome, Safari, Bitwarden, or add a login." : "Try searching for a different domain or username.")
            sub.translatesAutoresizingMaskIntoConstraints = false
            sub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            sub.textColor = NSColor(white: 0.45, alpha: 1.0)
            emptyView.addSubview(sub)
            
            let btnStack = NSStackView()
            btnStack.translatesAutoresizingMaskIntoConstraints = false
            btnStack.orientation = .horizontal
            btnStack.spacing = 8
            btnStack.alignment = .centerY
            emptyView.addSubview(btnStack)
            
            let impBtn = NSButton()
            impBtn.translatesAutoresizingMaskIntoConstraints = false
            impBtn.bezelStyle = .regularSquare
            impBtn.isBordered = false
            impBtn.wantsLayer = true
            impBtn.layer?.cornerRadius = 5
            impBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            impBtn.setMonochromeTitle("Import Passwords...", color: .white, font: NSFont.systemFont(ofSize: 11, weight: .medium))
            impBtn.target = self
            impBtn.action = #selector(importPasswordsPrompt)
            btnStack.addArrangedSubview(impBtn)
            
            let addBtn = NSButton()
            addBtn.translatesAutoresizingMaskIntoConstraints = false
            addBtn.bezelStyle = .regularSquare
            addBtn.isBordered = false
            addBtn.wantsLayer = true
            addBtn.layer?.cornerRadius = 5
            addBtn.layer?.backgroundColor = NSColor.white.cgColor
            addBtn.setMonochromeTitle("+ Add Login", color: NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 1.0), font: NSFont.systemFont(ofSize: 11, weight: .semibold))
            addBtn.target = self
            addBtn.action = #selector(openAddPasswordModal)
            btnStack.addArrangedSubview(addBtn)
            
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor, constant: -36),
                icon.widthAnchor.constraint(equalToConstant: 44),
                icon.heightAnchor.constraint(equalToConstant: 44),
                
                label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
                label.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                
                sub.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
                sub.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                
                btnStack.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 16),
                btnStack.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
                
                impBtn.heightAnchor.constraint(equalToConstant: 28),
                impBtn.widthAnchor.constraint(equalToConstant: 130),
                addBtn.heightAnchor.constraint(equalToConstant: 28),
                addBtn.widthAnchor.constraint(equalToConstant: 96)
            ])
            
            stack.addArrangedSubview(emptyView)
            return
        }
        
        func createSectionLabel(text: String, isAccent: Bool) -> NSView {
            let v = NSView()
            v.translatesAutoresizingMaskIntoConstraints = false
            v.heightAnchor.constraint(equalToConstant: 20).isActive = true
            let lbl = NSTextField(labelWithString: text)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
            lbl.textColor = isAccent ? .white : NSColor(white: 0.45, alpha: 1.0)
            v.addSubview(lbl)
            NSLayoutConstraint.activate([
                lbl.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
                lbl.centerYAnchor.constraint(equalTo: v.centerYAnchor)
            ])
            return v
        }
        
        if !activeMatches.isEmpty {
            let activeHeader = createSectionLabel(text: "MATCHING ACTIVE TAB", isAccent: true)
            stack.addArrangedSubview(activeHeader)
            activeHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            
            for entry in activeMatches {
                let row = OnyxPasswordRowView(entry: entry, isCurrentSite: true)
                configurePasswordRowCallbacks(row)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            
            if !otherEntries.isEmpty {
                let sep = NSBox()
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.boxType = .custom
                sep.borderWidth = 0
                sep.fillColor = NSColor(white: 1.0, alpha: 0.08)
                stack.addArrangedSubview(sep)
                NSLayoutConstraint.activate([
                    sep.heightAnchor.constraint(equalToConstant: 1),
                    sep.widthAnchor.constraint(equalTo: stack.widthAnchor)
                ])
                
                let allHeader = createSectionLabel(text: "ALL VAULT LOGINS", isAccent: false)
                stack.addArrangedSubview(allHeader)
                allHeader.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        
        for entry in otherEntries {
            let row = OnyxPasswordRowView(entry: entry, isCurrentSite: false)
            configurePasswordRowCallbacks(row)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
    
    private func configurePasswordRowCallbacks(_ row: OnyxPasswordRowView) {
        row.onAutofill = { [weak self] entry in
            self?.autofillActiveTab(with: entry)
        }
        row.onCopyPassword = { [weak self] entry in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.password, forType: .string)
            self?.showVaultToastHUD(icon: "key.fill", title: "PASSWORD COPIED", message: "Password for \(entry.title) copied to clipboard")
        }
        row.onCopyUsername = { [weak self] entry in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.username, forType: .string)
            self?.showVaultToastHUD(icon: "person.fill", title: "USERNAME COPIED", message: "Username \(entry.username) copied to clipboard")
        }
        row.onEdit = { [weak self] entry in
            self?.passwordsPopover?.performClose(nil)
            self?.showPasswordEditorModal(entry: entry)
        }
        row.onDelete = { [weak self] entry in
            guard let self = self else { return }
            let persisted = self.passwordStore.delete(id: entry.id)
            self.refreshPasswordManagerList(query: self.passwordSearchField?.stringValue ?? "")
            self.updatePasswordsBadge(for: self.activeWebView.url)
            if persisted {
                self.showVaultToastHUD(icon: "trash", title: "LOGIN REMOVED", message: "Deleted \(entry.title) from vault")
            } else {
                self.showVaultNotSavedToast()
            }
        }
    }
    
    @objc func passwordSearchChanged(_ sender: NSTextField) {
        refreshPasswordManagerList(query: sender.stringValue)
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField {
            if tf === passwordSearchField {
                refreshPasswordManagerList(query: tf.stringValue)
            } else if tf === searchField {
                updateSearchContainerGlow(for: tf.stringValue)
                handleSearchFieldInputChanged(query: tf.stringValue)
            }
        }
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === searchField {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if suggestionsPopover?.isShown == true {
                    suggestionsView?.moveSelection(direction: -1)
                    if let item = suggestionsView?.selectedItem() {
                        searchField.stringValue = item.searchQuery ?? item.urlString ?? item.title
                    }
                    return true
                }
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if suggestionsPopover?.isShown == true {
                    suggestionsView?.moveSelection(direction: 1)
                    if let item = suggestionsView?.selectedItem() {
                        searchField.stringValue = item.searchQuery ?? item.urlString ?? item.title
                    }
                    return true
                }
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if suggestionsPopover?.isShown == true {
                    closeSuggestionsPopover()
                    return true
                }
                // Second Escape: restore the current URL and return focus to the page.
                updateSearchField(url: activeWebView.url ?? activeTab.url)
                window?.makeFirstResponder(activeWebView)
                return true
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if suggestionsPopover?.isShown == true, let selected = suggestionsView?.selectedItem() {
                    closeSuggestionsPopover()
                    executeSelectedSuggestion(selected)
                    return true
                }
                closeSuggestionsPopover()
                searchFieldSubmitted()
                return true
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if suggestionsPopover?.isShown == true, let selected = suggestionsView?.selectedItem() {
                    searchField.stringValue = selected.searchQuery ?? selected.urlString ?? selected.title
                    return true
                }
            }
        }
        return false
    }
    
    @objc func generateQuickPasswordAction() {
        let pass = passwordStore.generateStrongPassword(length: 16)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pass, forType: .string)
        showVaultToastHUD(icon: "dice.fill", title: "STRONG PASSWORD GENERATED", message: "16-char crypto password copied to clipboard")
    }
    
    @objc func openAddPasswordModal() {
        passwordsPopover?.performClose(nil)
        showPasswordEditorModal(entry: nil)
    }
    
    func showPasswordEditorModal(entry: OnyxPasswordEntry?) {
        guard let parentWindow = self.window else { return }
        
        let isNew = (entry == nil)
        let activeURLStr = activeWebView.url?.absoluteString ?? ""
        let activeHost = activeWebView.url?.host ?? ""
        let initialTitle = entry?.title ?? (activeHost.isEmpty ? "" : activeHost.replacingOccurrences(of: "www.", with: "").capitalized)
        let initialURL = entry?.urlString ?? (!activeURLStr.contains("startpage.html") && !activeURLStr.isEmpty ? activeURLStr : "")
        let initialUser = entry?.username ?? ""
        let initialPass = entry?.password ?? ""
        let initialNotes = entry?.notes ?? ""
        
        let sheetWidth: CGFloat = 460
        let sheetHeight: CGFloat = 544
        
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = isNew ? "Add New Login" : "Edit Login"
        sheetWindow.titlebarAppearsTransparent = true
        sheetWindow.backgroundColor = NSColor(red: 18/255.0, green: 18/255.0, blue: 22/255.0, alpha: 1.0)
        
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
        container.material = .popover
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.40).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        sheetWindow.contentView = container
        
        let headerIcon = NSImageView()
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: isNew ? "lock.badge.plus.fill" : "pencil.circle.fill", accessibilityDescription: nil) {
            headerIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
            headerIcon.contentTintColor = .white
        }
        container.addSubview(headerIcon)
        
        let headerTextStack = NSStackView()
        headerTextStack.translatesAutoresizingMaskIntoConstraints = false
        headerTextStack.orientation = .vertical
        headerTextStack.spacing = 2
        headerTextStack.alignment = .leading
        container.addSubview(headerTextStack)
        
        let titleLabel = NSTextField(labelWithString: isNew ? "Add Login to Onyx Vault" : "Edit Login Credentials")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        headerTextStack.addArrangedSubview(titleLabel)
        
        let subtitleLabel = NSTextField(labelWithString: "Stored encrypted locally with fast autofill integration.")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        subtitleLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
        headerTextStack.addArrangedSubview(subtitleLabel)
        
        let topSep = NSBox()
        topSep.translatesAutoresizingMaskIntoConstraints = false
        topSep.boxType = .custom
        topSep.borderWidth = 0
        topSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(topSep)
        
        func createFormContainer(placeholder: String, value: String) -> (box: NSView, field: NSTextField) {
            let box = NSView()
            box.translatesAutoresizingMaskIntoConstraints = false
            box.wantsLayer = true
            box.layer?.cornerRadius = 6
            box.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
            box.layer?.borderWidth = 1
            box.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
            
            let tf = NSTextField()
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.isBordered = false
            tf.drawsBackground = false
            tf.focusRingType = .none
            tf.textColor = .white
            tf.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
            tf.stringValue = value
            tf.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor(white: 0.38, alpha: 1.0),
                    .font: NSFont.systemFont(ofSize: 12.5, weight: .regular)
                ]
            )
            box.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
                tf.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
                tf.centerYAnchor.constraint(equalTo: box.centerYAnchor)
            ])
            return (box, tf)
        }
        
        func createFieldLabel(text: String) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)
            lbl.textColor = NSColor(white: 0.5, alpha: 1.0)
            return lbl
        }
        
        // Field 1: Title
        let titleFieldLabel = createFieldLabel(text: "SERVICE / WEBSITE NAME")
        container.addSubview(titleFieldLabel)
        let (titleBox, titleInput) = createFormContainer(placeholder: "e.g. GitHub, Google, Amazon", value: initialTitle)
        container.addSubview(titleBox)
        
        // Field 2: URL
        let urlFieldLabel = createFieldLabel(text: "WEBSITE URL / DOMAIN")
        container.addSubview(urlFieldLabel)
        let (urlBox, urlInput) = createFormContainer(placeholder: "e.g. https://github.com/login", value: initialURL)
        container.addSubview(urlBox)
        
        // Field 3: Username
        let userFieldLabel = createFieldLabel(text: "USERNAME / EMAIL")
        container.addSubview(userFieldLabel)
        let (userBox, userInput) = createFormContainer(placeholder: "e.g. developer@onyx.dev", value: initialUser)
        container.addSubview(userBox)
        
        // Field 4: Password
        let passFieldLabel = createFieldLabel(text: "PASSWORD")
        container.addSubview(passFieldLabel)
        
        let passContainer = NSView()
        passContainer.translatesAutoresizingMaskIntoConstraints = false
        passContainer.wantsLayer = true
        passContainer.layer?.cornerRadius = 6
        passContainer.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        passContainer.layer?.borderWidth = 1
        passContainer.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        container.addSubview(passContainer)
        
        let securePassInput = NSSecureTextField()
        securePassInput.translatesAutoresizingMaskIntoConstraints = false
        securePassInput.isBordered = false
        securePassInput.drawsBackground = false
        securePassInput.focusRingType = .none
        securePassInput.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        securePassInput.textColor = .white
        securePassInput.stringValue = initialPass
        securePassInput.placeholderAttributedString = NSAttributedString(
            string: "Enter password",
            attributes: [.foregroundColor: NSColor(white: 0.38, alpha: 1.0), .font: NSFont.systemFont(ofSize: 12.5, weight: .regular)]
        )
        passContainer.addSubview(securePassInput)
        
        let plainPassInput = NSTextField()
        plainPassInput.translatesAutoresizingMaskIntoConstraints = false
        plainPassInput.isBordered = false
        plainPassInput.drawsBackground = false
        plainPassInput.focusRingType = .none
        plainPassInput.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        plainPassInput.textColor = NSColor(white: 0.95, alpha: 1.0)
        plainPassInput.stringValue = initialPass
        plainPassInput.isHidden = true
        passContainer.addSubview(plainPassInput)
        
        var isEyeRevealed = false
        let eyeToggleBtn = NSButton()
        eyeToggleBtn.translatesAutoresizingMaskIntoConstraints = false
        eyeToggleBtn.bezelStyle = .regularSquare
        eyeToggleBtn.isBordered = false
        eyeToggleBtn.wantsLayer = true
        eyeToggleBtn.layer?.cornerRadius = 4
        eyeToggleBtn.toolTip = "Toggle Password Visibility"
        if let img = NSImage(systemSymbolName: "eye", accessibilityDescription: nil) {
            eyeToggleBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            eyeToggleBtn.contentTintColor = NSColor(white: 0.6, alpha: 1.0)
        }
        passContainer.addSubview(eyeToggleBtn)
        
        let generatePasswordBtn = NSButton()
        generatePasswordBtn.translatesAutoresizingMaskIntoConstraints = false
        generatePasswordBtn.bezelStyle = .regularSquare
        generatePasswordBtn.isBordered = false
        generatePasswordBtn.wantsLayer = true
        generatePasswordBtn.layer?.cornerRadius = 4
        generatePasswordBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        generatePasswordBtn.imagePosition = .imageLeading
        if let img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Generate") {
            generatePasswordBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold))
            generatePasswordBtn.contentTintColor = NSColor(white: 0.85, alpha: 1.0)
        }
        generatePasswordBtn.setMonochromeTitle(" Generate", color: NSColor(white: 0.90, alpha: 1.0), font: NSFont.systemFont(ofSize: 10.5, weight: .semibold))
        generatePasswordBtn.toolTip = "Generate strong 16-character password"
        passContainer.addSubview(generatePasswordBtn)
        
        class ButtonHandler: NSObject {
            let act: () -> Void
            init(_ act: @escaping () -> Void) { self.act = act }
            @objc func trigger() { act() }
        }
        
        let eyeHandler = ButtonHandler {
            isEyeRevealed.toggle()
            if isEyeRevealed {
                plainPassInput.stringValue = securePassInput.stringValue
                securePassInput.isHidden = true
                plainPassInput.isHidden = false
                if let img = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil) {
                    eyeToggleBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
                }
            } else {
                securePassInput.stringValue = plainPassInput.stringValue
                plainPassInput.isHidden = true
                securePassInput.isHidden = false
                if let img = NSImage(systemSymbolName: "eye", accessibilityDescription: nil) {
                    eyeToggleBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
                }
            }
        }
        objc_setAssociatedObject(eyeToggleBtn, "eyeHandler", eyeHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        eyeToggleBtn.target = eyeHandler
        eyeToggleBtn.action = #selector(ButtonHandler.trigger)
        
        let genHandler = ButtonHandler { [weak self] in
            guard let self = self else { return }
            let pass = self.passwordStore.generateStrongPassword(length: 16)
            securePassInput.stringValue = pass
            plainPassInput.stringValue = pass
            isEyeRevealed = true
            securePassInput.isHidden = true
            plainPassInput.isHidden = false
            if let img = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil) {
                eyeToggleBtn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pass, forType: .string)
            self.showVaultToastHUD(icon: "sparkles", title: "PASSWORD GENERATED", message: "16-char crypto password copied to clipboard")
        }
        objc_setAssociatedObject(generatePasswordBtn, "genHandler", genHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        generatePasswordBtn.target = genHandler
        generatePasswordBtn.action = #selector(ButtonHandler.trigger)
        
        // Field 5: Notes
        let notesFieldLabel = createFieldLabel(text: "NOTES (OPTIONAL)")
        container.addSubview(notesFieldLabel)
        let (notesBox, notesInput) = createFormContainer(placeholder: "PIN, 2FA backup codes, or account notes", value: initialNotes)
        container.addSubview(notesBox)
        
        // Bottom Action Bar
        let bottomSep = NSBox()
        bottomSep.translatesAutoresizingMaskIntoConstraints = false
        bottomSep.boxType = .custom
        bottomSep.borderWidth = 0
        bottomSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        container.addSubview(bottomSep)
        
        let cancelBtn = NSButton()
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.bezelStyle = .regularSquare
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.cornerRadius = 6
        cancelBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        cancelBtn.setMonochromeTitle("Cancel", color: NSColor(white: 0.75, alpha: 1.0), font: NSFont.systemFont(ofSize: 12, weight: .medium))
        cancelBtn.keyEquivalent = "\u{1b}"
        container.addSubview(cancelBtn)
        
        let saveBtn = NSButton()
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.bezelStyle = .regularSquare
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.cornerRadius = 6
        saveBtn.layer?.backgroundColor = NSColor.white.cgColor
        saveBtn.setMonochromeTitle(isNew ? "Save Login" : "Update Login", color: NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 1.0), font: NSFont.systemFont(ofSize: 12, weight: .semibold))
        saveBtn.keyEquivalent = "\r"
        container.addSubview(saveBtn)
        
        let cancelHandler = ButtonHandler { [weak parentWindow, weak sheetWindow] in
            guard let pw = parentWindow, let sw = sheetWindow else { return }
            pw.endSheet(sw, returnCode: .cancel)
        }
        objc_setAssociatedObject(cancelBtn, "cancelHandler", cancelHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        cancelBtn.target = cancelHandler
        cancelBtn.action = #selector(ButtonHandler.trigger)
        
        let saveHandler = ButtonHandler { [weak self, weak parentWindow, weak sheetWindow] in
            guard let self = self, let pw = parentWindow, let sw = sheetWindow else { return }
            let finalPass = isEyeRevealed ? plainPassInput.stringValue : securePassInput.stringValue
            var finalTitle = titleInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var finalURL = urlInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalUser = userInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalNotes = notesInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if finalTitle.isEmpty {
                if !finalURL.isEmpty, let u = URL(string: finalURL), let h = u.host {
                    finalTitle = h.replacingOccurrences(of: "www.", with: "").capitalized
                } else {
                    finalTitle = finalUser.isEmpty ? "Saved Login" : finalUser
                }
            }
            if !finalURL.isEmpty && !finalURL.lowercased().hasPrefix("http://") && !finalURL.lowercased().hasPrefix("https://") {
                finalURL = "https://" + finalURL
            }
            
            var newEntry = entry ?? OnyxPasswordEntry(title: finalTitle, urlString: finalURL, username: finalUser, password: finalPass, notes: finalNotes)
            newEntry.title = finalTitle
            newEntry.urlString = finalURL
            newEntry.username = finalUser
            newEntry.password = finalPass
            newEntry.notes = finalNotes
            newEntry.updatedAt = Date()
            
            let persisted = self.passwordStore.addOrUpdate(newEntry)
            self.updatePasswordsBadge(for: self.activeWebView.url)
            self.refreshPasswordManagerList(query: self.passwordSearchField?.stringValue ?? "")
            if persisted {
                self.showVaultToastHUD(icon: "checkmark.shield.fill", title: "LOGIN SAVED", message: "Saved \(finalTitle) to vault")
            } else {
                self.showVaultNotSavedToast()
            }
            pw.endSheet(sw, returnCode: .OK)
        }
        objc_setAssociatedObject(saveBtn, "saveHandler", saveHandler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        saveBtn.target = saveHandler
        saveBtn.action = #selector(ButtonHandler.trigger)
        
        NSLayoutConstraint.activate([
            headerIcon.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            headerIcon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            headerIcon.widthAnchor.constraint(equalToConstant: 28),
            headerIcon.heightAnchor.constraint(equalToConstant: 28),
            
            headerTextStack.leadingAnchor.constraint(equalTo: headerIcon.trailingAnchor, constant: 12),
            headerTextStack.centerYAnchor.constraint(equalTo: headerIcon.centerYAnchor),
            headerTextStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            
            topSep.topAnchor.constraint(equalTo: headerIcon.bottomAnchor, constant: 16),
            topSep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            topSep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            topSep.heightAnchor.constraint(equalToConstant: 1),
            
            titleFieldLabel.topAnchor.constraint(equalTo: topSep.bottomAnchor, constant: 16),
            titleFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            titleBox.topAnchor.constraint(equalTo: titleFieldLabel.bottomAnchor, constant: 8),
            titleBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            titleBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            titleBox.heightAnchor.constraint(equalToConstant: 40),
            
            urlFieldLabel.topAnchor.constraint(equalTo: titleBox.bottomAnchor, constant: 16),
            urlFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            urlBox.topAnchor.constraint(equalTo: urlFieldLabel.bottomAnchor, constant: 8),
            urlBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            urlBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            urlBox.heightAnchor.constraint(equalToConstant: 40),
            
            userFieldLabel.topAnchor.constraint(equalTo: urlBox.bottomAnchor, constant: 16),
            userFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            userBox.topAnchor.constraint(equalTo: userFieldLabel.bottomAnchor, constant: 8),
            userBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            userBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            userBox.heightAnchor.constraint(equalToConstant: 40),
            
            passFieldLabel.topAnchor.constraint(equalTo: userBox.bottomAnchor, constant: 16),
            passFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            passContainer.topAnchor.constraint(equalTo: passFieldLabel.bottomAnchor, constant: 8),
            passContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            passContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            passContainer.heightAnchor.constraint(equalToConstant: 40),
            
            securePassInput.leadingAnchor.constraint(equalTo: passContainer.leadingAnchor, constant: 12),
            securePassInput.centerYAnchor.constraint(equalTo: passContainer.centerYAnchor),
            securePassInput.trailingAnchor.constraint(equalTo: eyeToggleBtn.leadingAnchor, constant: -8),
            
            plainPassInput.leadingAnchor.constraint(equalTo: passContainer.leadingAnchor, constant: 12),
            plainPassInput.centerYAnchor.constraint(equalTo: passContainer.centerYAnchor),
            plainPassInput.trailingAnchor.constraint(equalTo: eyeToggleBtn.leadingAnchor, constant: -8),
            
            generatePasswordBtn.trailingAnchor.constraint(equalTo: passContainer.trailingAnchor, constant: -8),
            generatePasswordBtn.centerYAnchor.constraint(equalTo: passContainer.centerYAnchor),
            generatePasswordBtn.heightAnchor.constraint(equalToConstant: 26),
            generatePasswordBtn.widthAnchor.constraint(equalToConstant: 88),
            
            eyeToggleBtn.trailingAnchor.constraint(equalTo: generatePasswordBtn.leadingAnchor, constant: -6),
            eyeToggleBtn.centerYAnchor.constraint(equalTo: passContainer.centerYAnchor),
            eyeToggleBtn.widthAnchor.constraint(equalToConstant: 26),
            eyeToggleBtn.heightAnchor.constraint(equalToConstant: 26),
            
            notesFieldLabel.topAnchor.constraint(equalTo: passContainer.bottomAnchor, constant: 16),
            notesFieldLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            
            notesBox.topAnchor.constraint(equalTo: notesFieldLabel.bottomAnchor, constant: 8),
            notesBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            notesBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            notesBox.heightAnchor.constraint(equalToConstant: 40),
            
            bottomSep.topAnchor.constraint(equalTo: notesBox.bottomAnchor, constant: 20),
            bottomSep.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            bottomSep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            bottomSep.heightAnchor.constraint(equalToConstant: 1),
            
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -12),
            cancelBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            cancelBtn.heightAnchor.constraint(equalToConstant: 36),
            cancelBtn.widthAnchor.constraint(equalToConstant: 88),
            
            saveBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            saveBtn.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            saveBtn.heightAnchor.constraint(equalToConstant: 36),
            saveBtn.widthAnchor.constraint(equalToConstant: 108)
        ])
        
        parentWindow.beginSheet(sheetWindow, completionHandler: nil)
    }
    
    @objc func importPasswordsPrompt() {
        passwordsPopover?.performClose(nil)
        
        let panel = NSOpenPanel()
        panel.title = "Import Passwords into Onyx"
        panel.prompt = "Import"
        panel.message = "Select a CSV or JSON export from Chrome, Safari, Firefox, Bitwarden, 1Password, or LastPass."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.commaSeparatedText, .json, .plainText]
        } else {
            panel.allowedFileTypes = ["csv", "json", "txt"]
        }
        
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            let result = OnyxPasswordImporter.importFromFile(url: url)
            if let err = result.error {
                let alert = NSAlert()
                alert.messageText = "Import Failed"
                alert.informativeText = err
                alert.alertStyle = .warning
                if let win = self.window {
                    alert.beginSheetModal(for: win, completionHandler: nil)
                } else {
                    alert.runModal()
                }
                return
            }
            
            let (imported, updated, persisted) = self.passwordStore.importEntries(result.entries)
            guard persisted else {
                self.showVaultNotSavedToast()
                return
            }
            self.showVaultToastHUD(
                icon: "checkmark.shield.fill",
                title: "IMPORT SUCCESSFUL",
                message: "Imported \(imported) logins, updated \(updated) from \(result.source)"
            )
            self.updatePasswordsBadge(for: self.activeWebView.url)
            self.refreshPasswordManagerList(query: self.passwordSearchField?.stringValue ?? "")
        }
        
        if let win = self.window {
            panel.beginSheetModal(for: win, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
    
    @objc func exportPasswordsPrompt() {
        passwordsPopover?.performClose(nil)
        
        let entries = passwordStore.allEntries()
        guard !entries.isEmpty else {
            showVaultToastHUD(icon: "exclamationmark.triangle", title: "VAULT EMPTY", message: "No passwords in vault to export")
            return
        }
        
        let panel = NSSavePanel()
        panel.title = "Export Onyx Passwords"
        panel.prompt = "Export"
        panel.message = "Export vault credentials as RFC-4180 standard CSV."
        panel.nameFieldStringValue = "Onyx_Passwords_Export.csv"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.commaSeparatedText]
        } else {
            panel.allowedFileTypes = ["csv"]
        }
        
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            let csv = OnyxPasswordExporter.exportToCSV(entries: entries)
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                self.showVaultToastHUD(icon: "square.and.arrow.up.fill", title: "VAULT EXPORTED", message: "Exported \(entries.count) logins to \(url.lastPathComponent)")
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        
        if let win = self.window {
            panel.beginSheetModal(for: win, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
    
    func autofillActiveTab(with entry: OnyxPasswordEntry) {
        let webView = activeWebView
        
        // Re-check at fill time: the page must be the entry's site (or a subdomain), and over HTTPS
        // unless it is a loopback dev server or the login itself was saved on plain http.
        let pageHost = URLClassifier.normalizedHost(webView.url)
        guard entry.matches(host: pageHost) else {
            let shownHost = pageHost.isEmpty ? "this page" : pageHost
            showVaultToastHUD(icon: "exclamationmark.shield.fill", title: "AUTOFILL BLOCKED",
                              message: "This login is for \(entry.domain), not \(shownHost)")
            return
        }
        let pageScheme = webView.url?.scheme?.lowercased() ?? ""
        let entryIsHTTP = entry.urlString.lowercased().hasPrefix("http://")
        guard pageScheme == "https" || (pageScheme == "http" && (URLClassifier.isLoopback(pageHost) || entryIsHTTP)) else {
            showVaultToastHUD(icon: "exclamationmark.shield.fill", title: "AUTOFILL BLOCKED",
                              message: "Not autofilled over an insecure (http) connection")
            return
        }
        
        let js = """
        (function() {
            const user = \(JS.string(entry.username));
            const pass = \(JS.string(entry.password));
            
            let passInputs = Array.from(document.querySelectorAll('input[type="password"]'));
            if (passInputs.length === 0) {
                passInputs = Array.from(document.querySelectorAll('input[autocomplete*="password"], input[name*="pass"], input[id*="pass"]'));
            }
            
            let filled = false;
            for (const pInput of passInputs) {
                pInput.focus();
                pInput.value = pass;
                pInput.dispatchEvent(new Event('input', { bubbles: true }));
                pInput.dispatchEvent(new Event('change', { bubbles: true }));
                pInput.dispatchEvent(new Event('blur', { bubbles: true }));
                filled = true;
                
                let form = pInput.closest('form');
                let uInput = null;
                if (form) {
                    uInput = form.querySelector('input[type="email"], input[type="text"], input[autocomplete*="username"], input[name*="user"], input[name*="login"], input[id*="user"], input[id*="login"]');
                }
                if (!uInput) {
                    let allInputs = Array.from(document.querySelectorAll('input:not([type="hidden"]):not([type="password"]):not([type="submit"])'));
                    uInput = allInputs.find(i => i.type === 'text' || i.type === 'email' || i.type === 'tel') || allInputs[0];
                }
                if (uInput && user.length > 0) {
                    uInput.focus();
                    uInput.value = user;
                    uInput.dispatchEvent(new Event('input', { bubbles: true }));
                    uInput.dispatchEvent(new Event('change', { bubbles: true }));
                    uInput.dispatchEvent(new Event('blur', { bubbles: true }));
                }
            }
            return filled;
        })();
        """
        
        webView.evaluateJavaScript(js) { [weak self] (result, error) in
            let success = (result as? Bool) == true
            if success {
                self?.showVaultToastHUD(icon: "sparkles", title: "AUTOFILL SUCCESSFUL", message: "Filled credentials for \(entry.title)")
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.password, forType: .string)
                self?.showVaultToastHUD(icon: "key.fill", title: "PASSWORD COPIED", message: "No login fields found. Copied password to clipboard")
            }
        }
    }
    
    func updatePasswordsBadge(for url: URL?) {
        guard let url = url else {
            passwordsButton?.setHasMatch(false)
            return
        }
        let host: String
        if let h = url.host, !h.isEmpty {
            host = h
        } else if url.isFileURL {
            host = url.lastPathComponent
        } else {
            host = ""
        }
        guard !host.isEmpty else {
            passwordsButton?.setHasMatch(false)
            return
        }
        let matches = passwordStore.find(forHost: host)
        passwordsButton?.setHasMatch(!matches.isEmpty)
    }
    
    func showVaultToastHUD(icon: String, title: String, message: String) {
        activeToastHUD?.removeFromSuperview()
        guard let content = self.window?.contentView else { return }
        let hud = OnyxToastHUD(iconName: icon, title: title, message: message)
        content.addSubview(hud)
        self.activeToastHUD = hud
        
        NSLayoutConstraint.activate([
            hud.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
            hud.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            hud.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            hud.heightAnchor.constraint(equalToConstant: 42)
        ])
        hud.animateIn()
    }
    
    func injectPasswordSaveListener(into webView: WKWebView) {
        guard let url = webView.url, (url.scheme == "http" || url.scheme == "https" || url.scheme == "file") else { return }
        let js = """
        (function() {
            if (window.__onyxPasswordSaveListenerAttached) return;
            window.__onyxPasswordSaveListenerAttached = true;
            
            function checkAndNotify(container) {
                try {
                    let passInput = container.querySelector('input[type="password"]');
                    if (!passInput || !passInput.value) return;
                    let pass = passInput.value;
                    if (pass.length < 3) return;
                    
                    let user = '';
                    let userInputs = Array.from(container.querySelectorAll('input[type="email"], input[type="text"], input[autocomplete*="username"], input[name*="user"], input[name*="login"], input[id*="user"], input[id*="login"]'));
                    for (let u of userInputs) {
                        if (u.value && u.value.trim().length > 0) {
                            user = u.value.trim();
                            break;
                        }
                    }
                    
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.onyxSavePasswordPrompt) {
                        window.webkit.messageHandlers.onyxSavePasswordPrompt.postMessage({
                            username: user,
                            password: pass,
                            url: window.location.href,
                            title: document.title || window.location.hostname
                        });
                    }
                } catch(e) {}
            }
            
            document.addEventListener('submit', function(e) {
                if (e.target) checkAndNotify(e.target);
            }, true);
            
            document.addEventListener('click', function(e) {
                let btn = e.target.closest('button, input[type="submit"], [role="button"]');
                if (!btn) return;
                let form = btn.closest('form') || document;
                checkAndNotify(form);
            }, true);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    /// Shown instead of a success toast when the vault could not be loaded and refuses writes.
    func showVaultNotSavedToast() {
        showVaultToastHUD(icon: "lock.trianglebadge.exclamationmark", title: "NOT SAVED", message: "Vault is locked; relaunch Onyx to retry")
    }
    
    /// Launch-time explanation of why the vault is locked.
    func vaultLockedMessage() -> String {
        switch passwordStore.loadFailure {
        case .keychainError(let status)?:
            return "Keychain access failed (\(status)); saving disabled"
        case .unreadable?:
            return "Vault data unreadable; left untouched, saving disabled"
        case nil:
            return "Saving passwords is disabled"
        }
    }
    
    func handleSavePasswordPromptMessage(_ dict: [String: Any], from webView: WKWebView) {
        guard UserDefaults.standard.object(forKey: "OnyxOfferSavePasswords") as? Bool ?? true else { return }
        // Don't offer to save into a vault that cannot persist anything.
        guard passwordStore.canPersist else { return }
        let username = (dict["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = (dict["password"] as? String) ?? ""
        // Use the tab's real URL, never the page-supplied one: a page could otherwise
        // get credentials filed under another site's domain.
        let urlStr = webView.url?.absoluteString ?? ""
        let title = webView.title ?? (dict["title"] as? String) ?? "Login"
        
        guard password.count >= 3 else { return }
        
        let parsedURL = URL(string: urlStr)
        let domain: String
        if let h = parsedURL?.host, !h.isEmpty {
            domain = h
        } else if parsedURL?.isFileURL == true {
            domain = parsedURL?.lastPathComponent ?? "Local File"
        } else {
            domain = urlStr
        }
        let existing = passwordStore.allEntries().first(where: {
            $0.matches(host: domain) && $0.username.lowercased() == username.lowercased() && $0.password == password
        })
        if existing != nil { return }
        
        activeSavePromptHUD?.removeFromSuperview()
        
        let hud = OnyxSavePasswordHUD(username: username, password: password, urlString: urlStr, title: title)
        hud.onSave = { [weak self] in
            let newEntry = OnyxPasswordEntry(
                title: title.isEmpty ? domain : title,
                urlString: urlStr,
                username: username,
                password: password
            )
            guard let self = self else { return }
            let persisted = self.passwordStore.addOrUpdate(newEntry)
            self.updatePasswordsBadge(for: self.activeWebView.url)
            if persisted {
                self.showVaultToastHUD(icon: "checkmark.shield.fill", title: "LOGIN SAVED", message: "Saved credentials for \(domain)")
            } else {
                self.showVaultNotSavedToast()
            }
        }
        
        webContainerView.addSubview(hud)
        self.activeSavePromptHUD = hud
        
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: webContainerView.topAnchor, constant: 16),
            hud.centerXAnchor.constraint(equalTo: webContainerView.centerXAnchor),
            hud.widthAnchor.constraint(equalToConstant: 480),
            hud.heightAnchor.constraint(equalToConstant: 56)
        ])
        hud.animateIn()
    }
}
