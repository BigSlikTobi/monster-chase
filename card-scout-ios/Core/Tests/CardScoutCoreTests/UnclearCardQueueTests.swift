import XCTest
@testable import CardScoutCore

final class UnclearCardQueueTests: XCTestCase {
    private func card(_ id: String, confirmed: Bool = false, state: String = "analyzed") -> OwnedCard {
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-10-16", marketSources: [], confidence: confirmed ? "high" : "medium", conditionNotes: "", rationale: "", needsReview: true)
        a.identityConfirmed = confirmed
        return OwnedCard(id: id, state: state, frontFile: "front.jpg", analysis: a)
    }
    func testSnapshotIncludesOnlyUnclearCardsAndDoesNotGrowFromNewResults() {
        let first = card("first"), failed = card("failed", state: "failed")
        let queue = UnclearCardQueue(cards: [first, card("price-only", confirmed: true), card("busy", state: "processing"), failed, first])
        XCTAssertEqual(queue.cardIDs, ["first", "failed"])
        XCTAssertEqual(queue.currentID, "first")
        XCTAssertEqual(queue.total, 2)
    }
    func testSkipIsOnePassOnlyAndStaleCallbacksCannotSkipTheNextCard() {
        let cards = [card("first"), card("second")]
        var queue = UnclearCardQueue(cards: cards)
        XCTAssertTrue(queue.skip(cardID: "first"))
        XCTAssertFalse(queue.skip(cardID: "first"))
        XCTAssertFalse(queue.photoSaved(cardID: "first"))
        XCTAssertEqual(queue.currentID, "second")
        XCTAssertEqual(queue.skippedIDs, ["first"])
        XCTAssertEqual(UnclearCardQueue(cards: cards).currentID, "first", "A later pass can revisit skipped cards")
    }
    func testResumeDropsResolvedDeletedAndRunningCardsWithoutAddingNewOnes() throws {
        var queue = UnclearCardQueue(cards: [card("resolved"), card("deleted"), card("running"), card("keep")])
        queue = try JSONDecoder().decode(UnclearCardQueue.self, from: JSONEncoder().encode(queue))
        queue.reconcile(cards: [card("resolved", confirmed: true), card("running", state: "queued"), card("keep"), card("new")])
        XCTAssertEqual(queue.remainingIDs, ["keep"])
        XCTAssertEqual(queue.noLongerNeededIDs, ["resolved", "deleted", "running"])
        queue.reconcile(cards: [card("keep")])
        XCTAssertEqual(queue.noLongerNeededIDs.count, 3)
        XCTAssertEqual(queue.total, 4)
    }
    func testPhotoRevisionAndQueueAdvancePersistTogetherAndDoNotLoopAfterUnclearResult() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        try disk.writePhoto(Data([1, 2]), name: "front.jpg")
        var library = Library(); library.cards = [card("first"), card("second")]
        library.unclearCardQueue = UnclearCardQueue(cards: library.cards)
        try disk.save(library)
        var updated = try disk.retakePhotos(cardID: "first", front: nil, back: Data([3, 4]), in: library)
        XCTAssertEqual(updated.cards.map(\.id), ["first", "second"])
        XCTAssertEqual(updated.cards[0].frontFile, "front.jpg")
        XCTAssertEqual(updated.cards[0].state, "queued")
        XCTAssertEqual(updated.unclearCardQueue?.currentID, "second")
        XCTAssertEqual(updated.unclearCardQueue?.photoSavedIDs, ["first"])
        XCTAssertEqual(try disk.load().unclearCardQueue, updated.unclearCardQueue)
        let result = try XCTUnwrap(library.cards[0].analysis)
        try updated.applyJobResult(cardID: "first", jobID: updated.cards[0].jobID, status: "analyzed", analysis: result, collection: nil, error: nil)
        updated.unclearCardQueue?.reconcile(cards: updated.cards)
        XCTAssertEqual(updated.unclearCardQueue?.remainingIDs, ["second"])
        updated.unclearCardQueue?.skip(cardID: "second")
        XCTAssertNil(updated.unclearCardQueue?.currentID)
        XCTAssertEqual(updated.unclearCardQueue?.visited, 2)
    }
    func testCancelledOrInvalidPhotoDoesNotAdvanceAndUnrelatedRetakeDoesNotAdvance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        try disk.writePhoto(Data([1]), name: "front.jpg")
        var library = Library(); library.cards = [card("first"), card("other")]
        library.unclearCardQueue = UnclearCardQueue(cards: library.cards)
        try disk.save(library)
        XCTAssertThrowsError(try disk.retakePhotos(cardID: "first", front: nil, back: nil, in: library))
        XCTAssertEqual(try disk.load().unclearCardQueue?.currentID, "first")
        let changedOther = try disk.retakePhotos(cardID: "other", front: nil, back: Data([2]), in: library)
        XCTAssertEqual(changedOther.unclearCardQueue?.currentID, "first")
        XCTAssertTrue(changedOther.unclearCardQueue?.photoSavedIDs.isEmpty == true)
    }
    func testLibraryWithoutQueueStillDecodes() throws {
        let library = try JSONDecoder().decode(Library.self, from: Data("{\"version\":1,\"cards\":[],\"collections\":[],\"hunts\":[],\"hotCards\":[],\"importedLegacy\":true}".utf8))
        XCTAssertNil(library.unclearCardQueue)
    }
}
