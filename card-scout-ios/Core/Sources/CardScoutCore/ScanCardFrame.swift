import Foundation
import CoreGraphics

/// Vision coordinates: normalized, origin at the bottom left; clockwise corners.
public struct ScanCardFrame: Equatable, Sendable {
    public let corners: [CGPoint]
    public init(corners: [CGPoint]) { self.corners = corners }
    public var bounds: CGRect {
        guard let first = corners.first else { return .zero }
        return corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            CGRect(x: min(rect.minX, point.x), y: min(rect.minY, point.y),
                   width: max(rect.maxX, point.x) - min(rect.minX, point.x),
                   height: max(rect.maxY, point.y) - min(rect.minY, point.y))
        }
    }
    public static func best(_ candidates: [Self], imageSize: CGSize) -> Self? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        func score(_ card: Self) -> CGFloat {
            let box = card.bounds
            return box.width * box.height - hypot(box.midX - 0.5, box.midY - 0.5) * 0.08
        }
        return candidates.filter { card in
            guard card.corners.count == 4,
                  card.corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.x > 0.008 && $0.x < 0.992 && $0.y > 0.008 && $0.y < 0.992 }) else { return false }
            let box = card.bounds
            guard box.width >= 0.18, box.height >= 0.18, box.width * box.height >= 0.08 else { return false }
            func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
                hypot((a.x - b.x) * imageSize.width, (a.y - b.y) * imageSize.height)
            }
            let p = card.corners
            let width = distance(p[0], p[1]) + distance(p[3], p[2])
            let height = distance(p[0], p[3]) + distance(p[1], p[2])
            let aspect = min(width, height) / max(width, height)
            return aspect >= 0.55 && aspect <= 0.88
        }.max { score($0) < score($1) }
    }
    /// Matches the preview layer's aspect fit/fill transform and Vision's vertical origin.
    public func previewPoints(imageSize: CGSize, viewSize: CGSize, aspectFill: Bool = true) -> [CGPoint] {
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }
        let xScale = viewSize.width / imageSize.width, yScale = viewSize.height / imageSize.height
        let scale = aspectFill ? max(xScale, yScale) : min(xScale, yScale)
        let width = imageSize.width * scale, height = imageSize.height * scale
        return corners.map { CGPoint(x: $0.x * width + (viewSize.width - width) / 2,
                                     y: (1 - $0.y) * height + (viewSize.height - height) / 2) }
    }
}
