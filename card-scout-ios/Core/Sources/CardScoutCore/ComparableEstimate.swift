import Foundation

/// Transient comparison evidence with a median headline and observed range.
/// Never an exact valuation of the owned card.
public struct ComparableEstimate: Codable, Hashable, Sendable {
    public var lowCents: Int
    public var highCents: Int
    public var currency: String
    public var shipping: String
    public var cardCount: Int
    public var confidence: String
    public var scopeLabel: String
    public var checkedAt: String
    public var expiresAt: Double
    public var references: [MarketReference]

    public func isFresh(asOf: Date = Date()) -> Bool {
        guard confidence == "low", (3...12).contains(cardCount), references.count == cardCount,
              Set(references.map(\.url)).count == cardCount,
              lowCents > 0, highCents >= lowCents, expiresAt.isFinite,
              expiresAt > asOf.timeIntervalSince1970, expiresAt <= asOf.timeIntervalSince1970 + 86_460,
              lowCents == references.map(\.lowCents).min(), highCents == references.map(\.highCents).max() else { return false }
        return references.allSatisfy {
            $0.isFresh(asOf: asOf) && ($0.expiresAt ?? 0) >= expiresAt &&
            $0.grade == "raw" && $0.matchQuality == "near" && ["sold", "guide"].contains($0.kind) &&
            $0.currency == currency && $0.shipping == shipping && $0.lowCents > 0 &&
            $0.highCents >= $0.lowCents && URL(string: $0.url)?.scheme == "https"
        }
    }
    public func marketSummary(asOf: Date = Date()) -> RawMarketSummary? {
        isFresh(asOf: asOf) ? RawMarketSummary(references: references, comparison: self) : nil
    }
}
