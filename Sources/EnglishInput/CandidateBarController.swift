import Cocoa
import EnglishInputCore

/// The 小鹤双拼 candidate bar, styled after the system shuangpin input
/// method: a capsule of numbered candidates with the highlighted one on an
/// accent-color pill, a divider, then a chevron for the next page. System
/// colors throughout, so it follows light and dark. One shared instance;
/// the active controller sets the callbacks when it shows the bar.
final class CandidateBarController {
    static let shared = CandidateBarController()

    private let panel: NSPanel
    private let background = NSVisualEffectView()
    private let bar = CandidateBarView()

    /// Called with the index on the current page when a candidate is clicked.
    var onSelect: ((Int) -> Void)?
    /// Called with +1 / -1 to turn the page (chevron click, scrolling).
    var onPage: ((Int) -> Void)?

    private init() {
        panel = PanelPlacement.makePanel()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active  // stay vibrant: the IME is never the active app
        background.maskImage = CandidateBarView.capsuleMask
        bar.frame = background.bounds
        bar.autoresizingMask = [.width, .height]
        background.addSubview(bar)
        panel.contentView = background
        bar.onSelect = { [weak self] index in self?.onSelect?(index) }
        bar.onPage = { [weak self] delta in self?.onPage?(delta) }
    }

    func show(candidates: ArraySlice<ChineseCandidate>, highlighted: Int, page: Int, pageCount: Int,
              appearance: String, near caretRect: NSRect) {
        PanelPlacement.applyAppearance(appearance, to: panel)
        bar.update(candidates: Array(candidates), highlighted: highlighted,
                   canPageBack: page > 0, canPageForward: page + 1 < pageCount)
        let size = bar.fittingSize
        panel.setFrame(NSRect(origin: PanelPlacement.origin(for: size, caretRect: caretRect), size: size),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// Draws the cells itself: the bar is one row that never wraps, so frames
/// are simple sums and double as hit-test rects.
private final class CandidateBarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onPage: ((Int) -> Void)?

    static let height: CGFloat = 38
    private static let pillHeight: CGFloat = 30
    private static let edgeInset: CGFloat = 4
    private static let cellPadding: CGFloat = 9
    private static let cellSpacing: CGFloat = 2
    private static let chevronWidth: CGFloat = 30
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let textFont = NSFont.systemFont(ofSize: 18)
    private static let commentFont = NSFont.systemFont(ofSize: 12)

    /// A capsule the background is masked to; stretches to any width.
    static let capsuleMask: NSImage = {
        let side = height
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: side / 2, yRadius: side / 2).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: side / 2, left: side / 2, bottom: side / 2, right: side / 2)
        image.resizingMode = .stretch
        return image
    }()

    private struct Cell {
        var number: String
        var text: String
        var comment: String?
        var frame: NSRect
    }

    private var cells: [Cell] = []
    private var highlighted = 0
    private var hovered: Int?
    private var pressed: Int?
    private var canPageBack = false
    private var canPageForward = false
    private var scrollAccumulator: CGFloat = 0

    /// Pressing the chevron is index -1 in `pressed`.
    private static let chevronIndex = -1

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var fittingSize: NSSize {
        let cellsWidth = (cells.last?.frame.maxX ?? Self.edgeInset)
        return NSSize(width: cellsWidth + 1 + Self.chevronWidth + Self.edgeInset, height: Self.height)
    }

    func update(candidates: [ChineseCandidate], highlighted: Int, canPageBack: Bool, canPageForward: Bool) {
        self.highlighted = highlighted
        self.canPageBack = canPageBack
        self.canPageForward = canPageForward
        hovered = nil
        var x = Self.edgeInset
        cells = candidates.enumerated().map { offset, candidate in
            let number = "\(offset + 1)"
            var width = Self.cellPadding * 2 + Self.measure(number, Self.numberFont) + 5
                + Self.measure(candidate.text, Self.textFont)
            if let comment = candidate.comment {
                width += 4 + Self.measure(comment, Self.commentFont)
            }
            let frame = NSRect(x: x, y: Self.edgeInset, width: ceil(width), height: Self.pillHeight)
            x = frame.maxX + Self.cellSpacing
            return Cell(number: number, text: candidate.text, comment: candidate.comment, frame: frame)
        }
        needsDisplay = true
    }

    private static func measure(_ string: String, _ font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    private var chevronFrame: NSRect {
        let x = (cells.last?.frame.maxX ?? Self.edgeInset) + 1
        return NSRect(x: x, y: 0, width: Self.chevronWidth, height: Self.height)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        for (index, cell) in cells.enumerated() {
            let isHighlighted = index == highlighted
            if isHighlighted || index == hovered {
                (isHighlighted ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).setFill()
                let radius = cell.frame.height / 2
                NSBezierPath(roundedRect: cell.frame, xRadius: radius, yRadius: radius).fill()
            }
            let primary: NSColor = isHighlighted ? .white : .labelColor
            let secondary: NSColor = isHighlighted ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
            var x = cell.frame.minX + Self.cellPadding
            x += drawText(cell.number, Self.numberFont, secondary, x: x, in: cell.frame) + 5
            x += drawText(cell.text, Self.textFont, primary, x: x, in: cell.frame)
            if let comment = cell.comment {
                _ = drawText(comment, Self.commentFont, secondary, x: x + 4, in: cell.frame)
            }
        }

        // Divider, then the chevron (dimmed on the last page).
        let chevron = chevronFrame
        NSColor.separatorColor.setFill()
        NSRect(x: chevron.minX, y: 10, width: 1, height: Self.height - 20).fill()
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next page")?
            .withSymbolConfiguration(config) {
            let tint: NSColor = canPageForward ? .secondaryLabelColor : .tertiaryLabelColor
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                tint.set()
                rect.fill(using: .sourceIn)
                return true
            }
            let origin = NSPoint(x: chevron.midX - symbol.size.width / 2, y: chevron.midY - symbol.size.height / 2)
            tinted.draw(in: NSRect(origin: origin, size: symbol.size))
        }

        // Hairline edge so the capsule reads on any background.
        NSColor.separatorColor.setStroke()
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                xRadius: Self.height / 2, yRadius: Self.height / 2)
        edge.lineWidth = 0.5
        edge.stroke()
    }

    /// Draws `string` vertically centered in `frame` at `x`; returns its width.
    private func drawText(_ string: String, _ font: NSFont, _ color: NSColor, x: CGFloat, in frame: NSRect) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: x, y: frame.midY - size.height / 2))
        return size.width
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // .activeAlways: the IME process is never the active app.
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }

    private func target(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        if chevronFrame.contains(point) { return Self.chevronIndex }
        return cells.firstIndex { $0.frame.contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        let target = target(at: event).flatMap { $0 == Self.chevronIndex ? nil : $0 }
        if target != hovered {
            hovered = target
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = target(at: event)
    }

    /// Acts only if released over what was pressed, like a button.
    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let pressed, pressed == target(at: event) else { return }
        if pressed == Self.chevronIndex {
            if canPageForward { onPage?(1) }
        } else {
            onSelect?(pressed)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY
        guard abs(scrollAccumulator) > 10 else { return }
        let delta = scrollAccumulator < 0 ? 1 : -1
        scrollAccumulator = 0
        if (delta > 0 && canPageForward) || (delta < 0 && canPageBack) { onPage?(delta) }
    }
}
