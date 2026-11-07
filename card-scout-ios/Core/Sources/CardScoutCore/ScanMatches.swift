import Foundation

private func matchText(_ value: String?) -> String {
    let text = (value ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "").replacingOccurrences(of: ".", with: "")
    return text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
}

public struct CardMatch: Codable, Hashable, Identifiable, Sendable {
    public var collectionID: String
    public var number: String
    public var id: String { collectionID + "|" + number }
    public init(collectionID: String, number: String) { self.collectionID = collectionID; self.number = number }
}

public struct ScanSelection: Codable, Hashable, Sendable {
    public var photoJobID: String
    public var selectedAt: String
    public var match: CardMatch?
    public var checklistSourceURL: String?
    public var checklistCheckedAt: String?
}

public struct CardFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var cardIDs: [String]
    public init(id: String = UUID().uuidString.lowercased(), name: String, cardIDs: [String] = []) {
        self.id = id; self.name = name; self.cardIDs = cardIDs
    }
}

extension Library {
    public var collectedCards: [OwnedCard] { cards.filter { $0.isScanDraft != true } }
    public var scanDrafts: [OwnedCard] { cards.filter { $0.isScanDraft == true } }

    public mutating func setFolders(cardID: String, folderIDs: Set<String>, newFolderName: String? = nil) throws {
        guard collectedCards.contains(where: { $0.id == cardID }), folderIDs.isSubset(of: Set((folders ?? []).map(\.id))) else { throw StoreError.invalidResult }
        let name = newFolderName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard name.count <= 80 else { throw StoreError.invalidResult }
        var updated = folders ?? []
        var selected = folderIDs
        if !name.isEmpty {
            if let existing = updated.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { selected.insert(existing.id) }
            else { let created = CardFolder(name: name); updated.append(created); selected.insert(created.id) }
        }
        for index in updated.indices {
            updated[index].cardIDs.removeAll { $0 == cardID }
            if selected.contains(updated[index].id) { updated[index].cardIDs.append(cardID) }
        }
        folders = updated
    }

    /// Local fallback and manual search work even without the worker or Decisions.
    /// Only actual checklist rows are offered; parallel membership is never invented.
    public func matches(for card: OwnedCard, query: String = "", limit: Int = 5) -> [CardMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = card.analysis
        var scored: [(CardMatch, Int)] = []
        for collection in collections {
            for entry in collection.cards {
                let match = CardMatch(collectionID: collection.id, number: entry.number)
                let text = "\(entry.player) \(entry.number) \(collection.year) \(collection.name) \(collection.subset) \(collection.parallel ?? "Base")"
                if !query.isEmpty {
                    guard query.split(separator: " ").allSatisfy({ text.localizedStandardContains(String($0)) }) else { continue }
                }
                let name = !matchText(a?.player).isEmpty && matchText(entry.player) == matchText(a?.player)
                let number = !matchText(a?.cardNumber).isEmpty && matchText(entry.number) == matchText(a?.cardNumber)
                // Server OCR recovery may find the correct row even when BOTH
                // initial fields are wrong. Do not hide that recovered match.
                let suggested = card.matchSuggestions?.contains(match) == true
                let ocr = " " + matchText(card.captureText) + " "
                let ocrName = !matchText(entry.player).isEmpty && ocr.contains(" " + matchText(entry.player) + " ")
                guard !query.isEmpty || name || number || suggested || ocrName else { continue }
                var score = (name ? 30 : 0) + (number ? 20 : 0)
                if a?.year == collection.year { score += 12 }
                if matchText(a?.setName) == matchText(collection.name) { score += 16 }
                if matchText(a?.brand) == matchText(collection.brand) { score += 4 }
                if matchText(a?.subset) == matchText(collection.subset) { score += 12 }
                if matchText(a?.parallel) == matchText(collection.parallel) { score += 6 }
                if let rank = card.matchSuggestions?.firstIndex(of: match) { score += 10_000 - rank * 100 }
                scored.append((match, score))
            }
        }
        return scored.sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }.prefix(max(0, min(limit, 100))).map(\.0)
    }

    /// One atomic library save commits identity, ownership and folder membership.
    /// A second tap cannot create a second card or queue another assessment.
    public mutating func collectScan(cardID: String, match: CardMatch?, folderID: String?, newFolderName: String? = nil) throws {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { throw StoreError.missingCard }
        guard cards[index].isScanDraft == true else { return }
        var updated = self
        var folder = folderID
        if let name = newFolderName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            guard name.count <= 80 else { throw StoreError.invalidResult }
            if let existing = updated.folders?.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { folder = existing.id }
            else { let created = CardFolder(name: name); updated.folders = (updated.folders ?? []) + [created]; folder = created.id }
        }
        if let folder, updated.folders?.contains(where: { $0.id == folder }) != true { throw StoreError.invalidResult }
        if let match {
            if updated.cards[index].analysis == nil {
                updated.cards[index].analysis = CardAnalysis(recommendation: "Keep", marketCheckedAt: "", marketSources: [], confidence: "low", conditionNotes: "", rationale: "", needsReview: true)
            }
            try updated.correctAssignment(cardID: cardID, collectionID: match.collectionID, number: match.number)
            // A new job carries the explicit assignment. Old responses cannot overwrite it.
            updated.cards[index].state = "queued"
            updated.cards[index].fastPipeline = false
            updated.cards[index].preservesPreviousAnalysis = true
        } else {
            // Saving unidentified is explicit. A suggested checklist slot is not ownership.
            let oldJob = updated.cards[index].jobID
            updated.supersededJobIDs = Array(Set((updated.supersededJobIDs ?? []) + [oldJob]))
            updated.cards[index].analysisJobID = UUID().uuidString.lowercased()
            if var partial = updated.cards[index].analysis {
                let notes = partial.uncertainties
                partial.clearAssessmentAfterCorrection()
                partial.uncertainties = notes
                partial.collectionID = nil; partial.identityConfirmed = false
                partial.rationale = "Karte gespeichert. Die genaue Zuordnung ist noch offen."
                updated.cards[index].analysis = partial
            }
            updated.cards[index].state = "unidentified"
            updated.cards[index].hasProvisionalAnalysis = updated.cards[index].analysis != nil
        }
        let checklist = match.flatMap { choice in updated.collections.first { $0.id == choice.collectionID } }
        updated.cards[index].scanSelection = ScanSelection(photoJobID: cards[index].jobID,
            selectedAt: ISO8601DateFormatter().string(from: Date()), match: match,
            checklistSourceURL: checklist?.sourceURL, checklistCheckedAt: checklist?.checkedAt)
        updated.cards[index].isScanDraft = false
        if let folder, let i = updated.folders?.firstIndex(where: { $0.id == folder }) {
            if updated.folders?[i].cardIDs.contains(cardID) != true { updated.folders?[i].cardIDs.append(cardID) }
            updated.lastUsedFolderID = folder
        }
        self = updated
    }
}
