import XCTest
@testable import CardScoutCore

final class BatchReanalysisTests: XCTestCase {
    private var root: URL!
    private var disk: DiskStore!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        disk = try DiskStore(root: root)
        try disk.writePhoto(Data([1, 2, 3]), name: "front.jpg")
        try disk.writePhoto(Data([4, 5]), name: "back.jpg")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func card(confirmed: Bool = false) -> OwnedCard {
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-10-16", marketSources: [], confidence: confirmed ? "high" : "medium", conditionNotes: "", rationale: "", needsReview: !confirmed)
        a.identityConfirmed = confirmed
        return OwnedCard(state: "analyzed", frontFile: "front.jpg", backFile: "back.jpg", analysis: a)
    }
    func testBatchKeepsCollectionAndPhotosAndDoesNotRepeat() throws {
        var library = Library(); library.cards = [card(), card(), card(confirmed: true)]
        try disk.save(library)
        let jobs = Set(library.cards.map(\.jobID))
        let updated = try disk.reanalyzeUnclear(jobIDs: jobs, in: library)
        XCTAssertEqual(updated.cards.map(\.id), library.cards.map(\.id))
        XCTAssertEqual(updated.cards[2], library.cards[2])
        for index in 0..<2 {
            XCTAssertEqual(updated.cards[index].state, "queued")
            XCTAssertNotEqual(updated.cards[index].jobID, library.cards[index].jobID)
            XCTAssertEqual(updated.cards[index].frontFile, library.cards[index].frontFile)
            XCTAssertEqual(updated.cards[index].backFile, library.cards[index].backFile)
            XCTAssertEqual(updated.cards[index].analysis, library.cards[index].analysis)
            XCTAssertNil(updated.cards[index].refreshOfJobID)
            XCTAssertEqual(updated.cards[index].fastPipeline, false)
        }
        XCTAssertEqual(try disk.load().cards, updated.cards)
        XCTAssertEqual(try disk.reanalyzeUnclear(jobIDs: jobs, in: updated).cards, updated.cards)
        var completed = updated
        completed.cards[0].state = "analyzed"
        XCTAssertEqual(try disk.reanalyzeUnclear(jobIDs: jobs, in: completed).cards, completed.cards)
        XCTAssertEqual(try Data(contentsOf: disk.photoURL("front.jpg")), Data([1, 2, 3]))
    }
    func testMissingPhotoAbortsWholeBatchWithoutChangingSavedCollection() throws {
        var library = Library(); library.cards = [card(), card()]
        library.cards[1].backFile = "missing.jpg"
        try disk.save(library)
        XCTAssertThrowsError(try disk.reanalyzeUnclear(jobIDs: Set(library.cards.map(\.jobID)), in: library))
        XCTAssertEqual(try disk.load().cards, library.cards)
    }
    func testNamedCollegeLicenseReviewRechecksPhotosEvenWithConfirmedIdentity() throws {
        var library = Library(); library.cards = [card(confirmed: true), card(confirmed: true), card(confirmed: true)]
        for index in 0..<2 {
            library.cards[index].analysis?.licenseScope = "unlicensed"
            library.cards[index].analysis?.needsReview = true
        }
        library.cards[1].manualAssignment = true
        let jobs = Set(library.cards.map(\.jobID))
        let updated = try disk.reanalyzeUnclear(jobIDs: jobs, in: library)
        XCTAssertNotEqual(updated.cards[0].jobID, library.cards[0].jobID)
        XCTAssertEqual(updated.cards[0].analysis, library.cards[0].analysis)
        XCTAssertNil(updated.cards[0].refreshOfJobID)
        XCTAssertEqual(updated.cards[0].fastPipeline, false)
        XCTAssertEqual(updated.cards[1], library.cards[1])
        XCTAssertEqual(updated.cards[2], library.cards[2])
        XCTAssertEqual(try disk.reanalyzeUnclear(jobIDs: jobs, in: updated).cards, updated.cards)
    }
    func testOnlyNamedCompletedUnclearCardsAreQueued() throws {
        var library = Library(); library.cards = [card(), card(), card()]
        library.cards[1].state = "processing"
        let updated = try disk.reanalyzeUnclear(jobIDs: Set(library.cards.prefix(2).map(\.jobID)), in: library)
        XCTAssertNotEqual(updated.cards[0].jobID, library.cards[0].jobID)
        XCTAssertEqual(updated.cards[1], library.cards[1])
        XCTAssertEqual(updated.cards[2], library.cards[2])
        XCTAssertThrowsError(try disk.reanalyzeUnclear(jobIDs: Set((0..<201).map(String.init)), in: library))
    }
    func testNamedFailedCardCanRecoverWithSavedPhotosAndOldJobIsSuperseded() throws {
        var library = Library(); library.cards = [card()]
        library.cards[0].state = "failed"
        let oldJob = library.cards[0].jobID
        let updated = try disk.reanalyzeUnclear(jobIDs: [oldJob], in: library)
        XCTAssertEqual(updated.cards[0].state, "queued")
        XCTAssertEqual(updated.cards[0].frontFile, library.cards[0].frontFile)
        XCTAssertEqual(updated.cards[0].backFile, library.cards[0].backFile)
        XCTAssertTrue(updated.supersededJobIDs!.contains(oldJob))
        XCTAssertEqual(try disk.reanalyzeUnclear(jobIDs: [oldJob], in: updated).cards, updated.cards)
    }
    func testAllSavedPassIncludesConfirmedAndFailedCardsWithoutChangingManualChoices() throws {
        var library = Library(); library.cards = [card(confirmed: true), card(), card()]
        library.cards[0].manualAssignment = true
        library.cards[1].state = "failed"
        let operation = UUID().uuidString.lowercased()
        let updated = try disk.reanalyzeAllSaved(operationID: operation, in: library)
        XCTAssertEqual(updated.cards.map(\.id), library.cards.map(\.id))
        XCTAssertEqual(updated.cards.map(\.frontFile), library.cards.map(\.frontFile))
        XCTAssertEqual(updated.cards[0].manualAssignment, true)
        XCTAssertEqual(updated.cards[0].fastPipeline, false)
        XCTAssertEqual(updated.cards[1].fastPipeline, true)
        XCTAssertTrue(updated.cards.allSatisfy { $0.state == "queued" && $0.refreshOfJobID == nil })
        let repeated = try disk.reanalyzeAllSaved(operationID: operation, in: updated)
        XCTAssertEqual(repeated.cards, updated.cards)
        XCTAssertEqual(try disk.load().savedPhotoReanalysisOperationID, operation)
    }
    func testAllSavedPassIsAtomicWhenAPhotoIsMissing() throws {
        var library = Library(); library.cards = [card(), card()]
        library.cards[1].frontFile = "missing.jpg"
        try disk.save(library)
        XCTAssertThrowsError(try disk.reanalyzeAllSaved(operationID: UUID().uuidString, in: library))
        XCTAssertEqual(try disk.load().cards, library.cards)
        XCTAssertNil(try disk.load().savedPhotoReanalysisOperationID)
    }
}
