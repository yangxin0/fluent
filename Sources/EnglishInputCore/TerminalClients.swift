import Foundation

/// Terminal emulators draw IME marked text as a single row at the cursor and
/// clip whatever runs past the window edge, so a long composition becomes
/// invisible. For these clients the IME also shows the typed text in its own
/// panel once the composition nears the edge. Users can override detection
/// via the `terminalMode` config key.
public enum TerminalClients {
    public static let bundleIDs: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "dev.warp.warp-stable",
        "dev.warp.warp",
        "com.raphaelamorim.rio",
        "co.zeit.hyper",
        "org.tabby",
    ]

    /// `extra` lets the config add apps to the built-in whitelist.
    public static func isTerminal(bundleID: String?, extra: [String] = []) -> Bool {
        guard let bundleID else { return false }
        let id = bundleID.lowercased()
        return bundleIDs.contains(id) || extra.contains { $0.lowercased() == id }
    }
}

/// Predicts whether a monospaced client's marked text is about to run past
/// the window edge. Pure geometry so it can be unit-tested. Every call uses
/// the caret rect and window edge measured *now*, so a window that moves or
/// resizes mid-composition is handled.
public struct EdgeTracker: Equatable {
    /// Plausible cell widths in points; outside this the caret rect's width
    /// is not a cell and we estimate from the line height instead.
    public static let cellWidthRange = 3.0...40.0
    public static let lineHeightRange = 8.0...80.0
    /// Typical monospace advance as a fraction of the *line* height (a line
    /// is ~1.2× the font size and the advance ~0.6× the size), used when
    /// only the line height is usable. Slightly high on purpose: it is
    /// better to show the typed text a little early than a little late.
    public static let monoAspect = 0.5
    /// Fallback when no usable geometry is available.
    public static let fallbackCharacterLimit = 60

    /// Whether the client's caret rect follows the end of the marked text
    /// (true), stays at its start (false), or has not been determined yet.
    public private(set) var caretFollowsText: Bool?
    private var lastMinX: Double?
    private var lastCount: Int?

    public init() {}

    /// `known` is an exact width (from the client's font or the config) and
    /// wins when plausible; then the caret rect's own width; then an
    /// estimate from the line height.
    public static func cellWidth(caretWidth: Double, caretHeight: Double, known: Double? = nil) -> Double? {
        if let known, cellWidthRange.contains(known) { return known }
        if cellWidthRange.contains(caretWidth) { return caretWidth }
        if lineHeightRange.contains(caretHeight) { return caretHeight * monoAspect }
        return nil
    }

    /// Feed the current measurement; returns whether the marked text is
    /// within `marginCells` of `edgeX`.
    public mutating func update(caretMinX: Double, caretMaxX: Double, caretHeight: Double,
                                characterCount: Int, edgeX: Double,
                                knownCellWidth: Double? = nil,
                                marginCells: Double = 2) -> Bool {
        guard let width = Self.cellWidth(caretWidth: caretMaxX - caretMinX, caretHeight: caretHeight,
                                         known: knownCellWidth)
        else { return characterCount >= Self.fallbackCharacterLimit }

        // Learn from consecutive keystrokes whether the rect moved by the
        // typed distance (follows the text) or stayed put (anchored). Any
        // other jump means the window moved; keep what we knew.
        if let lastMinX, let lastCount, characterCount != lastCount {
            let dx = caretMinX - lastMinX
            let expected = Double(characterCount - lastCount) * width
            if abs(dx - expected) < width / 2 {
                caretFollowsText = true
            } else if abs(dx) < width / 2 {
                caretFollowsText = false
            }
        }
        lastMinX = caretMinX
        lastCount = characterCount

        let end = caretFollowsText == true
            ? caretMaxX
            : caretMinX + Double(characterCount) * width
        return end >= edgeX - marginCells * width
    }
}
