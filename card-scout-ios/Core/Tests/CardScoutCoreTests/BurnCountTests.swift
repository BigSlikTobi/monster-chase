import XCTest
@testable import CardScoutCore

final class BurnCountTests: XCTestCase {
    func valueCard(low: Int?, high: Int? = nil, currency: String = "EUR") -> OwnedCard {
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-11-01", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        a.player = "Fixture"; a.identityConfirmed = true; a.marketLowCents = low; a.marketHighCents = high ?? low; a.currency = currency
        return OwnedCard(state: "analyzed", analysis: a)
    }
    func burn(cards: [OwnedCard], purchases: [CardPurchase], currency: String = "EUR") -> BurnCount {
        var library = Library(); library.cards = cards; library.purchases = purchases
        let now = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
        return BurnCount(statistics: CollectionStatistics(library: library, asOf: now), currency: currency)
    }
    func purchase(_ amount: Int, category: PurchaseCategory = .box, currency: String = "EUR", quantity: Int = 1) -> CardPurchase {
        CardPurchase(title: "Fixture", category: category, amountCents: amount, currency: currency, quantity: quantity, purchasedOn: "2026-11-01")
    }
    func testMissingSpendingAndPricesNeverBecomeZeroOrShame() {
        let empty = burn(cards: [], purchases: [])
        XCTAssertNil(empty.spentCents); XCTAssertNil(empty.valueLowCents); XCTAssertNil(empty.burnHighCents)
        XCTAssertEqual(empty.mood, .curious)
        let noLedger = burn(cards: [valueCard(low: 1000)], purchases: [])
        XCTAssertNil(noLedger.burnLowCents); XCTAssertEqual(noLedger.mood, .curious)
    }
    func testPartialCoverageShowsExplicitlyIndicativeBurn() {
        let partial = burn(cards: [valueCard(low: 100), valueCard(low: nil)], purchases: [purchase(10000)])
        XCTAssertEqual(partial.spentCents, 10000); XCTAssertEqual(partial.pricedCards, 1)
        XCTAssertTrue(partial.canCompare); XCTAssertEqual(partial.burnHighCents, 9900)
        XCTAssertTrue(partial.isIndicative); XCTAssertFalse(partial.hasCompleteCoverage)
    }
    func testRangeOverlappingSpendStaysUncertain() {
        let summary = burn(cards: [valueCard(low: 800, high: 1200)], purchases: [purchase(1000)])
        XCTAssertEqual(summary.burnLowCents, -200); XCTAssertEqual(summary.burnHighCents, 200)
        XCTAssertEqual(summary.mood, .curious)
    }
    func testAboveCostShowsNegativeBurnAndProudMood() {
        let summary = burn(cards: [valueCard(low: 1500)], purchases: [purchase(1000)])
        XCTAssertEqual(summary.burnLowCents, -500); XCTAssertEqual(summary.burnHighCents, -500)
        XCTAssertEqual(summary.mood, .proud)
    }
    func testProfitableRangeAndBreakEvenPreserveSignedDifference() {
        let profit = burn(cards: [valueCard(low: 1500, high: 2000)], purchases: [purchase(1000)])
        XCTAssertEqual(profit.burnLowCents, -1000)
        XCTAssertEqual(profit.burnHighCents, -500)
        let even = burn(cards: [valueCard(low: 1000)], purchases: [purchase(1000)])
        XCTAssertEqual(even.burnLowCents, 0)
        XCTAssertEqual(even.burnHighCents, 0)
    }
    func testPerformanceRequiresWholeRangeToClearThreshold() {
        XCTAssertEqual(burn(cards: [valueCard(low: 1250)], purchases: [purchase(1000)]).performance, .excellent)
        XCTAssertEqual(burn(cards: [valueCard(low: 1100, high: 1400)], purchases: [purchase(1000)]).performance, .ahead)
        XCTAssertEqual(burn(cards: [valueCard(low: 750)], purchases: [purchase(1000)]).performance, .heavyBurn)
        XCTAssertEqual(burn(cards: [valueCard(low: 500, high: 900)], purchases: [purchase(1000)]).performance, .behind)
        XCTAssertEqual(burn(cards: [valueCard(low: 1000)], purchases: [purchase(1000)]).performance, .breakEven)
        let touchingZero = burn(cards: [valueCard(low: 1000, high: 1200)], purchases: [purchase(1000)])
        XCTAssertEqual(touchingZero.burnLowCents, -200)
        XCTAssertEqual(touchingZero.burnHighCents, 0)
        XCTAssertEqual(touchingZero.performance, .uncertain)
        XCTAssertEqual(burn(cards: [valueCard(low: nil)], purchases: [purchase(1000)]).performance, .unknown)
        XCTAssertEqual(burn(cards: [valueCard(low: 100), valueCard(low: nil)], purchases: [purchase(1000)]).performance, .heavyBurn)
        XCTAssertEqual(burn(cards: [valueCard(low: 100)], purchases: [purchase(0)]).performance, .unknown)
    }
    func testDeficitUsesWholePurchaseOnceAndExcludesSuppliesAndOtherCurrency() {
        let summary = burn(cards: [valueCard(low: 500, high: 700)], purchases: [purchase(1000, quantity: 5), purchase(9000, category: .supplies), purchase(5000, category: .other), purchase(100000, currency: "USD")])
        XCTAssertEqual(summary.spentCents, 1000); XCTAssertEqual(summary.purchaseCount, 1)
        XCTAssertEqual(summary.burnLowCents, 300); XCTAssertEqual(summary.burnHighCents, 500)
        XCTAssertEqual(summary.mood, .roasted)
    }
    func testDifferentCurrencyValuesCannotOffsetSpending() {
        let summary = burn(cards: [valueCard(low: 20000, currency: "USD")], purchases: [purchase(1000)])
        XCTAssertNil(summary.valueLowCents); XCTAssertNil(summary.burnLowCents); XCTAssertEqual(summary.mood, .curious)
    }
    func testExplicitManualEstimateEnablesComparisonButDoesNotChangeMarketHistory() throws {
        var library = Library(); library.cards = [valueCard(low: nil)]
        library.purchases = [purchase(1000)]
        try library.setManualBurnValue(amountCents: 500, currency: "EUR")
        let stats = CollectionStatistics(library: library)
        let summary = BurnCount(statistics: stats, currency: "EUR", manualValueCents: library.currentManualBurnValue(currency: "EUR")?.amountCents)
        XCTAssertTrue(summary.isManualValue); XCTAssertTrue(summary.canCompare)
        XCTAssertEqual(summary.burnHighCents, 500); XCTAssertEqual(summary.mood, .roasted)
        XCTAssertNil(stats.portfolioValue(currency: "EUR")); XCTAssertTrue(library.portfolioValues().isEmpty)
        XCTAssertFalse(library.recordPortfolioObservation())
        library.cards.append(valueCard(low: 100))
        XCTAssertNil(library.currentManualBurnValue(currency: "EUR"))
    }
    func testManualValuePersistenceZeroAndRemoval() throws {
        var library = Library(); library.cards = [valueCard(low: 100)]
        try library.setManualBurnValue(amountCents: 0, currency: "EUR")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root); try disk.save(library)
        var restored = try disk.load()
        XCTAssertEqual(restored.currentManualBurnValue(currency: "EUR")?.amountCents, 0)
        XCTAssertNil(restored.currentManualBurnValue(currency: "USD"))
        XCTAssertThrowsError(try restored.setManualBurnValue(amountCents: -1, currency: "EUR"))
        XCTAssertThrowsError(try restored.setManualBurnValue(amountCents: 100, currency: "BAD"))
        try restored.setManualBurnValue(amountCents: nil, currency: "EUR")
        XCTAssertNil(restored.currentManualBurnValue(currency: "EUR"))
    }

    func testEstimatesJoinKnownValuesWithoutMixingCurrenciesOrCountingUnknownCards() {
        var library = Library()
        let exact = valueCard(low: 1000)
        let estimate = valueCard(low: nil)
        let unknown = valueCard(low: nil)
        library.cards = [exact, estimate, unknown, valueCard(low: 99999, currency: "USD")]
        library.purchases = [purchase(2000)]
        let cached = CollectionCardValue(cardID: estimate.id, currency: "EUR", lowCents: 500, highCents: 500,
            isEstimate: true, basis: "Comparison median", checkedAt: "2026-11-07")
        let now = ISO8601DateFormatter().date(from: "2026-11-07T12:00:00Z")!
        let stats = CollectionStatistics(library: library, asOf: now, cachedValues: [cached])
        XCTAssertEqual(stats.estimatedCollectionValue(currency: "EUR")?.low, 1500)
        XCTAssertEqual(stats.estimatedCollectionValue(currency: "EUR")?.high, 1500)
        XCTAssertEqual(stats.portfolioValue(currency: "EUR")?.low, 1000)
        let result = BurnCount(statistics: stats, currency: "EUR")
        XCTAssertEqual(result.valueLowCents, 1500); XCTAssertEqual(result.burnHighCents, 500)
        XCTAssertEqual(result.pricedCards, 2); XCTAssertTrue(result.includesComparisonEstimates)
        XCTAssertTrue(result.isIndicative)
    }

}
