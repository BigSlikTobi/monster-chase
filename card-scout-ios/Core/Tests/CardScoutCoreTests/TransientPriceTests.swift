import XCTest
@testable import CardScoutCore

final class TransientPriceTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-16T13:00:00Z")!
    func analysis(expires: Double?) -> CardAnalysis {
        let ref = MarketReference(provider: "CardSight", url: "https://showme.cards/fixture", kind: "sold", grade: "raw", matchQuality: "exact",
            lowCents: 71, highCents: 71, currency: "USD", saleDate: "2026-10-01", checkedAt: "2026-10-16", shipping: "unknown", expiresAt: expires)
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-10-16", marketSources: [], confidence: "high", conditionNotes: "Zustand gespeichert.", rationale: "Behalten.", needsReview: false)
        a.player = "Terrance Ferguson"; a.identityConfirmed = true
        a.insights = CardInsights(rarityTier: "base", rarityBullets: [], conditionStatus: "no_obvious_damage", conditionIssues: [], conditionLimitations: [],
            marketBullets: ["Von CardSight gemeldete Auktion."], marketReferences: [ref], sourceChecks: [SourceCheck(provider: "CardSight", status: "found")], actionReason: "Behalten.")
        return a
    }
    func testProviderPriceRequiresFreshBoundedExpiry() {
        let fresh = analysis(expires: now.timeIntervalSince1970 + 100)
        XCTAssertEqual(fresh.insights?.marketSummary(asOf: now)?.orderingValueCents, 71)
        for expiry in [nil, now.timeIntervalSince1970 - 1, now.timeIntervalSince1970 + 100000] {
            XCTAssertNil(analysis(expires: expiry).insights?.marketSummary(asOf: now))
            XCTAssertTrue(analysis(expires: expiry).currentPricing(asOf: now).insights!.marketReferences.isEmpty)
        }
    }
    func testDiskNeverPersistsProviderPricesButKeepsAssessmentAndPhotos() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        var library = Library()
        library.cards = [OwnedCard(state: "analyzed", frontFile: "front.jpg", analysis: analysis(expires: now.timeIntervalSince1970 + 100))]
        try disk.save(library)
        let bytes = try String(contentsOf: root.appendingPathComponent("library.json"), encoding: .utf8)
        XCTAssertFalse(bytes.contains("showme.cards"))
        XCTAssertFalse(bytes.contains("CardSight"))
        let restored = try disk.load()
        XCTAssertEqual(restored.cards[0].analysis?.player, "Terrance Ferguson")
        XCTAssertEqual(restored.cards[0].analysis?.conditionNotes, "Zustand gespeichert.")
        XCTAssertEqual(restored.cards[0].frontFile, "front.jpg")
        XCTAssertEqual(library.cards[0].analysis?.insights?.marketReferences.count, 1)
        XCTAssertTrue(restored.cards[0].analysis!.insights!.marketReferences.isEmpty)
    }
    func testOldSourceReferencesStillWorkWithoutExpiry() {
        var a = analysis(expires: nil)
        a.insights!.marketReferences[0].provider = "SportsCardsPro"
        XCTAssertNotNil(a.insights?.marketSummary(asOf: now))
        XCTAssertEqual(a.withoutTransientPricing().insights?.marketReferences.count, 1)
    }
    func testSlablineGuideExpiresAndNeverEntersSavedLibrary() throws {
        var a = analysis(expires: now.timeIntervalSince1970 + 100)
        a.insights!.marketReferences[0].provider = "Slabline"
        a.insights!.marketReferences[0].kind = "guide"
        a.insights!.marketReferences[0].saleDate = nil
        a.insights!.sourceChecks = [SourceCheck(provider: "Slabline", status: "found")]
        XCTAssertTrue(a.insights!.marketSummary(asOf: now)!.isGuide)
        XCTAssertTrue(a.withoutTransientPricing().insights!.marketReferences.isEmpty)
        XCTAssertTrue(a.withoutTransientPricing().insights!.sourceChecks.isEmpty)
        XCTAssertTrue(a.currentPricing(asOf: now.addingTimeInterval(200)).insights!.marketReferences.isEmpty)
        a.insights!.marketReferences[0].expiresAt = nil
        XCTAssertNil(a.insights!.marketSummary(asOf: now))
    }
    func testMidpointGuideHasTheSameExpiryAndPersistenceBoundary() throws {
        var a = analysis(expires: now.timeIntervalSince1970 + 100)
        a.insights!.marketReferences[0].provider = "Midpoint"
        a.insights!.marketReferences[0].kind = "guide"
        a.insights!.marketReferences[0].saleDate = nil
        a.insights!.sourceChecks = [SourceCheck(provider: "Midpoint", status: "found")]
        XCTAssertTrue(a.insights!.marketSummary(asOf: now)!.isGuide)
        XCTAssertTrue(a.withoutTransientPricing().insights!.marketReferences.isEmpty)
        XCTAssertTrue(a.withoutTransientPricing().insights!.sourceChecks.isEmpty)
        XCTAssertTrue(a.currentPricing(asOf: now.addingTimeInterval(200)).insights!.marketReferences.isEmpty)
    }
}
