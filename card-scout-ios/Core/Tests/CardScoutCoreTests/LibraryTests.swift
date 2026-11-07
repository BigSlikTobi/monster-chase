import XCTest
@testable import CardScoutCore

final class LibraryTests: XCTestCase {
    func testDurablePhotosAndQueueAcrossRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        var library = Library(); let card = OwnedCard(frontFile: "one.jpg")
        library.cards = [card]
        try disk.writePhoto(Data([1, 2, 3]), name: "one.jpg"); try disk.save(library)
        let second = try DiskStore(root: root)
        XCTAssertEqual(try second.load().cards.first?.id, card.id)
        XCTAssertEqual(try second.load().cards.first?.state, "queued")
        XCTAssertEqual(try Data(contentsOf: second.photoURL("one.jpg")), Data([1, 2, 3]))
    }
    func testUnsafePhotoPathsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        for path in ["../secret", "/tmp/secret", "folder/image.jpg", "..", ""] { XCTAssertThrowsError(try disk.photoURL(path)) }
    }
    func testDamagedLibraryIsNotSilentlyReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        try Data("not json".utf8).write(to: root.appendingPathComponent("library.json"))
        XCTAssertThrowsError(try disk.load())
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("library.json"), encoding: .utf8), "not json")
    }
    func testPairingRequiresTLSAndPin() throws {
        let token = String(repeating: "x", count: 48), pin = String(repeating: "a", count: 64)
        let valid = URL(string: "cardscout://pair?url=https%3A%2F%2Fmac.local%3A8743&token=\(token)&pin=\(pin)")!
        XCTAssertEqual(try Pairing.parse(valid).baseURL, "https://mac.local:8743")
        for value in ["cardscout://pair?url=http://mac.local&token=\(token)&pin=\(pin)", "cardscout://pair?url=https://mac.local&token=x&pin=\(pin)", "cardscout://pair?url=https://mac.local&token=\(token)&pin=bad", "cardscout://pair?url=https://mac.local&token=\(token)&token=\(token)&pin=\(pin)"] { XCTAssertThrowsError(try Pairing.parse(URL(string: value)!)) }
    }
    func testChecklistPersistsAllSlots() throws {
        let set = CardCollection(id: "base", name: "Optic", year: 2025, brand: "Panini", expectedCount: 300, checklistComplete: true, cards: (1...300).map { ChecklistCard(number: String($0), player: "Fixture", team: "Fixture") })
        let decoded = try JSONDecoder().decode(CardCollection.self, from: JSONEncoder().encode(set))
        XCTAssertEqual(decoded.cards.count, 300)
        XCTAssertEqual(decoded.ownedCount(in: []), 0)
    }
    func testDuplicatesAndParallelsDoNotInflateBinder() {
        let set = CardCollection(id: "base", name: "Optic", year: 2025, brand: "Panini", cards: [ChecklistCard(number: "60", player: "Daunte Culpepper", team: "Miami Dolphins")])
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-09-07", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        a.cardNumber = "60"; a.collectionID = "base"; a.identityConfirmed = true
        let first = OwnedCard(analysis: a), duplicate = OwnedCard(analysis: a)
        a.collectionID = "holo"; let holo = OwnedCard(analysis: a)
        a.collectionID = "base"; a.identityConfirmed = false; let uncertain = OwnedCard(analysis: a)
        let inventory = [first, duplicate, holo, uncertain]
        XCTAssertEqual(set.ownedCount(in: inventory), 1)
        XCTAssertEqual(set.owned(for: "60", in: inventory).count, 2)
    }
    func testAcknowledgmentQueueSurvivesRestartAndOldLibrariesDecode() throws {
        var library = Library(); library.pendingAcknowledgments = ["saved-card"]
        let encoder = JSONEncoder()
        XCTAssertEqual(try JSONDecoder().decode(Library.self, from: encoder.encode(library)).pendingAcknowledgments, ["saved-card"])
        var object = try JSONSerialization.jsonObject(with: encoder.encode(library)) as! [String: Any]
        object.removeValue(forKey: "pendingAcknowledgments")
        XCTAssertNil(try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: object)).pendingAcknowledgments)
    }
}
