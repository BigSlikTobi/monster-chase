import Foundation

public struct ChaseSale: Codable, Equatable, Sendable {
    public var priceCents: Int
    public var date: String
    public var url: String
}

/// Short-lived provider view. Never persisted in the owned-card library.
public struct MarketSnapshot: Codable, Equatable, Sendable {
    public static let productIDs = ["2025-panini-donruss-optic", "2026-topps-flagship-football"]
    public var version: Int
    public var productID: String
    public var revision: String
    public var status: String
    public var message: String?
    public var checkedAt: String
    public var expiresAt: Double
    public var checkedCards: Int
    public var totalCards: Int
    public var matchedCards: Int
    public var excludedSales: Int
    public var capped: Bool
    public var cards: [ChaseCard]
    public var isFresh: Bool { expiresAt > Date().timeIntervalSince1970 }
    public var usableCards: [ChaseCard] { isFresh ? cards : [] }
    public static func deepLinkProduct(_ url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "cardscout",
              parts.host == "ranking", parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.port == nil else { return nil }
        return productIDs.first { parts.path == "/" + $0 }
    }
    public func validate(for product: String, now: Date = Date()) throws {
        guard version == 1, productID == product, Self.productIDs.contains(product),
              ["empty", "ready", "refreshing", "error", "unavailable"].contains(status),
              !revision.isEmpty, cards.count <= 500, (0...5000).contains(totalCards),
              (0...totalCards).contains(checkedCards), (0...totalCards).contains(matchedCards),
              excludedSales >= 0, expiresAt.isFinite, expiresAt <= now.timeIntervalSince1970 + 86_460,
              Set(cards.map(\.id)).count == cards.count else { throw StoreError.invalidResult }
        if status == "ready" {
            guard matchedCards >= cards.count, checkedCards == totalCards,
                  capped == (matchedCards > cards.count), Self.validDate(checkedAt),
                  expiresAt > now.timeIntervalSince1970 else { throw StoreError.invalidResult }
        }
        for card in cards {
            guard card.id.hasPrefix(product + ":cardsight:"), !card.player.isEmpty, !card.variant.isEmpty,
                  !card.number.isEmpty, card.currency == "USD", let amount = card.priceCents,
                  (1..<1_000_000_000).contains(amount), let count = card.saleCount, (1...25).contains(count),
                  card.priceKind == (count == 1 ? "single_sale" : "sold_median"),
                  let low = card.saleLowCents, let high = card.saleHighCents, low > 0, low <= amount, amount <= high,
                  let sales = card.sales, sales.count == min(5, count),
                  Set(sales.map(\.url)).count == sales.count,
                  Self.saleURL(card.sourceURL), card.priceSourceURL.map(Self.saleURL) == true,
                  card.priceCheckedAt == checkedAt,
                  card.imageURL.map(Self.imageURL) ?? true else { throw StoreError.invalidResult }
            for sale in sales {
                guard Self.saleURL(sale.url), Self.validDate(sale.date), (low...high).contains(sale.priceCents),
                      sale.date <= checkedAt else { throw StoreError.invalidResult }
            }
        }
    }
    private static func validDate(_ value: String) -> Bool {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
    private static func saleURL(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), url.scheme == "https", url.user == nil,
              url.password == nil, url.port == nil || url.port == 443 else { return false }
        return ["showme.cards", "www.ebay.com", "ebay.com"].contains(url.host ?? "")
    }
    private static func imageURL(_ value: String) -> Bool {
        guard let url = URLComponents(string: value) else { return false }
        return url.scheme == "https" && url.host == "i.ebayimg.com" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
}
