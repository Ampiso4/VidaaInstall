import AppKit

// Génère l'icône 1024×1024 : squircle dégradé navy → bleu roi → pervenche, halo bleu ciel, TV blanche.
let size: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(path); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path); ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
func c(_ h: UInt32) -> CGColor { CGColor(red: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1) }
let g = CGGradient(colorsSpace: space, colors: [c(0x091540), c(0x1B2CC1), c(0x7692FF)] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
// Lueurs
let glow = CGGradient(colorsSpace: space, colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.35), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 360, y: 760), startRadius: 0, endCenter: CGPoint(x: 360, y: 760), endRadius: 520, options: [])
let teal = CGGradient(colorsSpace: space, colors: [c(0xABD2FA).copy(alpha: 0.55)!, c(0xABD2FA).copy(alpha: 0)!] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(teal, startCenter: CGPoint(x: 780, y: 230), startRadius: 0, endCenter: CGPoint(x: 780, y: 230), endRadius: 420, options: [])
// Anneau
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22)); ctx.setLineWidth(10)
ctx.strokeEllipse(in: CGRect(x: 232, y: 232, width: 560, height: 560))
ctx.restoreGState()

// Symbole
let conf = NSImage.SymbolConfiguration(pointSize: 330, weight: .medium)
if let sym = NSImage(systemSymbolName: "tv", accessibilityDescription: nil)?.withSymbolConfiguration(conf) {
    let tinted = NSImage(size: sym.size, flipped: false) { r in
        sym.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
    }
    let s = tinted.size
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    tinted.draw(in: CGRect(x: (size - s.width) / 2, y: (size - s.height) / 2 + 10, width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
