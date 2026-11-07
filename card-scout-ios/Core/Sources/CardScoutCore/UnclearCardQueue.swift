import Foundation

/// One pass through stable owned-card IDs. New results cannot add a card back into this pass.
public struct UnclearCardQueue: Codable, Equatable, Sendable {
    public let cardIDs: [String]
    public private(set) var remainingIDs: [String]
    public private(set) var photoSavedIDs: [String] = []
    public private(set) var skippedIDs: [String] = []
    public private(set) var noLongerNeededIDs: [String] = []
    public var currentID: String? { remainingIDs.first }
    public var total: Int { cardIDs.count }
    public var visited: Int { total - remainingIDs.count }

    public static func isEligible(_ card: OwnedCard) -> Bool {
        card.isScanDraft != true && !card.isAwaitingAnalysis && ReviewIssue.identity(card) != nil
    }
    public init(cards: [OwnedCard]) {
        var seen: Set<String> = []
        let ids = cards.filter(Self.isEligible).map(\.id).filter { seen.insert($0).inserted }
        cardIDs = ids; remainingIDs = ids
    }
    @discardableResult public mutating func photoSaved(cardID: String) -> Bool {
        guard currentID == cardID else { return false }
        remainingIDs.removeFirst(); photoSavedIDs.append(cardID)
        return true
    }
    @discardableResult public mutating func skip(cardID: String) -> Bool {
        guard currentID == cardID else { return false }
        remainingIDs.removeFirst(); skippedIDs.append(cardID)
        return true
    }
    /// Recheck only the snapshot. Resolved, deleted, or already-running cards need no new photos now.
    public mutating func reconcile(cards: [OwnedCard]) {
        let eligible = Set(cards.filter(Self.isEligible).map(\.id))
        for id in remainingIDs where !eligible.contains(id) { noLongerNeededIDs.append(id) }
        remainingIDs.removeAll { !eligible.contains($0) }
    }
}
