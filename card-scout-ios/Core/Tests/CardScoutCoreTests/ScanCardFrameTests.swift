import XCTest
@testable import CardScoutCore

final class ScanCardFrameTests: XCTestCase {
    let imageSize = CGSize(width: 1200, height: 1600)
    func frame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> ScanCardFrame {
        ScanCardFrame(corners: [CGPoint(x: x, y: y + height), CGPoint(x: x + width, y: y + height),
                               CGPoint(x: x + width, y: y), CGPoint(x: x, y: y)])
    }
    func testCardCanSitAwayFromCentreWithoutFittingAGuide() {
        let card = frame(x: 0.64, y: 0.12, width: 0.30, height: 0.315)
        XCTAssertFalse(card.bounds.contains(CGPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(ScanCardFrame.best([card], imageSize: imageSize), card)
    }
    func testTiltedAndLandscapeCardsAreAccepted() {
        let tilted = ScanCardFrame(corners: [CGPoint(x: 0.21, y: 0.80), CGPoint(x: 0.71, y: 0.87),
                                             CGPoint(x: 0.81, y: 0.28), CGPoint(x: 0.30, y: 0.22)])
        XCTAssertNotNil(ScanCardFrame.best([tilted], imageSize: imageSize))
        let horizontal = frame(x: 0.10, y: 0.28, width: 0.75, height: 0.40)
        XCTAssertEqual(ScanCardFrame.best([horizontal], imageSize: imageSize), horizontal)
    }
    func testCroppedTinyAndSquareObjectsNeverTriggerAutoCapture() {
        let clipped = frame(x: -0.02, y: 0.2, width: 0.6, height: 0.63)
        let tiny = frame(x: 0.4, y: 0.4, width: 0.1, height: 0.105)
        let square = frame(x: 0.2, y: 0.2, width: 0.6, height: 0.45)
        XCTAssertNil(ScanCardFrame.best([clipped, tiny, square], imageSize: imageSize))
    }
    func testPhysicalBorderWinsOverAnInnerPrintedPanel() {
        let outer = frame(x: 0.2, y: 0.15, width: 0.6, height: 0.63)
        let inner = frame(x: 0.3, y: 0.25, width: 0.4, height: 0.42)
        XCTAssertEqual(ScanCardFrame.best([inner, outer], imageSize: imageSize), outer)
    }
    func testOutlineMatchesAspectFillAndVisionVerticalOrigin() {
        let card = frame(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let points = card.previewPoints(imageSize: CGSize(width: 300, height: 400), viewSize: CGSize(width: 300, height: 400))
        XCTAssertEqual(points[0].x, 60, accuracy: 0.001)
        XCTAssertEqual(points[0].y, 80, accuracy: 0.001)
        let cropped = card.previewPoints(imageSize: CGSize(width: 300, height: 400), viewSize: CGSize(width: 300, height: 300))
        XCTAssertEqual(cropped[0].y, 30, accuracy: 0.001)
        let fitted = card.previewPoints(imageSize: CGSize(width: 300, height: 400), viewSize: CGSize(width: 300, height: 300), aspectFill: false)
        XCTAssertEqual(fitted[0].x, 82.5, accuracy: 0.001)
        XCTAssertEqual(fitted[0].y, 60, accuracy: 0.001)
    }
}
