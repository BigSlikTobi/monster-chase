import XCTest
@testable import CardScoutCore

final class CollectionResetTests: XCTestCase {
    func testResetBacksUpPhotosAndCannotRepeatAfterNewCaptures() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let disk = try DiskStore(root: parent.appendingPathComponent("CardScout"))
        let bytes = Data([1, 2, 3])
        try disk.writePhoto(bytes, name: "old.jpg")
        var library = Library(); library.cards = [OwnedCard(frontFile: "old.jpg")]
        library.pendingAcknowledgments = [library.cards[0].id]
        try disk.save(library)
        let operation = UUID()
        let fresh = try disk.resetCollection(operationID: operation)
        XCTAssertTrue(fresh.cards.isEmpty)
        XCTAssertTrue(fresh.importedLegacy)
        XCTAssertTrue(fresh.pendingAcknowledgments?.isEmpty == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try disk.photoURL("old.jpg").path))
        let backup = parent.appendingPathComponent("CardScout-ResetBackups/\(operation.uuidString.lowercased())")
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("photos/old.jpg")), bytes)
        XCTAssertEqual(try JSONDecoder().decode(Library.self, from: Data(contentsOf: backup.appendingPathComponent("library.json"))).cards.count, 1)
        var newer = fresh; newer.cards = [OwnedCard(frontFile: "new.jpg")]
        try disk.writePhoto(bytes, name: "new.jpg"); try disk.save(newer)
        XCTAssertEqual(try disk.resetCollection(operationID: operation).cards.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try disk.photoURL("new.jpg").path))
    }
}
