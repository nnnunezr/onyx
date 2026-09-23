import Cocoa
import CoreGraphics

func createAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    let scale = size / 1024.0
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    
    // Inset for standard macOS icon margin (standard macOS Human Interface Guidelines)
    let margin = 82.0 * scale
    let iconRect = rect.insetBy(dx: margin, dy: margin)
    let cornerRadius = 185.0 * scale
    let cx = iconRect.midX
    let cy = iconRect.midY
    
    // 1. Soft drop shadow under the squircle
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14.0 * scale), blur: 28.0 * scale, color: NSColor(white: 0, alpha: 0.65).cgColor)
    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor(red: 7/255.0, green: 7/255.0, blue: 9/255.0, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    
    // 2. Base Squircle with Obsidian / Space Black Gradient
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        NSColor(red: 24/255.0, green: 24/255.0, blue: 30/255.0, alpha: 1.0).cgColor,
        NSColor(red: 13/255.0, green: 13/255.0, blue: 16/255.0, alpha: 1.0).cgColor,
        NSColor(red: 6/255.0, green: 6/255.0, blue: 8/255.0, alpha: 1.0).cgColor
    ] as CFArray
    let gradLocations: [CGFloat] = [0.0, 0.50, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: gradLocations) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
                               end: CGPoint(x: iconRect.midX, y: iconRect.minY),
                               options: [])
    }
    
    // Ambient central celestial glow (soft white bloom behind the orb)
    if let orbGlow = CGGradient(colorsSpace: colorSpace,
                                colors: [
                                    NSColor(white: 1.0, alpha: 0.08).cgColor,
                                    NSColor(white: 1.0, alpha: 0.03).cgColor,
                                    NSColor(white: 1.0, alpha: 0.0).cgColor
                                ] as CFArray,
                                locations: [0.0, 0.45, 1.0]) {
        ctx.drawRadialGradient(orbGlow,
                               startCenter: CGPoint(x: cx, y: cy),
                               startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy),
                               endRadius: 360.0 * scale,
                               options: [])
    }
    
    // Inner squircle rim highlight
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
    ctx.setLineWidth(1.8 * scale)
    ctx.addPath(squirclePath)
    ctx.strokePath()
    
    // 3. Floating Thinking-Orb Emblem (Directly derived from the Homepage Floating Orb)
    // We project 3D harmonic particle orbits with depth sorting and luminous node glow.
    
    struct ProjectedDot {
        var x: CGFloat
        var y: CGFloat
        var z: CGFloat
        var r: CGFloat
        var alpha: CGFloat
        var isBeacon: Bool
    }
    
    var dots: [ProjectedDot] = []
    
    // Projection helper: yaw, pitch/tilt
    func project(x: CGFloat, y: CGFloat, z: CGFloat, yaw: CGFloat, tilt: CGFloat, scale3D: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let st = sin(tilt), ct = cos(tilt)
        let sy = sin(yaw), cyw = cos(yaw)
        
        let x1 = x * cyw + z * sy
        let z1 = -x * sy + z * cyw
        let y1 = y * ct - z1 * st
        let z2 = y * st + z1 * ct
        return (cx + x1 * scale3D, cy + y1 * scale3D, z2)
    }
    
    // Main Breathing Ribbon (Homepage signature: multi-lane undulating particle ring)
    let ringRadius: CGFloat = 220.0 * scale
    let lanes = 5
    let segments = 84
    let ringTilt: CGFloat = 0.42 // ~24 deg tilt for Apple 3D depth
    let ringYaw: CGFloat = -0.25
    
    // Subtle underlying luminous track for silhouette readability at all sizes
    ctx.saveGState()
    ctx.setLineWidth(1.5 * scale)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.14).cgColor)
    let trackPath = CGMutablePath()
    for i in 0...100 {
        let a = CGFloat(i) / 100.0 * CGFloat.pi * 2
        let (px, py, _) = project(x: cos(a) * ringRadius, y: sin(a) * ringRadius * 0.96, z: 0, yaw: ringYaw, tilt: ringTilt, scale3D: 1.0)
        if i == 0 { trackPath.move(to: CGPoint(x: px, y: py)) }
        else { trackPath.addLine(to: CGPoint(x: px, y: py)) }
    }
    trackPath.closeSubpath()
    ctx.addPath(trackPath)
    ctx.strokePath()
    ctx.restoreGState()
    
    // Generate the breathing harmonic dots across lanes
    for lane in 0..<lanes {
        let laneOffset = (CGFloat(lane) - CGFloat(lanes - 1) / 2.0) * (14.0 * scale)
        let edgeFactor = abs(CGFloat(lane) - CGFloat(lanes - 1) / 2.0) / max(1.0, CGFloat(lanes - 1) / 2.0)
        
        for s in 0..<segments {
            let a = (CGFloat(s) / CGFloat(segments)) * CGFloat.pi * 2
            // Harmonic modulation matching Jakub Antalik wave
            let wobble = (0.09 * sin(a * 3.0 + CGFloat(lane) * 0.3) + 0.04 * sin(a * 5.0 - 0.4))
            let rMod = ringRadius * (1.0 + wobble)
            
            let x = cos(a) * rMod
            let y = sin(a) * rMod + laneOffset
            let z = sin(a * 2.0) * (16.0 * scale) // subtle 3D vertical curvature
            
            let (px, py, pz) = project(x: x, y: y, z: z, yaw: ringYaw, tilt: ringTilt, scale3D: 1.0)
            
            // Normalized depth (-1 to 1)
            let depthNorm = (pz / (ringRadius * 1.2) + 1.0) / 2.0
            let clampedDepth = max(0.0, min(1.0, depthNorm))
            
            // Front dots are larger and brighter
            let baseR = (2.2 + 3.4 * clampedDepth) * (1.0 - 0.22 * edgeFactor) * scale
            let alpha = (0.28 + 0.72 * pow(clampedDepth, 1.3)) * (1.0 - 0.18 * edgeFactor)
            
            dots.append(ProjectedDot(x: px, y: py, z: pz, r: max(1.0 * scale, baseR), alpha: alpha, isBeacon: false))
        }
    }
    
    // Secondary intersecting celestial orbit (from orbits mode - dynamic planetary / AI intelligence ring)
    let orbit2Radius: CGFloat = 195.0 * scale
    let orbit2Tilt: CGFloat = -0.58
    let orbit2Yaw: CGFloat = 0.78
    let orbit2Segments = 64
    
    // Second subtle guide path
    ctx.saveGState()
    ctx.setLineWidth(1.2 * scale)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
    let trackPath2 = CGMutablePath()
    for i in 0...100 {
        let a = CGFloat(i) / 100.0 * CGFloat.pi * 2
        let (px, py, _) = project(x: cos(a) * orbit2Radius, y: sin(a) * orbit2Radius, z: 0, yaw: orbit2Yaw, tilt: orbit2Tilt, scale3D: 1.0)
        if i == 0 { trackPath2.move(to: CGPoint(x: px, y: py)) }
        else { trackPath2.addLine(to: CGPoint(x: px, y: py)) }
    }
    trackPath2.closeSubpath()
    ctx.addPath(trackPath2)
    ctx.strokePath()
    ctx.restoreGState()
    
    for s in 0..<orbit2Segments {
        let a = (CGFloat(s) / CGFloat(orbit2Segments)) * CGFloat.pi * 2
        let x = cos(a) * orbit2Radius
        let y = sin(a) * orbit2Radius
        let z: CGFloat = 0
        let (px, py, pz) = project(x: x, y: y, z: z, yaw: orbit2Yaw, tilt: orbit2Tilt, scale3D: 1.0)
        let depthNorm = (pz / (orbit2Radius * 1.2) + 1.0) / 2.0
        let clampedDepth = max(0.0, min(1.0, depthNorm))
        let baseR = (1.8 + 2.8 * clampedDepth) * scale
        let alpha = (0.22 + 0.68 * pow(clampedDepth, 1.4))
        dots.append(ProjectedDot(x: px, y: py, z: pz, r: max(0.9 * scale, baseR), alpha: alpha, isBeacon: false))
    }
    
    // Primary Beacon Nodes (Glowing Satellite Particles along the trajectories)
    let beaconAngles: [(radius: CGFloat, angle: CGFloat, yaw: CGFloat, tilt: CGFloat)] = [
        (ringRadius * 1.05, 0.45, ringYaw, ringTilt),
        (ringRadius * 0.98, 2.25, ringYaw, ringTilt),
        (ringRadius * 1.02, 3.80, ringYaw, ringTilt),
        (ringRadius * 0.95, 5.35, ringYaw, ringTilt),
        (orbit2Radius, 1.10, orbit2Yaw, orbit2Tilt),
        (orbit2Radius, 4.30, orbit2Yaw, orbit2Tilt)
    ]
    
    for b in beaconAngles {
        let x = cos(b.angle) * b.radius
        let y = sin(b.angle) * b.radius
        let (px, py, pz) = project(x: x, y: y, z: 0, yaw: b.yaw, tilt: b.tilt, scale3D: 1.0)
        let depthNorm = (pz / (ringRadius * 1.2) + 1.0) / 2.0
        let clampedDepth = max(0.0, min(1.0, depthNorm))
        let beaconR = (4.5 + 4.5 * clampedDepth) * scale
        let alpha = 0.85 + 0.15 * clampedDepth
        dots.append(ProjectedDot(x: px, y: py, z: pz, r: beaconR, alpha: alpha, isBeacon: true))
    }
    
    // Luminous Central Nexus (Singularity Core)
    let coreR: CGFloat = 8.0 * scale
    dots.append(ProjectedDot(x: cx, y: cy, z: 0, r: coreR, alpha: 0.98, isBeacon: true))
    
    // Sort dots by Z depth (back to front painter's algorithm)
    dots.sort { $0.z < $1.z }
    
    // Draw all dots with soft optical bloom for beacons and crisp definition for orbital ring
    for dot in dots {
        ctx.saveGState()
        let dotRect = CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2)
        
        if dot.isBeacon {
            // Luminous halo around beacon nodes
            ctx.setShadow(offset: .zero, blur: 12.0 * scale, color: NSColor(white: 1.0, alpha: 0.85).cgColor)
            ctx.setFillColor(NSColor(white: 1.0, alpha: dot.alpha).cgColor)
            ctx.fillEllipse(in: dotRect)
            
            // Intense white core
            let innerCore = dotRect.insetBy(dx: dot.r * 0.35, dy: dot.r * 0.35)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: innerCore)
        } else {
            // Normal particle dot with subtle depth alpha
            if dot.z > 0 {
                // Foreground subtle bloom
                ctx.setShadow(offset: .zero, blur: 4.0 * scale, color: NSColor(white: 1.0, alpha: 0.4 * dot.alpha).cgColor)
            }
            ctx.setFillColor(NSColor(white: 1.0, alpha: dot.alpha).cgColor)
            ctx.fillEllipse(in: dotRect)
        }
        ctx.restoreGState()
    }
    
    // Subtle central lens glow
    if let centerBloom = CGGradient(colorsSpace: colorSpace,
                                    colors: [
                                        NSColor(white: 1.0, alpha: 0.35).cgColor,
                                        NSColor(white: 1.0, alpha: 0.08).cgColor,
                                        NSColor(white: 1.0, alpha: 0.0).cgColor
                                    ] as CFArray,
                                    locations: [0.0, 0.30, 1.0]) {
        ctx.drawRadialGradient(centerBloom,
                               startCenter: CGPoint(x: cx, y: cy),
                               startRadius: 0,
                               endCenter: CGPoint(x: cx, y: cy),
                               endRadius: 40.0 * scale,
                               options: [])
    }
    
    ctx.restoreGState() // Close squircle clip
    
    image.unlockFocus()
    return image
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let fileManager = FileManager.default
let iconsetPath = "/Users/nata/Company/Browser/Onyx.iconset"
try? fileManager.removeItem(atPath: iconsetPath)
try? fileManager.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true, attributes: nil)

for (name, s) in sizes {
    let img = createAppIcon(size: s)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let pngData = rep.representation(using: .png, properties: [:]) {
        let filePath = "\(iconsetPath)/\(name)"
        try? pngData.write(to: URL(fileURLWithPath: filePath))
    }
}

print("Iconset generated successfully at \(iconsetPath)")
