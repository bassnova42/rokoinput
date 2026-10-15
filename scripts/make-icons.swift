import Cocoa
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
func image(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22).fill()
    let font = NSFont.systemFont(ofSize: CGFloat(size) * 0.66, weight: .bold)
    let text = NSAttributedString(string: "R", attributes: [.font: font, .foregroundColor: NSColor.white])
    let extent = text.size()
    text.draw(at: NSPoint(x: (CGFloat(size) - extent.width) / 2, y: (CGFloat(size) - extent.height) / 2))
    image.unlockFocus()
    return image
}
let family = NSImage(size: NSSize(width: 512, height: 512))
for size in [16, 32, 64, 128, 256, 512, 1024] {
    if let tiff = image(size: size).tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) { family.addRepresentation(rep) }
}
// TIFF representation is a supported bundle icon format; avoid external artwork dependencies.
try family.tiffRepresentation!.write(to: directory.appendingPathComponent("RokoInput.tiff"))
let view = NSView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
final class GlyphView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSAttributedString(string: "R", attributes: [.font: NSFont.systemFont(ofSize: 16, weight: .bold), .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 2, y: -1))
    }
}
let glyph = GlyphView(frame: view.frame)
try glyph.dataWithPDF(inside: glyph.bounds).write(to: directory.appendingPathComponent("menu-icon.pdf"))
