import Cocoa
import WebKit
import UniformTypeIdentifiers

// MARK: - Jakub Antalik Thinking-Orbs Engine (Native 3D Canvas in Swift)
enum ThinkingOrbMode {
    case orbits      // Working / page loading
    case globe       // Searching / AI research query
    case wave        // Listening / audio / focus
    case breathing   // Idle calm ring
    case rubik       // Solving / deep synthesis
}

struct OrbDot {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
    var r: CGFloat
    var white: CGFloat
    var a: CGFloat
}

class ThinkingOrbView: NSView {
    var mode: ThinkingOrbMode = .orbits
    private var displayTimer: Timer?
    private var startTime: CFTimeInterval = 0
    
    override var isFlipped: Bool { return true }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func startAnimation(mode: ThinkingOrbMode = .orbits) {
        self.mode = mode
        self.isHidden = false
        if displayTimer == nil {
            startTime = CACurrentMediaTime()
            displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                // Safety net: never animate longer than 15 s (a missed stop used to keep the
                // main thread redrawing at 60 Hz forever). Freeze on the current frame.
                if CACurrentMediaTime() - self.startTime > 15 {
                    self.displayTimer?.invalidate()
                    self.displayTimer = nil
                    return
                }
                self.needsDisplay = true
            }
        }
    }
    
    func stopAnimation() {
        displayTimer?.invalidate()
        displayTimer = nil
        self.isHidden = true
        needsDisplay = true
    }
    
    private func hashD(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - floor(h)
    }
    
    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        return atan2(sin(a - b), cos(a - b))
    }
    
    private func project(yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double, x: Double, y: Double, z: Double) -> (Double, Double, Double) {
        let st = sin(tilt), ct = cos(tilt)
        let sy = sin(yaw), cyw = cos(yaw)
        let x1 = x * cyw + z * sy
        let z1 = -x * sy + z * cyw
        let y1 = y * ct - z1 * st
        let z2 = y * st + z1 * ct
        return (cx + x1 * scale, cy - y1 * scale, z2)
    }
    
    private func generateFrame(size: Double, t: Double) -> [OrbDot] {
        var dots: [OrbDot] = []
        let cx = size / 2.0
        let cy = size / 2.0
        let rScale = max(0.5, pow(size / 300.0, 0.6) * 1.6)
        
        switch mode {
        case .orbits:
            let R = (size / 2.0) * 0.84
            let orbitCount = 6
            let ghostCount = 18
            let particles = 2
            
            for orb in 0..<orbitCount {
                let h1 = hashD(Double(orb), 1.7)
                let h2 = hashD(Double(orb), 5.2)
                let h3 = hashD(Double(orb), 8.9)
                let ro = R * (0.45 + 0.52 * h1)
                let th = h1 * 2.0 * .pi
                let phi = acos(2.0 * h2 - 1.0)
                let nx = sin(phi) * cos(th)
                let ny = cos(phi)
                let nz = sin(phi) * sin(th)
                
                var ux = -ny, uy = nx, uz = 0.0
                let ul = max(1e-6, sqrt(ux * ux + uy * uy))
                ux /= ul; uy /= ul
                let vx = ny * uz - nz * uy
                let vy = nz * ux - nx * uz
                let vz = nx * uy - ny * ux
                let speed = (0.35 + 0.65 * h3) * (h3 > 0.5 ? 1.0 : -1.0) * 1.88
                
                for k in 0..<ghostCount {
                    let a = (Double(k) / Double(ghostCount)) * 2.0 * .pi
                    let (px, py, z) = project(yaw: t * 0.18, tilt: 0.32, cx: cx, cy: cy, scale: 1.0,
                                              x: (ux * cos(a) + vx * sin(a)) * ro,
                                              y: (uy * cos(a) + vy * sin(a)) * ro,
                                              z: (uz * cos(a) + vz * sin(a)) * ro)
                    let depth = (z / ro + 1.0) / 2.0
                    dots.append(OrbDot(x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                                       r: CGFloat(max(0.4, 0.75 * rScale)),
                                       white: 0.70,
                                       a: CGFloat(0.4 * (0.35 + 0.65 * depth))))
                }
                
                for m in 0..<particles {
                    let a = t * speed + (Double(m) / Double(particles)) * 2.0 * .pi + h2 * 6.0
                    let (px, py, z) = project(yaw: t * 0.18, tilt: 0.32, cx: cx, cy: cy, scale: 1.0,
                                              x: (ux * cos(a) + vx * sin(a)) * ro,
                                              y: (uy * cos(a) + vy * sin(a)) * ro,
                                              z: (uz * cos(a) + vz * sin(a)) * ro)
                    let depth = (z / ro + 1.0) / 2.0
                    dots.append(OrbDot(x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                                       r: CGFloat((1.1 + 1.4 * depth) * rScale),
                                       white: CGFloat(0.25 - 0.22 * depth),
                                       a: 0.95))
                }
            }
            
        case .globe:
            let spin = 0.65
            let radius = (size / 2.0) * 0.84
            let tilt = 0.4 + 0.06 * sin(t * 0.35)
            let scan = t * (spin + 1.5 * 3.8)
            let latRings = 8
            let lonDensity = 20
            
            for li in 0...latRings {
                let lat = -.pi / 2.0 + (Double(li) / Double(latRings)) * .pi
                let cosLat = cos(lat), sinLat = sin(lat)
                let lonCount = max(1, Int(abs(cosLat) * Double(lonDensity)))
                for lj in 0..<lonCount {
                    let lon = (Double(lj) / Double(lonCount)) * 2.0 * .pi
                    let (px, py, z) = project(yaw: t * spin, tilt: tilt, cx: cx, cy: cy, scale: radius,
                                              x: cosLat * cos(lon), y: sinLat, z: cosLat * sin(lon))
                    let depth = (z + 1.0) / 2.0
                    let d = angleDelta(lon + t * spin, scan)
                    let boost = exp(-(d * d) / 0.22) * max(0.0, z)
                    dots.append(OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                        r: CGFloat((0.6 + 1.4 * depth + 1.2 * boost) * rScale),
                        white: CGFloat(0.60 - 0.50 * depth),
                        a: CGFloat(0.40 + 0.60 * min(1.0, boost))
                    ))
                }
            }
            
        case .wave:
            let R = (size / 2.0) * 0.85
            let rings = 8
            let lonDensity = 18
            for ri in 0...rings {
                let lat = -.pi / 2.0 + (Double(ri) / Double(rings)) * .pi
                let cosLat = cos(lat), sinLat = sin(lat)
                let w = 0.62 * sin(t * 2.5 - Double(ri) * 0.6) + 0.38 * sin(t * 1.4 + Double(ri) * 0.9)
                let rr = R * (0.86 + 0.12 * w)
                let lonCount = max(1, Int(abs(cosLat) * Double(lonDensity)))
                for lj in 0..<lonCount {
                    let lon = (Double(lj) / Double(lonCount)) * 2.0 * .pi
                    let (px, py, z) = project(yaw: t * 0.2, tilt: 0.38, cx: cx, cy: cy, scale: 1.0,
                                              x: cosLat * cos(lon) * rr, y: sinLat * rr, z: cosLat * sin(lon) * rr)
                    let depth = (z / R + 1.0) / 2.0
                    let crest = max(0.0, w)
                    dots.append(OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                        r: CGFloat((0.6 + 1.4 * depth) * (1.0 + 0.4 * crest) * rScale),
                        white: CGFloat(0.62 - 0.52 * depth - 0.1 * crest),
                        a: CGFloat(0.45 + 0.55 * depth)
                    ))
                }
            }
            
        case .breathing:
            let R = (size / 2.0) * 0.78
            let wobAmp = 0.23 * 0.368
            let baseR = R / (1.0 + 0.85 * wobAmp)
            let lanes = 3, segs = 36
            for w in 0..<lanes {
                let laneOff = (Double(w) - Double(lanes - 1) / 2.0) * 0.08
                for k in 0..<segs {
                    let a = (Double(k) / Double(segs)) * 2.0 * .pi
                    let wob = (0.16 * sin(a * 3.0 - t * 1.8 + Double(w) * 0.25) + 0.07 * sin(a * 5.0 + t * 1.2)) * 0.368
                    let radial = 1.0 + wob
                    let x = cos(a) * (baseR * radial)
                    let y = sin(a) * (baseR * radial) + laneOff * baseR
                    let (px, py, z) = project(yaw: 0, tilt: 0.3, cx: cx, cy: cy, scale: 1.0, x: x, y: y, z: 0)
                    dots.append(OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                        r: CGFloat(1.2 * rScale),
                        white: 0.25,
                        a: CGFloat(0.55 + 0.45 * sin(t * 1.4 + a))
                    ))
                }
            }
            
        case .rubik:
            let R = (size / 2.0) * 0.82
            let latRings = 7, lonDensity = 16
            let spin = t * 0.55
            for li in 0...latRings {
                let lat = -.pi / 2.0 + (Double(li) / Double(latRings)) * .pi
                let cosLat = cos(lat), sinLat = sin(lat)
                let lonCount = max(1, Int(abs(cosLat) * Double(lonDensity)))
                for lj in 0..<lonCount {
                    let lon = (Double(lj) / Double(lonCount)) * 2.0 * .pi
                    let (px, py, z) = project(yaw: spin, tilt: 0.35 + 0.1 * sin(t * 0.9), cx: cx, cy: cy, scale: R,
                                              x: cosLat * cos(lon), y: sinLat, z: cosLat * sin(lon))
                    let depth = (z + 1.0) / 2.0
                    dots.append(OrbDot(
                        x: CGFloat(px), y: CGFloat(py), z: CGFloat(z),
                        r: CGFloat((0.6 + 1.5 * depth) * rScale),
                        white: CGFloat(0.60 - 0.50 * depth),
                        a: CGFloat(0.50 + 0.50 * depth)
                    ))
                }
            }
        }
        
        return dots.sorted { $0.z < $1.z }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let t = CACurrentMediaTime() - startTime
        let size = Double(min(bounds.width, bounds.height))
        guard size > 0 else { return }
        
        let frameDots = generateFrame(size: size, t: t)
        for d in frameDots {
            let alpha = max(0.0, min(1.0, d.a))
            let w = max(0.0, min(1.0, d.white))
            let g = 1.0 - w // Apple monochrome: bright white / silver dots on dark shell
            ctx.setFillColor(red: g, green: g, blue: g, alpha: alpha)
            ctx.fillEllipse(in: CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2.0, height: d.r * 2.0))
        }
    }
}
