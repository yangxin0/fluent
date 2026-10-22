import Cocoa

/// How the ⇧⇧ toggle's notice looks: the config's "toggleNotice".
enum ToggleNoticeStyle: String {
    /// The FL badge alone, floating under the caret: indigo for on, grey
    /// for off.
    case badge
    /// The badge and On or Off in a capsule at the caret, the ⇧⇧ keys after
    /// Off.
    case pill
    /// The badge and On or Off in a bubble pointing at the caret.
    case bubble
    /// The badge alone in a bubble pointing at the caret, the ⇧⇧ keys after
    /// it when off.
    case keys
}

/// The ⇧⇧ notice's own panel, under or over the caret. It ignores the
/// mouse; the candidate bar's controller hides one when it shows the other.
final class ToggleNoticePanel {
    private let panel = PanelPlacement.makePanel()
    private let badge = FloatingBadgeView()
    private let notice = MaterialNoticeView()

    init() {
        panel.ignoresMouseEvents = true
    }

    /// `badgeHeight` sizes the "badge" style; the others keep their own.
    func show(enabled: Bool, style: ToggleNoticeStyle, badgeHeight: CGFloat, appearance: String,
              near caretRect: NSRect) {
        PanelPlacement.applyAppearance(appearance, to: panel)
        let frame: NSRect
        switch style {
        case .badge:
            badge.enabled = enabled
            badge.height = badgeHeight
            panel.contentView = badge
            panel.hasShadow = false  // it draws its own
            frame = badge.frame(near: caretRect)
        case .pill:
            let size = MaterialNoticeView.size(style: style, enabled: enabled, tail: .none)
            notice.update(style: style, enabled: enabled, tail: .none)
            panel.contentView = notice
            panel.hasShadow = true
            frame = NSRect(origin: PanelPlacement.origin(for: size, caretRect: caretRect), size: size)
        case .bubble, .keys:
            // The tail points at the caret, up from under it or down from
            // over it; there is none when the caret is unknown.
            let known = caretRect.origin != .zero
            let size = MaterialNoticeView.size(style: style, enabled: enabled, tail: known ? .up(x: 0) : .none)
            frame = PanelPlacement.centredFrame(for: size, caretRect: caretRect)
            let x = caretRect.midX - frame.minX
            let tail: BubbleTail = !known ? .none : frame.minY > caretRect.minY ? .down(x: x) : .up(x: x)
            notice.update(style: style, enabled: enabled, tail: tail)
            panel.contentView = notice
            panel.hasShadow = true
        }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()  // the shape changes with the style and tail
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// Where a bubble's tail points from: up at a caret over it, down at one
/// under it, at `x` across the bubble; none when the caret is unknown.
enum BubbleTail {
    case up(x: CGFloat)
    case down(x: CGFloat)
    case none
}

private enum NoticeColor {
    /// Indigo from the app icon's tile, lighter in dark mode.
    static let indigo = dynamic(light: 0x5b52e8, dark: 0x7c74ff)
    static let off = dynamic(light: 0xaeaeb2, dark: 0x636366)
    static let key = dynamic(light: 0xffffff, dark: 0x3a3a3c)
    static let keyEdge = NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.18)
    }

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
    enum Look {
        /// Filled, the letters cut out of it.
        case cutOut(NSColor)
        /// Filled, with white letters.
        case filled(NSColor)
        /// An outline, the letters in its colour.
        case outline(NSColor)
    }

    static func size(height: CGFloat) -> NSSize {
        NSSize(width: height * 22 / 16, height: height)
    }

    static func shape(_ rect: NSRect) -> NSBezierPath {
        let radius = rect.height * 5 / 16
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    /// `letterScale` sizes the letters against the menu bar's.
    static func draw(in rect: NSRect, _ look: Look, letterScale: CGFloat = 1) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let line = letters(capHeight: rect.height * 8.5 / 16 * letterScale)
        // Centred on their ink, like the menu bar's.
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        func drawLetters() {
            cg.textMatrix = .identity
            cg.textPosition = CGPoint(x: rect.midX - ink.width / 2 - ink.minX, y: rect.midY - ink.height / 2 - ink.minY)
            CTLineDraw(line, cg)
        }
        cg.saveGState()
        switch look {
        case .cutOut(let color):
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            color.setFill()
            shape(rect).fill()
            cg.setBlendMode(.destinationOut)
            drawLetters()
            cg.endTransparencyLayer()
        case .filled(let color):
            color.setFill()
            shape(rect).fill()
            NSColor.white.setFill()
            drawLetters()
        case .outline(let color):
            color.set()
            let inset = rect.insetBy(dx: 0.75, dy: 0.75)
            let radius = rect.height * 5 / 16 - 0.75
            let outline = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
            outline.lineWidth = 1.5
            outline.stroke()
            drawLetters()
        }
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

/// The "badge" style: the badge on its own, with white letters and a shadow
/// it draws itself, in the padding around it.
private final class FloatingBadgeView: NSView {
    static let padding: CGFloat = 6
    /// Smaller letters than the menu bar's: at this size they crowd it.
    static let letterScale: CGFloat = 0.8

    /// Settings ▸ Appearance ▸ Badge size (`badgeSize`).
    var height: CGFloat = 18 {
        didSet { needsDisplay = true }
    }

    var badgeSize: NSSize { FLBadge.size(height: height) }

    var enabled = true {
        didSet { needsDisplay = true }
    }

    /// The panel's frame for the badge under (or over) the caret.
    func frame(near caretRect: NSRect) -> NSRect {
        PanelPlacement.centredFrame(for: badgeSize, caretRect: caretRect)
            .insetBy(dx: -Self.padding, dy: -Self.padding)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(origin: NSPoint(x: Self.padding, y: Self.padding), size: badgeSize)
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
        FLBadge.draw(in: rect, .filled(color), letterScale: Self.letterScale)
    }
}

/// While Fluent is off, the grey FL badge stays by the caret, so the off
/// state is never in doubt (#26): the ⇧⇧ notice's off badge, the same size
/// (`badgeSize`) and place, kept on screen.
final class OffBadgePanel {
    private let panel = PanelPlacement.makePanel()
    private let badge = FloatingBadgeView()

    init() {
        panel.ignoresMouseEvents = true
        panel.hasShadow = false  // the badge draws its own
        badge.enabled = false
        panel.contentView = badge
    }

    func show(height: CGFloat, appearance: String, near caretRect: NSRect) {
        PanelPlacement.applyAppearance(appearance, to: panel)
        badge.height = height
        panel.setFrame(badge.frame(near: caretRect), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// The "pill", "bubble" and "keys" styles: the popover material, like the
/// candidate bar's, as a capsule or as a bubble with a tail, and a hairline
/// edge; the badge (indigo for on, an outline for off), On or Off, and the
/// ⇧⇧ keys over it, as the style has them.
private final class MaterialNoticeView: NSVisualEffectView {
    static let tailHeight: CGFloat = 7
    private static let tailHalfWidth: CGFloat = 7
    private static let wordFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    private static let keyFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let keySize: CGFloat = 18

    /// One style's measures.
    private struct Metrics {
        var height: CGFloat
        var radius: CGFloat
        var badgeHeight: CGFloat
        var leading: CGFloat
        var trailing: CGFloat
        var minWidth: CGFloat = 0
        var word: Bool
        /// The ⇧⇧ keys when off.
        var keys: Bool
    }

    private static func metrics(_ style: ToggleNoticeStyle) -> Metrics {
        switch style {
        case .pill: Metrics(height: 34, radius: 17, badgeHeight: 18, leading: 10, trailing: 14, word: true, keys: true)
        case .keys: Metrics(height: 32, radius: 9, badgeHeight: 22, leading: 9, trailing: 9, minWidth: 52,
                            word: false, keys: true)
        case .bubble, .badge: Metrics(height: 32, radius: 9, badgeHeight: 22, leading: 10, trailing: 12,
                                      word: true, keys: false)
        }
    }

    private enum Item {
        case badge, word, keys
    }

    private var style = ToggleNoticeStyle.bubble
    private var enabled = true
    private var tail = BubbleTail.none
    private let content = ContentView()

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active  // stay vibrant: the IME is never the active app
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        content.drawContent = { [weak self] in self?.drawContent() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The panel's size: the body and its tail.
    static func size(style: ToggleNoticeStyle, enabled: Bool, tail: BubbleTail) -> NSSize {
        let body = bodySize(style: style, enabled: enabled)
        if case .none = tail { return body }
        return NSSize(width: body.width, height: body.height + tailHeight)
    }

    func update(style: ToggleNoticeStyle, enabled: Bool, tail: BubbleTail) {
        self.style = style
        self.enabled = enabled
        let size = Self.size(style: style, enabled: enabled, tail: tail)
        let radius = Self.metrics(style).radius
        // The tail stays on the straight part of the edge.
        let limit = radius + Self.tailHalfWidth
        func clamped(_ x: CGFloat) -> CGFloat { min(max(x, limit), size.width - limit) }
        self.tail = switch tail {
        case .up(let x): .up(x: clamped(x))
        case .down(let x): .down(x: clamped(x))
        case .none: .none
        }
        setFrameSize(size)
        content.frame = bounds
        let pointing = self.tail
        maskImage = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            Self.path(in: rect, radius: radius, tail: pointing, inset: 0).fill()
            return true
        }
        content.needsDisplay = true
    }

    private static func items(style: ToggleNoticeStyle, enabled: Bool) -> [Item] {
        let m = metrics(style)
        var items: [Item] = [.badge]
        if m.word { items.append(.word) }
        if m.keys && !enabled { items.append(.keys) }
        return items
    }

    private static func word(enabled: Bool) -> NSAttributedString {
        NSAttributedString(string: enabled ? "On" : "Off", attributes: [
            .font: wordFont, .foregroundColor: enabled ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ])
    }

    private static func width(of item: Item, style: ToggleNoticeStyle, enabled: Bool) -> CGFloat {
        switch item {
        case .badge: FLBadge.size(height: metrics(style).badgeHeight).width
        case .word: ceil(word(enabled: enabled).size().width)
        case .keys: 2 * keySize + 3
        }
    }

    /// Space before an item that follows another.
    private static func gap(before item: Item) -> CGFloat {
        item == .keys ? 10 : 8
    }

    private static func bodySize(style: ToggleNoticeStyle, enabled: Bool) -> NSSize {
        let m = metrics(style)
        var total = m.leading + m.trailing
        for (offset, item) in items(style: style, enabled: enabled).enumerated() {
            total += width(of: item, style: style, enabled: enabled) + (offset > 0 ? gap(before: item) : 0)
        }
        return NSSize(width: max(total, m.minWidth), height: m.height)
    }

    private static func body(in bounds: NSRect, tail: BubbleTail) -> NSRect {
        var body = bounds
        switch tail {
        case .up: body.size.height -= tailHeight
        case .down: body.origin.y += tailHeight; body.size.height -= tailHeight
        case .none: break
        }
        return body
    }

    /// The outline, tail included, `inset` inside `bounds`.
    private static func path(in bounds: NSRect, radius: CGFloat, tail: BubbleTail, inset d: CGFloat) -> NSBezierPath {
        let body = body(in: bounds, tail: tail).insetBy(dx: d, dy: d)
        let r = radius - d, w = tailHalfWidth, h = tailHeight
        let path = NSBezierPath()
        path.move(to: NSPoint(x: body.minX + r, y: body.minY))
        if case .down(let x) = tail {
            path.line(to: NSPoint(x: x - w, y: body.minY))
            path.line(to: NSPoint(x: x, y: body.minY - h))
            path.line(to: NSPoint(x: x + w, y: body.minY))
        }
        path.appendArc(withCenter: NSPoint(x: body.maxX - r, y: body.minY + r), radius: r, startAngle: 270, endAngle: 0)
        path.appendArc(withCenter: NSPoint(x: body.maxX - r, y: body.maxY - r), radius: r, startAngle: 0, endAngle: 90)
        if case .up(let x) = tail {
            path.line(to: NSPoint(x: x + w, y: body.maxY))
            path.line(to: NSPoint(x: x, y: body.maxY + h))
            path.line(to: NSPoint(x: x - w, y: body.maxY))
        }
        path.appendArc(withCenter: NSPoint(x: body.minX + r, y: body.maxY - r), radius: r, startAngle: 90, endAngle: 180)
        path.appendArc(withCenter: NSPoint(x: body.minX + r, y: body.minY + r), radius: r, startAngle: 180, endAngle: 270)
        path.close()
        return path
    }

    private func drawContent() {
        let m = Self.metrics(style)
        NSColor.separatorColor.setStroke()
        let edge = Self.path(in: bounds, radius: m.radius, tail: tail, inset: 0.25)
        edge.lineWidth = 0.5
        edge.stroke()

        let body = Self.body(in: bounds, tail: tail)
        let items = Self.items(style: style, enabled: enabled)
        // A lone badge sits in the middle of the bubble.
        var x = items == [.badge] ? body.midX - Self.width(of: .badge, style: style, enabled: enabled) / 2
            : body.minX + m.leading
        for (offset, item) in items.enumerated() {
            if offset > 0 { x += Self.gap(before: item) }
            let width = Self.width(of: item, style: style, enabled: enabled)
            switch item {
            case .badge:
                let size = FLBadge.size(height: m.badgeHeight)
                let rect = NSRect(x: x, y: body.midY - size.height / 2, width: size.width, height: size.height)
                FLBadge.draw(in: rect, enabled ? .cutOut(NoticeColor.indigo) : .outline(.secondaryLabelColor))
            case .word:
                let text = Self.word(enabled: enabled)
                let font = Self.wordFont
                // Centred on the cap height, like the badge's letters.
                let baseline = body.midY - font.capHeight / 2
                text.draw(at: NSPoint(x: x, y: baseline + font.descender))
            case .keys:
                for index in 0..<2 {
                    let rect = NSRect(x: x + CGFloat(index) * (Self.keySize + 3), y: body.midY - Self.keySize / 2,
                                      width: Self.keySize, height: Self.keySize)
                    drawKey(in: rect)
                }
            }
            x += width
        }
    }

    private func drawKey(in rect: NSRect) {
        let key = NSBezierPath(roundedRect: rect.insetBy(dx: 0.3, dy: 0.3), xRadius: 4.5, yRadius: 4.5)
        NoticeColor.key.setFill()
        key.fill()
        NoticeColor.keyEdge.setStroke()
        key.lineWidth = 0.6
        key.stroke()
        let shift = NSAttributedString(string: "⇧", attributes: [
            .font: Self.keyFont, .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let size = shift.size()
        shift.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    /// Draws over the material; ignores the mouse.
    private final class ContentView: NSView {
        var drawContent: (() -> Void)?

        override func draw(_ dirtyRect: NSRect) {
            drawContent?()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
