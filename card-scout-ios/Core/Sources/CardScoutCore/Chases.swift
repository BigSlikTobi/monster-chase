import Foundation

/// A dated raw-price catalog. Owned-card assessments remain separate.
public struct ChaseCatalog: Codable, Equatable, Sendable {
    public var version: Int
    public var revision: String
    public var checkedAt: String
    public var products: [ChaseProduct]

    public func validate() throws {
        guard [1, 2].contains(version), !revision.isEmpty, Self.validDate(checkedAt), !products.isEmpty,
              products.count <= 50 else { throw StoreError.invalidResult }
        var productIDs = Set<String>(), cardIDs = Set<String>()
        var validDates: Set<String> = [checkedAt]
        for product in products {
            guard !product.id.isEmpty, productIDs.insert(product.id).inserted, !product.name.isEmpty,
                  (2020...2100).contains(product.year), product.licenseScope == "nfl_and_nflpa",
                  Self.https(product.sourceURL), !product.boxSummary.isEmpty,
                  !product.cards.isEmpty, product.cards.count <= 200_000,
                  version != 1 || product.cards.count == 10,
                  Set(product.cards.map(\.rank)) == Set(1...product.cards.count) else { throw StoreError.invalidResult }
            if let coverage = product.coverage {
                guard ["partial", "imported"].contains(coverage.status), !coverage.sourceName.isEmpty,
                      coverage.sourceURLs.allSatisfy(Self.https), !coverage.sourceURLs.isEmpty,
                      coverage.cardCount == product.cards.count,
                      coverage.scope.map({ ["price_guides", "official_chases"].contains($0) }) ?? true
                else { throw StoreError.invalidResult }
            } else if version == 2 { throw StoreError.invalidResult }
            for card in product.cards {
                guard card.id.hasPrefix(product.id + ":"), cardIDs.insert(card.id).inserted,
                      !card.player.isEmpty, !card.variant.isEmpty, !card.number.isEmpty,
                      !card.packLabel.isEmpty, Self.https(card.sourceURL),
                      card.imageURL.map(Self.https) ?? true, ["scan", "preview", "unavailable"].contains(card.imageKind),
                      card.priceCents == nil || (card.priceCents! > 0 && card.priceCents! < 1_000_000_000 && card.currency == "USD" && card.priceKind == "guide"),
                      card.priceSourceURL.map(Self.https) ?? (card.priceCents == nil),
                      card.priceCheckedAt != nil || card.priceCents == nil,
                      card.oddsSourceURL.map(Self.https) ?? (card.odds == nil)
                else { throw StoreError.invalidResult }
                if let date = card.priceCheckedAt, !validDates.contains(date) {
                    guard Self.validDate(date) else { throw StoreError.invalidResult }
                    validDates.insert(date)
                }
            }
        }
    }
    private static func https(_ value: String) -> Bool {
        guard let url = URLComponents(string: value) else { return false }
        return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
    }
    private static func validDate(_ value: String) -> Bool {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

public struct ChaseCoverage: Codable, Equatable, Sendable {
    public var status: String
    public var sourceName: String
    public var sourceURLs: [String]
    public var cardCount: Int
    public var scope: String?

    public init(status: String, sourceName: String, sourceURLs: [String], cardCount: Int, scope: String? = nil) {
        self.status = status
        self.sourceName = sourceName
        self.sourceURLs = sourceURLs
        self.cardCount = cardCount
        self.scope = scope
    }
}

public enum ToppsChaseFamily: String, CaseIterable, Sendable {
    case all
    case goldenMirror
    case autograph
    case relic
    case allKings
    case rookie1957

    public var label: String {
        switch self {
        case .all: "Alle"
        case .goldenMirror: "Golden Mirror"
        case .autograph: "Autos"
        case .relic: "Relics"
        case .allKings: "All Kings"
        case .rookie1957: "1957 Rookies"
        }
    }
}

public struct ChaseImageReference: Equatable, Sendable {
    public var url: String
    public var sourceURL: String
    public var label: String
    public var isRepresentative: Bool
}

public struct ChaseProduct: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var year: Int
    public var brand: String
    public var collectionNames: [String]
    public var licenseScope: String
    public var badge: String
    public var boxSummary: [String]
    public var oddsNote: String
    public var sourceURL: String
    public var rankingLabel: String
    public var cards: [ChaseCard]
    public var coverage: ChaseCoverage?
    public var title: String { "\(name) \(year)" }
    public func matches(_ collection: CardCollection) -> Bool {
        collection.year == year && collection.brand.caseInsensitiveCompare(brand) == .orderedSame &&
        collectionNames.contains { $0.caseInsensitiveCompare(collection.name) == .orderedSame }
    }
    public var hasOfficialChaseChecklist: Bool {
        guard let coverage else { return false }
        if coverage.scope == "official_chases" { return true }

        // Build 10 reached MyApple while the catalog still used the older
        // coverage shape. Recognize only that exact, trusted Topps snapshot so
        // the Chase view also works offline; the next sync repairs the metadata.
        guard coverage.scope == nil,
              id == "2026-topps-flagship-football",
              coverage.status == "imported",
              coverage.sourceName == "Topps official checklist",
              coverage.cardCount == cards.count,
              coverage.sourceURLs.contains("https://www.topps.com/pages/topps-flagship-football"),
              !cards.isEmpty,
              cards.allSatisfy({ $0.id.hasPrefix(id + ":topps:") })
        else { return false }
        return true
    }
    public var needsOfficialScopeRepair: Bool {
        hasOfficialChaseChecklist && coverage?.scope == nil
    }
    public func imageReference(for card: ChaseCard) -> ChaseImageReference? {
        if let url = card.imageURL, !url.isEmpty {
            return ChaseImageReference(url: url, sourceURL: card.sourceURL,
                                       label: card.imageKind == "preview" ? "Hersteller-Vorschau" : "Kartenfoto",
                                       isRepresentative: false)
        }
        guard hasOfficialChaseChecklist, card.id.hasPrefix(id + ":topps:") else { return nil }

        let asset: (path: String, label: String)? = switch card.variant {
        case "Flagship First Signatures":
            ("blta1ddc46e8f5a8fd3/6a84d6c936492a8ff385d003/2026_Topps_Flagship_Football_FlagshipFirstSignatures_GoldInk_CarnellTate_FR_%284%29.jpg", "Flagship First · offizielles Beispiel")
        case "Flagship First Dual Signatures":
            ("blt2e3004a57df2dc9a/6a84c5594acc96185a246f5c/2026_Topps_Flagship_Football_FlagshipFirstDualSignatures_RedInk_CarsonBeck_JeremiyahLove_FR.jpg", "Flagship First Dual · offizielles Beispiel")
        case "All Kings":
            ("blta5cd5647b9a1e1a4/6a84d713b689510710a25e05/26TFOB_8353_FR_GoldParallel.png", "All Kings · offizielles Beispiel")
        case "Ring of Honor Signatures":
            ("bltadb1359ca0202a24/6a84d780762d1e36c95cb000/2026_Topps_Flagship_Football_RingOfHonorSignature_ROHS-TB_Base_TomBrady_FR.jpg", "Ring of Honor · offizielles Beispiel")
        case "Real One Relics", "Rookie Real One Relics":
            ("bltcfee3a2b25fc0069/6a85c8fee41d7f64f6652abf/2026_Topps_Flagship_Football_RealOneRelics_Red_JaydenDaniels_FR_%282%29.jpg", "Real One Relics · offizielles Beispiel")
        case "Island Ink":
            ("blt691600d984ce64b5/6a84d68f0c407bfaf1d343ae/2026_Topps_Flagship_Football_IslandInk_Foilfractor_PeytonManning_FR.jpg", "Island Ink · offizielles Beispiel")
        case "Super Bowl Champion Signatures":
            ("bltb94669f4ae3b9f89/6a84d7338bbe58dbf490de51/2026_Topps_Flagship_Football_SuperBowlChampionSignature_Base_JohnElway_FR_%282%29.jpg", "Super Bowl Champions · offizielles Beispiel")
        case "1957 Rookie Variation":
            ("blt9a781c2a60054d72/6a84c5321eb9e5f3af2c3132/2026_Topps_Flagship_Football_1957RookieVariation_CalebDowns_FR.jpg", "1957 Rookie · offizielles Beispiel")
        case _ where card.variant.localizedCaseInsensitiveContains("Golden Mirror"):
            ("blt68174a8cc762894f/6a84d6ef62f1e21677afdd6c/26TFOB_1824_FR_%281%29.jpg", "Golden Mirror · offizielles Beispiel")
        default: nil
        }
        guard let asset else { return nil }
        let url = "https://images.contentstack.io/v3/assets/bltc7206971cb4b2bfc/\(asset.path)?width=600&quality=82&format=jpg"
        return ChaseImageReference(url: url,
                                   sourceURL: "https://www.topps.com/pages/topps-flagship-football",
                                   label: asset.label, isRepresentative: true)
    }
    public var coverageLabel: String {
        let count = coverage?.cardCount ?? cards.count
        if hasOfficialChaseChecklist { return "Offizielle Chase-Liste · \(count) Karten" }
        return coverage?.status == "imported" ? "Preiskatalog · \(count) Karten" : "Teilbestand · \(count) Karten"
    }

    /// Only the manufacturer checklist entries. Sold-market cards that do not
    /// match an exact checklist entry stay out of these filters.
    public func officialChaseCards(family: ToppsChaseFamily = .all) -> [ChaseCard] {
        guard hasOfficialChaseChecklist else { return [] }
        let official = cards.filter { $0.id.hasPrefix(id + ":topps:") }
        return official.filter { card in
            switch family {
            case .all: true
            case .goldenMirror: card.variant.localizedCaseInsensitiveContains("Golden Mirror")
            case .autograph: card.rarity.localizedCaseInsensitiveContains("Autograph")
            case .relic: card.rarity.localizedCaseInsensitiveContains("Relic")
            case .allKings: card.variant.caseInsensitiveCompare("All Kings") == .orderedSame
            case .rookie1957: card.variant.caseInsensitiveCompare("1957 Rookie Variation") == .orderedSame
            }
        }
    }

    /// Keeps every official chase target while adding verified sold evidence.
    /// A market card only replaces an official target when set and card number match;
    /// duplicate checklist numbers additionally require the exact player identity.
    public func mergingMarketCards(_ marketCards: [ChaseCard]) -> ChaseProduct {
        guard hasOfficialChaseChecklist else {
            var result = self
            result.cards = marketCards
            return result
        }
        var result = self
        var merged = cards
        var candidates: [String: [Int]] = [:]
        for index in merged.indices {
            candidates[Self.setNumberKey(merged[index]), default: []].append(index)
        }
        var matched = Set<Int>()
        var extras: [ChaseCard] = []
        for market in marketCards {
            let available = (candidates[Self.setNumberKey(market)] ?? []).filter { !matched.contains($0) }
            let index: Int?
            if available.count == 1 {
                index = available[0]
            } else {
                index = available.first { Self.normalized(merged[$0].player) == Self.normalized(market.player) }
            }
            guard let index else { extras.append(market); continue }
            matched.insert(index)
            let official = merged[index]
            var priced = official
            priced.imageURL = market.imageURL ?? official.imageURL
            priced.imageKind = market.imageURL == nil ? official.imageKind : market.imageKind
            priced.priceCents = market.priceCents
            priced.currency = market.currency
            priced.priceKind = market.priceKind
            priced.priceSourceURL = market.priceSourceURL
            priced.priceCheckedAt = market.priceCheckedAt
            priced.saleCount = market.saleCount
            priced.saleLowCents = market.saleLowCents
            priced.saleHighCents = market.saleHighCents
            priced.sales = market.sales
            merged[index] = priced
        }
        merged.append(contentsOf: extras)
        for index in merged.indices { merged[index].rank = index + 1 }
        result.cards = merged
        return result
    }

    private static func setNumberKey(_ card: ChaseCard) -> String {
        normalized(card.variant) + "|" + normalized(card.number)
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }
}

public struct ChaseCard: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var rank: Int
    public var player: String
    public var variant: String
    public var number: String
    public var rarity: String
    public var packLabel: String
    public var reason: String
    public var imageURL: String?
    public var imageKind: String
    public var sourceURL: String
    public var priceCents: Int?
    public var currency: String?
    public var priceKind: String?
    public var priceSourceURL: String?
    public var priceCheckedAt: String?
    public var odds: String?
    public var oddsSourceURL: String?
    public var saleCount: Int?
    public var saleLowCents: Int?
    public var saleHighCents: Int?
    public var sales: [ChaseSale]?
    public var priceLabel: String {
        switch priceKind {
        case "sold_median": "Median · \(saleCount ?? 0) Verkäufe · Raw"
        case "single_sale": "1 Verkauf · Raw"
        default: "Richtwert · Raw"
        }
    }
    public var label: String { "\(player) · \(variant) #\(number)" }
    public var valueLabel: String? {
        guard let priceCents, let currency else { return nil }
        return (Double(priceCents) / 100).formatted(.currency(code: currency).locale(ScoutLocalization.locale).precision(.fractionLength(0...2)))
    }
    public func hunt(product: ChaseProduct) -> HuntCard {
        HuntCard(id: id, label: label, productName: product.title, player: player, imageURL: imageURL, sourceURL: sourceURL)
    }
}

extension Library {
    /// Replacement is transactional: no owned-card, photo, analysis, or Lookout mutation.
    public mutating func applyChaseCatalog(_ incoming: ChaseCatalog) throws {
        try incoming.validate()
        chaseCatalog = incoming
        if !incoming.products.contains(where: { $0.id == selectedChaseProductID }) {
            selectedChaseProductID = incoming.products.first?.id
        }
    }
    @discardableResult public mutating func addChaseHunt(_ card: ChaseCard, product: ChaseProduct) -> Bool {
        guard product.cards.contains(where: { $0.id == card.id }), !hasChaseHunt(card, product: product) else { return false }
        hunts.append(card.hunt(product: product)); return true
    }
    public func hasChaseHunt(_ card: ChaseCard, product: ChaseProduct) -> Bool {
        hunts.contains {
            $0.id == card.id ||
            ($0.productName.caseInsensitiveCompare(product.title) == .orderedSame &&
             $0.label.caseInsensitiveCompare(card.label) == .orderedSame)
        }
    }
    public func chaseFilter(for productID: String) -> ChaseFilter { chaseFilters?[productID] ?? ChaseFilter() }
    public mutating func setChaseFilter(_ filter: ChaseFilter, for productID: String) {
        guard filter.isValid else { return }
        if chaseFilters == nil { chaseFilters = [:] }
        chaseFilters?[productID] = filter
    }
}

/// The threshold is strict: "over $100" does not include a $100 card.
public struct ChaseFilter: Codable, Equatable, Sendable {
    public var minimumCents: Int = 0
    public init(minimumCents: Int = 0) { self.minimumCents = minimumCents }
    public var isValid: Bool { (0..<1_000_000_000).contains(minimumCents) }
    public var label: String {
        minimumCents == 0 ? "Alle" : "Über " + (Double(minimumCents) / 100).formatted(.currency(code: "USD").locale(ScoutLocalization.locale).precision(.fractionLength(0...2)))
    }
    public static func parseDollars(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard value.range(of: #"^\d{1,7}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let cents = NSDecimalNumber(decimal: decimal * 100).intValue
        return (0..<1_000_000_000).contains(cents) ? cents : nil
    }
}

public struct RankedChase: Identifiable, Equatable, Sendable {
    public let card: ChaseCard
    public let rank: Int?
    public var id: String { card.id }
}

public struct ChaseRanking: Sendable {
    public let priced: [RankedChase]
    public let unknown: [RankedChase]
    public init(cards: [ChaseCard], sold: Bool = false) {
        func before(_ a: ChaseCard, _ b: ChaseCard) -> Bool {
            let left = "\(a.player)|\(a.variant)|\(a.number)|\(a.id)"
            let right = "\(b.player)|\(b.variant)|\(b.number)|\(b.id)"
            return left < right
        }
        let kinds = sold ? ["sold_median", "single_sale"] : ["guide"]
        let eligible = cards.filter { kinds.contains($0.priceKind ?? "") && $0.currency == "USD" && ($0.priceCents ?? 0) > 0 }
            .sorted { a, b in a.priceCents != b.priceCents ? a.priceCents! > b.priceCents! : before(a, b) }
        var lastPrice: Int?, position = 0
        priced = eligible.enumerated().map { index, card in
            if card.priceCents != lastPrice { position = index + 1; lastPrice = card.priceCents }
            return RankedChase(card: card, rank: position)
        }
        let pricedIDs = Set(eligible.map(\.id))
        unknown = cards.filter { !pricedIDs.contains($0.id) }.sorted(by: before).map { RankedChase(card: $0, rank: nil) }
    }
    public func matching(_ filter: ChaseFilter, query: String = "") -> [RankedChase] {
        guard filter.isValid else { return [] }
        return priced.filter { ($0.card.priceCents ?? 0) > filter.minimumCents && Self.matches($0.card, query: query) }
    }
    public func unknownMatching(query: String) -> [RankedChase] {
        unknown.filter { Self.matches($0.card, query: query) }
    }
    private static func matches(_ card: ChaseCard, query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || card.label.localizedStandardContains(text)
    }
}
