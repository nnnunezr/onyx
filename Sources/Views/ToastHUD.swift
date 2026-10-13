import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Universal Onyx Toast HUD
class OnyxToastHUD: NSView {
    /// Purely informational: clicks go through to the page underneath (it can sit over a
    /// trading page's buttons for several seconds).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(iconName: String, title: String, message: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.18).cgColor
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.45).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowRadius = 10
        
        let blur = NSVisualEffectView()
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 10
        blur.layer?.masksToBounds = true
        addSubview(blur)
        
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: title) {
            iconView.image = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            iconView.contentTintColor = .white
        }
        addSubview(iconView)
        
        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading
        addSubview(textStack)
        
        let headerLabel = NSTextField(labelWithString: title.uppercased())
        headerLabel.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        headerLabel.textColor = .white
        textStack.addArrangedSubview(headerLabel)
        
        let msgLabel = NSTextField(labelWithString: message)
        msgLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        msgLabel.textColor = .white
        msgLabel.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(msgLabel)
        
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func animateIn() {
        alphaValue = 0
        let transform = CATransform3DMakeTranslation(0, -10, 0)
        layer?.transform = transform
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            Motion.prepare(ctx)
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().alphaValue = 1.0
            self.layer?.transform = CATransform3DIdentity
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
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
