import Foundation

/// Last displayed amounts only. Provider evidence stays transient.
public struct DashboardValueCache: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        let jobID: String
        let identity: String
        let value: CollectionCardValue
        let savedAt: Date
        let refreshAfter: Date
        var portfolioValue: PortfolioCardValue?
    }
    public var entries: [String: Entry] = [:]
    public init() {}

    private func identity(_ card: OwnedCard) -> String {
        guard let a = card.analysis else { return "" }
        return [a.collectionID, a.player, a.year.map(String.init), a.brand, a.setName,
                a.subset, a.parallel, a.cardNumber, a.serialNumber]
            .map { $0 ?? "" }.joined(separator: "\u{1f}")
    }
    private func matches(_ entry: Entry, _ card: OwnedCard) -> Bool {
        card.hasCurrentAnalysis && card.analysis?.identityConfirmed == true &&
        card.analysis?.knownIdentityConflict == nil && entry.jobID == card.jobID && entry.identity == identity(card)
    }
    public func values(in library: Library) -> [CollectionCardValue] {
        library.collectedCards.compactMap { card in
            guard let entry = entries[card.id], matches(entry, card) else { return nil }
            var value = entry.value; value.isCached = true
            return value
        }
    }
    public func portfolioValues(in library: Library, asOf: Date = Date()) -> [PortfolioCardValue] {
        library.collectedCards.compactMap { card in
            guard let entry = entries[card.id], isFresh(card, asOf: asOf) else { return nil }
            return entry.portfolioValue
        }
    }
    public func isFresh(_ card: OwnedCard, asOf: Date = Date()) -> Bool {
        guard let entry = entries[card.id], matches(entry, card) else { return false }
        return entry.savedAt <= asOf && entry.refreshAfter > asOf
    }
    public mutating func update(card: OwnedCard, value: CollectionCardValue?, refreshAfter: Date, asOf: Date = Date(), portfolioValue: PortfolioCardValue? = nil) {
        guard let value else { entries.removeValue(forKey: card.id); return }
        entries[card.id] = Entry(jobID: card.jobID, identity: identity(card), value: value,
            savedAt: asOf, refreshAfter: min(refreshAfter, asOf.addingTimeInterval(86400)), portfolioValue: portfolioValue)
    }
    public mutating func prune(in library: Library) {
        entries = entries.filter { id, entry in library.collectedCards.contains { $0.id == id && matches(entry, $0) } }
    }
}

extension DiskStore {
    public func loadDashboardValues() -> DashboardValueCache {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("dashboard-values.json")),
              let cache = try? JSONDecoder().decode(DashboardValueCache.self, from: data) else { return DashboardValueCache() }
        return cache
    }
    public func saveDashboardValues(_ cache: DashboardValueCache) throws {
        try JSONEncoder().encode(cache).write(to: root.appendingPathComponent("dashboard-values.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
