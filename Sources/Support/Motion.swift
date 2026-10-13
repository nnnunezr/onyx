import Cocoa

// MARK: - Motion
/// Shared animation rules for native UI.
/// - `prepare(_:)` goes after a group's `ctx.duration`: it turns on implicit animation, without
///   which layer properties set inside `runAnimationGroup` (background, border, shadow) snap
///   instead of animating, and makes the group instant under Reduce Motion.
/// - `centerScale` pulses a layer-backed view around its center. NSView layers have their anchor
///   at the bottom-left corner, so a plain `transform.scale` grew the view from that corner.
enum Motion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func prepare(_ ctx: NSAnimationContext) {
        ctx.allowsImplicitAnimation = true
        if reduceMotion { ctx.duration = 0 }
    }

    /// Transform that scales by `s` (and shifts by `dx`) around the layer's center.
    static func centered(_ layer: CALayer, scale s: CGFloat, dx: CGFloat = 0) -> CATransform3D {
        let w = layer.bounds.width, h = layer.bounds.height
        let ax = layer.anchorPoint.x * w, ay = layer.anchorPoint.y * h
        let cx = w / 2 - ax, cy = h / 2 - ay
        var t = CATransform3DMakeTranslation(cx + dx, cy, 0)
        t = CATransform3DScale(t, s, s, 1)
        return CATransform3DTranslate(t, -cx, -cy, 0)
    }

    static func centerScale(_ layer: CALayer?, scales: [CGFloat], shifts: [CGFloat]? = nil,
                            keyTimes: [NSNumber], duration: CFTimeInterval,
                            timing: CAMediaTimingFunction, key: String) {
        guard let layer = layer, !reduceMotion else { return }
        let anim = CAKeyframeAnimation(keyPath: "transform")
        anim.values = scales.enumerated().map { i, s in
            NSValue(caTransform3D: centered(layer, scale: s, dx: shifts?[i] ?? 0))
        }
        anim.keyTimes = keyTimes
        anim.duration = duration
        anim.timingFunction = timing
        layer.add(anim, forKey: key)
    }
}
