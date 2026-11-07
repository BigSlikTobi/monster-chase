import XCTest
@testable import CardScoutCore

final class MarketTests: XCTestCase {
    let today = ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z")!
    func reference(_ amount: Int, currency: String = "USD", shipping: String = "excluded", date: String = "2026-09-01") -> MarketReference {
        MarketReference(provider: "SportsCardsPro", url: "https://www.sportscardspro.com/game/fixture", kind: "sold", grade: "raw", matchQuality: "exact", lowCents: amount, highCents: amount, currency: currency, saleDate: date, checkedAt: "2026-09-07", shipping: shipping)
    }
    func info(_ refs: [MarketReference]) -> CardInsights {
        CardInsights(rarityTier: "base", rarityBullets: [], conditionStatus: "no_obvious_damage", conditionIssues: [], conditionLimitations: [], marketBullets: [], marketReferences: refs, sourceChecks: [], actionReason: "Behalten.")
    }
    func testRecentComparableSalesUseMedianAndObservedRange() {
        let summary = info([reference(100), reference(200), reference(900)]).marketSummary(asOf: today)!
        XCTAssertEqual(summary.valueLabel, reference(200).valueLabel)
        XCTAssertEqual(summary.orderingValueCents, 200)
        XCTAssertEqual(summary.basisLabel, "Median · 3 Verkäufe")
        XCTAssertNotNil(summary.rangeLabel)
    }
    func testNeverMixCurrenciesOrShippingBases() {
        let summary = info([reference(100), reference(200), reference(2000, currency: "EUR"), reference(3000, shipping: "included")]).marketSummary(asOf: today)!
        XCTAssertEqual(summary.references.count, 2)
        XCTAssertEqual(summary.valueLabel, reference(150).valueLabel)
        XCTAssertEqual(summary.orderingValueCents, 150)
        XCTAssertEqual(summary.primary.currency, "USD")
    }
    func testGuideWorksWithoutSalesAndIsLabelledAsEstimate() {
        var guide = reference(112); guide.kind = "guide"; guide.saleDate = nil
        let summary = info([guide]).marketSummary(asOf: today)!
        XCTAssertTrue(summary.isGuide); XCTAssertEqual(summary.basisLabel, "Richtwert")
        XCTAssertEqual(summary.valueLabel, guide.valueLabel)
    }
    func testExactSalesAlwaysWinOverGuide() {
        var guide = reference(112); guide.kind = "guide"; guide.saleDate = nil
        XCTAssertFalse(info([guide, reference(10)]).marketSummary(asOf: today)!.isGuide)
        XCTAssertFalse(info([guide, reference(10, date: "2026-01-01"), reference(30, date: "2026-01-02")]).marketSummary(asOf: today)!.isGuide)
        XCTAssertFalse(info([guide, reference(100), reference(200)]).marketSummary(asOf: today)!.isGuide)
    }
    func testSingleSaleAndSparseOlderEvidenceStayExplicit() {
        let single = info([reference(100)]).marketSummary(asOf: today)!
        XCTAssertEqual(single.basisLabel, "Einzelverkauf")
        XCTAssertTrue(single.dateLabel.contains("2026-09-01"))
        let older = info([reference(100, date: "2026-01-01"), reference(200, date: "2026-01-02")]).marketSummary(asOf: today)!
        XCTAssertTrue(older.dateLabel.contains("2026-01-01"))
    }
    func testGradedNearFutureAndAncientSalesNeverBecomeHeadline() {
        var graded = reference(10000); graded.grade = "PSA 10"
        var near = reference(1000); near.matchQuality = "near"
        XCTAssertNil(info([graded, near, reference(100, date: "2024-01-01"), reference(100, date: "2999-01-01")]).marketSummary(asOf: today))
    }
    func testVersionTwoCardsGetOneMarketUpgrade() {
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-09-07", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        a.insights = info([])
        var card = OwnedCard(state: "analyzed", analysis: a); card.requestedAnalysisVersion = 2
        XCTAssertTrue(card.needsInsightUpgrade)
        card.requestedAnalysisVersion = 3; XCTAssertFalse(card.needsInsightUpgrade)
        card.requestedAnalysisVersion = 2; card.state = "processing"; XCTAssertFalse(card.needsInsightUpgrade)
    }
    func testNewSourceFieldsAndLegacyReferencesDecode() throws {
        var sale = reference(100); sale.title = "Fixture"; sale.listingURL = "https://www.ebay.com/itm/123456789012"
        XCTAssertEqual(try JSONDecoder().decode(MarketReference.self, from: JSONEncoder().encode(sale)), sale)
        sale.title = nil; sale.listingURL = nil
        XCTAssertEqual(try JSONDecoder().decode(MarketReference.self, from: JSONEncoder().encode(sale)), sale)
    }
    func testManualCorrectionCannotRestoreOldServerIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root); try disk.writePhoto(Data([1]), name: "front.jpg")
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-09-07", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        a.identityConfirmed = true; a.insights = info([])
        a.clearAssessmentAfterCorrection()
        var library = Library(); library.cards = [OwnedCard(state: "analyzed", frontFile: "front.jpg", analysis: a)]
        let updated = try disk.reanalyze(cardID: library.cards[0].id, in: library)
        XCTAssertNil(updated.cards[0].refreshOfJobID)
    }
}
