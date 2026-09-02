import XCTest
@testable import EnglishInputCore

final class TerminalClientsTests: XCTestCase {
    func testDetection() {
        XCTAssertTrue(TerminalClients.isTerminal(bundleID: "com.github.wez.wezterm"))
        XCTAssertTrue(TerminalClients.isTerminal(bundleID: "com.apple.Terminal"))
        XCTAssertTrue(TerminalClients.isTerminal(bundleID: "com.googlecode.iterm2"))
        XCTAssertFalse(TerminalClients.isTerminal(bundleID: "com.apple.Safari"))
        XCTAssertFalse(TerminalClients.isTerminal(bundleID: "com.microsoft.VSCode"))
        XCTAssertFalse(TerminalClients.isTerminal(bundleID: nil))
        XCTAssertTrue(TerminalClients.isTerminal(bundleID: "com.microsoft.VSCode",
                                                 extra: ["com.microsoft.vscode"]))
    }

    func testTerminalAppsDecodes() throws {
        let json = #"{"baseURL":"https://x/v1","apiKey":"k","model":"m","terminalApps":["com.example.term"]}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.terminalApps, ["com.example.term"])
    }

    // Window spans x = 0...800, 8pt cells (16pt lines), composition at x = 400.

    /// Type `chars` characters one at a time, feeding the tracker a rect per
    /// keystroke; returns the result of the last keystroke.
    private func type(_ chars: Int, caretX: (Int) -> Double, width: Double = 8, edge: Double = 800) -> (EdgeTracker, Bool) {
        var tracker = EdgeTracker()
        var reached = false
        for n in 1...chars {
            let x = caretX(n)
            reached = tracker.update(caretMinX: x, caretMaxX: x + width, caretHeight: 16,
                                     characterCount: n, edgeX: edge)
        }
        return (tracker, reached)
    }

    func testStartAnchoredCaretUsesCharacterCount() {
        // Rect stays at the start of the marked text (WezTerm style).
        let (tracker, at47) = type(47, caretX: { _ in 400 })
        XCTAssertEqual(tracker.caretFollowsText, false)
        XCTAssertFalse(at47)                                // ends at 776, margin at 784
        XCTAssertTrue(type(48, caretX: { _ in 400 }).1)     // ends at 784
    }

    func testEndAnchoredCaretUsesCaretPosition() {
        // Rect follows the end of the marked text; count must not be double-counted.
        let (tracker, at10) = type(10, caretX: { n in 400 + Double(n) * 8 })
        XCTAssertEqual(tracker.caretFollowsText, true)
        XCTAssertFalse(at10)
        XCTAssertFalse(type(46, caretX: { n in 400 + Double(n) * 8 }).1)  // maxX 776
        XCTAssertTrue(type(47, caretX: { n in 400 + Double(n) * 8 }).1)   // maxX 784
    }

    func testWindowMovingMidCompositionUsesFreshGeometry() {
        // Anchored caret; after 10 chars the window (and rect) jump left by 300.
        var tracker = EdgeTracker()
        var reached = false
        for n in 1...30 {
            let x: Double = n <= 10 ? 400 : 100
            reached = tracker.update(caretMinX: x, caretMaxX: x + 8, caretHeight: 16,
                                     characterCount: n, edgeX: n <= 10 ? 800 : 500)
        }
        XCTAssertEqual(tracker.caretFollowsText, false)
        XCTAssertFalse(reached)   // 100 + 30*8 = 340 < 484
        for n in 31...48 {
            reached = tracker.update(caretMinX: 100, caretMaxX: 108, caretHeight: 16,
                                     characterCount: n, edgeX: 500)
        }
        XCTAssertTrue(reached)    // 100 + 48*8 = 484
    }

    func testZeroWidthRectEstimatesCellFromLineHeight() {
        // Width 0, height 16 → 8pt cells; 48 chars from x=400 end at 784.
        XCTAssertEqual(EdgeTracker.cellWidth(caretWidth: 0, caretHeight: 16), 8)
        XCTAssertFalse(type(47, caretX: { _ in 400 }, width: 0).1)
        XCTAssertTrue(type(48, caretX: { _ in 400 }, width: 0).1)
    }

    func testKnownCellWidthWinsOverEstimates() {
        XCTAssertEqual(EdgeTracker.cellWidth(caretWidth: 1, caretHeight: 20.5, known: 9.7), 9.7)
        XCTAssertEqual(EdgeTracker.cellWidth(caretWidth: 12, caretHeight: 20.5, known: 9.7), 9.7)
        // Implausible override is ignored.
        XCTAssertEqual(EdgeTracker.cellWidth(caretWidth: 12, caretHeight: 20.5, known: 500), 12)
        // WezTerm-like: 1pt-wide rect, 1920pt window, real cell 9.7 → ~195 cells.
        var tracker = EdgeTracker()
        var reached = false
        for n in 1...190 {
            reached = tracker.update(caretMinX: 27, caretMaxX: 28, caretHeight: 20.5,
                                     characterCount: n, edgeX: 1920, knownCellWidth: 9.7)
        }
        XCTAssertFalse(reached)
        XCTAssertTrue(tracker.update(caretMinX: 27, caretMaxX: 28, caretHeight: 20.5,
                                     characterCount: 194, edgeX: 1920, knownCellWidth: 9.7))
    }

    func testNoUsableGeometryFallsBackToLength() {
        XCTAssertNil(EdgeTracker.cellWidth(caretWidth: 0, caretHeight: 0))
        var tracker = EdgeTracker()
        XCTAssertFalse(tracker.update(caretMinX: 0, caretMaxX: 0, caretHeight: 0,
                                      characterCount: 59, edgeX: 800))
        XCTAssertTrue(tracker.update(caretMinX: 0, caretMaxX: 0, caretHeight: 0,
                                     characterCount: 60, edgeX: 800))
    }
}
