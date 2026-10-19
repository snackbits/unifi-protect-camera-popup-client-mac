// Renders the DMG window background (600 × 400 pt) as PNG at the given scale. Everything sits in
// the top 340 pt: newer Finder versions keep a toolbar in the window, which hides the bottom 50 pt.
// Usage: swift make-background.swift <out.png> <scale>
//
// Mid-tone indigo on purpose: Finder draws the icon labels black in Light Mode and white in
// Dark Mode, on top of this picture – both stay readable on a mid-tone, neither on white or black.
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write("usage: make-background.swift <out.png> <scale>\n".data(using: .utf8)!)
    exit(2)
}
let size = NSSize(width: 600, height: 400)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
// Top-left origin, like Finder's icon positions; a flipped context keeps text upright.
let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
cg.translateBy(x: 0, y: size.height * scale)
cg.scaleBy(x: scale, y: -scale)
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

NSGradient(starting: color(0x6E7192), ending: color(0x5C5F80))!
    .draw(in: NSRect(origin: .zero, size: size), angle: 90)

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
func text(_ string: String, y: CGFloat, height: CGFloat, size fontSize: CGFloat, weight: NSFont.Weight,
          alpha: CGFloat, inset: CGFloat = 40) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        .paragraphStyle: paragraph,
    ]
    NSAttributedString(string: string, attributes: attributes)
        .draw(with: NSRect(x: inset, y: y, width: size.width - 2 * inset, height: height),
              options: [.usesLineFragmentOrigin], context: nil)
}

text("UniFi Camera Popup installieren", y: 24, height: 28, size: 20, weight: .semibold, alpha: 1)
text("Zieh die App auf den Ordner „Programme“.", y: 56, height: 20, size: 13, weight: .regular, alpha: 0.85)

// Arrow between the two icons (centres at x 160 and 440, y 140).
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 248, y: 140))
arrow.line(to: NSPoint(x: 350, y: 140))
arrow.move(to: NSPoint(x: 338, y: 129))
arrow.line(to: NSPoint(x: 352, y: 140))
arrow.line(to: NSPoint(x: 338, y: 151))
color(0xFFFFFF, 0.9).setStroke()
arrow.stroke()

// First launch hint (the app is not notarized). macOS 15+ offers no way out in the warning itself:
// „Trotzdem öffnen“ only exists in System Settings, after a first attempt to open the app.
let box = NSRect(x: 30, y: 226, width: 540, height: 108)
color(0x000000, 0.18).setFill()
NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
text("Beim ersten Öffnen blockiert macOS die App", y: 236, height: 18, size: 12, weight: .semibold, alpha: 1, inset: 44)
let steps = [
    "1.  App öffnen – in der Meldung auf „Fertig“ klicken.",
    "2.  Systemeinstellungen › Datenschutz & Sicherheit, ganz nach unten scrollen.",
    "3.  Bei „UniFi Camera Popup“ auf „Trotzdem öffnen“ (Open Anyway) klicken",
    "     und im nächsten Fenster noch einmal „Trotzdem öffnen“.",
]
let left = NSMutableParagraphStyle()
left.alignment = .left
for (index, line) in steps.enumerated() {
    NSAttributedString(string: line, attributes: [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.88),
        .paragraphStyle: left,
    ]).draw(with: NSRect(x: 64, y: 260 + CGFloat(index) * 17, width: 480, height: 17),
            options: [.usesLineFragmentOrigin], context: nil)
}

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[1]))
