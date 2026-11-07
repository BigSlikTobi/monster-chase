import XCTest
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import CardScoutCore

final class CardPhotoEncodingTests: XCTestCase {
    func testAllExifRotationsAndMirrorsAreBakedIntoPixels() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8,
            bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let colors: [[CGFloat]] = [[1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1], [1, 1, 0, 1]]
        for index in 0..<4 {
            context.setFillColor(try XCTUnwrap(CGColor(colorSpace: space, components: colors[index])))
            context.fill(CGRect(x: (index % 2) * 300, y: (index / 2) * 200, width: 300, height: 200))
        }
        let original = try XCTUnwrap(context.makeImage())
        let renderer = CIContext()
        for orientation in 1...8 {
            let source = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(source, UTType.tiff.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, original, [kCGImagePropertyOrientation: orientation,
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 52.0, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let jpeg = try XCTUnwrap(CardPhotoEncoding.jpeg(source as Data))
            let decoded = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
            let actual = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
            let expectedCI = CIImage(cgImage: original).oriented(forExifOrientation: Int32(orientation))
            let expected = try XCTUnwrap(renderer.createCGImage(expectedCI, from: expectedCI.extent))
            XCTAssertEqual(actual.width, expected.width, "EXIF \(orientation)")
            XCTAssertEqual(actual.height, expected.height, "EXIF \(orientation)")
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [String: Any])
            XCTAssertEqual((properties[kCGImagePropertyOrientation as String] as? Int) ?? 1, 1)
            XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
            for (x, y) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] {
                let a = try pixel(actual, x: x, y: y), e = try pixel(expected, x: x, y: y)
                for component in 0..<3 { XCTAssertEqual(a[component], e[component], accuracy: 12, "EXIF \(orientation)") }
            }
            let second = try XCTUnwrap(CardPhotoEncoding.jpeg(jpeg))
            let secondSource = try XCTUnwrap(CGImageSourceCreateWithData(second as CFData, nil))
            let secondImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(secondSource, 0, nil))
            XCTAssertEqual(secondImage.width, actual.width)
            XCTAssertEqual(secondImage.height, actual.height)
        }
    }
    private func pixel(_ image: CGImage, x: Double, y: Double) throws -> [Double] {
        let cropped = try XCTUnwrap(image.cropping(to: CGRect(x: Int(Double(image.width) * x), y: Int(Double(image.height) * y), width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes.map(Double.init)
    }
    func testInvalidPhotoIsRejected() { XCTAssertNil(CardPhotoEncoding.jpeg(Data([1, 2, 3]))) }
}
