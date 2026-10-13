import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Download Models & Management
class OnyxDownloadItem: Identifiable {
    let id: UUID = UUID()
    weak var download: WKDownload?
    var filename: String
    var destinationURL: URL?
    var sourceURL: URL?
    var totalBytes: Int64 = 0
    var receivedBytes: Int64 = 0
    var progressFraction: Double = 0.0
    var state: State = .downloading
    let startDate: Date = Date()
    var finishDate: Date?
    var errorMessage: String?
    /// "Download Linked File As…" / "Save Image As…": ask where to save instead of ~/Downloads.
    var asksForLocation = false
    /// Script-started download (navigation type .other) in the main frame. If the server answers
    /// with a plain HTML page, it is opened in this web view instead of saved.
    weak var openPageInsteadWebView: WKWebView?
    
    enum State {
        case downloading
        case completed
        case failed
        case cancelled
    }
    
    init(download: WKDownload?, filename: String, sourceURL: URL?) {
        self.download = download
        self.filename = filename
        self.sourceURL = sourceURL
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        if totalBytes > 0 {
            return formatter.string(fromByteCount: totalBytes)
        } else if receivedBytes > 0 {
            return formatter.string(fromByteCount: receivedBytes)
        } else if let dest = destinationURL, let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path), let sz = attrs[.size] as? Int64 {
            return formatter.string(fromByteCount: sz)
        }
        return "Zero KB"
    }
    
    var iconName: String {
        let ext = (destinationURL?.pathExtension ?? (filename as NSString).pathExtension).lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff":
            return "photo"
        case "zip", "tar", "gz", "7z", "rar", "dmg", "pkg", "iso":
            return "archivebox"
        case "pdf", "doc", "docx", "pages", "txt", "md", "rtf":
            return "doc.text"
        case "swift", "js", "ts", "py", "html", "css", "json", "c", "cpp", "rs", "sh":
            return "curlybraces"
        case "mp3", "wav", "m4a", "flac", "aac":
            return "music.note"
        case "mp4", "mov", "mkv", "avi", "webm":
            return "film"
        case "xls", "xlsx", "numbers", "csv":
            return "tablecells"
        case "key", "ppt", "pptx":
            return "play.rectangle"
        default:
            return "doc"
        }
    }
}

// MARK: - Downloads Navigation Icon Button (Apple-style with progress & badge)
class DownloadsNavButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private let iconView = NSImageView()
    private let badgeDot = NSView()
    private let progressLayer = CAShapeLayer()
    
    var isDownloading: Bool = false {
        didSet { updateVisuals() }
    }
    var progress: Double = 0.0 {
        didSet { updateProgressRing() }
    }
    var hasUnseenFinished: Bool = false {
        didSet { updateVisuals() }
    }
    
    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.title = ""
        self.attributedTitle = NSAttributedString(string: "")
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.wantsLayer = true
        self.target = target
        self.action = action
        self.toolTip = "Downloads (⌘J)"
        self.layer?.cornerRadius = 6
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Downloads") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            iconView.image = img.withSymbolConfiguration(config)
            iconView.contentTintColor = NSColor(white: 0.82, alpha: 1.0)
        }
        addSubview(iconView)
        
        progressLayer.strokeColor = NSColor.white.cgColor
        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.lineWidth = 1.5
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0
        progressLayer.lineCap = .round
        layer?.addSublayer(progressLayer)
        
        badgeDot.translatesAutoresizingMaskIntoConstraints = false
        badgeDot.wantsLayer = true
        badgeDot.layer?.cornerRadius = 3
        badgeDot.layer?.backgroundColor = NSColor(white: 0.95, alpha: 1.0).cgColor
        badgeDot.layer?.shadowColor = NSColor.white.cgColor
        badgeDot.layer?.shadowOpacity = 0.8
        badgeDot.layer?.shadowRadius = 2
        badgeDot.isHidden = true
        addSubview(badgeDot)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
            
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            badgeDot.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            badgeDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            badgeDot.widthAnchor.constraint(equalToConstant: 6),
            badgeDot.heightAnchor.constraint(equalToConstant: 6)
        ])
        
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func layout() {
        super.layout()
        let radius: CGFloat = 10.0
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: -CGFloat.pi / 2, endAngle: 1.5 * CGFloat.pi, clockwise: false)
        progressLayer.path = path
    }
    
    func updateVisuals() {
        badgeDot.isHidden = !hasUnseenFinished || isDownloading
        if isDownloading {
            progressLayer.isHidden = false
            if let img = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Downloading") {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                iconView.image = img.withSymbolConfiguration(config)
                iconView.contentTintColor = NSColor.white
            }
        } else {
            progressLayer.isHidden = true
            if let img = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Downloads") {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                iconView.image = img.withSymbolConfiguration(config)
                iconView.contentTintColor = hasUnseenFinished ? NSColor.white : NSColor(white: 0.82, alpha: 1.0)
            }
        }
    }
    
    /// Progress arrives every 250 ms; the ring glides between ticks instead of stepping.
    func updateProgressRing() {
        let target = CGFloat(max(0.04, min(1.0, progress)))
        let current = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = target
        CATransaction.commit()
        guard !Motion.reduceMotion, target > current else { return }
        let glide = CABasicAnimation(keyPath: "strokeEnd")
        glide.fromValue = current
        glide.toValue = target
        glide.duration = 0.25
        glide.timingFunction = CAMediaTimingFunction(name: .linear)
        progressLayer.add(glide, forKey: "glide")
    }
    
    func triggerBounce() {
        Motion.centerScale(layer, scales: [1.0, 1.28, 0.92, 1.08, 1.0], keyTimes: [0, 0.3, 0.55, 0.8, 1.0],
                           duration: 0.38, timing: CAMediaTimingFunction(name: .easeInEaseOut), key: "bounce")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            self.iconView.contentTintColor = NSColor.white
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.updateVisuals()
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if let m = self.menu {
            NSMenu.popUpContextMenu(m, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

// MARK: - Flipped Clip View for Top-Aligned Scroll Views
class FlippedClipView: NSClipView {
    override var isFlipped: Bool { return true }
}

// MARK: - Onyx Download Row View (Popover row with live progress and actions)
class OnyxDownloadRowView: NSView {
    let item: OnyxDownloadItem
    var onShowInFinder: (() -> Void)?
    var onOpenFile: (() -> Void)?
    var onCancel: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    
    private let titleLabel = NSTextField()
    private let subLabel = NSTextField()
    private let progressBar = NSBox()
    private var progressWidthConstraint: NSLayoutConstraint?
    
    init(item: OnyxDownloadItem) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.clear.cgColor
        
        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 7
        iconPlate.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        addSubview(iconPlate)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: item.iconName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = NSColor(white: 0.88, alpha: 1.0)
        }
        iconPlate.addSubview(iconView)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.drawsBackground = false
        titleLabel.stringValue = item.filename
        titleLabel.font = NSFont.systemFont(ofSize: 12.0, weight: .medium)
        titleLabel.textColor = NSColor.white
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)
        
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.isBezeled = false
        subLabel.isEditable = false
        subLabel.drawsBackground = false
        subLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        subLabel.textColor = NSColor(white: 0.70, alpha: 1.0)
        addSubview(subLabel)
        
        let progressTrack = NSBox()
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.boxType = .custom
        progressTrack.borderWidth = 0
        progressTrack.fillColor = NSColor(white: 1.0, alpha: 0.08)
        progressTrack.layer?.cornerRadius = 1
        addSubview(progressTrack)
        
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.boxType = .custom
        progressBar.borderWidth = 0
        progressBar.fillColor = NSColor.white
        progressBar.layer?.cornerRadius = 1
        progressTrack.addSubview(progressBar)
        
        progressWidthConstraint = progressBar.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint?.isActive = true
        
        let actionsStack = NSStackView()
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        actionsStack.orientation = .horizontal
        actionsStack.spacing = 4
        actionsStack.alignment = .centerY
        addSubview(actionsStack)
        
        if case .downloading = item.state {
            let cancelBtn = NavIconButton(iconName: "xmark.circle", tooltip: "Cancel Download", target: self, action: #selector(cancelClicked))
            actionsStack.addArrangedSubview(cancelBtn)
        } else if case .completed = item.state {
            let finderBtn = NavIconButton(iconName: "magnifyingglass", tooltip: "Show in Finder", target: self, action: #selector(finderClicked))
            let openBtn = NavIconButton(iconName: "arrow.up.forward.app", tooltip: "Open File", target: self, action: #selector(openClicked))
            actionsStack.addArrangedSubview(finderBtn)
            actionsStack.addArrangedSubview(openBtn)
        }
        
        updateContent()
        
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            
            iconPlate.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconPlate.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 32),
            iconPlate.heightAnchor.constraint(equalToConstant: 32),
            
            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            
            subLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionsStack.leadingAnchor, constant: -8),
            
            progressTrack.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            progressTrack.topAnchor.constraint(equalTo: subLabel.bottomAnchor, constant: 3),
            progressTrack.trailingAnchor.constraint(equalTo: actionsStack.leadingAnchor, constant: -12),
            progressTrack.heightAnchor.constraint(equalToConstant: 2),
            
            progressBar.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressBar.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressBar.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actionsStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        if case .downloading = item.state {
            progressTrack.isHidden = false
        } else {
            progressTrack.isHidden = true
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func updateContent() {
        titleLabel.stringValue = item.filename
        switch item.state {
        case .downloading:
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let rec = formatter.string(fromByteCount: item.receivedBytes)
            if item.totalBytes > 0 {
                let tot = formatter.string(fromByteCount: item.totalBytes)
                let pct = Int(item.progressFraction * 100.0)
                subLabel.stringValue = "\(rec) of \(tot) (\(pct)%)"
                progressWidthConstraint?.constant = CGFloat(item.progressFraction) * 130.0
            } else {
                subLabel.stringValue = "\(rec) downloaded"
            }
        case .completed:
            subLabel.stringValue = "\(item.formattedSize) • Ready"
            subLabel.textColor = NSColor(white: 0.70, alpha: 1.0)
        case .failed:
            subLabel.stringValue = item.errorMessage ?? "Download failed"
            subLabel.textColor = NSColor(red: 248/255.0, green: 113/255.0, blue: 113/255.0, alpha: 1.0)
        case .cancelled:
            subLabel.stringValue = "Cancelled"
            subLabel.textColor = NSColor(white: 0.40, alpha: 1.0)
        }
    }
    
    @objc private func finderClicked() { onShowInFinder?() }
    @objc private func openClicked() { onOpenFile?() }
    @objc private func cancelClicked() { onCancel?() }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.05).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            Motion.prepare(ctx)
            self.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

// MARK: - Download Notification HUD Banner (Apple-style floating toast)
class DownloadNotificationHUD: NSView {
    let fileURL: URL
    private var trackingArea: NSTrackingArea?
    
    init(filename: String, fileURL: URL) {
        self.fileURL = fileURL
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.14).cgColor
        layer?.backgroundColor = NSColor(red: 18/255.0, green: 18/255.0, blue: 22/255.0, alpha: 0.94).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowRadius = 12
        
        let blur = NSVisualEffectView()
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        addSubview(blur)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Downloaded") {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = NSColor(red: 52/255.0, green: 211/255.0, blue: 153/255.0, alpha: 1.0)
        }
        addSubview(iconView)
        
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading
        addSubview(textStack)
        
        let headerLabel = NSTextField(labelWithString: "DOWNLOAD COMPLETE")
        headerLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        headerLabel.textColor = NSColor(red: 52/255.0, green: 211/255.0, blue: 153/255.0, alpha: 1.0)
        textStack.addArrangedSubview(headerLabel)
        
        let nameLabel = NSTextField(labelWithString: filename)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = NSColor.white
        nameLabel.lineBreakMode = .byTruncatingMiddle
        textStack.addArrangedSubview(nameLabel)
        
        let finderBtn = NSButton()
        finderBtn.translatesAutoresizingMaskIntoConstraints = false
        finderBtn.bezelStyle = .regularSquare
        finderBtn.isBordered = false
        finderBtn.wantsLayer = true
        finderBtn.layer?.cornerRadius = 6
        finderBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        finderBtn.layer?.borderWidth = 1
        finderBtn.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        finderBtn.attributedTitle = NSAttributedString(string: "Show in Finder", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ])
        finderBtn.target = self
        finderBtn.action = #selector(showInFinderClicked)
        addSubview(finderBtn)
        
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: finderBtn.leadingAnchor, constant: -10),
            
            finderBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            finderBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            finderBtn.heightAnchor.constraint(equalToConstant: 26),
            finderBtn.widthAnchor.constraint(equalToConstant: 96)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    @objc private func showInFinderClicked() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        dismiss()
    }
    
    override func mouseDown(with event: NSEvent) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        dismiss()
    }
    
    func animateIn() {
        alphaValue = 0
        let transform = CATransform3DMakeTranslation(0, -10, 0)
        layer?.transform = transform
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            Motion.prepare(ctx)
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().alphaValue = 1.0
            self.layer?.transform = CATransform3DIdentity
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            self?.dismiss()
        }
    }
    
    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            Motion.prepare(ctx)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.removeFromSuperview()
        })
    }
}
