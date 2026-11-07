import XCTest
@testable import CardScoutCore

final class CaptureTests: XCTestCase {
    private var root: URL!
    private var disk: DiskStore!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        disk = try DiskStore(root: root)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testHundredCapturesPersistOfflineWithoutChangingExistingCard() throws {
        var library = Library()
        library.cards = [OwnedCard(frontFile: "original.jpg", backFile: "back.jpg")]
        try disk.writePhoto(Data([1]), name: "original.jpg")
        try disk.writePhoto(Data([2]), name: "back.jpg")
        let original = library.cards[0]
        let captures = (0..<100).map { CapturePhoto(front: Data([UInt8($0 + 1)]), text: "Card \($0)") }
        let updated = try disk.addCaptures(captures, sessionID: "session", to: library)
        let restored = try disk.load()
        XCTAssertEqual(restored.cards.count, 101)
        XCTAssertEqual(Set(restored.cards.map(\.id)).count, 101)
        XCTAssertEqual(restored.cards.last, original)
        XCTAssertEqual(restored.cards.filter { $0.captureSessionID == "session" }.count, 100)
        XCTAssertTrue(restored.cards.prefix(100).allSatisfy { $0.fastPipeline == true && $0.state == "queued" })
        XCTAssertEqual(restored.cards, updated.cards)
        XCTAssertEqual(try Data(contentsOf: disk.photoURL("original.jpg")), Data([1]))
    }

    func testInvalidBatchCannotReplaceLibraryOrLeaveNewFiles() throws {
        let original = Library(); try disk.save(original)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("photos").path)
        XCTAssertThrowsError(try disk.addCaptures([CapturePhoto(front: Data([1])), CapturePhoto(front: Data())], sessionID: "session", to: original))
        XCTAssertEqual(try disk.load().cards.count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("photos").path), before)
    }

    func testProvisionalIdentityAppearsBeforePricingAndCannotBeAcknowledged() throws {
        var library = Library(); var card = OwnedCard(frontFile: "front.jpg"); card.fastPipeline = true
        library.cards = [card]
        let analysis = CardAnalysis(player: "Daunte Culpepper", recommendation: "Keep", marketCheckedAt: "2026-10-13", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        XCTAssertTrue(try library.applyJobResult(cardID: card.id, jobID: card.jobID, status: "identified", analysis: analysis, collection: nil, error: nil))
        XCTAssertTrue(library.cards[0].hasDisplayableAnalysis)
        XCTAssertFalse(library.cards[0].hasCurrentAnalysis)
        XCTAssertTrue(library.cards[0].isAwaitingAnalysis)
        XCTAssertTrue((library.pendingAcknowledgments ?? []).isEmpty)
        _ = try library.applyJobResult(cardID: card.id, jobID: card.jobID, status: "enriching", analysis: analysis, collection: nil, error: nil)
        XCTAssertEqual(library.cards[0].title, "Daunte Culpepper")
        _ = try library.applyJobResult(cardID: card.id, jobID: card.jobID, status: "analyzed", analysis: analysis, collection: nil, error: nil)
        XCTAssertEqual(library.pendingAcknowledgments, [card.jobID])
        XCTAssertEqual(library.cards.count, 1)
    }

    func testCorrectionRejectsLateRefreshAndKeepsUserMetadata() throws {
        var analysis = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-10-13", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        analysis.player = "Wrong player"
        var card = OwnedCard(state: "enriching", frontFile: "front.jpg", analysis: analysis)
        card.isFavorite = true; card.storageLocation = "Box A"; card.notes = "Trade copy"
        var library = Library(); library.cards = [card]
        let collection = CardCollection(id: "optic", name: "Donruss Optic", year: 2025, brand: "Panini", cards: [ChecklistCard(number: "60", player: "Daunte Culpepper", team: "Miami Dolphins")])
        library.collections = [collection]
        try library.correctAssignment(cardID: card.id, collectionID: collection.id, number: "60")
        XCTAssertFalse(try library.applyJobResult(cardID: card.id, jobID: card.jobID, status: "analyzed", analysis: analysis, collection: nil, error: nil))
        XCTAssertEqual(library.cards[0].analysis?.player, "Daunte Culpepper")
        XCTAssertEqual(library.supersededJobIDs, [card.jobID])
        XCTAssertTrue(library.cards[0].isFavorite == true)
        XCTAssertEqual(library.cards[0].storageLocation, "Box A")
        XCTAssertEqual(library.cards[0].notes, "Trade copy")
        XCTAssertTrue(library.cards[0].manualAssignment == true)
    }

    func testOlderProvisionalChecklistCannotDropAnotherOwnedCard() throws {
        let analysis = CardAnalysis(player: "Daunte Culpepper", recommendation: "Keep", marketCheckedAt: "2026-10-13", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        let card = OwnedCard(frontFile: "front.jpg")
        let first = ChecklistCard(number: "60", player: "Daunte Culpepper", team: "Miami Dolphins")
        let second = ChecklistCard(number: "61", player: "Another Player", team: "Team")
        var current = CardCollection(id: "optic", name: "Donruss Optic", year: 2025, brand: "Panini", cards: [first, second])
        current.checklistComplete = false
        var stale = current; stale.cards = [first]
        var library = Library(); library.cards = [card]; library.collections = [current]
        _ = try library.applyJobResult(cardID: card.id, jobID: card.jobID, status: "identified", analysis: analysis, collection: stale, error: nil)
        XCTAssertEqual(Set(library.collections[0].cards.map(\.number)), ["60", "61"])
        var conflicting = stale; conflicting.cards[0].player = "Wrong Player"
        let before = library
        XCTAssertThrowsError(try library.applyJobResult(cardID: card.id, jobID: card.jobID, status: "analyzed", analysis: analysis, collection: conflicting, error: nil))
        XCTAssertEqual(library.cards, before.cards)
        XCTAssertEqual(library.collections, before.collections)
    }

    func testRetakeSupersedesPricingWithoutChangingCardIdentity() throws {
        let oldAssessment = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-10-13", marketSources: [], confidence: "high", conditionNotes: "Old condition", rationale: "", needsReview: false)
        var card = OwnedCard(state: "enriching", frontFile: "front.jpg", analysis: oldAssessment); card.fastPipeline = true; card.hasProvisionalAnalysis = true
        try disk.writePhoto(Data([1]), name: "front.jpg")
        var library = Library(); library.cards = [card]
        let updated = try disk.retakePhotos(cardID: card.id, front: Data([2]), back: nil, in: library)
        XCTAssertEqual(updated.cards[0].id, card.id)
        XCTAssertEqual(updated.supersededJobIDs, [card.jobID])
        XCTAssertFalse(updated.cards[0].hasDisplayableAnalysis)
    }

    func testLegacyLibraryStillDecodesAndNewMetadataSurvivesSave() throws {
        var card = OwnedCard(frontFile: "front.jpg")
        let old = try JSONDecoder().decode(OwnedCard.self, from: JSONEncoder().encode(card))
        XCTAssertNil(old.fastPipeline); XCTAssertNil(old.captureSessionID)
        card.isFavorite = true; card.storageLocation = "Binder 2"; card.notes = "Gift"
        var library = Library(); library.cards = [card]; try disk.save(library)
        XCTAssertEqual(try disk.load().cards[0], card)
    }
}
