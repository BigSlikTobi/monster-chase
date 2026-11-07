import XCTest
@testable import CardScoutCore

final class RetakeTests: XCTestCase {
    private var root: URL!
    private var disk: DiskStore!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        disk = try DiskStore(root: root)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func fixture(state: String = "analyzed") throws -> Library {
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-09-07", marketSources: [], confidence: "high", conditionNotes: "Old photo assessment", rationale: "Old assessment", needsReview: false)
        a.collectionID = "optic"; a.identityConfirmed = true; a.cardNumber = "60"; a.player = "Daunte Culpepper"
        var library = Library()
        library.cards = [OwnedCard(id: "11111111-1111-4111-a111-111111111111", createdAt: "2026-09-07", state: state, frontFile: "original-front.jpg", backFile: "original-back.jpg", analysis: a)]
        library.collections = [CardCollection(id: "optic", name: "Donruss Optic", year: 2025, brand: "Panini", cards: [ChecklistCard(number: "60", player: "Daunte Culpepper", team: "Miami Dolphins")])]
        try disk.writePhoto(Data("original front".utf8), name: "original-front.jpg")
        try disk.writePhoto(Data("original back".utf8), name: "original-back.jpg")
        try disk.save(library)
        return library
    }
    func testFrontRetakePreservesSameCardBackAndOriginalPhoto() throws {
        let old = try fixture(), id = old.cards[0].id
        let updated = try disk.retakePhotos(cardID: id, front: Data("new front".utf8), back: nil, in: old)
        XCTAssertEqual(updated.cards.count, 1)
        XCTAssertEqual(updated.cards[0].id, id)
        XCTAssertEqual(updated.cards[0].createdAt, old.cards[0].createdAt)
        XCTAssertEqual(updated.cards[0].backFile, "original-back.jpg")
        XCTAssertEqual(updated.collections[0].ownedCount(in: updated.cards), 1)
        XCTAssertEqual(try Data(contentsOf: disk.photoURL("original-front.jpg")), Data("original front".utf8))
        XCTAssertEqual(try Data(contentsOf: disk.photoURL(updated.cards[0].frontFile)), Data("new front".utf8))
        XCTAssertNotEqual(updated.cards[0].jobID, id)
        XCTAssertEqual(updated.cards[0].state, "queued")
        XCTAssertFalse(updated.cards[0].hasCurrentAnalysis)
        XCTAssertEqual(try disk.load().cards[0], updated.cards[0])
    }
    func testBackOnlyRetakeDoesNotReplaceFront() throws {
        let old = try fixture()
        let updated = try disk.retakePhotos(cardID: old.cards[0].id, front: nil, back: Data("new back".utf8), in: old)
        XCTAssertEqual(updated.cards[0].frontFile, "original-front.jpg")
        XCTAssertNotEqual(updated.cards[0].backFile, old.cards[0].backFile)
        XCTAssertEqual(try Data(contentsOf: disk.photoURL(updated.cards[0].backFile!)), Data("new back".utf8))
    }
    func testBothPhotosUseOneNewJobAndSurviveOfflineRestart() throws {
        let old = try fixture()
        let updated = try disk.retakePhotos(cardID: old.cards[0].id, front: Data("new front".utf8), back: Data("new back".utf8), in: old)
        let restored = try DiskStore(root: root).load()
        XCTAssertEqual(restored.cards[0].jobID, updated.cards[0].jobID)
        XCTAssertTrue(restored.cards[0].frontFile.hasPrefix(restored.cards[0].jobID))
        XCTAssertTrue(restored.cards[0].backFile!.hasPrefix(restored.cards[0].jobID))
        XCTAssertEqual(restored.cards[0].state, "queued")
    }
    func testInvalidRetakeLeavesOriginalLibraryUntouched() throws {
        let old = try fixture(), id = old.cards[0].id
        XCTAssertThrowsError(try disk.retakePhotos(cardID: id, front: nil, back: nil, in: old))
        XCTAssertThrowsError(try disk.retakePhotos(cardID: id, front: Data("new front".utf8), back: Data(), in: old))
        XCTAssertThrowsError(try disk.retakePhotos(cardID: "missing", front: Data([1]), back: nil, in: old))
        XCTAssertEqual(try disk.load().cards[0], old.cards[0])
        XCTAssertEqual(try Data(contentsOf: disk.photoURL("original-front.jpg")), Data("original front".utf8))
    }
    func testLibraryWriteFailureDoesNotSwitchPhotoReferences() throws {
        let old = try fixture()
        let file = root.appendingPathComponent("library.json")
        let backup = root.appendingPathComponent("previous-library.json")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertThrowsError(try disk.retakePhotos(cardID: old.cards[0].id, front: Data([9]), back: nil, in: old))
        let restored = try JSONDecoder().decode(Library.self, from: Data(contentsOf: backup))
        XCTAssertEqual(restored.cards[0], old.cards[0])
        XCTAssertEqual(try Data(contentsOf: disk.photoURL("original-front.jpg")), Data("original front".utf8))
    }
    func testOldResultCannotOverwriteRetakenPhotosOrCollection() throws {
        let old = try fixture(state: "processing"), id = old.cards[0].id
        var updated = try disk.retakePhotos(cardID: id, front: Data([7]), back: nil, in: old)
        XCTAssertEqual(updated.supersededJobIDs, [old.cards[0].jobID])
        var stale = old.cards[0].analysis!; stale.collectionID = "wrong"; stale.player = "Wrong player"
        XCTAssertFalse(try updated.applyJobResult(cardID: id, jobID: old.cards[0].jobID, status: "analyzed", analysis: stale, collection: nil, error: nil))
        XCTAssertEqual(updated.cards[0].analysis?.player, "Daunte Culpepper")
        XCTAssertEqual(updated.cards[0].state, "queued")
        XCTAssertTrue(try updated.applyJobResult(cardID: id, jobID: updated.cards[0].jobID, status: "analyzed", analysis: old.cards[0].analysis, collection: old.collections[0], error: nil))
        XCTAssertTrue(updated.cards[0].hasCurrentAnalysis)
        XCTAssertEqual(updated.cards.count, 1)
        XCTAssertEqual(updated.pendingAcknowledgments, [updated.cards[0].jobID])
    }
    func testRepeatedRetakesOnlyAcceptLatestRevision() throws {
        let old = try fixture()
        let first = try disk.retakePhotos(cardID: old.cards[0].id, front: Data([1]), back: nil, in: old)
        var second = try disk.retakePhotos(cardID: old.cards[0].id, front: nil, back: Data([2]), in: first)
        XCTAssertEqual(second.supersededJobIDs, [first.cards[0].jobID])
        XCTAssertFalse(try second.applyJobResult(cardID: old.cards[0].id, jobID: first.cards[0].jobID, status: "failed", analysis: nil, collection: nil, error: "Old error"))
        XCTAssertNil(second.cards[0].error)
        XCTAssertEqual(second.cards[0].frontFile, first.cards[0].frontFile)
    }
    func testOriginalRecordsAndLibraryDecodeWithoutRevisionFields() throws {
        let old = try fixture()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        object.removeValue(forKey: "supersededJobIDs")
        let restored = try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.cards[0].analysisJobID)
        XCTAssertEqual(restored.cards[0].jobID, restored.cards[0].id)
        XCTAssertNil(restored.supersededJobIDs)
    }
}
