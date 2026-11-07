import XCTest
@testable import CardScoutCore

final class InsightTests: XCTestCase {
    private func reference(grade: String = "raw", match: String = "exact") -> MarketReference {
        MarketReference(provider: "Beckett", url: "https://www.beckett.com/card/fixture", kind: "guide", grade: grade, condition: "NM-MT", matchQuality: match, lowCents: 100, highCents: 300, currency: "USD", checkedAt: "2026-09-07", shipping: "not_applicable")
    }
    private func insights() -> CardInsights {
        CardInsights(rarityTier: "base", rarityBullets: ["Basiskarte ohne Nummerierung."], conditionStatus: "no_obvious_damage", conditionIssues: [], conditionLimitations: ["Glanz im unteren Bereich."], marketBullets: ["Beckett-Leitwert für ungegradete Karten."], marketReferences: [reference()], sourceChecks: [SourceCheck(provider: "PSA", status: "no_match"), SourceCheck(provider: "Beckett", status: "found")], actionReason: "Für die Sammlung behalten.")
    }
    private func analysis() -> CardAnalysis {
        var value = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-09-07", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        value.player = "Daunte Culpepper"; value.subset = "Base"; value.cardNumber = "60"; value.identityConfirmed = true
        return value
    }
    func testOldAnalysisDecodesWithoutInsightsAndRequestsOneUpgrade() throws {
        let original = OwnedCard(state: "analyzed", analysis: analysis())
        let decoded = try JSONDecoder().decode(OwnedCard.self, from: JSONEncoder().encode(original))
        XCTAssertNil(decoded.analysis?.insights)
        XCTAssertTrue(decoded.needsInsightUpgrade)
    }
    func testInsightBulletsAndOriginalCurrencySurvivePersistence() throws {
        var a = analysis(); a.insights = insights()
        let decoded = try JSONDecoder().decode(CardAnalysis.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(decoded.insights, a.insights)
        XCTAssertEqual(decoded.insights?.rawReference?.currency, "USD")
        XCTAssertNil(decoded.marketLowCents)
        XCTAssertEqual(decoded.insights?.rawReference?.condition, "NM-MT")
    }
    func testGradedAndNearReferencesNeverBecomeTheRawHeadline() {
        var info = insights()
        info.marketReferences = [reference(grade: "PSA 10"), reference(match: "near"), reference(match: "proxy")]
        XCTAssertNil(info.rawReference)
        info.marketReferences.append(reference())
        XCTAssertEqual(info.rawReference?.grade, "raw")
        XCTAssertEqual(info.rawReference?.matchQuality, "exact")
    }
    func testNoObviousDamageIsNotAProfessionalGrade() {
        var info = insights()
        XCTAssertEqual(info.conditionLabel, "Keine klaren Schäden sichtbar")
        XCTAssertTrue(info.conditionIssues.isEmpty)
        XCTAssertEqual(info.conditionLimitations.count, 1)
        info.conditionStatus = "not_assessable"
        XCTAssertEqual(info.conditionLabel, "Besseres Foto nötig")
        info.conditionStatus = "visible_damage"; info.conditionIssues = ["Knick unten links."]
        XCTAssertEqual(info.conditionLabel, "Sichtbare Spuren")
    }
    func testCorrectionClearsAllOldPricesAndInsightClaims() {
        var a = analysis(); a.insights = insights(); a.marketLowCents = 100; a.marketHighCents = 300
        a.clearAssessmentAfterCorrection()
        XCTAssertNil(a.insights); XCTAssertNil(a.marketLowCents); XCTAssertNil(a.marketHighCents)
        XCTAssertTrue(a.marketSources.isEmpty); XCTAssertEqual(a.recommendation, "Keep")
    }
    func testReanalysisKeepsPhotosAndCardAndDoesNotLoopAfterOldServerResponse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        try disk.writePhoto(Data([1, 2]), name: "front.jpg"); try disk.writePhoto(Data([3, 4]), name: "back.jpg")
        var library = Library(); library.cards = [OwnedCard(state: "analyzed", frontFile: "front.jpg", backFile: "back.jpg", analysis: analysis())]
        library.cards[0].analysis?.insights = insights()
        try disk.save(library)
        let id = library.cards[0].id
        var updated = try disk.reanalyze(cardID: id, in: library)
        XCTAssertEqual(updated.cards.count, 1); XCTAssertEqual(updated.cards[0].id, id)
        XCTAssertEqual(updated.cards[0].frontFile, "front.jpg"); XCTAssertEqual(updated.cards[0].backFile, "back.jpg")
        XCTAssertEqual(updated.cards[0].requestedAnalysisVersion, 3)
        XCTAssertEqual(updated.cards[0].refreshOfJobID, id)
        XCTAssertFalse(updated.cards[0].hasCurrentAnalysis)
        XCTAssertTrue(updated.cards[0].hasDisplayableAnalysis)
        XCTAssertNotEqual(updated.cards[0].jobID, id)
        XCTAssertEqual(try disk.load().cards[0], updated.cards[0])
        updated.cards[0].state = "analyzed"
        XCTAssertFalse(updated.cards[0].needsInsightUpgrade, "An old server response must not cause endless re-analysis")
        let photos = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("photos").path)
        XCTAssertEqual(Set(photos), Set(["front.jpg", "back.jpg"]))
        let retaken = try disk.retakePhotos(cardID: id, front: Data([9]), back: nil, in: updated)
        XCTAssertFalse(retaken.cards[0].hasDisplayableAnalysis, "Old condition must be hidden when pixels change")
        XCTAssertNil(retaken.cards[0].refreshOfJobID, "Changed photos must get a full analysis")
    }
    func testReanalysisMissingPhotoDoesNotChangePersistedLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        var library = Library(); library.cards = [OwnedCard(state: "analyzed", frontFile: "missing.jpg", analysis: analysis())]
        try disk.save(library)
        XCTAssertThrowsError(try disk.reanalyze(cardID: library.cards[0].id, in: library))
        XCTAssertEqual(try disk.load().cards, library.cards)
    }
    func testRefreshSupersedesInFlightJobAndRejectsItsLateResult() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root); try disk.writePhoto(Data([1]), name: "front.jpg")
        var library = Library(); library.cards = [OwnedCard(state: "processing", frontFile: "front.jpg")]
        var updated = try disk.reanalyze(cardID: library.cards[0].id, in: library)
        XCTAssertEqual(updated.supersededJobIDs, [library.cards[0].jobID])
        XCTAssertFalse(try updated.applyJobResult(cardID: library.cards[0].id, jobID: library.cards[0].jobID, status: "analyzed", analysis: analysis(), collection: nil, error: nil))
    }
}
