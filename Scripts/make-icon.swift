// Generates the input source's menu-bar icon (16 + 32 pt reps): "A文", for
// English and Chinese in one input method, cut out of a rounded square. It is
// a template image (TISIconIsTemplate in Info.plist): only its shape counts,
// and macOS tints it for light and dark menu bars like its own sources.
// Usage: swift Scripts/make-icon.swift Resources/icon.tiff
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/icon.tiff"

func makeRep(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let s = CGFloat(size)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.03, dy: s * 0.03),
                               xRadius: s * 0.2, yRadius: s * 0.2)
    NSColor.black.setFill()
    rounded.fill()
    // The letters are holes in the square, as large as fit across it.
    let text = "A文" as NSString
    var fontSize = s * 0.56
    var attrs: [NSAttributedString.Key: Any] = [:]
    repeat {
        attrs = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: NSColor.black]
        fontSize -= s * 0.01
    } while text.size(withAttributes: attrs).width > s * 0.8
    let textSize = text.size(withAttributes: attrs)
    context.compositingOperation = .destinationOut
    text.draw(at: NSPoint(x: (s - textSize.width) / 2, y: (s - textSize.height) / 2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let data = NSBitmapImageRep.representationOfImageReps(in: [makeRep(size: 16), makeRep(size: 32)],
                                                      using: .tiff, properties: [:])!
try data.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
