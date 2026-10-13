import Cocoa
import WebKit
import UniformTypeIdentifiers

extension BrowserController {
    // MARK: - Toolbar Extensions & Pinning System Implementation
    func applyToolbarPins() {
        suggestedTabsBtn.isHidden = !OnyxToolbarTool.aiResearch.isPinned
        downloadsButton.isHidden = !OnyxToolbarTool.downloads.isPinned
        passwordsButton.isHidden = !OnyxToolbarTool.passwords.isPinned
        shieldButton.isHidden = !OnyxToolbarTool.shield.isPinned
    }
    
    func setupExtensionContextMenus() {
        let tools: [(OnyxToolbarTool, NSButton)] = [
            (.aiResearch, suggestedTabsBtn),
            (.downloads, downloadsButton),
            (.passwords, passwordsButton),
            (.shield, shieldButton)
        ]
        
        for (tool, btn) in tools {
            let menu = NSMenu(title: tool.title)
            
            let titleItem = NSMenuItem(title: tool.title, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            if let icon = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                titleItem.image = icon.withSymbolConfiguration(cfg)
            }
            menu.addItem(titleItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let unpinItem = NSMenuItem(title: "Unpin from Toolbar", action: #selector(togglePinFromMenu(_:)), keyEquivalent: "")
            unpinItem.target = self
            unpinItem.representedObject = tool
            if let pinIcon = NSImage(systemSymbolName: "pin.slash", accessibilityDescription: nil) {
                unpinItem.image = pinIcon.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
            }
            menu.addItem(unpinItem)
            
            let openItem = NSMenuItem(title: "Open " + tool.title, action: #selector(openToolFromMenu(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = tool
            menu.addItem(openItem)
            
            btn.menu = menu
        }
    }
    
    @objc func togglePinFromMenu(_ sender: NSMenuItem) {
        guard let tool = sender.representedObject as? OnyxToolbarTool else { return }
        tool.setPinned(!tool.isPinned)
        applyToolbarPins()
        if let pop = extensionsPopover, pop.isShown {
            showExtensionsPopover()
        }
    }
    
    @objc func openToolFromMenu(_ sender: NSMenuItem) {
        guard let tool = sender.representedObject as? OnyxToolbarTool else { return }
        launchTool(tool)
    }
    
    func launchTool(_ tool: OnyxToolbarTool) {
        switch tool {
        case .aiResearch:
            showSuggestedTabsPopover()
        case .downloads:
            toggleDownloadsPopover()
        case .passwords:
            togglePasswordsPopover()
        case .shield:
            showPrivacyReport()
        }
    }
    
    @objc func toggleExtensionsPopover() {
        if let pop = extensionsPopover, pop.isShown {
            pop.performClose(nil)
            return
        }
        showExtensionsPopover()
    }
    
    func showExtensionsPopover() {
        extensionsPopover?.performClose(nil)
        
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        
        let width: CGFloat = 290
        let height: CGFloat = 250
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
        
        // Header (44px)
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        
        let headerIcon = NSImageView()
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: "Extensions") {
            headerIcon.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
            headerIcon.contentTintColor = .white
        }
        header.addSubview(headerIcon)
        
        let titleStack = NSStackView()
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.orientation = .vertical
        titleStack.spacing = 1
        titleStack.alignment = .leading
        header.addSubview(titleStack)
        
        let headerTitle = NSTextField(labelWithString: "EXTENSIONS & TOOLS")
        headerTitle.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        headerTitle.textColor = .white
        titleStack.addArrangedSubview(headerTitle)
        
        let headerSubtitle = NSTextField(labelWithString: "Pin to toolbar or quick launch")
        headerSubtitle.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        headerSubtitle.textColor = NSColor(white: 0.50, alpha: 1.0)
        titleStack.addArrangedSubview(headerSubtitle)
        
        let headerSep = NSBox()
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        headerSep.boxType = .custom
        headerSep.borderWidth = 0
        headerSep.fillColor = NSColor(white: 1.0, alpha: 0.08)
        header.addSubview(headerSep)
        
        // Rows stack
        let listStack = NSStackView()
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.orientation = .vertical
        listStack.spacing = 4
        listStack.alignment = .leading
        container.addSubview(listStack)
        
        for tool in OnyxToolbarTool.allCases {
            let row = createExtensionRowView(tool: tool, onPinToggle: { [weak self] in
                tool.setPinned(!tool.isPinned)
                self?.applyToolbarPins()
                self?.showExtensionsPopover()
            }, onLaunch: { [weak self, weak popover] in
                popover?.performClose(nil)
                self?.launchTool(tool)
            })
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            row.leadingAnchor.constraint(equalTo: listStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: listStack.trailingAnchor).isActive = true
        }
        
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),
            container.heightAnchor.constraint(equalToConstant: height),
            
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            
            headerIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            headerIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerIcon.widthAnchor.constraint(equalToConstant: 18),
            headerIcon.heightAnchor.constraint(equalToConstant: 18),
            
            titleStack.leadingAnchor.constraint(equalTo: headerIcon.trailingAnchor, constant: 10),
            titleStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            
            headerSep.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            headerSep.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerSep.heightAnchor.constraint(equalToConstant: 1),
            
            listStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            listStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            listStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            listStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8)
        ])
        
        let vc = NSViewController()
        vc.view = container
        popover.contentViewController = vc
        self.extensionsPopover = popover
        
        popover.show(relativeTo: extensionsButton.bounds, of: extensionsButton, preferredEdge: .maxY)
        if let popWin = container.window {
            popWin.isOpaque = false
            popWin.backgroundColor = .clear
        }
    }
    
    func createExtensionRowView(tool: OnyxToolbarTool, onPinToggle: @escaping () -> Void, onLaunch: @escaping () -> Void) -> NSView {
        class ExtensionRowItemView: NSView {
            var onLaunch: (() -> Void)?
            private var trackingArea: NSTrackingArea?
            
            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                if let ta = trackingArea { removeTrackingArea(ta) }
                trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
                addTrackingArea(trackingArea!)
            }
            
            override func mouseEntered(with event: NSEvent) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    Motion.prepare(ctx)
                    self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
                    self.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
                }
            }
            
            override func mouseExited(with event: NSEvent) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    Motion.prepare(ctx)
                    self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.02).cgColor
                    self.layer?.borderColor = NSColor(white: 1.0, alpha: 0.06).cgColor
                }
            }
            
            override func mouseUp(with event: NSEvent) {
                let loc = convert(event.locationInWindow, from: nil)
                if bounds.contains(loc) {
                    onLaunch?()
                }
            }
        }
        
        let row = ExtensionRowItemView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.02).cgColor
        row.layer?.borderWidth = 1
        row.layer?.borderColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        row.onLaunch = onLaunch
        
        // Icon Plate
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 6
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        row.addSubview(iconPlate)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: tool.iconName, accessibilityDescription: tool.title) {
            iconView.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
            iconView.contentTintColor = tool.isPinned ? .white : NSColor(white: 0.70, alpha: 1.0)
        }
        iconPlate.addSubview(iconView)
        
        // Text Stack
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        row.addSubview(textStack)
        
        let titleLabel = NSTextField(labelWithString: tool.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        textStack.addArrangedSubview(titleLabel)
        
        let subLabel = NSTextField(labelWithString: tool.subtitle)
        subLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        subLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        textStack.addArrangedSubview(subLabel)
        
        // Pin Button
        let pinBtn = NSButton()
        pinBtn.translatesAutoresizingMaskIntoConstraints = false
        pinBtn.bezelStyle = .regularSquare
        pinBtn.isBordered = false
        pinBtn.wantsLayer = true
        pinBtn.layer?.cornerRadius = 5
        pinBtn.layer?.backgroundColor = tool.isPinned ? NSColor(white: 1.0, alpha: 0.18).cgColor : NSColor(white: 1.0, alpha: 0.04).cgColor
        pinBtn.layer?.borderWidth = 1
        pinBtn.layer?.borderColor = tool.isPinned ? NSColor(white: 1.0, alpha: 0.30).cgColor : NSColor(white: 1.0, alpha: 0.08).cgColor
        pinBtn.toolTip = tool.isPinned ? "Unpin from toolbar" : "Pin to toolbar"
        
        let pinIconName = tool.isPinned ? "pin.fill" : "pin"
        if let pinImg = NSImage(systemSymbolName: pinIconName, accessibilityDescription: "Pin") {
            pinBtn.image = pinImg.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            pinBtn.contentTintColor = tool.isPinned ? .white : NSColor(white: 0.45, alpha: 1.0)
        }
        
        class PinActionHandler: NSObject {
            let act: () -> Void
            init(_ act: @escaping () -> Void) { self.act = act }
            @objc func trigger() { act() }
        }
        let handler = PinActionHandler(onPinToggle)
        objc_setAssociatedObject(pinBtn, "pinHandler", handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        pinBtn.target = handler
        pinBtn.action = #selector(PinActionHandler.trigger)
        row.addSubview(pinBtn)
        
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 44),
            
            iconPlate.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            iconPlate.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 26),
            iconPlate.heightAnchor.constraint(equalToConstant: 26),
            
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            
            textStack.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 8),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: pinBtn.leadingAnchor, constant: -6),
            
            pinBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            pinBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            pinBtn.widthAnchor.constraint(equalToConstant: 24),
            pinBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return row
    }
}
