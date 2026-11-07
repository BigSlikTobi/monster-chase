import XCTest
@testable import CardScoutCore

final class SoldRankingTests: XCTestCase {
    func snapshot() throws -> MarketSnapshot {
        var card = try ChaseTests().catalog().products[0].cards[0]
        card.id = "2025-panini-donruss-optic:cardsight:fixture"
        card.priceCents = 35000; card.priceKind = "sold_median"; card.currency = "USD"
        card.saleCount = 2; card.saleLowCents = 34000; card.saleHighCents = 36000
        card.sourceURL = "https://showme.cards/abcde"; card.priceSourceURL = card.sourceURL
        card.imageURL = "https://i.ebayimg.com/images/test.jpg"; card.priceCheckedAt = "2026-09-08"
        card.sales = [ChaseSale(priceCents: 34000, date: "2026-09-02", url: card.sourceURL),
                      ChaseSale(priceCents: 36000, date: "2026-09-03", url: "https://showme.cards/abcdF")]
        return MarketSnapshot(version: 1, productID: "2025-panini-donruss-optic", revision: "fixture", status: "ready",
                              checkedAt: "2026-09-08", expiresAt: Date().timeIntervalSince1970 + 3600,
                              checkedCards: 902, totalCards: 902, matchedCards: 1, excludedSales: 2, capped: false, cards: [card])
    }
    func testMedianAndSingleSaleAreExplicitAndGuidesStaySeparate() throws {
        let s = try snapshot(); var single = s.cards[0]
        single.id += "single"; single.priceKind = "single_sale"; single.saleCount = 1; single.priceCents = 40000
        let guide = try ChaseTests().catalog().products[0].cards[0]
        let ranking = ChaseRanking(cards: s.cards + [single, guide], sold: true)
        XCTAssertEqual(ranking.priced.count, 2)
        XCTAssertEqual(ranking.priced[0].card.priceLabel, "1 Verkauf · Raw")
        XCTAssertEqual(ranking.priced[1].card.priceLabel, "Median · 2 Verkäufe · Raw")
        XCTAssertEqual(ranking.unknown.map(\.id), [guide.id])
        XCTAssertEqual(ChaseRanking(cards: s.cards).priced.count, 0)
    }
    func testSnapshotValidationAndNoTenLimit() throws {
        var s = try snapshot()
        s.cards = (1...35).map { n in var c = s.cards[0]; c.id += "\(n)"; c.rank = n; return c }
        s.matchedCards = 35
        try s.validate(for: s.productID)
        XCTAssertEqual(ChaseRanking(cards: s.cards, sold: true).matching(ChaseFilter(minimumCents: 20000)).count, 35)
        XCTAssertEqual(ChaseRanking(cards: s.cards, sold: true).matching(ChaseFilter(minimumCents: 35000)).count, 0)
    }
    func testExpiredViewsAndCrossProductOrBadEvidenceAreRejected() throws {
        let s = try snapshot()
        XCTAssertThrowsError(try s.validate(for: "2026-topps-flagship-football"))
        var expired = s; expired.expiresAt = Date().timeIntervalSince1970 - 1
        XCTAssertThrowsError(try expired.validate(for: s.productID))
        XCTAssertTrue(expired.usableCards.isEmpty)
        var wrong = s; wrong.cards[0].priceKind = "guide"
        XCTAssertThrowsError(try wrong.validate(for: s.productID))
        wrong = s; wrong.cards[0].sales?[0].url = "https://localhost/private"
        XCTAssertThrowsError(try wrong.validate(for: s.productID))
        wrong = s; wrong.cards[0].saleCount = 1
        XCTAssertThrowsError(try wrong.validate(for: s.productID))
    }
    func testProviderViewDoesNotAlterOrPersistInOwnedLibrary() throws {
        let s = try snapshot()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root); var library = Library()
        library.cards = [OwnedCard(state: "analyzed", frontFile: "keep.jpg")]
        try disk.save(library)
        let before = try Data(contentsOf: root.appendingPathComponent("library.json"))
        try s.validate(for: s.productID)
        _ = ChaseRanking(cards: s.cards, sold: true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), before)
        XCTAssertFalse(String(data: before, encoding: .utf8)!.contains("cardsight"))
    }
    func testRealRuntimeCacheWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["CARDSCOUT_MARKET_CACHE"] else { throw XCTSkip("Optional live cache check") }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let s = try JSONDecoder().decode(MarketSnapshot.self, from: data)
        try s.validate(for: s.productID)
        XCTAssertGreaterThan(s.cards.count, 10)
        XCTAssertEqual(ChaseRanking(cards: s.cards, sold: true).priced.count, s.cards.count)
    }
    func testRankingLinksOnlyAllowTheKnownProductsWithoutCredentials() {
        let good = "cardscout://ranking/2025-panini-donruss-optic"
        XCTAssertEqual(MarketSnapshot.deepLinkProduct(URL(string: good)!), "2025-panini-donruss-optic")
        for url in [good + "?url=https://evil.example", good + "#fragment", good.replacingOccurrences(of: "ranking", with: "secret@ranking"), "cardscout://ranking/other", "https://ranking/2025-panini-donruss-optic"] {
            XCTAssertNil(MarketSnapshot.deepLinkProduct(URL(string: url)!))
        }
    }
}
