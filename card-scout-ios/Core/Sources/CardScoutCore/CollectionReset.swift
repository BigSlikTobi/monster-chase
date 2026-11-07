import Foundation

extension DiskStore {
    /// Explicit maintenance operation. A repeated launch with the same UUID must
    /// never erase cards captured after the reset. Pairing remains in Keychain.
    public func resetCollection(operationID: UUID) throws -> Library {
        let receipt = root.appendingPathComponent("reset-receipt.json")
        let identifier = operationID.uuidString.lowercased()
        if let data = try? Data(contentsOf: receipt),
           let previous = try? JSONDecoder().decode(ResetReceipt.self, from: data), previous.operationID == identifier {
            return try load()
        }
        let files = FileManager.default
        let backup = root.deletingLastPathComponent().appendingPathComponent("CardScout-ResetBackups")
            .appendingPathComponent(identifier)
        try files.createDirectory(at: backup, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let libraryFile = root.appendingPathComponent("library.json")
        let photos = root.appendingPathComponent("photos")
        for source in [libraryFile, photos] {
            let destination = backup.appendingPathComponent(source.lastPathComponent)
            if files.fileExists(atPath: source.path), !files.fileExists(atPath: destination.path) {
                try files.copyItem(at: source, to: destination)
            }
        }
        let old = try load()
        var fresh = Library()
        // Never bootstrap the removed library back from an old worker export.
        fresh.importedLegacy = true
        try save(fresh)
        if files.fileExists(atPath: photos.path) { try files.removeItem(at: photos) }
        try files.createDirectory(at: photos, withIntermediateDirectories: true)
        let result = ResetReceipt(operationID: identifier, removedCards: old.cards.count, cards: 0, photos: 0)
        try JSONEncoder().encode(result).write(to: receipt, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return fresh
    }
}

private struct ResetReceipt: Codable {
    let operationID: String
    let removedCards: Int
    let cards: Int
    let photos: Int
}
