import XCTest
import CoreGraphics
@testable import CardScoutCore

final class CardPhotoCropTests: XCTestCase {
    func canvas() throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: 1000, height: 1400, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    func testBlankPhotoIsNotInventedIntoACard() throws {
        let context = try canvas()
        context.setFillColor(CGColor(gray: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1400))
        XCTAssertNil(CardPhotoCrop.crop(try XCTUnwrap(context.makeImage())))
    }

    func testPhysicalBorderIsKeptInsteadOfSmallerPrintedPanel() throws {
        let context = try canvas()
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1400))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 200, y: 280, width: 600, height: 840))
        context.setFillColor(CGColor(red: 0.7, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 240, y: 330, width: 520, height: 700))
        let crop = try XCTUnwrap(CardPhotoCrop.crop(try XCTUnwrap(context.makeImage())))
        XCTAssertEqual(Double(crop.width), 600, accuracy: 20)
        XCTAssertEqual(Double(crop.height), 840, accuracy: 20)
    }
}
