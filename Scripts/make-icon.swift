// Generates a simple menu-bar icon (16 + 32 pt reps) for the input source.
// Usage: swift Scripts/make-icon.swift Resources/icon.tiff
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/icon.tiff"

func makeRep(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.03, dy: s * 0.03),
                               xRadius: s * 0.2, yRadius: s * 0.2)
    NSColor.black.setFill()
    rounded.fill()
    let text = "E✦" as NSString
    let font = NSFont.systemFont(ofSize: s * 0.55, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let textSize = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (s - textSize.width) / 2, y: (s - textSize.height) / 2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let data = NSBitmapImageRep.representationOfImageReps(in: [makeRep(size: 16), makeRep(size: 32)],
                                                      using: .tiff, properties: [:])!
try data.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
