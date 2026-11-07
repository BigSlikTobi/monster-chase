import Foundation

/// User-requested local valuation history. Stores derived owned-card amounts only,
/// never provider responses, comparable listings, source URLs or photos.
public struct PortfolioCardValue: Codable, Equatable, Sendable {
    public let cardID: String
    public let identityKey: String
    public let comparisonKey: String
    public let currency: String
    public let lowCents: Int
    public let highCents: Int
    public var midpointCents: Double { (Double(lowCents) + Double(highCents)) / 2 }
}

public struct PortfolioObservation: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let observedAt: Date
    public let totalCards: Int
    public let values: [PortfolioCardValue]
    public func values(currency: String) -> [PortfolioCardValue] { values.filter { $0.currency == currency } }
    public func midpoint(currency: String) -> Double { values(currency: currency).reduce(0) { $0 + $1.midpointCents } }
}

public struct PortfolioChange: Sendable {
    public let from: Date
    public let matchedCards: Int
    public let previousCents: Double
    public let currentCents: Double
    public var deltaCents: Double { currentCents - previousCents }
    public var percentage: Double? { previousCents > 0 ? deltaCents / previousCents : nil }
}

extension Library {
    public func portfolioValues(asOf: Date = Date(), cachedValues: [PortfolioCardValue] = []) -> [PortfolioCardValue] {
        let prices = CollectionStatistics(library: self, asOf: asOf).values.filter(\.isPortfolioEligible)
        let current = prices.compactMap { price -> PortfolioCardValue? in
            guard let card = collectedCards.first(where: { $0.id == price.cardID }), let a = card.analysis else { return nil }
            let identity = [a.collectionID, a.player, a.year.map(String.init), a.brand, a.setName, a.subset, a.parallel, a.cardNumber, a.serialNumber]
                .map { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.joined(separator: "\u{1f}")
            let summary = a.insights?.marketSummary(asOf: asOf)
            let basis = summary.map { ($0.isGuide ? "guide" : "sold") + "|" + $0.primary.shipping } ?? "legacy-range"
            return PortfolioCardValue(cardID: card.id, identityKey: identity, comparisonKey: basis, currency: price.currency,
                lowCents: price.lowCents, highCents: price.highCents)
        }
        let currentIDs = Set(current.map(\.cardID))
        let ownedIDs = Set(collectedCards.map(\.id))
        return (current + cachedValues.filter { !currentIDs.contains($0.cardID) && ownedIDs.contains($0.cardID) })
            .sorted { $0.cardID < $1.cardID }
    }

    /// Keep the initial baseline, then at most two observations per UTC day.
    /// An empty/failed price load is never recorded as a zero-value portfolio.
    @discardableResult public mutating func recordPortfolioObservation(asOf: Date = Date(), cachedValues: [PortfolioCardValue] = []) -> Bool {
        let values = portfolioValues(asOf: asOf, cachedValues: cachedValues)
        guard !values.isEmpty else { return false }
        var history = portfolioHistory ?? []
        guard history.last.map({ $0.observedAt <= asOf }) ?? true else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        if let last = history.last, calendar.isDate(last.observedAt, inSameDayAs: asOf),
           last.values == values, last.totalCards == collectedCards.count { return false }
        let observation = PortfolioObservation(id: UUID().uuidString.lowercased(), observedAt: asOf, totalCards: collectedCards.count, values: values)
        if history.count >= 2, calendar.isDate(history[history.count - 2].observedAt, inSameDayAs: asOf) {
            history[history.count - 1] = observation
        } else { history.append(observation) }
        // Bounded local storage; the chart explicitly names its earliest retained date.
        if history.count > 730 { history.removeFirst(history.count - 730) }
        portfolioHistory = history
        return true
    }

    /// Compare only identical owned cards, currency and valuation/shipping basis.
    /// Additions, removals, corrected identities and missing prices cannot create a gain.
    public func portfolioChange(currency: String, asOf: Date = Date(), cachedValues: [PortfolioCardValue] = []) -> PortfolioChange? {
        let current = portfolioValues(asOf: asOf, cachedValues: cachedValues).filter { $0.currency == currency }
        guard let baseline = (portfolioHistory ?? []).first(where: { $0.observedAt <= asOf && !$0.values(currency: currency).isEmpty }) else { return nil }
        let old = baseline.values(currency: currency)
        let pairs = current.compactMap { value -> (PortfolioCardValue, PortfolioCardValue)? in
            guard value.comparisonKey != "legacy-range" else { return nil }
            guard let previous = old.first(where: { $0.cardID == value.cardID && $0.identityKey == value.identityKey && $0.comparisonKey == value.comparisonKey }) else { return nil }
            return (previous, value)
        }
        guard !pairs.isEmpty else { return nil }
        return PortfolioChange(from: baseline.observedAt, matchedCards: pairs.count,
            previousCents: pairs.reduce(0) { $0 + $1.0.midpointCents }, currentCents: pairs.reduce(0) { $0 + $1.1.midpointCents })
    }

    public func recommendedCards(_ action: String) -> [OwnedCard] {
        collectedCards.filter { card in
            guard card.hasCurrentAnalysis, let a = card.analysis, a.identityConfirmed == true,
                  a.confidence == "high", !a.needsReview, a.knownIdentityConflict == nil,
                  let insights = a.insights, !insights.actionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  a.recommendation == action else { return false }
            return action != "Grade" || insights.conditionStatus == "no_obvious_damage"
        }.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
    }
}

extension CollectionStatistics {
    public func portfolioValue(currency: String) -> (low: Int, high: Int)? {
        let matching = values.filter { $0.isPortfolioEligible && $0.currency == currency }
        guard !matching.isEmpty else { return nil }
        return (matching.reduce(0) { $0 + $1.lowCents }, matching.reduce(0) { $0 + $1.highCents })
    }
}
