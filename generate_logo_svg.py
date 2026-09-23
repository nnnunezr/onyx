import math

def project(x, y, z, yaw, tilt, scale3d, cx, cy):
    st, ct = math.sin(tilt), math.cos(tilt)
    sy, cyw = math.sin(yaw), math.cos(yaw)
    
    x1 = x * cyw + z * sy
    z1 = -x * sy + z * cyw
    y1 = y * ct - z1 * st
    z2 = y * st + z1 * ct
    return cx + x1 * scale3d, cy - y1 * scale3d, z2

def generate_svg():
    width = 512
    height = 512
    cx, cy = 256, 256
    scale = 512.0 / 1024.0
    
    ringRadius = 220.0 * scale
    lanes = 5
    segments = 84
    ringTilt = 0.42
    ringYaw = -0.25
    
    orbit2Radius = 195.0 * scale
    orbit2Tilt = -0.58
    orbit2Yaw = 0.78
    orbit2Segments = 64
    
    dots = []
    
    # Ring dots
    for lane in range(lanes):
        laneOffset = (lane - (lanes - 1) / 2.0) * (14.0 * scale)
        edgeFactor = abs(lane - (lanes - 1) / 2.0) / max(1.0, (lanes - 1) / 2.0)
        for s in range(segments):
            a = (s / segments) * math.pi * 2
            wobble = 0.09 * math.sin(a * 3.0 + lane * 0.3) + 0.04 * math.sin(a * 5.0 - 0.4)
            rMod = ringRadius * (1.0 + wobble)
            x = math.cos(a) * rMod
            y = math.sin(a) * rMod + laneOffset
            z = math.sin(a * 2.0) * (16.0 * scale)
            px, py, pz = project(x, y, z, ringYaw, ringTilt, 1.0, cx, cy)
            
            depthNorm = (pz / (ringRadius * 1.2) + 1.0) / 2.0
            clampedDepth = max(0.0, min(1.0, depthNorm))
            baseR = (2.2 + 3.4 * clampedDepth) * (1.0 - 0.22 * edgeFactor) * scale
            alpha = (0.28 + 0.72 * math.pow(clampedDepth, 1.3)) * (1.0 - 0.18 * edgeFactor)
            dots.append({'x': px, 'y': py, 'z': pz, 'r': max(1.0 * scale, baseR), 'alpha': alpha, 'isBeacon': False})
            
    # Orbit 2 dots
    for s in range(orbit2Segments):
        a = (s / orbit2Segments) * math.pi * 2
        x = math.cos(a) * orbit2Radius
        y = math.sin(a) * orbit2Radius
        z = 0
        px, py, pz = project(x, y, z, orbit2Yaw, orbit2Tilt, 1.0, cx, cy)
        depthNorm = (pz / (orbit2Radius * 1.2) + 1.0) / 2.0
        clampedDepth = max(0.0, min(1.0, depthNorm))
        baseR = (1.8 + 2.8 * clampedDepth) * scale
        alpha = (0.22 + 0.68 * math.pow(clampedDepth, 1.4))
        dots.append({'x': px, 'y': py, 'z': pz, 'r': max(0.9 * scale, baseR), 'alpha': alpha, 'isBeacon': False})
        
    # Beacons
    beaconAngles = [
        (ringRadius * 1.05, 0.45, ringYaw, ringTilt),
        (ringRadius * 0.98, 2.25, ringYaw, ringTilt),
        (ringRadius * 1.02, 3.80, ringYaw, ringTilt),
        (ringRadius * 0.95, 5.35, ringYaw, ringTilt),
        (orbit2Radius, 1.10, orbit2Yaw, orbit2Tilt),
        (orbit2Radius, 4.30, orbit2Yaw, orbit2Tilt)
    ]
    for radius, angle, yaw, tilt in beaconAngles:
        x = math.cos(angle) * radius
        y = math.sin(angle) * radius
        px, py, pz = project(x, y, 0, yaw, tilt, 1.0, cx, cy)
        depthNorm = (pz / (ringRadius * 1.2) + 1.0) / 2.0
        clampedDepth = max(0.0, min(1.0, depthNorm))
        beaconR = (4.5 + 4.5 * clampedDepth) * scale
        alpha = 0.85 + 0.15 * clampedDepth
        dots.append({'x': px, 'y': py, 'z': pz, 'r': beaconR, 'alpha': alpha, 'isBeacon': True})
        
    # Singularity Core
    coreR = 8.0 * scale
    dots.append({'x': cx, 'y': cy, 'z': 0, 'r': coreR, 'alpha': 0.98, 'isBeacon': True})
    
    dots.sort(key=lambda d: d['z'])
    
    # Ring continuous path
    track1_points = []
    for i in range(101):
        a = (i / 100.0) * math.pi * 2
        px, py, _ = project(math.cos(a) * ringRadius, math.sin(a) * ringRadius * 0.96, 0, ringYaw, ringTilt, 1.0, cx, cy)
        track1_points.append(f"{px:.1f},{py:.1f}")
        
    track2_points = []
    for i in range(101):
        a = (i / 100.0) * math.pi * 2
        px, py, _ = project(math.cos(a) * orbit2Radius, math.sin(a) * orbit2Radius, 0, orbit2Yaw, orbit2Tilt, 1.0, cx, cy)
        track2_points.append(f"{px:.1f},{py:.1f}")
        
    svg_lines = [
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">',
        '  <defs>',
        '    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="0%" y2="100%">',
        '      <stop offset="0%" stop-color="#18181e"/>',
        '      <stop offset="50%" stop-color="#0d0d10"/>',
        '      <stop offset="100%" stop-color="#060608"/>',
        '    </linearGradient>',
        '    <radialGradient id="centerBloom" cx="50%" cy="50%" r="50%">',
        '      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.22"/>',
        '      <stop offset="40%" stop-color="#ffffff" stop-opacity="0.06"/>',
        '      <stop offset="100%" stop-color="#ffffff" stop-opacity="0.0"/>',
        '    </radialGradient>',
        '    <filter id="beaconGlow" x="-50%" y="-50%" width="200%" height="200%">',
        '      <feGaussianBlur in="SourceGraphic" stdDeviation="4" result="blur"/>',
        '      <feMerge>',
        '        <feMergeNode in="blur"/>',
        '        <feMergeNode in="SourceGraphic"/>',
        '      </feMerge>',
        '    </filter>',
        '  </defs>',
        '  <!-- macOS Squircle Background -->',
        '  <rect x="41" y="41" width="430" height="430" rx="92" ry="92" fill="url(#bgGrad)" stroke="rgba(255,255,255,0.12)" stroke-width="1"/>',
        '  <!-- Ambient Glow -->',
        '  <circle cx="256" cy="256" r="180" fill="url(#centerBloom)"/>',
        '  <!-- Orbital Guidance Trajectories -->',
        f'  <polygon points="{" ".join(track1_points)}" fill="none" stroke="rgba(255,255,255,0.14)" stroke-width="1"/>',
        f'  <polygon points="{" ".join(track2_points)}" fill="none" stroke="rgba(255,255,255,0.10)" stroke-width="1"/>',
        '  <!-- Projected Harmonic Dots & Nodes -->'
    ]
    
    for d in dots:
        if d['isBeacon']:
            svg_lines.append(f'  <circle cx="{d["x"]:.1f}" cy="{d["y"]:.1f}" r="{d["r"]:.1f}" fill="#ffffff" opacity="{d["alpha"]:.2f}" filter="url(#beaconGlow)"/>')
        else:
            svg_lines.append(f'  <circle cx="{d["x"]:.1f}" cy="{d["y"]:.1f}" r="{d["r"]:.1f}" fill="#ffffff" opacity="{d["alpha"]:.2f}"/>')
            
    svg_lines.append('</svg>')
    
    with open('/Users/nata/Company/Browser/logo.svg', 'w') as f:
        f.write('\n'.join(svg_lines) + '\n')

generate_svg()
print("logo.svg generated successfully")
