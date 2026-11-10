import AppKit

// Bannière du README (1280×640, aussi au format « social preview » de GitHub).
// usage : make_banner <icône 1024.png> <capture.png> <sortie.png>
let a = CommandLine.arguments
let W: CGFloat = 1280, H: CGFloat = 640
func hex(_ h: UInt32, _ al: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: al)
}
let navy = hex(0x091540), royal = hex(0x1B2CC1), peri = hex(0x7692FF), sky = hex(0xABD2FA)
let icon = NSImage(contentsOfFile: a[1])!, shot = NSImage(contentsOfFile: a[2])!

let img = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    navy.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    func blob(_ c: NSColor, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
    }
    blob(royal.withAlphaComponent(0.9), 180, 120, 560)
    blob(peri.withAlphaComponent(0.55), 1150, 560, 520)
    blob(sky.withAlphaComponent(0.25), 700, 0, 380)

    icon.draw(in: NSRect(x: 64, y: 150, width: 150, height: 150))
    func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ c: NSColor, width: CGFloat = 520) {
        let p = NSMutableParagraphStyle(); p.lineSpacing = 4
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c, .paragraphStyle: p])
            .draw(with: NSRect(x: x, y: y, width: width, height: 300), options: [.usesLineFragmentOrigin])
    }
    let word = NSMutableAttributedString(string: "Vidaa", attributes: [.font: NSFont.systemFont(ofSize: 64, weight: .light), .foregroundColor: NSColor.white])
    word.append(NSAttributedString(string: "Install", attributes: [.font: NSFont.systemFont(ofSize: 64, weight: .heavy), .foregroundColor: sky]))
    word.draw(at: NSPoint(x: 72, y: 318))
    text("Installe tes propres apps web sur un téléviseur Hisense VIDAA, depuis ton Mac.", 74, 410,
         .systemFont(ofSize: 25, weight: .medium), NSColor.white.withAlphaComponent(0.85), width: 470)
    text("SCAN · APPAIRAGE · INSTALLATION · SAUVEGARDES", 74, 520, .systemFont(ofSize: 14, weight: .bold), peri, width: 520)

    // Capture inclinée à droite
    ctx.saveGState()
    ctx.translateBy(x: 900, y: 330)
    ctx.rotate(by: -0.045)
    let sw: CGFloat = 740, sh = sw * shot.size.height / shot.size.width
    shot.draw(in: NSRect(x: -sw / 2 + 60, y: -sh / 2, width: sw, height: sh))
    ctx.restoreGState()
    return true
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: W, height: H)); NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
