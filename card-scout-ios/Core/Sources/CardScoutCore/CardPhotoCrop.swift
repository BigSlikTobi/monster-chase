import CoreGraphics
import CoreImage
import Vision

/// Display-only perspective correction. Never replaces the capture used as evidence.
public enum CardPhotoCrop {
    public static func crop(_ image: CGImage) -> CGImage? {
        // Use a small, standard sRGB raster for consistent Vision input across
        // camera color spaces/devices. Apply the resulting corners to the full image.
        let scale = min(1, 1000 / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let raster = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        raster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let detectionImage = raster.makeImage() else { return nil }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 16
        request.minimumConfidence = 0.7
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 0.95
        request.minimumSize = 0.15
        request.quadratureTolerance = 25
        #if targetEnvironment(simulator)
        request.usesCPUOnly = true
        #endif
        do { try VNImageRequestHandler(cgImage: detectionImage).perform([request]) }
        catch { return nil }
        var observations = request.results ?? []
        if observations.isEmpty {
            let document = VNDetectDocumentSegmentationRequest()
            try? VNImageRequestHandler(cgImage: detectionImage).perform([document])
            observations = (document.results ?? []).filter { $0.confidence >= 0.7 }
        }
        let frames = observations.map { ScanCardFrame(corners: [$0.topLeft, $0.topRight, $0.bottomRight, $0.bottomLeft]) }
        guard let frame = ScanCardFrame.best(frames, imageSize: CGSize(width: image.width, height: image.height)),
              let card = observations.first(where: { [$0.topLeft, $0.topRight, $0.bottomRight, $0.bottomLeft] == frame.corners }) else { return nil }
        func vector(_ point: CGPoint) -> CIVector { CIVector(x: point.x * CGFloat(image.width), y: point.y * CGFloat(image.height)) }
        let corrected = CIImage(cgImage: image).applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": vector(card.topLeft), "inputTopRight": vector(card.topRight),
            "inputBottomLeft": vector(card.bottomLeft), "inputBottomRight": vector(card.bottomRight)
        ])
        let ratio = min(corrected.extent.width, corrected.extent.height) / max(corrected.extent.width, corrected.extent.height)
        guard ratio >= 0.55, ratio <= 0.88, corrected.extent.width > 120, corrected.extent.height > 120 else { return nil }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(corrected, from: corrected.extent)
    }
}
