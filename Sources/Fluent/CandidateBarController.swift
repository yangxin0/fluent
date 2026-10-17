import Cocoa
import FluentCore

/// The 小鹤双拼 candidate bar, styled after the system shuangpin input
/// method: a capsule of numbered candidates with the highlighted one on an
/// accent-color pill, a divider, then a chevron that expands the bar into a
/// grid of more candidates. System colors throughout, so it follows light
/// and dark. One shared instance; the active controller sets the callbacks
/// when it shows the bar.
final class CandidateBarController {
    static let shared = CandidateBarController()

    private let panel: NSPanel
    private let background = PanelChromeView()
    private let bar = CandidateBarView()

    /// Called with the index (into all candidates) of a clicked candidate.
    var onSelect: ((Int) -> Void)?
    /// Called with +1 / -1 to turn the page (scrolling).
    var onPage: ((Int) -> Void)?
    /// Called when the chevron is clicked.
    var onToggleExpanded: (() -> Void)?

    private init() {
        panel = PanelPlacement.makePanel()
        bar.frame = background.bounds
        bar.autoresizingMask = [.width, .height]
        background.addSubview(bar)
        panel.contentView = background
        bar.onSelect = { [weak self] index in self?.onSelect?(index) }
        bar.onPage = { [weak self] delta in self?.onPage?(delta) }
        bar.onToggleExpanded = { [weak self] in self?.onToggleExpanded?() }
    }

    /// `candidates` are shown in rows of `columns`, the first being
    /// candidate `firstIndex`; one row unless `expanded`. The highlighted
    /// row is numbered 1… for the number keys.
    func show(candidates: ArraySlice<ChineseCandidate>, highlighted: Int, columns: Int, expanded: Bool,
              canPageBack: Bool, canPageForward: Bool, appearance: String, near caretRect: NSRect) {
        PanelPlacement.applyAppearance(appearance, to: panel)
        bar.update(candidates: Array(candidates), firstIndex: candidates.startIndex, highlighted: highlighted,
                   columns: columns, expanded: expanded, canPageBack: canPageBack, canPageForward: canPageForward)
        background.cornerRadius = expanded ? CandidateBarView.cardRadius : CandidateBarView.rowHeight / 2
        let size = bar.fittingSize
        panel.setFrame(NSRect(origin: PanelPlacement.origin(for: size, caretRect: caretRect), size: size),
                       display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// Draws the cells itself: frames are simple sums and double as hit-test
/// rects.
private final class CandidateBarView: NSView {
    var onSelect: ((Int) -> Void)?
    var onPage: ((Int) -> Void)?
    var onToggleExpanded: (() -> Void)?

    static let rowHeight: CGFloat = 38
    private static let pillHeight: CGFloat = 30
    private static let edgeInset: CGFloat = 4
    private static let cellPadding: CGFloat = 9
    private static let cellSpacing: CGFloat = 2
    private static let chevronWidth: CGFloat = 30
    static let cardRadius: CGFloat = 12
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let textFont = NSFont.systemFont(ofSize: 18)
    private static let commentFont = NSFont.systemFont(ofSize: 12)

    private struct Cell {
        var index: Int
        var row: Int
        var column: Int
        var text: String
        var comment: String?
        var frame: NSRect
    }

    private var cells: [Cell] = []
    private var highlighted = 0
    private var columns = 1
    private var expanded = false
    private var hovered: Int?
    private var pressed: Int?
    private var canPageBack = false
    private var canPageForward = false
    private var scrollAccumulator: CGFloat = 0
    private var contentWidth: CGFloat = 0

    /// Pressing the chevron is this index in `pressed`.
    private static let chevronIndex = -1

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var fittingSize: NSSize {
        let rows = max(1, (cells.count + columns - 1) / columns)
        let height = expanded ? CGFloat(rows) * (Self.pillHeight + Self.cellSpacing) - Self.cellSpacing
            + 2 * Self.edgeInset : Self.rowHeight
        return NSSize(width: contentWidth + 1 + Self.chevronWidth + Self.edgeInset, height: height)
    }

    func update(candidates: [ChineseCandidate], firstIndex: Int, highlighted: Int, columns: Int,
                expanded: Bool, canPageBack: Bool, canPageForward: Bool) {
        self.highlighted = highlighted
        self.columns = max(columns, 1)
        self.expanded = expanded
        self.canPageBack = canPageBack
        self.canPageForward = canPageForward
        hovered = nil
        let widths = candidates.map(Self.cellWidth)
        // In the grid, every column is as wide as its widest cell so the rows
        // line up; a single row just packs its cells.
        var columnWidths = [CGFloat](repeating: 0, count: self.columns)
        for (offset, width) in widths.enumerated() {
            columnWidths[offset % self.columns] = max(columnWidths[offset % self.columns], width)
        }
        cells = candidates.enumerated().map { offset, candidate in
            let row = offset / self.columns, column = offset % self.columns
            let x = expanded
                ? Self.edgeInset + columnWidths[..<column].reduce(0, +) + CGFloat(column) * Self.cellSpacing
                : Self.edgeInset + widths[..<offset].reduce(0, +) + CGFloat(offset) * Self.cellSpacing
            let y = Self.edgeInset + CGFloat(row) * (Self.pillHeight + Self.cellSpacing)
            let width = expanded ? columnWidths[column] : widths[offset]
            return Cell(index: firstIndex + offset, row: row, column: column, text: candidate.text,
                        comment: candidate.comment, frame: NSRect(x: x, y: y, width: width, height: Self.pillHeight))
        }
        contentWidth = cells.map(\.frame.maxX).max() ?? Self.edgeInset
        needsDisplay = true
    }

    private static func cellWidth(_ candidate: ChineseCandidate) -> CGFloat {
        var width = cellPadding * 2 + measure("8", numberFont) + 5 + measure(candidate.text, textFont)
        if let comment = candidate.comment {
            width += 4 + measure(comment, commentFont)
        }
        return ceil(width)
    }

    private static func measure(_ string: String, _ font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    /// Next to the first row, after the divider.
    private var chevronFrame: NSRect {
        NSRect(x: contentWidth + 1, y: 0, width: Self.chevronWidth,
               height: Self.rowHeight)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let highlightedRow = cells.first { $0.index == highlighted }?.row
        for cell in cells {
            let isHighlighted = cell.index == highlighted
            if isHighlighted || cell.index == hovered {
                (isHighlighted ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor).setFill()
                let radius = cell.frame.height / 2
                NSBezierPath(roundedRect: cell.frame, xRadius: radius, yRadius: radius).fill()
            }
            let primary: NSColor = isHighlighted ? .white : .labelColor
            let secondary: NSColor = isHighlighted ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
            var x = cell.frame.minX + Self.cellPadding
            // Only the highlighted row is numbered: the number keys pick in it.
            if cell.row == highlightedRow {
                _ = drawText("\(cell.column + 1)", Self.numberFont, secondary, x: x, in: cell.frame)
            }
            x += Self.measure("8", Self.numberFont) + 5
            x += drawText(cell.text, Self.textFont, primary, x: x, in: cell.frame)
            if let comment = cell.comment {
                _ = drawText(comment, Self.commentFont, secondary, x: x + 4, in: cell.frame)
            }
        }

        // Divider, then the chevron: down to expand (dimmed when there is
        // nothing more), up to collapse the grid.
        let chevron = chevronFrame
        NSColor.separatorColor.setFill()
        NSRect(x: chevron.minX, y: 10, width: 1, height: Self.rowHeight - 20).fill()
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                accessibilityDescription: expanded ? "Fewer candidates" : "More candidates")?
            .withSymbolConfiguration(config) {
            let tint: NSColor = expanded || canPageForward ? .secondaryLabelColor : .tertiaryLabelColor
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                tint.set()
                rect.fill(using: .sourceIn)
                return true
            }
            let origin = NSPoint(x: chevron.midX - symbol.size.width / 2, y: chevron.midY - symbol.size.height / 2)
            tinted.draw(in: NSRect(origin: origin, size: symbol.size))
        }
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
        return cells.first { $0.frame.contains(point) }?.index
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
            if expanded || canPageForward { onToggleExpanded?() }
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
