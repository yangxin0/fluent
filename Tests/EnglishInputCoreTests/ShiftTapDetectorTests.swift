import XCTest
@testable import EnglishInputCore

final class ShiftTapDetectorTests: XCTestCase {
    private var detector = ShiftTapDetector(maxTapDuration: 0.3, maxTapInterval: 0.4)

    func testQuickDoubleTapFires() {
        detector.shiftDown(at: 0.0)
        XCTAssertFalse(detector.shiftUp(at: 0.1))
        detector.shiftDown(at: 0.3)
        XCTAssertTrue(detector.shiftUp(at: 0.4))
    }

    func testTripleTapFiresOnlyOnce() {
        detector.shiftDown(at: 0.0)
        _ = detector.shiftUp(at: 0.1)
        detector.shiftDown(at: 0.2)
        XCTAssertTrue(detector.shiftUp(at: 0.3))
        // The sequence resets after firing; a lone third tap is a fresh first tap.
        detector.shiftDown(at: 0.4)
        XCTAssertFalse(detector.shiftUp(at: 0.5))
    }

    func testSlowSecondTapDoesNotFire() {
        detector.shiftDown(at: 0.0)
        _ = detector.shiftUp(at: 0.1)
        detector.shiftDown(at: 1.0)  // gap 0.9 > maxTapInterval
        XCTAssertFalse(detector.shiftUp(at: 1.1))
    }

    func testLongHoldIsNotATap() {
        detector.shiftDown(at: 0.0)
        XCTAssertFalse(detector.shiftUp(at: 0.5))  // held 0.5 > maxTapDuration
        detector.shiftDown(at: 0.6)
        XCTAssertFalse(detector.shiftUp(at: 0.7))
    }

    func testKeypressBetweenTapsInterrupts() {
        detector.shiftDown(at: 0.0)
        _ = detector.shiftUp(at: 0.1)
        detector.interrupt()  // user typed a key
        detector.shiftDown(at: 0.2)
        XCTAssertFalse(detector.shiftUp(at: 0.3))
    }

    func testShiftedLetterDoesNotCountAsTap() {
        // Shift down, letter typed (interrupt), shift up — like typing "A".
        detector.shiftDown(at: 0.0)
        detector.interrupt()
        XCTAssertFalse(detector.shiftUp(at: 0.1))
        // Followed by a genuine double tap, which still works.
        detector.shiftDown(at: 0.3)
        XCTAssertFalse(detector.shiftUp(at: 0.4))
        detector.shiftDown(at: 0.5)
        XCTAssertTrue(detector.shiftUp(at: 0.6))
    }

    func testHoldThenTapDoesNotFire() {
        detector.shiftDown(at: 0.0)
        _ = detector.shiftUp(at: 0.5)  // hold, not a tap
        detector.shiftDown(at: 0.6)
        XCTAssertFalse(detector.shiftUp(at: 0.7))  // first real tap
        detector.shiftDown(at: 0.8)
        XCTAssertTrue(detector.shiftUp(at: 0.9))  // second tap fires
    }
}
