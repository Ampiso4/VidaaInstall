import AppKit

// Fond de la fenêtre du .dmg (640×400 pt, rendu @1x et @2x).
// Positions des icônes (centres) à garder en phase avec tools/dmg/settings.py :
// app (170, 175) · Applications (470, 175) · guide (480, 312).
let out = CommandLine.arguments[1]
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let W: CGFloat = 640, H: CGFloat = 400

func hex(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
let navy = hex(0x091540), royal = hex(0x1B2CC1), peri = hex(0x7692FF), sky = hex(0xABD2FA)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
// Image « retournée » : repère haut-gauche comme le Finder, texte compris.
let art = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
let ctx = NSGraphicsContext.current!.cgContext
navy.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
func blob(_ c: NSColor, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c.cgColor, c.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}
blob(royal.withAlphaComponent(0.85), 90, 60, 320)
blob(peri.withAlphaComponent(0.55), 600, 330, 300)
blob(sky.withAlphaComponent(0.22), 380, 10, 220)

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor, center: Bool = false, width: CGFloat = 600) {
    let p = NSMutableParagraphStyle(); p.alignment = center ? .center : .left; p.lineSpacing = 2
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p]
    NSAttributedString(string: s, attributes: a).draw(with: NSRect(x: center ? x - width / 2 : x, y: y, width: width, height: 80),
                                                     options: [.usesLineFragmentOrigin])
}

// Titre
text("Installer VidaaInstall", W / 2, 22, size: 20, weight: .bold, color: .white, center: true)
text("Glisse l'app sur le dossier Applications", W / 2, 50, size: 12.5, weight: .medium, color: sky, center: true)

// Bande en verre derrière les icônes : les libellés du Finder restent lisibles en clair comme en sombre.
func glass(_ r: CGRect, _ alpha: CGFloat) {
    let path = CGPath(roundedRect: r, cornerWidth: 22, cornerHeight: 22, transform: nil)
    ctx.addPath(path); ctx.setFillColor(peri.withAlphaComponent(alpha).cgColor); ctx.fillPath()
    ctx.addPath(path); ctx.setStrokeColor(sky.withAlphaComponent(0.35).cgColor); ctx.setLineWidth(1); ctx.strokePath()
}
glass(CGRect(x: 60, y: 92, width: 520, height: 168), 0.42)

// Flèche
ctx.setStrokeColor(sky.cgColor); ctx.setLineWidth(3); ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [2, 9])
ctx.move(to: CGPoint(x: 248, y: 170)); ctx.addLine(to: CGPoint(x: 382, y: 170)); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
ctx.move(to: CGPoint(x: 372, y: 160)); ctx.addLine(to: CGPoint(x: 386, y: 170)); ctx.addLine(to: CGPoint(x: 372, y: 180)); ctx.strokePath()

// Encart « première ouverture »
glass(CGRect(x: 60, y: 272, width: 520, height: 112), 0.3)
let badge = CGPath(ellipseIn: CGRect(x: 80, y: 292, width: 26, height: 26), transform: nil)
ctx.addPath(badge); ctx.setFillColor(sky.cgColor); ctx.fillPath()
text("!", 93, 294, size: 16, weight: .heavy, color: navy, center: true, width: 26)
text("Première ouverture ?", 118, 290, size: 14, weight: .bold, color: .white, width: 280)
text("macOS va bloquer l'app la première fois. Ouvre ce guide : 30 secondes, une seule fois.",
     118, 312, size: 11.5, weight: .regular, color: NSColor.white.withAlphaComponent(0.8), width: 290)
ctx.setStrokeColor(sky.cgColor); ctx.setLineWidth(2.5)
ctx.move(to: CGPoint(x: 405, y: 318)); ctx.addLine(to: CGPoint(x: 425, y: 318)); ctx.strokePath()
ctx.move(to: CGPoint(x: 418, y: 311)); ctx.addLine(to: CGPoint(x: 426, y: 318)); ctx.addLine(to: CGPoint(x: 418, y: 325)); ctx.strokePath()

return true
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
art.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
