// Generates the input source's menu-bar icon: "FL" in SF Rounded, cut out of
// a rounded rectangle a little wider than tall, the shape of Apple's ABC
// badge. It is a template image (TISIconIsTemplate in Info.plist): only its
// shape counts, and macOS tints it for light and dark menu bars like its own
// sources. 21×15 pt, with 1x and 2x reps.
// Usage: swift Scripts/make-icon.swift Resources/icon.tiff
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/icon.tiff"
let points = NSSize(width: 21, height: 15)

func makeRep(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(points.width * scale), pixelsHigh: Int(points.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    let rect = NSRect(origin: .zero, size: points)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5).fill()
    // The letters are holes in the badge.
    let base = NSFont.systemFont(ofSize: 10.5, weight: .bold)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 10.5)!
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let text = "FL" as NSString
    let textSize = text.size(withAttributes: attrs)
    context.compositingOperation = .destinationOut
    text.draw(at: NSPoint(x: (points.width - textSize.width) / 2, y: (points.height - textSize.height) / 2),
              withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    // Set after drawing: a sized rep scales its context itself.
    rep.size = points
    return rep
}

let data = NSBitmapImageRep.representationOfImageReps(in: [makeRep(scale: 1), makeRep(scale: 2)],
                                                      using: .tiff, properties: [:])!
try data.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
