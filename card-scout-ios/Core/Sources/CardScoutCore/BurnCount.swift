import Foundation

public enum BurnPerformance: Sendable { case unknown, uncertain, breakEven, ahead, excellent, behind, heavyBurn }

public enum BurnMood: String, Sendable { case curious, proud, roasted }

/// A playful hobby comparison, not a realized loss or investment return.
public struct BurnCount: Sendable {
    public let isManualValue: Bool
    public let currency: String
    public let spentCents: Int?
    public let valueLowCents: Int?
    public let valueHighCents: Int?
    public let pricedCards: Int
    public let totalCards: Int
    public let purchaseCount: Int
    public let includesComparisonEstimates: Bool
    public var isIndicative: Bool { !isManualValue && (!hasCompleteCoverage || includesComparisonEstimates) }
    public var hasCompleteCoverage: Bool { totalCards > 0 && (isManualValue || pricedCards == totalCards) }
    public var canCompare: Bool { spentCents != nil && valueLowCents != nil }
    public var burnLowCents: Int? {
        guard canCompare, let spentCents, let valueHighCents else { return nil }
        return spentCents - valueHighCents
    }
    public var burnHighCents: Int? {
        guard canCompare, let spentCents, let valueLowCents else { return nil }
        return spentCents - valueLowCents
    }
    /// Classify the displayed estimate. Ranges must clear a threshold in full.
    public var performance: BurnPerformance {
        guard let low = burnLowCents, let high = burnHighCents, let spentCents else { return .unknown }
        if low == 0 && high == 0 { return .breakEven }
        if low <= 0 && high >= 0 { return .uncertain }
        if high < 0 {
            return spentCents > 0 && Double(-high) / Double(spentCents) >= 0.25 ? .excellent : .ahead
        }
        return spentCents > 0 && Double(low) / Double(spentCents) >= 0.25 ? .heavyBurn : .behind
    }
    public var mood: BurnMood {
        guard canCompare, let spentCents, let valueLowCents, let valueHighCents else { return .curious }
        if valueLowCents >= spentCents { return .proud }
        if valueHighCents < spentCents { return .roasted }
        return .curious
    }
    public init(statistics: CollectionStatistics, currency: String, manualValueCents: Int? = nil) {
        let manual = manualValueCents.flatMap { (0...100_000_000).contains($0) ? $0 : nil }
        isManualValue = manual != nil
        self.currency = currency
        // Card/pack/box totals include fees once; supplies and other costs stay in the ledger.
        let purchases = statistics.purchases.filter { $0.currency == currency && [.card, .pack, .box].contains($0.category) }
        spentCents = purchases.isEmpty ? nil : purchases.reduce(0) { $0 + $1.amountCents }
        purchaseCount = purchases.count
        let value = statistics.estimatedCollectionValue(currency: currency)
        includesComparisonEstimates = statistics.values.contains { $0.currency == currency && !$0.isPortfolioEligible }
        valueLowCents = manual ?? value?.low; valueHighCents = manual ?? value?.high
        pricedCards = statistics.values.filter { $0.currency == currency }.count
        totalCards = statistics.totalCards
    }
}


public struct ManualBurnValue: Codable, Equatable, Sendable {
    public let amountCents: Int
    public let currency: String
    public let recordedAt: Date
    public let cardIDs: [String]
}

extension Library {
    public func currentManualBurnValue(currency: String) -> ManualBurnValue? {
        guard let value = burnManualValues?[currency], value.currency == currency,
              (0...100_000_000).contains(value.amountCents),
              value.cardIDs == collectedCards.map(\.id).sorted() else { return nil }
        return value
    }
    public mutating func setManualBurnValue(amountCents: Int?, currency: String, asOf: Date = Date()) throws {
        guard CardPurchase.currencies.contains(currency) else { throw StoreError.invalidResult }
        if let amountCents {
            guard (0...100_000_000).contains(amountCents), !collectedCards.isEmpty else { throw StoreError.invalidResult }
            var values = burnManualValues ?? [:]
            values[currency] = ManualBurnValue(amountCents: amountCents, currency: currency, recordedAt: asOf, cardIDs: collectedCards.map(\.id).sorted())
            burnManualValues = values
        } else { burnManualValues?.removeValue(forKey: currency) }
    }
}
