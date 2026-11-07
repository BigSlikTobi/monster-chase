import XCTest
@testable import CardScoutCore

final class ScanMatchTests: XCTestCase {
    func fixture() -> Library {
        var library = Library()
        library.collections = [CardCollection(id: "optic", name: "Donruss Optic", year: 2025, brand: "Panini", cards: [ChecklistCard(number: "257", player: "Derrick Harmon", team: "Pittsburgh Steelers")]),
                               CardCollection(id: "scope", name: "Donruss Optic", year: 2025, brand: "Panini", parallel: "Orange Scope", cards: [ChecklistCard(number: "257", player: "Derrick Harmon", team: "Pittsburgh Steelers")])]
        var card = OwnedCard(frontFile: "saved-front.jpg")
        card.isScanDraft = true
        card.analysis = CardAnalysis(player: "Derrick Harmon", year: 2025, cardNumber: "257", recommendation: "Keep", marketCheckedAt: "", marketSources: [], confidence: "medium", conditionNotes: "", rationale: "", needsReview: true)
        library.cards = [card]
        return library
    }

    func testDraftSurvivesDiskAndDoesNotCountAsOwned() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        let library = try disk.addCaptures([CapturePhoto(front: Data([1, 2, 3]))], sessionID: "scan", to: Library(), asDraft: true)
        let loaded = try disk.load()
        XCTAssertEqual(loaded.scanDrafts.count, 1)
        XCTAssertEqual(loaded.collectedCards.count, 0)
        XCTAssertEqual(try Data(contentsOf: disk.photoURL(library.cards[0].frontFile)), Data([1, 2, 3]))
    }

    func testSelectionIsAtomicIdempotentAndRejectsLateResults() throws {
        var library = fixture()
        let original = library.cards[0]
        let match = CardMatch(collectionID: "scope", number: "257")
        try library.collectScan(cardID: original.id, match: match, folderID: nil, newFolderName: "Steelers")
        let job = library.cards[0].jobID
        XCTAssertNotEqual(job, original.jobID)
        XCTAssertEqual(library.cards[0].frontFile, original.frontFile)
        XCTAssertEqual(library.cards[0].analysis?.parallel, "Orange Scope")
        XCTAssertTrue(library.cards[0].manualAssignment == true)
        XCTAssertEqual(library.cards[0].state, "queued")
        XCTAssertEqual(library.collectedCards.count, 1)
        XCTAssertEqual(library.folders?.first?.cardIDs, [original.id])
        XCTAssertNil(library.cards[0].analysis?.marketLowCents)
        XCTAssertFalse(try library.applyJobResult(cardID: original.id, jobID: original.jobID, status: "analyzed", analysis: original.analysis, collection: nil, error: nil))
        try library.collectScan(cardID: original.id, match: match, folderID: nil, newFolderName: "Steelers")
        XCTAssertEqual(library.cards[0].jobID, job)
        XCTAssertEqual(library.folders?.count, 1)
        XCTAssertEqual(library.folders?.first?.cardIDs.count, 1)
    }

    func testMultipleFoldersDoNotCreateCopiesAndCanBeRemoved() throws {
        var library = fixture()
        let id = library.cards[0].id
        try library.collectScan(cardID: id, match: nil, folderID: nil, newFolderName: "Rookies")
        let first = try XCTUnwrap(library.folders?.first?.id)
        try library.setFolders(cardID: id, folderIDs: [first], newFolderName: "Steelers")
        XCTAssertEqual(library.folders?.filter { $0.cardIDs.contains(id) }.count, 2)
        XCTAssertEqual(library.collectedCards.count, 1)
        try library.setFolders(cardID: id, folderIDs: [])
        XCTAssertTrue(library.folders?.allSatisfy { $0.cardIDs.isEmpty } == true)
        XCTAssertEqual(library.collectedCards.count, 1)
    }

    func testSelectedIdentityRejectsConflictingAssessmentOnCurrentJob() throws {
        var library = fixture()
        let id = library.cards[0].id
        try library.collectScan(cardID: id, match: CardMatch(collectionID: "scope", number: "257"), folderID: nil)
        var incoming = try XCTUnwrap(library.cards[0].analysis)
        incoming.parallel = "Fire"
        XCTAssertFalse(try library.applyJobResult(cardID: id, jobID: library.cards[0].jobID, status: "analyzed", analysis: incoming, collection: nil, error: nil))
        XCTAssertEqual(library.cards[0].analysis?.parallel, "Orange Scope")
    }

    func testInvalidFolderOrMatchLeavesDraftUnchanged() throws {
        var library = fixture()
        let original = library.cards[0]
        XCTAssertThrowsError(try library.collectScan(cardID: original.id, match: CardMatch(collectionID: "missing", number: "257"), folderID: nil, newFolderName: "Should not exist"))
        XCTAssertEqual(library.cards[0], original)
        XCTAssertNil(library.folders)
        XCTAssertThrowsError(try library.collectScan(cardID: original.id, match: nil, folderID: "missing"))
        XCTAssertEqual(library.cards[0], original)
    }

    func testUnidentifiedSaveCannotOccupyChecklistSlotOrAcceptLateGuess() throws {
        var library = fixture()
        let original = library.cards[0]
        try library.collectScan(cardID: original.id, match: nil, folderID: nil)
        XCTAssertEqual(library.collectedCards.count, 1)
        XCTAssertEqual(library.cards[0].analysis?.player, original.analysis?.player)
        XCTAssertEqual(library.cards[0].analysis?.cardNumber, original.analysis?.cardNumber)
        XCTAssertEqual(library.cards[0].analysis?.identityConfirmed, false)
        XCTAssertNil(library.cards[0].analysis?.collectionID)
        XCTAssertNil(library.cards[0].analysis?.marketLowCents)
        XCTAssertEqual(library.cards[0].state, "unidentified")
        XCTAssertEqual(library.collections[0].ownedCount(in: library.cards), 0)
        XCTAssertFalse(try library.applyJobResult(cardID: original.id, jobID: original.jobID, status: "identified", analysis: original.analysis, collection: nil, error: nil))
    }

    func testRankingSearchAndOldLibraryCompatibility() throws {
        var library = fixture()
        library.cards[0].matchSuggestions = [CardMatch(collectionID: "scope", number: "257")]
        XCTAssertEqual(library.matches(for: library.cards[0]).first?.collectionID, "scope")
        XCTAssertEqual(library.matches(for: library.cards[0], query: "Harmon Orange").count, 1)
        XCTAssertTrue(library.matches(for: OwnedCard()).isEmpty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
        object.removeValue(forKey: "folders"); object.removeValue(forKey: "lastUsedFolderID")
        let restored = try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.cards.count, 1)
        XCTAssertNil(restored.folders)
    }

    func testServerRecoveryIsVisibleWhenBothInitialFieldsWereMisread() {
        var library = fixture()
        library.cards[0].analysis?.player = "Wrong Player"
        library.cards[0].analysis?.cardNumber = "999"
        let match = CardMatch(collectionID: "scope", number: "257")
        library.cards[0].matchSuggestions = [match]
        XCTAssertEqual(library.matches(for: library.cards[0]).first, match)
    }

    func testPunctuationAndSubsetRankTheSameCardFirst() {
        var library = fixture()
        library.collections[0].cards[0].player = "C.J. Stroud"
        library.collections[0].subset = "All-Chrome Team"
        library.collections[1].cards[0].player = "C.J. Stroud"
        library.collections[1].subset = "Other Insert"
        library.cards[0].analysis?.player = "CJ Stroud"
        library.cards[0].analysis?.cardNumber = nil
        library.cards[0].analysis?.subset = "All Chrome Team"
        XCTAssertEqual(library.matches(for: library.cards[0]).first?.collectionID, "optic")
        XCTAssertEqual(library.matches(for: library.cards[0]).count, 2)
    }
}
