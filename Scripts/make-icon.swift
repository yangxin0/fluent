// Generates the input source's menu-bar icon: "FL" in SF Rounded, cut out of
// a rounded rectangle the size of Apple's ABC badge (22×16 pt, corner radius
// 5 pt, letters 8.5 pt tall, measured from the menu bar). It is a template image
// (TISIconIsTemplate in Info.plist): only its shape counts, and macOS tints it
// for light and dark menu bars like its own sources. 1x and 2x reps.
// Usage: swift Scripts/make-icon.swift Resources/icon.tiff
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/icon.tiff"
let points = NSSize(width: 22, height: 16)
let radius: CGFloat = 5
let capHeight: CGFloat = 8.5

func makeRep(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(points.width * scale), pixelsHigh: Int(points.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: scale, y: scale)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(origin: .zero, size: points), xRadius: radius, yRadius: radius).fill()
    // The letters are holes in the badge, centred on their ink rather than
    // their line box, so the caps sit in the middle like ABC's "A".
    let base = NSFont.systemFont(ofSize: 10, weight: .bold)
    let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    let unit = NSFont(descriptor: rounded, size: 10)!
    let font = NSFont(descriptor: rounded, size: 10 * capHeight / unit.capHeight)!
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "FL", attributes: [.font: font]))
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    cg.setBlendMode(.destinationOut)
    cg.textPosition = CGPoint(x: (points.width - ink.width) / 2 - ink.minX,
                              y: (points.height - ink.height) / 2 - ink.minY)
    CTLineDraw(line, cg)
    NSGraphicsContext.restoreGraphicsState()
    // Set after drawing: a sized rep scales its context itself.
    rep.size = points
    return rep
}

let data = NSBitmapImageRep.representationOfImageReps(in: [makeRep(scale: 1), makeRep(scale: 2)],
                                                      using: .tiff, properties: [:])!
try data.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath)")
