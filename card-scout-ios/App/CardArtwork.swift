import UIKit
import ImageIO
import CardScoutCore

/// All display decoding and Vision work runs off the main actor.
actor CardImageDecoder {
    static let shared = CardImageDecoder()

    func image(data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(source, maxPixel: maxPixel)
    }

    func image(url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(source, maxPixel: maxPixel)
    }

    private func thumbnail(_ source: CGImageSource, maxPixel: Int) -> UIImage? {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    /// Cached display cutout: perspective-correct the physical card, without a stage or mat.
    /// An uncertain detection falls back to the photo rather than cutting printed artwork.
    func cutout(url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: min(3200, max(1600, maxPixel * 2))
              ] as CFDictionary) else { return nil }
        let card = CardPhotoCrop.crop(image) ?? image
        let scale = min(1, CGFloat(maxPixel) / CGFloat(max(card.width, card.height)))
        let size = CGSize(width: max(1, CGFloat(card.width) * scale), height: max(1, CGFloat(card.height) * scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: card).draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func artwork(url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(3200, max(1600, maxPixel * 2))
              ] as CFDictionary) else { return nil }
        // If all four edges cannot be found, show the photo unchanged. Never guess a cut.
        guard let card = CardPhotoCrop.crop(image) else {
            // Even an uncropped fallback must fit its thumbnail budget.
            let scale = min(1, CGFloat(maxPixel) / CGFloat(max(image.width, image.height)))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            }
        }
        let landscape = card.width > card.height
        let cardAspect = CGFloat(card.width) / CGFloat(card.height)
        let stageAspect: CGFloat = landscape ? 7 / 5 : 5 / 7
        let stageHeight = min(CGFloat(maxPixel) / max(1, stageAspect), CGFloat(card.height) / 0.84)
        let size = CGSize(width: stageHeight * stageAspect, height: stageHeight)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { drawing in
            let context = drawing.cgContext
            UIColor(red: 15/255, green: 16/255, blue: 16/255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // Quiet diagonal field markings and a deep-green corner echo the app palette.
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.055).cgColor)
            context.setLineWidth(max(1, size.width / 700))
            for index in -4...12 {
                let x = CGFloat(index) * size.width / 6
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x - size.height * 0.45, y: size.height))
            }
            context.strokePath()
            context.setFillColor(UIColor(red: 15/255, green: 61/255, blue: 46/255, alpha: 1).cgColor)
            context.move(to: CGPoint(x: 0, y: size.height * 0.80))
            context.addLine(to: CGPoint(x: size.width * 0.35, y: size.height))
            context.addLine(to: CGPoint(x: 0, y: size.height)); context.closePath(); context.fillPath()
            let available = size.width * 0.84
            let height = min(size.height * 0.84, available / cardAspect)
            let width = height * cardAspect
            let frame = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: size.height * 0.014), blur: size.width * 0.035, color: UIColor.black.withAlphaComponent(0.6).cgColor)
            UIImage(cgImage: card).draw(in: frame)
            context.restoreGState()
        }
    }
}
