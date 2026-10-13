import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Passwords Navigation Button (Key Icon with Dynamic Match Indicator)
class PasswordsNavButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var matchIndicator: NSView!
    private(set) var hasMatch: Bool = false
    
    init(target: AnyObject?, action: Selector, size: CGFloat = 28) {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.wantsLayer = true
        self.toolTip = "Passwords & Vault (⌘⌥P)"
        self.target = target
        self.action = action
        self.layer?.cornerRadius = 5
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        let iconPointSize: CGFloat = (size <= 24) ? 10 : 12
        if let img = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Passwords") {
            let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
            self.image = img.withSymbolConfiguration(config)
            self.contentTintColor = NSColor(white: 0.82, alpha: 1.0)
        }
        
        matchIndicator = NSView()
        matchIndicator.translatesAutoresizingMaskIntoConstraints = false
        matchIndicator.wantsLayer = true
        matchIndicator.layer?.cornerRadius = 2.5
        matchIndicator.layer?.backgroundColor = NSColor.white.cgColor
        matchIndicator.layer?.shadowColor = NSColor.white.cgColor
        matchIndicator.layer?.shadowOpacity = 0.8
        matchIndicator.layer?.shadowRadius = 3
        matchIndicator.layer?.shadowOffset = .zero
        matchIndicator.isHidden = true
        addSubview(matchIndicator)
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: size),
            self.heightAnchor.constraint(equalToConstant: size),
            matchIndicator.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            matchIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            matchIndicator.widthAnchor.constraint(equalToConstant: 5),
            matchIndicator.heightAnchor.constraint(equalToConstant: 5)
        ])
        self.setContentHuggingPriority(.required, for: .horizontal)
        self.setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func setHasMatch(_ match: Bool) {
        hasMatch = match
        matchIndicator.isHidden = !match
        if match {
            contentTintColor = NSColor.white
            toolTip = "✦ Saved Logins Available for Active Site (⌘⌥P)"
        } else {
            contentTintColor = NSColor(white: 0.82, alpha: 1.0)
            toolTip = "Passwords & Vault (⌘⌥P)"
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if let m = self.menu {
            NSMenu.popUpContextMenu(m, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

// MARK: - Onyx Password Row View
class OnyxPasswordRowView: NSView {
    let entry: OnyxPasswordEntry
    let isCurrentSite: Bool
    var isPasswordVisible = false
    var onAutofill: ((OnyxPasswordEntry) -> Void)?
    var onCopyPassword: ((OnyxPasswordEntry) -> Void)?
    var onCopyUsername: ((OnyxPasswordEntry) -> Void)?
    var onEdit: ((OnyxPasswordEntry) -> Void)?
    var onDelete: ((OnyxPasswordEntry) -> Void)?
    
    private var trackingArea: NSTrackingArea?
    private var passwordLabel: NSTextField!
    private var eyeButton: NSButton!
    
    init(entry: OnyxPasswordEntry, isCurrentSite: Bool = false) {
        self.entry = entry
        self.isCurrentSite = isCurrentSite
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = isCurrentSite ? NSColor(white: 1.0, alpha: 0.10).cgColor : NSColor.clear.cgColor
        if isCurrentSite {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(white: 1.0, alpha: 0.20).cgColor
        }
        
        // Left monogram icon plate (36x36)
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 8
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        addSubview(iconPlate)
        
        let monogram = NSTextField(labelWithString: String(entry.title.prefix(1)).uppercased())
        monogram.translatesAutoresizingMaskIntoConstraints = false
        monogram.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        monogram.textColor = .white
        iconPlate.addSubview(monogram)
        
        // Text info stack
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        addSubview(textStack)
        
        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 6
        titleRow.alignment = .centerY
        
        let titleLabel = NSTextField(labelWithString: entry.title)
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleRow.addArrangedSubview(titleLabel)
        
        if isCurrentSite {
            let matchPill = NSTextField(labelWithString: "Active Site")
            matchPill.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
            matchPill.textColor = .white
            matchPill.wantsLayer = true
            matchPill.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.14).cgColor
            matchPill.layer?.borderColor = NSColor(white: 1.0, alpha: 0.22).cgColor
            matchPill.layer?.borderWidth = 1
            matchPill.layer?.cornerRadius = 4
            titleRow.addArrangedSubview(matchPill)
        }
        textStack.addArrangedSubview(titleRow)
        
        let userLabel = NSTextField(labelWithString: entry.username.isEmpty ? entry.domain : entry.username)
        userLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        userLabel.textColor = NSColor(white: 0.72, alpha: 1.0)
        userLabel.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(userLabel)
        
        let passLabel = NSTextField(labelWithString: "••••••••••••")
        passLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        passLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        textStack.addArrangedSubview(passLabel)
        self.passwordLabel = passLabel
        
        // Right Action Buttons
        let actionsStack = NSStackView()
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 4
        actionsStack.alignment = .centerY
        addSubview(actionsStack)
        
        // Eye button (toggle reveal)
        eyeButton = createIconButton(systemName: "eye", tooltip: "Reveal Password") { [weak self] in
            guard let self = self else { return }
            self.isPasswordVisible.toggle()
            if self.isPasswordVisible {
                self.passwordLabel.stringValue = self.entry.password
                self.passwordLabel.textColor = NSColor(white: 0.95, alpha: 1.0)
                if let img = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide Password") {
                    self.eyeButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
                }
            } else {
                self.passwordLabel.stringValue = "••••••••••••"
                self.passwordLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
                if let img = NSImage(systemSymbolName: "eye", accessibilityDescription: "Reveal Password") {
                    self.eyeButton.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
                }
            }
        }
        actionsStack.addArrangedSubview(eyeButton)
        
        // Copy password button
        let copyPassBtn = createIconButton(systemName: "key.fill", tooltip: "Copy Password") { [weak self] in
            guard let self = self else { return }
            self.onCopyPassword?(self.entry)
        }
        actionsStack.addArrangedSubview(copyPassBtn)
        
        // Copy username button
        let copyUserBtn = createIconButton(systemName: "person.fill", tooltip: "Copy Username") { [weak self] in
            guard let self = self else { return }
            self.onCopyUsername?(self.entry)
        }
        actionsStack.addArrangedSubview(copyUserBtn)
        
        // Quick autofill button (if matching site)
        if isCurrentSite {
            let autofillBtn = createIconButton(systemName: "sparkles", tooltip: "Autofill in Active Tab") { [weak self] in
                guard let self = self else { return }
                self.onAutofill?(self.entry)
            }
            autofillBtn.contentTintColor = .white
            actionsStack.addArrangedSubview(autofillBtn)
        }
        
        // Edit button
        let editBtn = createIconButton(systemName: "pencil", tooltip: "Edit Login") { [weak self] in
            guard let self = self else { return }
            self.onEdit?(self.entry)
        }
        actionsStack.addArrangedSubview(editBtn)
        
        // Delete button
        let deleteBtn = createIconButton(systemName: "trash", tooltip: "Delete") { [weak self] in
            guard let self = self else { return }
            self.onDelete?(self.entry)
        }
        actionsStack.addArrangedSubview(deleteBtn)
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 60),
            
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 36),
            iconPlate.heightAnchor.constraint(equalToConstant: 36),
            
            monogram.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            monogram.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            
            textStack.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func createIconButton(systemName: String, tooltip: String, action: @escaping () -> Void) -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 4
        btn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        btn.toolTip = tooltip
        if let img = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip) {
            btn.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            btn.contentTintColor = NSColor(white: 0.80, alpha: 1.0)
        }
        
        class ActionHandler: NSObject {
            let act: () -> Void
            init(_ act: @escaping () -> Void) { self.act = act }
            @objc func trigger() { act() }
        }
        let handler = ActionHandler(action)
        objc_setAssociatedObject(btn, "btnActionHandler", handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        btn.target = handler
        btn.action = #selector(ActionHandler.trigger)
        
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 24),
            btn.heightAnchor.constraint(equalToConstant: 24)
        ])
        return btn
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
            self.layer?.backgroundColor = self.isCurrentSite ? NSColor(white: 1.0, alpha: 0.15).cgColor : NSColor(white: 1.0, alpha: 0.08).cgColor
            self.layer?.borderColor = self.isCurrentSite ? NSColor(white: 1.0, alpha: 0.25).cgColor : NSColor(white: 1.0, alpha: 0.16).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
            self.layer?.backgroundColor = self.isCurrentSite ? NSColor(white: 1.0, alpha: 0.10).cgColor : NSColor.clear.cgColor
            self.layer?.borderColor = self.isCurrentSite ? NSColor(white: 1.0, alpha: 0.20).cgColor : NSColor.clear.cgColor
        }
    }
}

// MARK: - Save Password Prompt HUD (Apple Obsidian Liquid Glass)
class OnyxSavePasswordHUD: NSVisualEffectView {
    var onSave: (() -> Void)?
    var onDismiss: (() -> Void)?
    
    init(username: String, password: String, urlString: String, title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.20).cgColor
        layer?.backgroundColor = NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 0.35).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.50
        layer?.shadowOffset = CGSize(width: 0, height: -5)
        layer?.shadowRadius = 20
        
        // Left Icon Squircle Plate (36x36)
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 10
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        addSubview(iconPlate)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Onyx Vault") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = .white
        }
        iconPlate.addSubview(iconView)
        
        // Text Stack
        let parsedURL = URL(string: urlString)
        let domain = (parsedURL?.host?.isEmpty == false) ? parsedURL!.host! : (title.isEmpty ? urlString : title)
        let cleanDomain = domain.replacingOccurrences(of: "www.", with: "")
        let displayUser = username.isEmpty ? "this site" : username
        
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        addSubview(textStack)
        
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY
        
        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = NSColor.white.cgColor
        dot.layer?.shadowColor = NSColor.white.cgColor
        dot.layer?.shadowRadius = 4
        dot.layer?.shadowOpacity = 0.8
        dot.layer?.shadowOffset = .zero
        topRow.addArrangedSubview(dot)
        
        let headLabel = NSTextField(labelWithString: "ONYX VAULT")
        headLabel.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold)
        headLabel.textColor = NSColor(white: 0.75, alpha: 1.0)
        topRow.addArrangedSubview(headLabel)
        
        let promptLabel = NSTextField(labelWithString: "• Save login for \(cleanDomain)?")
        promptLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        promptLabel.textColor = .white
        promptLabel.lineBreakMode = .byTruncatingTail
        topRow.addArrangedSubview(promptLabel)
        textStack.addArrangedSubview(topRow)
        
        let subLabel = NSTextField(labelWithString: "\(displayUser) • Encrypted local keychain")
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subLabel.textColor = NSColor(white: 0.55, alpha: 1.0)
        subLabel.lineBreakMode = .byTruncatingMiddle
        textStack.addArrangedSubview(subLabel)
        
        // Action Buttons Stack
        let btnStack = NSStackView()
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        btnStack.orientation = .horizontal
        btnStack.spacing = 8
        btnStack.alignment = .centerY
        addSubview(btnStack)
        
        let notNowBtn = NSButton()
        notNowBtn.translatesAutoresizingMaskIntoConstraints = false
        notNowBtn.bezelStyle = .regularSquare
        notNowBtn.isBordered = false
        notNowBtn.wantsLayer = true
        notNowBtn.layer?.cornerRadius = 7
        notNowBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        notNowBtn.layer?.borderWidth = 1
        notNowBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        notNowBtn.setMonochromeTitle("Not Now", color: NSColor(white: 0.85, alpha: 1.0), font: NSFont.systemFont(ofSize: 11.5, weight: .medium))
        notNowBtn.target = self
        notNowBtn.action = #selector(notNowClicked)
        btnStack.addArrangedSubview(notNowBtn)
        
        let saveBtn = NSButton()
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.bezelStyle = .regularSquare
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.cornerRadius = 7
        saveBtn.layer?.backgroundColor = NSColor.white.cgColor
        saveBtn.layer?.borderWidth = 1
        saveBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.35).cgColor
        saveBtn.setMonochromeTitle("Save Password", color: NSColor(red: 10/255.0, green: 10/255.0, blue: 14/255.0, alpha: 1.0), font: NSFont.systemFont(ofSize: 11.5, weight: .semibold))
        saveBtn.target = self
        saveBtn.action = #selector(saveClicked)
        btnStack.addArrangedSubview(saveBtn)
        
        let closeBtn = NSButton()
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.bezelStyle = .regularSquare
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.cornerRadius = 11
        closeBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
        if let ximg = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close") {
            closeBtn.image = ximg.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold))
            closeBtn.contentTintColor = NSColor(white: 0.65, alpha: 1.0)
        }
        closeBtn.target = self
        closeBtn.action = #selector(notNowClicked)
        btnStack.addArrangedSubview(closeBtn)
        
        NSLayoutConstraint.activate([
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 36),
            iconPlate.heightAnchor.constraint(equalToConstant: 36),
            
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            
            textStack.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: btnStack.leadingAnchor, constant: -12),
            
            btnStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            btnStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            notNowBtn.heightAnchor.constraint(equalToConstant: 28),
            notNowBtn.widthAnchor.constraint(equalToConstant: 76),
            saveBtn.heightAnchor.constraint(equalToConstant: 28),
            saveBtn.widthAnchor.constraint(equalToConstant: 108),
            closeBtn.heightAnchor.constraint(equalToConstant: 22),
            closeBtn.widthAnchor.constraint(equalToConstant: 22)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    @objc private func notNowClicked() {
        onDismiss?()
        dismiss()
    }
    
    @objc private func saveClicked() {
        onSave?()
        dismiss()
    }
    
    func animateIn() {
        alphaValue = 0
        let transform = CATransform3DMakeTranslation(0, -12, 0)
        layer?.transform = transform
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            Motion.prepare(ctx)
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().alphaValue = 1.0
            self.layer?.transform = CATransform3DIdentity
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.dismiss()
        }
    }
    
    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            Motion.prepare(ctx)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.removeFromSuperview()
        })
    }
}
