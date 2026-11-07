import XCTest
@testable import CardScoutCore

final class CollectionStatisticsTests: XCTestCase {
    let today = ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z")!
    func reference(_ price: Int, match: String = "exact", currency: String = "USD", shipping: String = "excluded", date: String = "2026-10-10", item: String? = nil) -> MarketReference {
        MarketReference(provider: "SportsCardsPro", url: "https://www.sportscardspro.com/game/fixture", kind: "sold", grade: "raw", matchQuality: match,
            lowCents: price, highCents: price, currency: currency, saleDate: date, checkedAt: "2026-10-16", shipping: shipping, listingURL: item)
    }
    func card(_ id: String, refs: [MarketReference] = [], confirmed: Bool = true, serial: String? = nil) -> OwnedCard {
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-10-16", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: !confirmed)
        a.player = "Player \(id)"; a.identityConfirmed = confirmed; a.collectionID = confirmed ? "fixture-set" : nil; a.cardNumber = id
        a.serialNumber = serial
        a.insights = CardInsights(rarityTier: serial == nil ? "base" : "numbered", rarityBullets: [], conditionStatus: "no_obvious_damage",
            conditionIssues: [], conditionLimitations: [], marketBullets: [], marketReferences: refs, sourceChecks: [], actionReason: "")
        return OwnedCard(id: id, createdAt: "2026-10-16T10:00:00Z", state: "analyzed", analysis: a)
    }
    func stats(cards: [OwnedCard] = [], purchases: [CardPurchase] = []) -> CollectionStatistics {
        var library = Library(); library.cards = cards; library.purchases = purchases
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return CollectionStatistics(library: library, asOf: today, calendar: calendar)
    }
    func testDecimalAmountsAreExactAndAmbiguousAmountsRejected() {
        XCTAssertEqual(CardPurchase.parseAmount("19,99"), 1999)
        XCTAssertEqual(CardPurchase.parseAmount("19.9"), 1990)
        XCTAssertEqual(CardPurchase.parseAmount(" 20 "), 2000)
        for invalid in ["-1", "1.999", "1,234.56", "0", "1e3", "€20", "1000001"] { XCTAssertNil(CardPurchase.parseAmount(invalid)) }
    }
    func testPurchaseTotalIsNotMultipliedByQuantityAndCurrenciesStaySeparate() {
        let euros = CardPurchase(title: "5 packs with shipping", amountCents: 2599, quantity: 5, purchasedOn: "2026-10-15")
        let dollars = CardPurchase(title: "Box", category: .box, amountCents: 12000, currency: "USD", purchasedOn: "2026-10-15")
        let snapshot = stats(purchases: [euros, dollars])
        XCTAssertEqual(snapshot.spending(currency: "EUR"), 2599)
        XCTAssertEqual(snapshot.spending(currency: "USD", category: .box), 12000)
        XCTAssertEqual(snapshot.spending(currency: "USD", category: .pack), 0)
    }
    func testInvalidOrFuturePurchasesAreNotCounted() {
        var purchase = CardPurchase(title: "Box", amountCents: 1000, purchasedOn: "2026-02-30")
        XCTAssertFalse(purchase.isValid)
        XCTAssertTrue(stats(purchases: [purchase]).purchases.isEmpty)
        purchase.purchasedOn = "2026-10-17"
        XCTAssertTrue(stats(purchases: [purchase]).purchases.isEmpty)
    }
    func testConfirmedMedianValuesAndMissingPricesStayDistinct() {
        let snapshot = stats(cards: [card("a", refs: [reference(100), reference(200), reference(900)]), card("b")])
        XCTAssertEqual(snapshot.confirmedValue(currency: "USD")?.low, 200)
        XCTAssertEqual(snapshot.pricedCards, 1)
        XCTAssertEqual(snapshot.totalCards, 2)
        XCTAssertNil(stats(cards: [card("b")]).confirmedValue(currency: "USD"))
    }
    func testUncertainVariantUsesMedianAsSeparateIndicatorOnly() {
        let snapshot = stats(cards: [card("pitts", refs: [reference(150, match: "near"), reference(179, match: "near"), reference(199, match: "near")], confirmed: false)])
        XCTAssertEqual(snapshot.values.first?.lowCents, 179)
        XCTAssertEqual(snapshot.values.first?.basis, "Median · 3 Vergleichsverkäufe")
        XCTAssertEqual(snapshot.indicativeCards, 1)
        XCTAssertEqual(snapshot.pricedCards, 0)
        XCTAssertNil(snapshot.confirmedValue(currency: "USD"))
    }
    func testDuplicateSaleAcrossProvidersIsCountedOnce() {
        let a = reference(100, match: "near", item: "https://www.ebay.com/itm/123456789012?tracking=x")
        var same = a; same.provider = "eBay"; same.listingURL = "https://www.ebay.de/itm/123456789012"
        let b = reference(300, match: "near", item: "https://www.ebay.com/itm/123456789013")
        XCTAssertEqual(stats(cards: [card("a", refs: [a, same, b], confirmed: false)]).values.first?.lowCents, 200)
    }
    func testUncertainVariantMedianResistsOneExpensiveSale() {
        let refs = [100, 100, 100, 800].enumerated().map { index, amount in
            reference(amount, match: "near", item: "https://www.ebay.com/itm/12345678901\(index)")
        }
        let snapshot = stats(cards: [card("a", refs: refs, confirmed: false)])
        XCTAssertEqual(snapshot.values.first?.lowCents, 100)
        XCTAssertEqual(snapshot.values.first?.highCents, 100)
        XCTAssertEqual(snapshot.values.first?.basis, "Median · 4 Vergleichsverkäufe")
        XCTAssertNil(snapshot.confirmedValue(currency: "USD"))
    }
    func testEstimatesNeverMixShippingCurrencyGradeOrProxyMatches() {
        var graded = reference(90000, match: "near"); graded.grade = "PSA 10"
        let refs = [reference(100, match: "near"), reference(200, match: "near"), reference(5000, match: "near", currency: "EUR"),
                    reference(9000, match: "near", shipping: "included"), reference(10000, match: "proxy"), graded]
        let value = stats(cards: [card("a", refs: refs, confirmed: false)]).values.first
        XCTAssertEqual(value?.currency, "USD"); XCTAssertEqual(value?.lowCents, 150)
    }
    func testPendingAndLowConfidenceCardsDoNotInventPricesOrHighlights() {
        var pending = card("a", refs: [reference(1000)], serial: "1/1"); pending.state = "enriching"
        var low = card("b", refs: [reference(5000)], confirmed: false, serial: "1/1"); low.analysis?.confidence = "low"
        let snapshot = stats(cards: [pending, low])
        XCTAssertTrue(snapshot.values.isEmpty)
        XCTAssertNil(snapshot.specialCardID)
    }
    func testSmallestVisibleNumberingWinsAndCopiesCountAsExtras() {
        var extra = card("duplicate"); extra.analysis?.cardNumber = "a"
        let snapshot = stats(cards: [card("a", serial: "05/99"), card("b", serial: "2/10"), extra])
        XCTAssertEqual(snapshot.specialCardID, "b")
        XCTAssertEqual(snapshot.duplicateExtras, 1)
        XCTAssertEqual(snapshot.numberedCards, 2)
        for bad in ["/99", "0/99", "100/99", "maybe 1/1", "unknown"] { XCTAssertNil(CollectionStatistics.serialLimit(bad)) }
    }
    func testGrowthCountsFractionalTimestampsAndExcludesFutureCaptures() {
        var a = card("a"); a.createdAt = "2026-10-15T23:00:00.123Z"
        var future = card("future"); future.createdAt = "2026-10-17T10:00:00Z"
        let snapshot = stats(cards: [a, future])
        XCTAssertEqual(snapshot.growth.count, 14)
        XCTAssertEqual(snapshot.growth.last?.count, 1)
    }
    func testLedgerPersistsAndOldLibrariesStillDecode() throws {
        let old = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(Library()))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "purchases")
        XCTAssertNil(try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: object)).purchases)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        var library = old
        library.purchases = [CardPurchase(title: "Pack", amountCents: 1499, purchasedOn: "2026-10-16")]
        try disk.save(library)
        XCTAssertEqual(try disk.load().purchases, library.purchases)
    }
}
