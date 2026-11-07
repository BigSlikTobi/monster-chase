import Foundation

public struct MarketReference: Codable, Hashable, Sendable {
    public var provider: String
    public var url: String
    public var kind: String
    public var grade: String
    public var condition: String?
    public var matchQuality: String
    public var lowCents: Int
    public var highCents: Int
    public var currency: String
    public var saleDate: String?
    public var checkedAt: String
    public var shipping: String
    public var title: String?
    public var listingURL: String?
    public var expiresAt: Double? = nil

    public func isFresh(asOf: Date = Date()) -> Bool {
        guard ["CardSight", "Slabline", "Midpoint"].contains(provider) else { return true }
        guard let expiresAt, expiresAt.isFinite else { return false }
        return expiresAt > asOf.timeIntervalSince1970 && expiresAt <= asOf.timeIntervalSince1970 + 86_460
    }

    public var valueLabel: String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency).locale(ScoutLocalization.locale).precision(.fractionLength(0...2))
        let low = (Double(lowCents) / 100).formatted(style)
        return lowCents == highCents ? low : "\(low) – \((Double(highCents) / 100).formatted(style))"
    }
    public var gradeLabel: String { grade == "raw" ? "Ungegradet" : grade }
    public var kindLabel: String { kind == "guide" ? "Richtwert" : "Verkauf" }
    public var shippingLabel: String {
        switch shipping {
        case "included": "inkl. Versand"
        case "excluded": "zzgl. Versand"
        case "unknown": "Versand unbekannt"
        default: "Preisguide · kein Verkauf"
        }
    }
    public var matchLabel: String { ["exact": "Gleiche Variante", "near": "Ähnliche Karte", "proxy": "Indirekter Vergleich"][matchQuality] ?? "Vergleich" }
}

public struct SourceCheck: Codable, Hashable, Sendable {
    public var provider: String
    public var status: String
    public var url: String?
    public var statusLabel: String {
        ["found": "Preis gefunden", "no_match": "Kein Preis gefunden", "paywalled": "Zugang nötig", "unavailable": "Nicht erreichbar", "not_checked": "Preis folgt"][status] ?? "Offen"
    }
}

public struct CardInsights: Codable, Hashable, Sendable {
    public var rarityTier: String
    public var rarityBullets: [String]
    public var conditionStatus: String
    public var conditionIssues: [String]
    public var conditionLimitations: [String]
    public var marketBullets: [String]
    public var marketReferences: [MarketReference]
    public var sourceChecks: [SourceCheck]
    public var actionReason: String

    public var rarityLabel: String {
        ["base": "Basiskarte", "insert": "Insert", "parallel": "Parallel", "numbered": "Nummeriert", "one_of_one": "1 of 1", "unknown": "Variante offen"][rarityTier] ?? "Variante offen"
    }
    public var conditionLabel: String {
        switch conditionStatus {
        case "visible_damage": "Sichtbare Spuren"
        case "no_obvious_damage": "Keine klaren Schäden sichtbar"
        default: "Besseres Foto nötig"
        }
    }
    /// A graded or non-matching reference must never become the headline value of a raw card.
    public var rawReference: MarketReference? {
        return marketSummary()?.primary
    }

    public func marketSummary(asOf: Date = Date()) -> RawMarketSummary? {
        let raw = marketReferences.filter { $0.isFresh(asOf: asOf) && $0.grade == "raw" && $0.matchQuality == "exact" && $0.lowCents > 0 && $0.highCents >= $0.lowCents }
        let guide = raw.filter { $0.kind == "guide" }.sorted { $0.checkedAt > $1.checkedAt }.first
        let dates = DateFormatter(); dates.locale = Locale(identifier: "en_US_POSIX")
        dates.timeZone = TimeZone(secondsFromGMT: 0); dates.dateFormat = "yyyy-MM-dd"
        let today = dates.date(from: dates.string(from: asOf)) ?? asOf
        let sales = raw.filter {
            guard $0.kind == "sold", $0.lowCents == $0.highCents, let text = $0.saleDate, let date = dates.date(from: text) else { return false }
            let age = today.timeIntervalSince(date) / 86400
            return age >= 0 && age <= 365
        }.sorted { ($0.saleDate ?? "") > ($1.saleDate ?? "") }
        // Never combine currencies or item-only and delivered amounts.
        let groups = Dictionary(grouping: sales) { $0.currency + ":" + $0.shipping }
        func preferred(_ lhs: [MarketReference], _ rhs: [MarketReference]) -> Bool {
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            let left = lhs.first?.saleDate ?? "", right = rhs.first?.saleDate ?? ""
            if left != right { return left > right }
            return (lhs.first?.currency ?? "") < (rhs.first?.currency ?? "")
        }
        var recentGroups: [[MarketReference]] = []
        for group in groups.values {
            let recent = group.filter { reference in
                guard let text = reference.saleDate, let date = dates.date(from: text) else { return false }
                return today.timeIntervalSince(date) / 86400 <= 90
            }
            if recent.count >= 2 { recentGroups.append(recent) }
        }
        if let recent = recentGroups.sorted(by: preferred).first { return RawMarketSummary(references: recent) }
        if let group = groups.values.sorted(by: preferred).first {
            return RawMarketSummary(references: group)
        }
        if let guide { return RawMarketSummary(references: [guide]) }
        return nil
    }
}

public struct RawMarketSummary: Sendable {
    public let references: [MarketReference]
    public var comparison: ComparableEstimate? = nil
    public var primary: MarketReference { references[0] }
    public var isComparable: Bool { comparison != nil }
    public var isGuide: Bool { !isComparable && primary.kind == "guide" }
    public var isEstimate: Bool { isGuide || isComparable }
    public var basisLabel: String { isComparable ? "Vergleichsmedian · \(references.count) Karten · geringe Sicherheit" : isGuide ? "Richtwert" : references.count == 1 ? "Einzelverkauf" : "Median · \(references.count) Verkäufe" }
    public var orderingValueCents: Double {
        if isGuide { return Double(primary.lowCents) }
        // Each comparison card contributes once. Ranged guides contribute their midpoint.
        // The midpoint of the overall min–max range would overvalue a single outlier.
        let amounts = references.map { isComparable ? (Double($0.lowCents) + Double($0.highCents)) / 2 : Double($0.lowCents) }.sorted()
        let middle = amounts.count / 2
        return amounts.count.isMultiple(of: 2) ? (amounts[middle - 1] + amounts[middle]) / 2 : amounts[middle]
    }
    public var valueLabel: String {
        if isGuide { return primary.valueLabel }
        let price = (orderingValueCents.rounded() / 100).formatted(.currency(code: primary.currency).locale(ScoutLocalization.locale).precision(.fractionLength(0...2)))
        return isComparable ? "ca. \(price)" : price
    }
    public var rangeLabel: String? {
        guard !isGuide, references.count > 1 else { return nil }
        var range = primary; range.lowCents = references.map(\.lowCents).min()!; range.highCents = references.map(\.highCents).max()!
        return range.valueLabel
    }
    public var dateLabel: String {
        if let comparison { return "Vergleich erstellt: \(comparison.checkedAt)" }
        let dates = references.compactMap(\.saleDate).sorted()
        guard let first = dates.first, let last = dates.last else { return "Stand: \(primary.checkedAt)" }
        return first == last ? "Verkauft: \(first)" : "Verkäufe: \(first) – \(last)"
    }
}

extension CardAnalysis {
    /// Transient provider evidence is never written into library.json or backups.
    public func withoutTransientPricing() -> CardAnalysis {
        var copy = self
        copy.comparableEstimate = nil
        if var info = copy.insights {
            let transient = info.marketReferences.contains { ["CardSight", "Slabline", "Midpoint"].contains($0.provider) } || info.sourceChecks.contains { ["CardSight", "Slabline", "Midpoint"].contains($0.provider) }
            info.marketReferences.removeAll { ["CardSight", "Slabline", "Midpoint"].contains($0.provider) }
            info.sourceChecks.removeAll { ["CardSight", "Slabline", "Midpoint"].contains($0.provider) }
            if transient { info.marketBullets = []; copy.marketSources = []; copy.marketLowCents = nil; copy.marketHighCents = nil }
            copy.insights = info
        }
        return copy
    }

    public func currentPricing(asOf: Date = Date()) -> CardAnalysis {
        var copy = self
        if copy.comparableEstimate?.isFresh(asOf: asOf) != true { copy.comparableEstimate = nil }
        guard var info = copy.insights else { return copy }
        let expired = info.marketReferences.contains { !$0.isFresh(asOf: asOf) }
        info.marketReferences.removeAll { !$0.isFresh(asOf: asOf) }
        if expired {
            info.marketBullets = []
            info.sourceChecks = info.sourceChecks.map { check in
                var value = check
                if ["CardSight", "Slabline", "Midpoint"].contains(value.provider) { value.status = "unavailable" }
                return value
            }
        }
        copy.insights = info
        return copy
    }

    public var discoveryRarity: String {
        insights?.rarityLabel ?? (serialNumber != nil ? "Nummeriert" : parallel != nil ? "Parallel" : subset == "Base" ? "Basiskarte" : "Variante")
    }
    public var rarityFacts: [String] {
        if let insights { return insights.rarityBullets }
        return [parallel ?? subset, serialNumber.map { "Nummerierung: \($0)" }, rookie == true ? "Rookie-Karte" : nil].compactMap { $0 }
    }
    public var needsInsightRefresh: Bool { insights == nil }
    public var marketSummary: RawMarketSummary? {
        guard identityConfirmed == true, knownIdentityConflict == nil else { return nil }
        return insights?.marketSummary() ?? comparableEstimate?.marketSummary()
    }
    public var actionLabel: String { ["Keep": "Behalten", "Sell": "Verkaufen", "Grade": "Grading prüfen", "Bulk": "Sammelkarte"][recommendation] ?? recommendation }

    public mutating func clearAssessmentAfterCorrection() {
        comparableEstimate = nil
        marketLowCents = nil; marketHighCents = nil; marketSources = []; insights = nil
        psa10ChanceLow = nil; psa10ChanceHigh = nil; recommendation = "Keep"; needsReview = true
        rationale = "Zuordnung korrigiert. Neu bewerten für aktuelle Ergebnisse."
        conditionNotes = ""; uncertainties = ["Bewertung nach Korrektur offen."]
    }
}

extension OwnedCard {
    public static let currentAnalysisVersion = 3
    public var needsInsightUpgrade: Bool {
        state == "analyzed" && analysis != nil && (requestedAnalysisVersion ?? 1) < Self.currentAnalysisVersion
    }
}
