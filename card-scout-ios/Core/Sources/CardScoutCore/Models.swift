import Foundation

public struct MarketSource: Codable, Hashable, Sendable {
    public var url: String
    public var title: String
    public var status: String
    public var matchQuality: String
    public var deliveredTotalCents: Int?
    public var currency: String
    public var saleDate: String?
}

public struct CardAnalysis: Codable, Hashable, Sendable {
    public var player: String?
    public var year: Int?
    public var brand: String?
    public var setName: String?
    public var subset: String?
    public var cardNumber: String?
    public var parallel: String?
    public var team: String?
    public var rookie: Bool?
    public var serialNumber: String?
    public var recommendation: String
    public var marketLowCents: Int?
    public var marketHighCents: Int?
    public var marketCheckedAt: String
    public var marketSources: [MarketSource]
    public var confidence: String
    public var conditionNotes: String
    public var rationale: String
    public var needsReview: Bool
    public var collectionID: String?
    public var identityConfirmed: Bool?
    public var licenseScope: String?
    public var psa10ChanceLow: Int?
    public var psa10ChanceHigh: Int?
    public var uncertainties: [String]?
    public var currency: String?
    public var insights: CardInsights?
    public var comparableEstimate: ComparableEstimate? = nil

    public var marketLabel: String {
        guard let low = marketLowCents, let high = marketHighCents else { return "Wert offen" }
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency ?? "EUR").locale(ScoutLocalization.locale).precision(.fractionLength(0...2))
        return low == high ? (Double(low) / 100).formatted(style) : "\((Double(low) / 100).formatted(style)) – \((Double(high) / 100).formatted(style))"
    }
}

public struct OwnedCard: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var createdAt: String
    public var state: String
    public var frontFile: String
    public var backFile: String?
    public var analysis: CardAnalysis?
    public var error: String?
    public var analysisJobID: String?
    public var requestedAnalysisVersion: Int?
    public var preservesPreviousAnalysis: Bool?
    public var refreshOfJobID: String?
    public var fastPipeline: Bool?
    public var captureSessionID: String?
    public var captureMode: String?
    public var captureText: String?
    public var isCollectible: Bool?
    public var isFavorite: Bool?
    public var storageLocation: String?
    public var notes: String?
    public var manualAssignment: Bool?
    public var uploadedJobID: String?
    public var scanSelection: ScanSelection?
    public var isScanDraft: Bool?
    public var awaitingBack: Bool?
    public var matchNotice: String?
    public var matchSuggestions: [CardMatch]?
    public var hasProvisionalAnalysis: Bool?
    public init(id: String = UUID().uuidString.lowercased(), createdAt: String = ISO8601DateFormatter().string(from: Date()), state: String = "queued", frontFile: String = "", backFile: String? = nil, analysis: CardAnalysis? = nil, error: String? = nil) {
        self.id = id; self.createdAt = createdAt; self.state = state; self.frontFile = frontFile; self.backFile = backFile; self.analysis = analysis; self.error = error
    }
    public var title: String { analysis?.player ?? (analysis == nil ? "Neue Karte" : "Spieler nicht erkannt") }
    public var jobID: String { analysisJobID ?? id }
    public var hasCurrentAnalysis: Bool { state == "analyzed" && analysis != nil }
    public var hasDisplayableAnalysis: Bool { analysis != nil && (hasCurrentAnalysis || preservesPreviousAnalysis == true || hasProvisionalAnalysis == true) }
    public var isAwaitingAnalysis: Bool { ["queued", "processing", "identified", "enriching"].contains(state) }
    public var stateLabel: String {
        switch state { case "awaiting_back": "Rückseite ergänzen"; case "queued": "Gespeichert"; case "processing": "Wird erkannt"; case "identified": analysis?.identityConfirmed == true ? "Erkannt · Preis folgt" : "Zuordnung prüfen · vorläufig"; case "enriching": "Preis wird geprüft"; case "failed": "Erneut versuchen"; default: analysis?.needsReview == true ? "Prüfen" : "Analysiert" }
    }
}

public struct ChecklistCard: Codable, Identifiable, Hashable, Sendable {
    public var id: String { number }
    public var number: String
    public var player: String
    public var team: String
    public var rookie: Bool
    public var imageURL: String?
    public var referenceImage: CardReferenceImage?
    public init(number: String, player: String, team: String, rookie: Bool = false, imageURL: String? = nil) { self.number = number; self.player = player; self.team = team; self.rookie = rookie; self.imageURL = imageURL }
}

public struct CardCollection: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var year: Int
    public var brand: String
    public var subset: String
    public var parallel: String?
    public var expectedCount: Int?
    public var checklistComplete: Bool
    public var sourceURL: String?
    public var checkedAt: String?
    public var cards: [ChecklistCard]
    public var referenceExample: CardReferenceImage?
    public init(id: String, name: String, year: Int, brand: String, subset: String = "Base", parallel: String? = nil, expectedCount: Int? = nil, checklistComplete: Bool = false, sourceURL: String? = nil, checkedAt: String? = nil, cards: [ChecklistCard]) {
        self.id = id; self.name = name; self.year = year; self.brand = brand; self.subset = subset; self.parallel = parallel; self.expectedCount = expectedCount; self.checklistComplete = checklistComplete; self.sourceURL = sourceURL; self.checkedAt = checkedAt; self.cards = cards
    }
    public func owned(for number: String, in inventory: [OwnedCard]) -> [OwnedCard] {
        inventory.filter { $0.isScanDraft != true && $0.analysis?.collectionID == id && $0.analysis?.cardNumber == number && $0.analysis?.identityConfirmed == true }
    }
    public func ownedCount(in inventory: [OwnedCard]) -> Int {
        cards.filter { !owned(for: $0.number, in: inventory).isEmpty }.count
    }
}

public struct HuntCard: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var label: String
    public var productName: String
    public var player: String?
    public var imageURL: String?
    public var sourceURL: String?
    public var status: String
    public init(id: String = UUID().uuidString.lowercased(), label: String, productName: String, player: String? = nil, imageURL: String? = nil, sourceURL: String? = nil, status: String = "hunting") { self.id = id; self.label = label; self.productName = productName; self.player = player; self.imageURL = imageURL; self.sourceURL = sourceURL; self.status = status }
}

public struct HotCard: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var rank: Int
    public var brandFamily: String
    public var productName: String
    public var label: String
    public var player: String?
    public var imageUrl: String
    public var imageSourceUrl: String
    public var whyHot: String
    public var currency: String
    public var marketLowCents: Int?
    public var marketHighCents: Int?
    public var lastSaleAt: String?
}

public struct Library: Codable, Sendable {
    public var version: Int = 1
    public var cards: [OwnedCard] = []
    public var collections: [CardCollection] = []
    public var hunts: [HuntCard] = []
    public var hotCards: [HotCard] = []
    public var hotCheckedAt: String?
    public var chaseCatalog: ChaseCatalog?
    public var selectedChaseProductID: String?
    public var chaseFilters: [String: ChaseFilter]?
    public var importedLegacy: Bool = false
    public var pendingAcknowledgments: [String]? = []
    public var supersededJobIDs: [String]? = []
    public var burnManualValues: [String: ManualBurnValue]?
    public var portfolioHistory: [PortfolioObservation]?
    public var purchases: [CardPurchase]? = []
    public var unclearCardQueue: UnclearCardQueue?
    public var folders: [CardFolder]?
    public var lastUsedFolderID: String?
    public var savedPhotoReanalysisOperationID: String?
    public init() {}

    /// Ignore results for photos that were replaced while an upload or analysis was in flight.
    @discardableResult
    public mutating func applyJobResult(cardID: String, jobID: String, status: String, analysis: CardAnalysis?, collection: CardCollection?, error: String?) throws -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == cardID }), cards[index].jobID == jobID else { return false }
        guard ["queued", "processing", "identified", "enriching", "analyzed", "failed"].contains(status), !["identified", "enriching", "analyzed"].contains(status) || analysis != nil else { throw StoreError.invalidResult }
        if cards[index].manualAssignment == true, let locked = cards[index].analysis, let incoming = analysis,
           ["identified", "enriching", "analyzed"].contains(status) {
            guard incoming.collectionID == locked.collectionID, incoming.cardNumber == locked.cardNumber,
                  incoming.player == locked.player, incoming.year == locked.year,
                  incoming.brand == locked.brand, incoming.setName == locked.setName,
                  incoming.subset == locked.subset, incoming.parallel == locked.parallel else { return false }
        }
        var mergedCollection = collection
        if let incoming = collection, let existing = collections.first(where: { $0.id == incoming.id }) {
            if existing.checklistComplete && !incoming.checklistComplete { mergedCollection = existing }
            else if !incoming.checklistComplete {
                var merged = incoming
                for entry in existing.cards {
                    if let i = merged.cards.firstIndex(where: { $0.number == entry.number }) {
                        guard merged.cards[i].player.caseInsensitiveCompare(entry.player) == .orderedSame else { throw StoreError.invalidResult }
                        if merged.cards[i].imageURL == nil { merged.cards[i].imageURL = entry.imageURL }
                    } else { merged.cards.append(entry) }
                }
                mergedCollection = merged
            }
        }
        if var incoming = mergedCollection, let existing = collections.first(where: { $0.id == incoming.id }) {
            if incoming.referenceExample == nil { incoming.referenceExample = existing.validReferenceExample }
            for entryIndex in incoming.cards.indices where incoming.cards[entryIndex].referenceImage == nil {
                if let entry = existing.cards.first(where: { $0.number == incoming.cards[entryIndex].number }),
                   let reference = entry.exactReference(in: incoming), reference.player == incoming.cards[entryIndex].player {
                    incoming.cards[entryIndex].referenceImage = reference
                }
            }
            mergedCollection = incoming
        }
        cards[index].state = status; cards[index].error = error
        if ["identified", "enriching", "analyzed"].contains(status), let analysis {
            cards[index].analysis = analysis
            cards[index].hasProvisionalAnalysis = status != "analyzed"
            if status == "analyzed" { cards[index].preservesPreviousAnalysis = false }
            if let collection = mergedCollection {
                if let i = collections.firstIndex(where: { $0.id == collection.id }) { collections[i] = collection }
                else { collections.append(collection) }
            }
            if status == "analyzed", !(pendingAcknowledgments ?? []).contains(jobID) { pendingAcknowledgments = (pendingAcknowledgments ?? []) + [jobID] }
        }
        return true
    }
}

public struct Pairing: Codable, Sendable, Equatable {
    public var baseURL: String
    public var token: String
    public var certificateSHA256: String
    public init(baseURL: String, token: String, certificateSHA256: String) { self.baseURL = baseURL; self.token = token; self.certificateSHA256 = certificateSHA256 }
    public static func parse(_ url: URL) throws -> Pairing {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "cardscout", c.host == "pair" else { throw StoreError.invalidPairing }
        let items = c.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { throw StoreError.invalidPairing }
        let d = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard let base = d["url"], let u = URLComponents(string: base), u.scheme == "https", u.host != nil, u.user == nil, u.password == nil, u.query == nil, u.fragment == nil, u.path.isEmpty || u.path == "/", let token = d["token"], token.count >= 32, let pin = d["pin"], pin.count == 64, pin.allSatisfy({ $0.isHexDigit }) else { throw StoreError.invalidPairing }
        return Pairing(baseURL: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")), token: token, certificateSHA256: pin.lowercased())
    }
}

public enum StoreError: Error { case invalidPairing, unsafePath, missingFront, missingCard, noPhotoChanges, invalidResult }

public struct DiskStore: Sendable {
    public let root: URL
    public init(root: URL) throws { self.root = root; try FileManager.default.createDirectory(at: root.appendingPathComponent("photos"), withIntermediateDirectories: true) }
    public func load() throws -> Library {
        let file = root.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return Library() }
        var library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: file))
        for index in library.cards.indices { library.cards[index].analysis = library.cards[index].analysis?.withoutTransientPricing() }
        return library
    }
    public func save(_ library: Library) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var durable = library
        for index in durable.cards.indices { durable.cards[index].analysis = durable.cards[index].analysis?.withoutTransientPricing() }
        let data = try encoder.encode(durable)
        try data.write(to: root.appendingPathComponent("library.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    public func photoURL(_ relative: String) throws -> URL {
        guard !relative.isEmpty, !relative.contains("/"), !relative.contains("\\"), !relative.contains("..") else { throw StoreError.unsafePath }
        return root.appendingPathComponent("photos").appendingPathComponent(relative)
    }
    public func writePhoto(_ data: Data, name: String) throws {
        guard !data.isEmpty else { throw StoreError.missingFront }
        try data.write(to: photoURL(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Write new files first, then switch the library atomically. Existing photos are never overwritten.
    public func retakePhotos(cardID: String, front: Data?, back: Data?, in library: Library) throws -> Library {
        guard let index = library.cards.firstIndex(where: { $0.id == cardID }) else { throw StoreError.missingCard }
        guard front != nil || back != nil else { throw StoreError.noPhotoChanges }
        var updated = library
        let jobID = UUID().uuidString.lowercased()
        if let front {
            let name = "\(jobID)-front.jpg"; try writePhoto(front, name: name); updated.cards[index].frontFile = name
        }
        if let back {
            let name = "\(jobID)-back.jpg"; try writePhoto(back, name: name); updated.cards[index].backFile = name
        }
        // The unchanged front remains required, including when only the back was retaken.
        guard !(try Data(contentsOf: photoURL(updated.cards[index].frontFile))).isEmpty else { throw StoreError.missingFront }
        updated = queueAnalysis(at: index, jobID: jobID, in: updated)
        updated.cards[index].preservesPreviousAnalysis = false
        updated.cards[index].manualAssignment = nil
        updated.cards[index].fastPipeline = true
        // Commit the queue advance with the new photo revision. A crash cannot resubmit this step.
        if var queue = updated.unclearCardQueue {
            queue.photoSaved(cardID: cardID)
            updated.unclearCardQueue = queue
        }
        try save(updated)
        return updated
    }

    /// Reuse the original files for a new assessment; never create a second collection card.
    public func reanalyze(cardID: String, in library: Library) throws -> Library {
        guard let index = library.cards.firstIndex(where: { $0.id == cardID }) else { throw StoreError.missingCard }
        let card = library.cards[index]
        guard !(try Data(contentsOf: photoURL(card.frontFile))).isEmpty else { throw StoreError.missingFront }
        if let back = card.backFile { guard !(try Data(contentsOf: photoURL(back))).isEmpty else { throw StoreError.missingFront } }
        var updated = queueAnalysis(at: index, jobID: UUID().uuidString.lowercased(), in: library)
        updated.cards[index].preservesPreviousAnalysis = card.hasDisplayableAnalysis
        // Manual corrections clear insights; never ask the Mac to restore its pre-correction identity.
        let canReuseIdentity = card.hasCurrentAnalysis && card.analysis?.identityConfirmed == true && card.analysis?.knownIdentityConflict == nil && card.analysis?.insights != nil
        updated.cards[index].refreshOfJobID = canReuseIdentity ? card.jobID : nil
        try save(updated)
        return updated
    }

    /// A bounded support batch targets old job IDs, so repeating a launch cannot queue it twice.
    /// Read every saved photo before committing any change. Resolved/manual cards stay untouched.
    public func reanalyzeUnclear(jobIDs: Set<String>, in library: Library) throws -> Library {
        guard jobIDs.count <= 200 else { throw StoreError.invalidResult }
        let indices = library.cards.indices.filter {
            let card = library.cards[$0]
            return jobIDs.contains(card.jobID) && ["analyzed", "failed"].contains(card.state) && card.manualAssignment == nil
                && (card.analysis?.identityConfirmed != true || card.analysis?.confidence != "high" || card.analysis?.needsReview == true)
        }
        guard !indices.isEmpty else { return library }
        for index in indices {
            let card = library.cards[index]
            guard !(try Data(contentsOf: photoURL(card.frontFile))).isEmpty else { throw StoreError.missingFront }
            if let back = card.backFile {
                guard !(try Data(contentsOf: photoURL(back))).isEmpty else { throw StoreError.missingFront }
            }
        }
        var updated = library
        for index in indices {
            updated = queueAnalysis(at: index, jobID: UUID().uuidString.lowercased(), in: updated)
            updated.cards[index].preservesPreviousAnalysis = library.cards[index].hasDisplayableAnalysis
            // Reinspect original pixels in the full Luna lane. No reuse of uncertain identities.
            updated.cards[index].fastPipeline = false
        }
        try save(updated)
        return updated
    }

    /// One explicit support operation reinspects saved pixels for all finished
    /// cards. The operation marker commits with the jobs, preventing a second lap.
    public func reanalyzeAllSaved(operationID: String, in library: Library) throws -> Library {
        guard UUID(uuidString: operationID) != nil else { throw StoreError.invalidResult }
        guard library.savedPhotoReanalysisOperationID != operationID else { return library }
        let indices = library.cards.indices.filter { ["analyzed", "failed"].contains(library.cards[$0].state) }
        guard indices.count <= 200 else { throw StoreError.invalidResult }
        for index in indices {
            let card = library.cards[index]
            guard !(try Data(contentsOf: photoURL(card.frontFile))).isEmpty else { throw StoreError.missingFront }
            if let back = card.backFile { guard !(try Data(contentsOf: photoURL(back))).isEmpty else { throw StoreError.missingFront } }
        }
        var updated = library
        for index in indices {
            updated = queueAnalysis(at: index, jobID: UUID().uuidString.lowercased(), in: updated)
            updated.cards[index].preservesPreviousAnalysis = library.cards[index].hasDisplayableAnalysis
            updated.cards[index].fastPipeline = library.cards[index].manualAssignment != true
            // Manual assignment stays attached to the card and submission.
        }
        updated.savedPhotoReanalysisOperationID = operationID
        try save(updated)
        return updated
    }

    private func queueAnalysis(at index: Int, jobID: String, in library: Library) -> Library {
        var updated = library
        let previous = library.cards[index]
        if previous.isAwaitingAnalysis || previous.state == "failed", !(updated.supersededJobIDs ?? []).contains(previous.jobID) {
            updated.supersededJobIDs = (updated.supersededJobIDs ?? []) + [previous.jobID]
        }
        updated.cards[index].analysisJobID = jobID
        updated.cards[index].requestedAnalysisVersion = OwnedCard.currentAnalysisVersion
        updated.cards[index].refreshOfJobID = nil
        updated.cards[index].uploadedJobID = nil
        updated.cards[index].hasProvisionalAnalysis = false
        updated.cards[index].state = "queued"; updated.cards[index].error = nil
        // Keep identity for the binder, but hasCurrentAnalysis is false until fresh results arrive.
        return updated
    }
}
