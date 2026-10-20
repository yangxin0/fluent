import Cocoa

/// The ⇧⇧ toggle's notice: the FL badge alone in a panel of its own,
/// floating under the caret, indigo for on and grey for off. It ignores the
/// mouse; the candidate bar's controller hides one when it shows the other.
final class ToggleNoticePanel {
    private let panel = PanelPlacement.makePanel()
    private let badge = FloatingBadgeView()

    init() {
        panel.ignoresMouseEvents = true
        panel.hasShadow = false  // the badge draws its own
        panel.contentView = badge
    }

    func show(enabled: Bool, appearance: String, near caretRect: NSRect) {
        PanelPlacement.applyAppearance(appearance, to: panel)
        badge.enabled = enabled
        let frame = PanelPlacement.centredFrame(for: FloatingBadgeView.badgeSize, caretRect: caretRect)
            .insetBy(dx: -FloatingBadgeView.padding, dy: -FloatingBadgeView.padding)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private enum NoticeColor {
    /// Indigo from the app icon's tile, lighter in dark mode.
    static let indigo = dynamic(light: 0x5b52e8, dark: 0x7c74ff)
    static let off = dynamic(light: 0xaeaeb2, dark: 0x636366)

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func dynamic(light: Int, dark: Int) -> NSColor {
        func rgb(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        return NSColor(name: nil) { isDark($0) ? rgb(dark) : rgb(light) }
    }
}

/// The menu bar's FL badge (Scripts/make-icon.swift: 22×16 pt, corner
/// radius 5 pt, letters 8.5 pt tall in SF Rounded) at any height.
private enum FLBadge {
    static func size(height: CGFloat) -> NSSize {
        NSSize(width: height * 22 / 16, height: height)
    }

    static func shape(_ rect: NSRect) -> NSBezierPath {
        let radius = rect.height * 5 / 16
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    /// Filled with `color`, with white letters.
    static func draw(in rect: NSRect, _ color: NSColor) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let line = letters(capHeight: rect.height * 8.5 / 16)
        // Centred on their ink, like the menu bar's.
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        cg.saveGState()
        color.setFill()
        shape(rect).fill()
        NSColor.white.setFill()
        cg.textMatrix = .identity
        cg.textPosition = CGPoint(x: rect.midX - ink.width / 2 - ink.minX, y: rect.midY - ink.height / 2 - ink.minY)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    /// "FL" drawn in the context's fill colour.
    private static func letters(capHeight: CGFloat) -> CTLine {
        let base = NSFont.systemFont(ofSize: 10, weight: .bold)
        let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let unit = NSFont(descriptor: rounded, size: 10)!
        let font = NSFont(descriptor: rounded, size: 10 * capHeight / unit.capHeight)!
        let fromContext = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)
        return CTLineCreateWithAttributedString(NSAttributedString(string: "FL", attributes: [
            .font: font, fromContext: true,
        ]))
    }
}

/// The badge on its own, with white letters and a shadow it draws itself,
/// in the padding around it.
private final class FloatingBadgeView: NSView {
    static let badgeSize = FLBadge.size(height: 24)
    static let padding: CGFloat = 6

    var enabled = true {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(origin: NSPoint(x: Self.padding, y: Self.padding), size: Self.badgeSize)
        let color = enabled ? NoticeColor.indigo : NoticeColor.off
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -1.5)
        shadow.shadowBlurRadius = 4
        shadow.set()
        color.setFill()
        FLBadge.shape(rect).fill()
        NSGraphicsContext.restoreGraphicsState()
        FLBadge.draw(in: rect, color)
    }
}
