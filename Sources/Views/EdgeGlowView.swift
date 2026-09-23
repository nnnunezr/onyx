import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Navigation Direction & Edge Glow Engine
enum NavigationDirection {
    case back
    case forward
}

class DirectionalEdgeGlowView: NSView {
    private let gradientLayer = CAGradientLayer()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.masksToBounds = true
        
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradientLayer)
        alphaValue = 0.0
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Mouse clicks always pass through to the active web view
    }
    
    func flash(edge: NavigationDirection, color: NSColor) {
        self.layer?.removeAllAnimations()
        gradientLayer.removeAllAnimations()
        
        let clearColor = NSColor.clear.cgColor
        let glowColor = color.cgColor
        
        if edge == .back {
            gradientLayer.colors = [glowColor, clearColor]
            gradientLayer.locations = [0.0, 0.14]
        } else {
            gradientLayer.colors = [clearColor, glowColor]
            gradientLayer.locations = [0.86, 1.0]
        }
        
        self.alphaValue = 1.0
        
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 1.0
        fadeAnim.toValue = 0.0
        fadeAnim.duration = 0.32
        fadeAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        fadeAnim.fillMode = .forwards
        fadeAnim.isRemovedOnCompletion = false
        
        self.layer?.add(fadeAnim, forKey: "fadeGlow")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
            self?.alphaValue = 0.0
            self?.layer?.removeAllAnimations()
        }
    }
}
