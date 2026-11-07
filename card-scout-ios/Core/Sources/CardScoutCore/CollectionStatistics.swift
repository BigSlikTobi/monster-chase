import Foundation

public enum PurchaseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case card, pack, box, supplies, other
    public var id: String { rawValue }
    public var label: String {
        switch self { case .card: "Einzelkarten"; case .pack: "Packs"; case .box: "Boxen"; case .supplies: "Zubehör"; case .other: "Sonstiges" }
    }
    public var symbol: String {
        switch self { case .card: "rectangle.portrait"; case .pack: "gift"; case .box: "shippingbox"; case .supplies: "archivebox"; case .other: "bag" }
    }
}

public struct CardPurchase: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var category: PurchaseCategory
    /// Total paid for the whole purchase, including shipping/fees. Never multiply by quantity.
    public var amountCents: Int
    public var currency: String
    public var quantity: Int
    public var purchasedOn: String
    public var cardID: String?
    public init(id: String = UUID().uuidString.lowercased(), title: String, category: PurchaseCategory = .pack,
                amountCents: Int = 0, currency: String = "EUR", quantity: Int = 1, purchasedOn: String, cardID: String? = nil) {
        self.id = id; self.title = title; self.category = category; self.amountCents = amountCents
        self.currency = currency; self.quantity = quantity; self.purchasedOn = purchasedOn; self.cardID = cardID
    }
    public static let currencies = ["EUR", "USD", "GBP"]
    public var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              (1...100_000_000).contains(amountCents), (1...999).contains(quantity), Self.currencies.contains(currency) else { return false }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: purchasedOn) else { return false }
        return formatter.string(from: date) == purchasedOn
    }
    public static func parseAmount(_ text: String) -> Int? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard clean.range(of: "^[0-9]{1,7}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil else { return nil }
        let parts = clean.split(separator: ".")
        guard let whole = Int(parts[0]) else { return nil }
        let fraction = parts.count == 2 ? Int(parts[1])! * (parts[1].count == 1 ? 10 : 1) : 0
        let cents = whole * 100 + fraction
        return (1...100_000_000).contains(cents) ? cents : nil
    }
}

public struct CollectionCardValue: Codable, Identifiable, Equatable, Sendable {
    public var id: String { cardID }
    public let cardID: String
    public let currency: String
    public let lowCents: Int
    public let highCents: Int
    public let isEstimate: Bool
    public let basis: String
    public let checkedAt: String
    public var isGuide: Bool = false
    public var isCached: Bool = false
    public var isPortfolioEligible: Bool { !isEstimate || isGuide }
    public var label: String {
        let low = Self.money(lowCents, currency: currency)
        let price = lowCents == highCents ? low : "\(low) – \(Self.money(highCents, currency: currency))"
        return isEstimate ? "ca. \(price)" : price
    }
    public static func money(_ cents: Int, currency: String) -> String {
        (Double(cents) / 100).formatted(.currency(code: currency).locale(ScoutLocalization.locale).precision(.fractionLength(0...2)))
    }
}

public struct CollectionGrowthPoint: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let count: Int
}

public struct CollectionStatistics: Sendable {
    public let totalCards: Int
    public let analyzedCards: Int
    public let rookieCards: Int
    public let numberedCards: Int
    public let favorites: Int
    public let duplicateExtras: Int
    public let distinctPlayers: Int
    public let purchases: [CardPurchase]
    public let values: [CollectionCardValue]
    public let specialCardID: String?
    public let specialReason: String?
    public let growth: [CollectionGrowthPoint]
    public var pricedCards: Int { values.filter { !$0.isEstimate }.count }
    public var indicativeCards: Int { values.filter(\.isEstimate).count }
    public var nextMilestone: Int { [10, 25, 50, 100, 250, 500, 1000].first { $0 > totalCards } ?? ((totalCards / 1000) + 1) * 1000 }
    public var spendingCurrencies: [String] { Array(Set(purchases.map(\.currency))).sorted() }
    public var valueCurrencies: [String] { Array(Set(values.map(\.currency))).sorted() }
    public func spending(currency: String, category: PurchaseCategory? = nil) -> Int {
        purchases.filter { $0.currency == currency && (category == nil || $0.category == category) }.reduce(0) { $0 + $1.amountCents }
    }
    public func confirmedValue(currency: String) -> (low: Int, high: Int)? {
        let matching = values.filter { !$0.isEstimate && $0.currency == currency }
        guard !matching.isEmpty else { return nil }
        return (matching.reduce(0) { $0 + $1.lowCents }, matching.reduce(0) { $0 + $1.highCents })
    }
    /// Indicative collection total, including comparison medians. Unknown values are not invented.
    public func estimatedCollectionValue(currency: String) -> (low: Int, high: Int)? {
        let matching = values.filter { $0.currency == currency }
        guard !matching.isEmpty else { return nil }
        return (matching.reduce(0) { $0 + $1.lowCents }, matching.reduce(0) { $0 + $1.highCents })
    }
    public func ranked(currency: String) -> [CollectionCardValue] {
        values.filter { $0.currency == currency }.sorted {
            if $0.isEstimate != $1.isEstimate { return !$0.isEstimate }
            if $0.lowCents != $1.lowCents { return $0.lowCents > $1.lowCents }
            return $0.cardID < $1.cardID
        }
    }
    public init(library: Library, asOf: Date = Date(), calendar: Calendar = .current, cachedValues: [CollectionCardValue] = []) {
        let cards = library.collectedCards
        let analyzed = cards.filter(\.hasCurrentAnalysis)
        let readable = analyzed.filter { $0.analysis?.player != nil && $0.analysis?.confidence != "low" }
        totalCards = cards.count; analyzedCards = analyzed.count
        rookieCards = readable.filter { $0.analysis?.rookie == true }.count
        numberedCards = readable.filter { Self.serialLimit($0.analysis?.serialNumber) != nil }.count
        favorites = cards.filter { $0.isFavorite == true }.count
        distinctPlayers = Set(readable.compactMap { $0.analysis?.player?.lowercased() }).count
        let duplicates = Dictionary(grouping: analyzed.filter { $0.analysis?.identityConfirmed == true && $0.analysis?.collectionID != nil && $0.analysis?.cardNumber != nil }) {
            [$0.analysis!.collectionID!, $0.analysis!.cardNumber!, $0.analysis!.parallel ?? ""].joined(separator: "|")
        }
        duplicateExtras = duplicates.values.reduce(0) { $0 + max(0, $1.count - 1) }
        let purchaseDate = DateFormatter(); purchaseDate.locale = Locale(identifier: "en_US_POSIX")
        purchaseDate.timeZone = calendar.timeZone; purchaseDate.dateFormat = "yyyy-MM-dd"
        purchases = (library.purchases ?? []).filter { $0.isValid && $0.purchasedOn <= purchaseDate.string(from: asOf) }.sorted {
            $0.purchasedOn == $1.purchasedOn ? $0.id > $1.id : $0.purchasedOn > $1.purchasedOn
        }
        let currentValues = analyzed.compactMap { Self.cardValue($0, asOf: asOf) }
        let currentIDs = Set(currentValues.map(\.cardID))
        let analyzedIDs = Set(analyzed.map(\.id))
        values = currentValues + cachedValues.filter { !currentIDs.contains($0.cardID) && analyzedIDs.contains($0.cardID) }
        let special = readable.compactMap { card -> (OwnedCard, Int, String)? in
            if let limit = Self.serialLimit(card.analysis?.serialNumber) {
                return (card, limit, limit == 1 ? "Sichtbar nummeriert: 1/1" : "Sichtbar nummeriert: \(card.analysis!.serialNumber!)")
            }
            guard card.analysis?.identityConfirmed == true else { return nil }
            if let parallel = card.analysis?.parallel, !parallel.isEmpty { return (card, 2_000_000, "Bestätigte Variante: \(parallel)") }
            if card.analysis?.insights?.rarityTier == "insert" { return (card, 3_000_000, "Bestätigtes Insert") }
            if card.analysis?.rookie == true { return (card, 4_000_000, "Rookie-Karte") }
            return nil
        }.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }.first
        specialCardID = special?.0.id; specialReason = special?.2
        let dateReader = ISO8601DateFormatter()
        let preciseReader = ISO8601DateFormatter(); preciseReader.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let captureDates = cards.compactMap { dateReader.date(from: $0.createdAt) ?? preciseReader.date(from: $0.createdAt) }
        let today = calendar.startOfDay(for: asOf)
        growth = (-13...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return CollectionGrowthPoint(date: day, count: captureDates.filter { $0 < end && $0 <= asOf }.count)
        }
    }
    public static func serialLimit(_ text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.replacingOccurrences(of: " ", with: "").split(separator: "/")
        guard parts.count == 2, let number = Int(parts[0]), let limit = Int(parts[1]),
              number >= 1, number <= limit, limit <= 1_000_000 else { return nil }
        return limit
    }
    private static func cardValue(_ card: OwnedCard, asOf: Date) -> CollectionCardValue? {
        guard let analysis = card.analysis, analysis.knownIdentityConflict == nil else { return nil }
        guard var info = analysis.insights else {
            if analysis.identityConfirmed == true, let low = analysis.marketLowCents, let high = analysis.marketHighCents, low > 0, high >= low {
                return CollectionCardValue(cardID: card.id, currency: analysis.currency ?? "EUR", lowCents: low, highCents: high,
                    isEstimate: false, basis: "Gespeicherte Preisspanne", checkedAt: analysis.marketCheckedAt)
            }
            return nil
        }
        var seenReferences = Set<String>()
        info.marketReferences = info.marketReferences.filter { reference in
            guard reference.isFresh(asOf: asOf) else { return false }
            guard reference.kind == "sold" else { return true }
            let url = reference.listingURL ?? reference.url
            let path = URLComponents(string: url)?.path ?? url
            let matcher = try! NSRegularExpression(pattern: "/itm/(?:[^/]+/)?([0-9]{9,15})(?:/|$)")
            let match = matcher.firstMatch(in: path, range: NSRange(path.startIndex..., in: path))
            let key: String
            if let match, let range = Range(match.range(at: 1), in: path) { key = "ebay:" + path[range] }
            else { key = "\(url)|\(reference.saleDate ?? "")|\(reference.lowCents)|\(reference.currency)|\(reference.shipping)" }
            return seenReferences.insert(key).inserted
        }
        if let summary = info.marketSummary(asOf: asOf) ?? analysis.comparableEstimate?.marketSummary(asOf: asOf), analysis.identityConfirmed == true {
            let low = summary.isGuide ? summary.primary.lowCents : Int(summary.orderingValueCents.rounded())
            return CollectionCardValue(cardID: card.id, currency: summary.primary.currency, lowCents: low,
                highCents: summary.isGuide ? summary.primary.highCents : low, isEstimate: summary.isEstimate,
                basis: summary.basisLabel, checkedAt: summary.references.map(\.checkedAt).min() ?? analysis.marketCheckedAt, isGuide: summary.isGuide)
        }
        guard analysis.player != nil, analysis.confidence != "low" else { return nil }
        let raw = info.marketReferences.filter { $0.grade == "raw" && ["exact", "near"].contains($0.matchQuality) && $0.lowCents > 0 && $0.highCents >= $0.lowCents }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        let today = formatter.date(from: formatter.string(from: asOf)) ?? asOf
        var seen = Set<String>()
        let sales = raw.filter { reference in
            guard reference.kind == "sold", reference.lowCents == reference.highCents,
                  let text = reference.saleDate, let date = formatter.date(from: text), formatter.string(from: date) == text else { return false }
            let age = today.timeIntervalSince(date) / 86400
            guard age >= 0, age <= 365 else { return false }
            let key = reference.listingURL.map { URLComponents(string: $0).map { ($0.host ?? "") + $0.path } ?? $0 }
                ?? "\(reference.url)|\(text)|\(reference.lowCents)|\(reference.currency)|\(reference.shipping)"
            return seen.insert(key).inserted
        }
        let recent = sales.filter { today.timeIntervalSince(formatter.date(from: $0.saleDate!)!) / 86400 <= 90 }
        func bestGroup(_ refs: [MarketReference]) -> [MarketReference]? {
            let groups: [String: [MarketReference]] = Dictionary(grouping: refs) { "\($0.currency)|\($0.shipping)" }
            let sorted: [[MarketReference]] = groups.values.sorted { left, right in
                if left.count != right.count { return left.count > right.count }
                let leftKey = (left.first?.currency ?? "") + (left.first?.shipping ?? "")
                let rightKey = (right.first?.currency ?? "") + (right.first?.shipping ?? "")
                return leftKey < rightKey
            }
            return sorted.first
        }
        let group = bestGroup(recent).flatMap { $0.count >= 2 ? $0 : nil } ?? bestGroup(sales)
        if let group, !group.isEmpty {
            let median = Int(RawMarketSummary(references: group).orderingValueCents.rounded())
            return CollectionCardValue(cardID: card.id, currency: group[0].currency, lowCents: median, highCents: median,
                isEstimate: true, basis: group.count == 1 ? "Ähnliche Karte · Einzelverkauf" : "Median · \(group.count) Vergleichsverkäufe",
                checkedAt: group.map(\.checkedAt).min() ?? analysis.marketCheckedAt)
        }
        if let guide = raw.filter({ $0.kind == "guide" }).sorted(by: { $0.checkedAt > $1.checkedAt }).first {
            return CollectionCardValue(cardID: card.id, currency: guide.currency, lowCents: guide.lowCents, highCents: guide.highCents,
                isEstimate: true, basis: "Vergleichsrichtwert", checkedAt: guide.checkedAt)
        }
        return nil
    }
}
