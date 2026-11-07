import XCTest
@testable import CardScoutCore

final class ComparablePriceTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!

    func estimate(_ prices: [Int]) -> ComparableEstimate {
        let refs = prices.enumerated().map { index, cents in
            MarketReference(provider: "CardSight", url: "https://example.com/card/\(index)", kind: "sold", grade: "raw",
                matchQuality: "near", lowCents: cents, highCents: cents, currency: "EUR", saleDate: "2026-11-01",
                checkedAt: "2026-11-06", shipping: "unknown", expiresAt: now.timeIntervalSince1970 + 300)
        }
        return ComparableEstimate(lowCents: prices.min()!, highCents: prices.max()!, currency: "EUR", shipping: "unknown",
            cardCount: prices.count, confidence: "low", scopeLabel: "2026 Bowman Base", checkedAt: "2026-11-06",
            expiresAt: now.timeIntervalSince1970 + 200, references: refs)
    }

    func testExpensiveOutlierDoesNotSetComparisonHeadlineOrSortValue() throws {
        let comparison = estimate([100, 100, 100, 800])
        let summary = try XCTUnwrap(comparison.marketSummary(asOf: now))
        XCTAssertEqual(summary.orderingValueCents, 100)
        XCTAssertEqual(summary.valueLabel, "ca. \(comparison.references[0].valueLabel)")
        XCTAssertEqual(summary.basisLabel, "Vergleichsmedian · 4 Karten · geringe Sicherheit")
        XCTAssertTrue(summary.isEstimate)
        var range = comparison.references[0]; range.highCents = 800
        XCTAssertEqual(summary.rangeLabel, range.valueLabel)
    }

    func testOddEvenAndUnsortedComparisonSamples() throws {
        for (prices, expected) in [([800, 100, 100], 100.0), ([800, 100, 200, 100], 150.0), ([100, 100, 100], 100.0)] {
            let summary = try XCTUnwrap(estimate(prices).marketSummary(asOf: now))
            XCTAssertEqual(summary.orderingValueCents, expected)
        }
    }

    func testRangedGuidesUseOneMidpointPerComparisonCard() throws {
        var comparison = estimate([100, 100, 100, 800])
        for index in comparison.references.indices {
            comparison.references[index].kind = "guide"
            comparison.references[index].saleDate = nil
            comparison.references[index].highCents += 100
        }
        comparison.highCents = 900
        let summary = try XCTUnwrap(comparison.marketSummary(asOf: now))
        XCTAssertEqual(summary.orderingValueCents, 150)
        XCTAssertTrue(summary.isComparable)
        XCTAssertFalse(summary.isGuide)
    }

    func testDisplayedMedianRoundsHalfCentsTheSameWayAsStatistics() throws {
        let comparison = estimate([100, 100, 101, 800])
        let summary = try XCTUnwrap(comparison.marketSummary(asOf: now))
        var rounded = comparison.references[0]; rounded.lowCents = 101; rounded.highCents = 101
        XCTAssertEqual(summary.orderingValueCents, 100.5)
        XCTAssertEqual(summary.valueLabel, "ca. \(rounded.valueLabel)")
    }

    func testExactGuideRangeStillShowsTheSourceRange() throws {
        var reference = estimate([100, 100, 800]).references[0]
        reference.kind = "guide"; reference.matchQuality = "exact"; reference.highCents = 200
        let summary = RawMarketSummary(references: [reference])
        XCTAssertTrue(summary.isGuide)
        XCTAssertEqual(summary.valueLabel, reference.valueLabel)
        XCTAssertNil(summary.rangeLabel)
    }

    func testCollectionUsesSameMedianAndKeepsComparisonsOutOfConfirmedValue() throws {
        var analysis = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-11-06", marketSources: [], confidence: "high",
            conditionNotes: "", rationale: "", needsReview: false)
        analysis.identityConfirmed = true
        analysis.insights = CardInsights(rarityTier: "base", rarityBullets: [], conditionStatus: "no_obvious_damage",
            conditionIssues: [], conditionLimitations: [], marketBullets: [], marketReferences: [], sourceChecks: [], actionReason: "")
        analysis.comparableEstimate = estimate([100, 100, 100, 800])
        var library = Library(); library.cards = [OwnedCard(state: "analyzed", analysis: analysis)]
        let stats = CollectionStatistics(library: library, asOf: now)
        let value = try XCTUnwrap(stats.values.first)
        XCTAssertEqual(value.lowCents, 100)
        XCTAssertEqual(value.highCents, 100)
        XCTAssertEqual(value.label, analysis.comparableEstimate?.marketSummary(asOf: now)?.valueLabel)
        XCTAssertEqual(stats.indicativeCards, 1)
        XCTAssertNil(stats.confirmedValue(currency: "EUR"))
        XCTAssertTrue(CollectionStatistics(library: library, asOf: now.addingTimeInterval(301)).values.isEmpty)
    }

    func testExactSalesKeepTheirOwnMedianWithTheSameOutlier() throws {
        var refs = estimate([100, 100, 100, 800]).references
        for index in refs.indices { refs[index].matchQuality = "exact" }
        let info = CardInsights(rarityTier: "base", rarityBullets: [], conditionStatus: "no_obvious_damage",
            conditionIssues: [], conditionLimitations: [], marketBullets: [], marketReferences: refs, sourceChecks: [], actionReason: "")
        let summary = try XCTUnwrap(info.marketSummary(asOf: now))
        XCTAssertEqual(summary.orderingValueCents, 100)
        XCTAssertEqual(summary.valueLabel, refs[0].valueLabel)
        XCTAssertEqual(summary.basisLabel, "Median · 4 Verkäufe")
        XCTAssertFalse(summary.isEstimate)
    }
}
