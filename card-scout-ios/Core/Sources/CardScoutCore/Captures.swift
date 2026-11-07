import Foundation

public enum ScanCaptureMode: String, CaseIterable, Sendable {
    case single, stack
}

public struct ScanSessionSummary: Sendable {
    public let saved: Int
    public let identified: Int
    public let processing: Int
    public let review: Int
    public init(cards: [OwnedCard]) {
        let complete = cards.filter { $0.awaitingBack != true }
        saved = complete.count
        identified = complete.filter { $0.analysis?.identityConfirmed == true && $0.analysis?.confidence == "high" && $0.analysis?.knownIdentityConflict == nil }.count
        review = complete.filter { card in
            if card.analysis?.identityConfirmed == true && card.analysis?.confidence == "high" && card.analysis?.knownIdentityConflict == nil { return false }
            return !card.isAwaitingAnalysis || (card.isScanDraft == true && card.state == "identified")
        }.count
        processing = saved - identified - review
    }
}

public struct CapturePhoto: Sendable {
    public let front: Data
    public let back: Data?
    public let text: String?
    public init(front: Data, back: Data? = nil, text: String? = nil) {
        self.front = front; self.back = back; self.text = text
    }
}

extension DiskStore {
    /// Persist the front immediately, but do not upload an incomplete pair.
    public func beginCapturePair(_ capture: CapturePhoto, sessionID: String, in library: Library, mode: ScanCaptureMode = .single) throws -> Library {
        guard !library.cards.contains(where: { $0.awaitingBack == true }), capture.back == nil, !capture.front.isEmpty else { throw StoreError.invalidResult }
        var updated = library
        var card = OwnedCard(state: "awaiting_back")
        card.frontFile = card.id + "-front.jpg"; card.isScanDraft = true; card.awaitingBack = true
        card.fastPipeline = true; card.captureSessionID = sessionID
        card.captureMode = mode.rawValue
        card.captureText = capture.text.map { String($0.prefix(1000)) }
        card.requestedAnalysisVersion = OwnedCard.currentAnalysisVersion
        do {
            try writePhoto(capture.front, name: card.frontFile)
            updated.cards.insert(card, at: 0); try save(updated)
            return updated
        } catch {
            if let url = try? photoURL(card.frontFile) { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    /// The explicit card ID prevents a late callback from attaching a back to another front.
    public func finishCapturePair(cardID: String, back: Data?, text: String? = nil, in library: Library) throws -> Library {
        guard let i = library.cards.firstIndex(where: { $0.id == cardID && $0.awaitingBack == true }),
              back?.isEmpty != true else { throw StoreError.invalidResult }
        // Stack mode always uses a complete pair. The mode is stored with the
        // front so an app restart or changed preference cannot change its route.
        guard library.cards[i].captureMode != ScanCaptureMode.stack.rawValue || back != nil else { throw StoreError.invalidResult }
        var updated = library
        let name = cardID + "-paired-back-" + UUID().uuidString.lowercased() + ".jpg"
        do {
            if let back {
                try writePhoto(back, name: name); updated.cards[i].backFile = name
                updated.cards[i].captureText = ["Vorderseite: " + String((updated.cards[i].captureText ?? "").prefix(900)),
                                                "Rückseite: " + String((text ?? "").prefix(900))].joined(separator: "\n")
            }
            updated.cards[i].awaitingBack = false; updated.cards[i].state = "queued"
            updated.cards[i].isScanDraft = updated.cards[i].captureMode != ScanCaptureMode.stack.rawValue
            try save(updated); return updated
        } catch {
            if back != nil, let url = try? photoURL(name) { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    /// Save the photo files before committing the batch. Only this attempt's files
    /// are removed on failure; existing cards, photos and job IDs stay intact.
    public func addCaptures(_ captures: [CapturePhoto], sessionID: String, to library: Library, asDraft: Bool = false) throws -> Library {
        guard !captures.isEmpty, captures.count <= 200,
              captures.allSatisfy({ !$0.front.isEmpty && ($0.back?.isEmpty != true) }) else { throw StoreError.missingFront }
        var updated = library
        var written: [String] = []
        do {
            var cards: [OwnedCard] = []
            for capture in captures {
                var card = OwnedCard()
                card.isScanDraft = asDraft ? true : nil
                card.fastPipeline = true; card.captureSessionID = sessionID
                card.captureText = capture.text.map { String($0.prefix(2000)) }
                card.requestedAnalysisVersion = OwnedCard.currentAnalysisVersion
                card.frontFile = card.id + "-front.jpg"
                written.append(card.frontFile); try writePhoto(capture.front, name: card.frontFile)
                if let back = capture.back {
                    let name = card.id + "-back.jpg"; written.append(name)
                    try writePhoto(back, name: name); card.backFile = name
                }
                cards.append(card)
            }
            updated.cards.insert(contentsOf: cards.reversed(), at: 0)
            try save(updated)
            return updated
        } catch {
            for name in written { if let url = try? photoURL(name) { try? FileManager.default.removeItem(at: url) } }
            throw error
        }
    }
}

extension Library {
    public mutating func correctAssignment(cardID: String, collectionID: String, number: String) throws {
        guard let index = cards.firstIndex(where: { $0.id == cardID }),
              let collection = collections.first(where: { $0.id == collectionID }),
              let entry = collection.cards.first(where: { $0.number.caseInsensitiveCompare(number.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame })
        else { throw StoreError.invalidResult }
        var analysis = cards[index].analysis ?? CardAnalysis(recommendation: "Keep", marketCheckedAt: "", marketSources: [], confidence: "low", conditionNotes: "", rationale: "", needsReview: true)
        let old = cards[index]
        if old.isAwaitingAnalysis || old.state == "failed" {
            supersededJobIDs = Array(Set((supersededJobIDs ?? []) + [old.jobID]))
        }
        // A correction is a new revision even if a remote result is already in flight.
        cards[index].analysisJobID = UUID().uuidString.lowercased()
        analysis.collectionID = collection.id; analysis.player = entry.player; analysis.team = entry.team
        analysis.year = collection.year; analysis.brand = collection.brand; analysis.setName = collection.name
        analysis.subset = collection.subset; analysis.parallel = collection.parallel
        analysis.cardNumber = entry.number; analysis.rookie = entry.rookie; analysis.serialNumber = nil
        analysis.identityConfirmed = true; analysis.confidence = "high"; analysis.clearAssessmentAfterCorrection()
        cards[index].analysis = analysis; cards[index].state = "analyzed"; cards[index].error = nil
        cards[index].refreshOfJobID = nil; cards[index].manualAssignment = true
        cards[index].hasProvisionalAnalysis = false
        cards[index].requestedAnalysisVersion = OwnedCard.currentAnalysisVersion
    }
}
