import XCTest
import CoreGraphics
@testable import CardScoutCore

final class CaptureGateTests: XCTestCase {
    func testAutofocusPulsesDoNotEraseAcceptableHandheldMotion() {
        var gate = CaptureGate()
        XCTAssertFalse(gate.update(rect: card, at: 0))
        XCTAssertFalse(gate.update(rect: card.offsetBy(dx: 0.01, dy: 0.01), at: 0.13, focusReady: false))
        XCTAssertTrue(gate.update(rect: card.offsetBy(dx: 0.025, dy: 0.015), at: 0.26))
        XCTAssertFalse(gate.update(rect: card, at: 0.4))
    }
    func testQualityFailureCannotAutoCaptureAndDoesNotRearmSameCard() {
        var gate = CaptureGate()
        XCTAssertFalse(gate.update(rect: card, at: 0))
        XCTAssertFalse(gate.update(rect: card, at: 1, qualityReady: false))
        XCTAssertFalse(gate.update(rect: card, at: 2))
        XCTAssertTrue(gate.update(rect: card, at: 3))
        XCTAssertFalse(gate.update(rect: card, at: 4, qualityReady: false))
        XCTAssertFalse(gate.isArmed)
        _ = gate.update(rect: nil, at: 5, qualityReady: false)
        _ = gate.update(rect: nil, at: 6, qualityReady: false)
        XCTAssertTrue(gate.isArmed)
    }
    let card = CGRect(x: 0.2, y: 0.15, width: 0.5, height: 0.7)
    func testAutomaticFrontBackPairRequiresRemovalBetweenSides() {
        var gate = CaptureGate()
        XCTAssertFalse(gate.update(rect: card, at: 0))
        XCTAssertTrue(gate.update(rect: card, at: 0.15))
        // Keeping the same front visible must never become a back photo.
        XCTAssertFalse(gate.update(rect: card, at: 0.3))
        XCTAssertFalse(gate.update(rect: card, at: 1))
        XCTAssertFalse(gate.update(rect: nil, at: 1.1))
        XCTAssertFalse(gate.update(rect: nil, at: 1.7))
        XCTAssertTrue(gate.isArmed)
        XCTAssertFalse(gate.update(rect: card, at: 1.85))
        XCTAssertTrue(gate.update(rect: card, at: 2))
        XCTAssertFalse(gate.update(rect: card, at: 2.15))
    }
    func testFocusedCardCanCaptureWithoutPreviewTextRecognition() {
        let frame = ScanCardFrame(corners: [CGPoint(x: 0.2, y: 0.85), CGPoint(x: 0.7, y: 0.85),
                                            CGPoint(x: 0.7, y: 0.15), CGPoint(x: 0.2, y: 0.15)])
        let readiness = CaptureReadiness.evaluate(frame: frame, focusReady: true)
        XCTAssertEqual(readiness, .ready)
        var gate = CaptureGate()
        XCTAssertFalse(gate.update(rect: frame.bounds, at: 0, qualityReady: readiness == .ready))
        XCTAssertTrue(gate.update(rect: frame.bounds, at: 0.6, qualityReady: readiness == .ready))
        XCTAssertEqual(CaptureReadiness.evaluate(frame: frame, focusReady: false), .focusing)
        XCTAssertEqual(CaptureReadiness.evaluate(frame: nil, focusReady: true), .missingCard)
        let small = ScanCardFrame(corners: [CGPoint(x: 0.4, y: 0.6), CGPoint(x: 0.6, y: 0.6),
                                            CGPoint(x: 0.6, y: 0.4), CGPoint(x: 0.4, y: 0.4)])
        XCTAssertEqual(CaptureReadiness.evaluate(frame: small, focusReady: true), .tooSmall)
    }
    func testSmallHandShakeDoesNotRequirePreciseAlignment() {
        var gate = CaptureGate()
        XCTAssertFalse(gate.update(rect: card, at: 0))
        XCTAssertTrue(gate.update(rect: card.offsetBy(dx: 0.03, dy: -0.02), at: 0.2))
        XCTAssertFalse(gate.update(rect: card.offsetBy(dx: -0.02, dy: 0.03), at: 0.5))
    }
    func testGentleHandheldDriftCanCapture() {
        var gate = CaptureGate()
        XCTAssertFalse(gate.update(rect: card, at: 0))
        XCTAssertTrue(gate.update(rect: card.offsetBy(dx: 0.025, dy: 0.02), at: 0.15))
        XCTAssertFalse(gate.update(rect: card.offsetBy(dx: 0.05, dy: 0.04), at: 0.3))
    }
    func testRapidMotionWithinPositionToleranceStillBlocksCapture() {
        var gate = CaptureGate()
        for step in 0...12 {
            XCTAssertFalse(gate.update(rect: card.offsetBy(dx: Double(step) * 0.04, dy: 0),
                                       at: Double(step) * 0.04))
        }
    }
    func testLongDetectionGapRequiresFreshFrames() {
        var gate = CaptureGate()
        XCTAssertFalse(gate.update(rect: card, at: 0))
        XCTAssertFalse(gate.update(rect: card, at: 3))
        XCTAssertTrue(gate.update(rect: card, at: 3.15))
    }
    func testFocusTransitionCannotRearmTheSameCapturedCard() {
        var gate = CaptureGate(); gate.didCapture()
        _ = gate.update(rect: nil, at: 1, focusReady: false)
        _ = gate.update(rect: nil, at: 2, focusReady: false)
        XCTAssertFalse(gate.isArmed)
        XCTAssertFalse(gate.update(rect: card, at: 3))
    }
    func testFocusBlocksShutterButKeepsTheStableCardCandidate() {
        var gate = CaptureGate()
        XCTAssertFalse(gate.update(rect: card, at: 0))
        XCTAssertFalse(gate.update(rect: card, at: 1, focusReady: false))
        XCTAssertTrue(gate.isArmed)
        XCTAssertTrue(gate.update(rect: card, at: 2))
        XCTAssertFalse(gate.update(rect: card, at: 2.15))
        XCTAssertFalse(gate.update(rect: card, at: 2.8))
    }
    func testStableCardIsCapturedOnceEvenIfItStaysInFrame() {
        var gate = CaptureGate()
        XCTAssertFalse(gate.update(rect: card, at: 0))
        XCTAssertTrue(gate.update(rect: card, at: 0.8))
        for time in 1...20 { XCTAssertFalse(gate.update(rect: card, at: Double(time))) }
    }
    func testMovingCardsNeverTriggerUntilTheySettle() {
        var gate = CaptureGate()
        for time in 0...10 {
            let rect = card.offsetBy(dx: time.isMultiple(of: 2) ? 0.1 : -0.1, dy: 0)
            XCTAssertFalse(gate.update(rect: rect, at: Double(time)))
        }
        XCTAssertFalse(gate.update(rect: card, at: 11))
        XCTAssertTrue(gate.update(rect: card, at: 12))
    }
    func testBriefOcclusionDoesNotCaptureSameCardAgain() {
        var gate = CaptureGate(); gate.didCapture()
        _ = gate.update(rect: nil, at: 1)
        _ = gate.update(rect: nil, at: 1.2)
        XCTAssertFalse(gate.update(rect: card, at: 1.4))
        XCTAssertFalse(gate.update(rect: card, at: 2.4))
    }
    func testNewCardAfterRemovalCanBeCaptured() {
        var gate = CaptureGate(); gate.didCapture()
        _ = gate.update(rect: nil, at: 1)
        _ = gate.update(rect: nil, at: 1.6)
        XCTAssertTrue(gate.isArmed)
        XCTAssertFalse(gate.update(rect: card, at: 2))
        XCTAssertTrue(gate.update(rect: card, at: 2.8))
    }
}
