import XCTest
@testable import CardScoutCore

final class DashboardValueCacheTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_794_000_000)
    func fixture() -> (Library, CollectionCardValue) {
        var library = Library()
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-11-07", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        a.player = "Fixture"; a.identityConfirmed = true; a.marketLowCents = 100; a.marketHighCents = 200
        library.cards = [OwnedCard(id: "a", state: "analyzed", analysis: a)]
        return (library, CollectionStatistics(library: library, asOf: now).values[0])
    }
    func testCacheSurvivesRestartWithoutProviderEvidenceAndExpiresOnlyForRefresh() throws {
        var (library, value) = fixture()
        value = CollectionCardValue(cardID: value.cardID, currency: value.currency, lowCents: 100, highCents: 200, isEstimate: true, basis: "Comparison", checkedAt: "2026-11-07") // comparisons stay separate
        var cache = DashboardValueCache()
        cache.update(card: library.cards[0], value: value, refreshAfter: now.addingTimeInterval(100000), asOf: now)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        try disk.saveDashboardValues(cache)
        cache = disk.loadDashboardValues()
        XCTAssertTrue(cache.isFresh(library.cards[0], asOf: now.addingTimeInterval(10)))
        XCTAssertFalse(cache.isFresh(library.cards[0], asOf: now.addingTimeInterval(86401)))
        library.cards[0].analysis?.marketLowCents = nil; library.cards[0].analysis?.marketHighCents = nil
        let stats = CollectionStatistics(library: library, asOf: now, cachedValues: cache.values(in: library))
        XCTAssertEqual(stats.values.first?.lowCents, 100)
        XCTAssertTrue(stats.values.first!.isCached)
        XCTAssertNil(stats.portfolioValue(currency: "EUR"))
        let bytes = try String(contentsOf: root.appendingPathComponent("dashboard-values.json"), encoding: .utf8)
        XCTAssertFalse(bytes.contains("marketReferences")); XCTAssertFalse(bytes.contains("marketSources"))
    }
    func testRetakesIdentityCorrectionsAndRemovalsInvalidateCache() {
        let (original, value) = fixture()
        var cache = DashboardValueCache()
        cache.update(card: original.cards[0], value: value, refreshAfter: now.addingTimeInterval(60), asOf: now)
        var library = original
        library.cards[0].analysis?.parallel = "Gold"
        XCTAssertTrue(cache.values(in: library).isEmpty)
        library = original; library.cards[0].analysisJobID = UUID().uuidString
        XCTAssertTrue(cache.values(in: library).isEmpty)
        library = original; library.cards.removeAll()
        cache.prune(in: library)
        XCTAssertTrue(cache.entries.isEmpty)
    }
    func testFreshPricesReplaceCachedAmountAndAuthoritativeEmptyResultRemovesIt() {
        var (library, value) = fixture()
        var cache = DashboardValueCache()
        cache.update(card: library.cards[0], value: value, refreshAfter: now.addingTimeInterval(60), asOf: now)
        library.cards[0].analysis?.marketLowCents = 300; library.cards[0].analysis?.marketHighCents = 400
        var stats = CollectionStatistics(library: library, asOf: now, cachedValues: cache.values(in: library))
        XCTAssertEqual(stats.values.count, 1); XCTAssertEqual(stats.values[0].lowCents, 300)
        XCTAssertFalse(stats.values[0].isCached)
        value = CollectionCardValue(cardID: value.cardID, currency: value.currency, lowCents: 400, highCents: 400, isEstimate: false, basis: "Saved", checkedAt: "2026-11-07")
        cache.update(card: library.cards[0], value: value, refreshAfter: now.addingTimeInterval(60), asOf: now)
        library.cards[0].analysis?.marketLowCents = nil; library.cards[0].analysis?.marketHighCents = nil
        stats = CollectionStatistics(library: library, asOf: now, cachedValues: cache.values(in: library))
        XCTAssertEqual(stats.values.first?.lowCents, 400)
        cache.update(card: library.cards[0], value: nil, refreshAfter: now, asOf: now)
        XCTAssertTrue(cache.values(in: library).isEmpty)
    }
    func testFreshCacheKeepsHistoryAndBurnCountAvailableAfterRestart() throws {
        var (library, value) = fixture()
        let baseline = library.portfolioValues(asOf: now)
        var cache = DashboardValueCache()
        cache.update(card: library.cards[0], value: value, refreshAfter: now.addingTimeInterval(60), asOf: now,
                     portfolioValue: baseline[0])
        library.cards[0].analysis?.marketLowCents = nil; library.cards[0].analysis?.marketHighCents = nil
        let cached = cache.portfolioValues(in: library, asOf: now)
        XCTAssertTrue(library.recordPortfolioObservation(asOf: now, cachedValues: cached))
        XCTAssertEqual(library.portfolioHistory?.last?.values.first?.lowCents, 100)
        library.purchases = [CardPurchase(title: "Box", amountCents: 1000, purchasedOn: "2026-01-01")]
        let stats = CollectionStatistics(library: library, asOf: now, cachedValues: cache.values(in: library))
        let burn = BurnCount(statistics: stats, currency: "EUR")
        XCTAssertEqual(burn.burnLowCents, 800)
        XCTAssertEqual(burn.burnHighCents, 900)
        XCTAssertTrue(cache.portfolioValues(in: library, asOf: now.addingTimeInterval(61)).isEmpty)
    }

}
