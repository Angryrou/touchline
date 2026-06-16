// Generates Touchline.icns from pure vector drawing — no external/copyrighted images.
// Design: pitch-green squircle with mow stripes + a classic white soccer ball
// (truncated-icosahedron pattern is generic geometry, not copyrightable) + a
// corner-kick arc as a subtle nod to the "touchline" name.
//
// Usage: swiftc make_icon.swift -o make_icon && ./make_icon
import CoreGraphics
import ImageIO
import Foundation

// MARK: - Helpers

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// Regular polygon path. `rotationDeg` rotates clockwise from "first vertex at top".
func polygon(center c: CGPoint, radius r: CGFloat, sides: Int, rotationDeg: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<sides {
        let deg = 90 + rotationDeg + CGFloat(i) * 360 / CGFloat(sides)
        let a = deg * .pi / 180
        let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// MARK: - Icon drawing (all metrics in a 1024 design space, scaled by s)

func drawIcon(px: Int) -> CGImage {
    let size = CGFloat(px)
    let s = size / 1024.0
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Squircle (Apple macOS icon grid: 824 content in 1024, r≈180).
    let rect = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 184 * s, cornerHeight: 184 * s, transform: nil)

    // --- Background: vertical pitch-green gradient ---
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let grad = CGGradient(colorsSpace: space,
                          colors: [rgb(0.184, 0.722, 0.353), rgb(0.055, 0.420, 0.188)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

    // --- Mow stripes (subtle alternating darker vertical bands) ---
    let bands = 7
    let bw = rect.width / CGFloat(bands)
    ctx.setFillColor(rgb(0, 0, 0, 0.08))
    for i in 0..<bands where i % 2 == 0 {
        ctx.fill(CGRect(x: rect.minX + CGFloat(i) * bw, y: rect.minY, width: bw, height: rect.height))
    }

    // --- Corner-kick arc (the "touchline" cue), lower-left ---
    // Already clipped to the squircle above, so lines can't escape the rounded corner.
    let corner = CGPoint(x: rect.minX + 96 * s, y: rect.minY + 96 * s)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.82))
    ctx.setLineWidth(10 * s)
    ctx.setLineCap(.round)
    let arc = CGMutablePath()
    arc.addArc(center: corner, radius: 66 * s, startAngle: 0, endAngle: .pi / 2, clockwise: false)
    ctx.addPath(arc); ctx.strokePath()
    // short touchlines running toward (not past) the corner
    ctx.move(to: CGPoint(x: corner.x, y: corner.y + 150 * s)); ctx.addLine(to: corner)
    ctx.addLine(to: CGPoint(x: corner.x + 150 * s, y: corner.y))
    ctx.strokePath()

    // --- Soft inner vignette for depth ---
    let vg = CGGradient(colorsSpace: space,
                        colors: [rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.22)] as CFArray,
                        locations: [0.55, 1])!
    ctx.drawRadialGradient(vg,
                           startCenter: CGPoint(x: size/2, y: size/2), startRadius: 0,
                           endCenter: CGPoint(x: size/2, y: size/2), endRadius: size * 0.62,
                           options: [])
    ctx.restoreGState()

    // --- Hero soccer ball ---
    let C = CGPoint(x: 512 * s, y: 548 * s)
    let R = 276 * s
    let ink = rgb(0.082, 0.094, 0.106)

    // Drop shadow under the ball.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16 * s), blur: 42 * s, color: rgb(0, 0, 0, 0.40))
    ctx.setFillColor(rgb(1, 1, 1, 1))
    ctx.fillEllipse(in: CGRect(x: C.x - R, y: C.y - R, width: 2 * R, height: 2 * R))
    ctx.restoreGState()

    // Sphere shading (light from upper-left).
    ctx.saveGState()
    let ballClip = CGMutablePath()
    ballClip.addEllipse(in: CGRect(x: C.x - R, y: C.y - R, width: 2 * R, height: 2 * R))
    ctx.addPath(ballClip); ctx.clip()
    let shade = CGGradient(colorsSpace: space,
                           colors: [rgb(1, 1, 1), rgb(0.86, 0.89, 0.87)] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(shade,
                           startCenter: CGPoint(x: C.x - R*0.35, y: C.y + R*0.35), startRadius: 0,
                           endCenter: C, endRadius: R * 1.15, options: [])

    // Classic pattern (clipped to the ball): central pentagon, 5 bold seams to rim,
    // 5 partial pentagons at the rim. Sized to stay legible down to 32px.
    let Rp = R * 0.46
    ctx.setFillColor(ink)
    ctx.addPath(polygon(center: C, radius: Rp, sides: 5, rotationDeg: 0))
    ctx.fillPath()

    ctx.setStrokeColor(ink)
    ctx.setLineWidth(R * 0.075)
    ctx.setLineCap(.round)
    for k in 0..<5 {
        let deg = 90 + CGFloat(k) * 72
        let a = deg * .pi / 180
        let p0 = CGPoint(x: C.x + Rp * cos(a), y: C.y + Rp * sin(a))
        let p1 = CGPoint(x: C.x + R * cos(a), y: C.y + R * sin(a))
        ctx.move(to: p0); ctx.addLine(to: p1)
    }
    ctx.strokePath()

    ctx.setFillColor(ink)
    for k in 0..<5 {
        let deg = 90 + CGFloat(k) * 72 + 36
        let a = deg * .pi / 180
        let oc = CGPoint(x: C.x + R * 1.08 * cos(a), y: C.y + R * 1.08 * sin(a))
        ctx.addPath(polygon(center: oc, radius: R * 0.46, sides: 5, rotationDeg: deg - 90))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Crisp rim.
    ctx.setStrokeColor(rgb(0.082, 0.094, 0.106, 0.35))
    ctx.setLineWidth(R * 0.02)
    ctx.strokeEllipse(in: CGRect(x: C.x - R, y: C.y - R, width: 2 * R, height: 2 * R))

    return ctx.makeImage()!
}

// MARK: - Write iconset

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = "Touchline.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename, pixels)
let targets: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

var cache: [Int: CGImage] = [:]
for (name, px) in targets {
    let img = cache[px] ?? drawIcon(px: px)
    cache[px] = img
    writePNG(img, to: "\(outDir)/\(name)")
}
// Also drop a standalone preview for inspection.
writePNG(cache[1024]!, to: "icon_preview_1024.png")
writePNG(cache[32]!, to: "icon_preview_32.png")
print("Wrote \(targets.count) icons into \(outDir)")
