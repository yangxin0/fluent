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

    func testBurstOfTapsTogglesOnce() {
        // Timings from a real log: four taps in ~0.7s used to toggle twice.
        var d = ShiftTapDetector()
        var fired = 0
        for (down, up) in [(16.312, 16.397), (16.484, 16.557), (16.637, 16.712), (17.014, 17.123)] {
            d.shiftDown(at: down)
            if d.shiftUp(at: up) { fired += 1 }
        }
        XCTAssertEqual(fired, 1)
        // A fresh double tap after the cooldown toggles again.
        d.shiftDown(at: 19.110); XCTAssertFalse(d.shiftUp(at: 19.188))
        d.shiftDown(at: 19.258); XCTAssertTrue(d.shiftUp(at: 19.338))
    }

    func testDoubleTapsHalfASecondApartAllFire() {
        // Timings from a real log: three deliberate double taps, the third
        // ~0.5s after the second fired, were eaten by a 0.6s cooldown.
        var d = ShiftTapDetector()
        var fired = 0
        for (down, up) in [(17.137, 17.216), (17.286, 17.369),
                           (18.033, 18.115), (18.210, 18.296),
                           (18.820, 18.930), (19.002, 19.085)] {
            d.shiftDown(at: down)
            if d.shiftUp(at: up) { fired += 1 }
        }
        XCTAssertEqual(fired, 3)
    }
}
