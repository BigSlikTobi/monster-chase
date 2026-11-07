import Foundation

/// A presentation group. Exact checklist IDs remain unchanged for matching and ownership.
public struct CollectionBinder: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let collections: [CardCollection]

    public func cards(in library: Library) -> [OwnedCard] {
        let ids = Set(collections.map(\.id))
        return library.collectedCards.filter { $0.analysis?.collectionID.map(ids.contains) == true }
    }

    public static func group(_ collections: [CardCollection]) -> [CollectionBinder] {
        let groups = Dictionary(grouping: collections) { family($0).lowercased() }
        return groups.map { key, values in
            CollectionBinder(id: key, name: family(values.sorted { $0.id < $1.id }[0]), collections: values.sorted {
                if $0.year != $1.year { return $0.year > $1.year }
                if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return ($0.parallel ?? $0.subset).localizedStandardCompare($1.parallel ?? $1.subset) == .orderedAscending
            })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func family(_ collection: CardCollection) -> String {
        let name = collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        // These product families deliberately include their Chrome/Optic editions.
        if words.contains("bowman") { return "Bowman Football" }
        if words.contains("donruss") { return "Donruss" }
        if words.contains("topps") { return "Topps Football" }
        // Unknown products retain their name rather than merging all sets by manufacturer.
        return name.isEmpty ? collection.brand : name
    }
}

extension Library {
    public var binders: [CollectionBinder] { CollectionBinder.group(collections) }
    public var collectibles: [OwnedCard] {
        collectedCards.filter { $0.isCollectible == true }.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
    }
}
