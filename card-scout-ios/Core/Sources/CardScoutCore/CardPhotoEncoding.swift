import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CardPhotoEncoding {
    /// Apply EXIF rotation/mirroring to the pixels before stripping metadata.
    /// This preserves the photographed content without stretching or cropping it.
    public static func jpeg(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2600
              ] as CFDictionary) else { return nil }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92,
                                                      kCGImagePropertyOrientation: 1] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? encoded as Data : nil
    }
}
