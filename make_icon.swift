// Generates Touchline.icns — an abstracted black/white soccer-ball mark on a
// TRANSPARENT background (no frame, no fill). Pure vector line-art: circle outline +
// center pentagon + 5 spokes. No copyrighted assets, no gradients/gloss.
//
// The mark is drawn in near-black; macOS renders it on the user's wallpaper/dock.
// For the menu bar the app uses an SF Symbol separately — this is the app icon.
//
// Usage: swiftc make_icon.swift -o make_icon && ./make_icon
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: Double,_ g: Double,_ b: Double,_ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
let ink = rgb(0.11, 0.11, 0.12)

func poly(_ c: CGPoint,_ r: CGFloat,_ rot: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<5 {
        let a = (90 + rot + CGFloat(i) * 72) * .pi / 180
        let pt = CGPoint(x: c.x + r*cos(a), y: c.y + r*sin(a))
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath(); return p
}

func drawIcon(px: Int) -> CGImage {
    let s = CGFloat(px) / 1024.0
    let g = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    g.setAllowsAntialiasing(true); g.interpolationQuality = .high

    // Mark fills ~78% of the canvas, centered — leaves the margin macOS icons expect.
    let C = CGPoint(x: 512*s, y: 512*s)
    let R = 392*s

    g.setStrokeColor(ink); g.setLineJoin(.round); g.setLineCap(.round)

    // outer circle
    g.setLineWidth(54*s)
    g.strokeEllipse(in: CGRect(x: C.x-R, y: C.y-R, width: 2*R, height: 2*R))

    // center pentagon (filled)
    let Rp = R*0.40
    g.addPath(poly(C, Rp, 0)); g.setFillColor(ink); g.fillPath()

    // 5 spokes from pentagon vertices to the rim
    g.setLineWidth(48*s)
    for k in 0..<5 {
        let a = (90 + CGFloat(k)*72) * .pi/180
        g.move(to: CGPoint(x: C.x + Rp*cos(a), y: C.y + Rp*sin(a)))
        g.addLine(to: CGPoint(x: C.x + R*cos(a), y: C.y + R*sin(a)))
    }
    g.strokePath()

    return g.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = "Touchline.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

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
writePNG(cache[1024]!, to: "icon_preview_1024.png")
print("Wrote \(targets.count) icons into \(outDir)")
