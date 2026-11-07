import SwiftUI
import Observation
import UIKit
import CardScoutCore

@MainActor @Observable final class AppStore {
    var library = Library()
    var dashboardValueCache = DashboardValueCache()
    var dashboardStatistics: CollectionStatistics {
        CollectionStatistics(library: library, cachedValues: dashboardValueCache.values(in: library))
    }
    var pairing = PairingKeychain.load()
    var pairingCandidate: Pairing?
    var lastError: String?
    var connected = false
    var connectionError: String?
    var syncing = false
    var captureSessionID = UUID().uuidString.lowercased()
    var showSettings = false
    var selectedTab = 0
    var showMarketRanking = false
    var chaseError: String?
    // Provider views never enter library.json or the phone's photo storage.
    var markets: [String: MarketSnapshot] = [:]
    var marketErrors: [String: String] = [:]
    private var loadingMarkets: Set<String> = []
    private var loadingCardPrices: Set<String> = []
    private var hydratedCardPriceJobs: Set<String> = []
    private var observedPriceJobs: Set<String> = []
    var priceStates: [String: String] = [:]
    private var nextPriceChecks: [String: Date] = [:]
    private var reanalysisCardIDs: Set<String> = []
    let disk: DiskStore?
    private var writable = true
    private var client: MacClient?
    private var loadedMatchChecklists = false
    private var loadedReferenceRevision: String?
    private var loadedCatalogRevision: String?
    private var lastChaseAttempt = Date.distantPast
    init() {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("CardScout")
            disk = try DiskStore(root: root)
            do {
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "--reset-collection"), arguments.indices.contains(index + 1),
                   let operationID = UUID(uuidString: arguments[index + 1]) {
                    library = try disk!.resetCollection(operationID: operationID)
                } else { library = try disk!.load() }
                do {
                    if let index = arguments.firstIndex(of: "--reanalyze-all-saved"), arguments.indices.contains(index + 1) {
                        let previous = library
                        library = try disk!.reanalyzeAllSaved(operationID: arguments[index + 1], in: library)
                        reanalysisCardIDs = Set(library.cards.filter { card in
                            previous.cards.contains { $0.id == card.id && $0.jobID != card.jobID }
                        }.map(\.id))
                    }
                    if let index = arguments.firstIndex(of: "--reanalyze-saved-jobs"), arguments.indices.contains(index + 1) {
                        let values = arguments[index + 1].split(separator: ",").map(String.init)
                        guard !values.isEmpty, values.count <= 200, values.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw StoreError.invalidResult }
                        let jobs = Set(values.map { $0.lowercased() })
                        let previous = library
                        library = try disk!.reanalyzeUnclear(jobIDs: jobs, in: library)
                        reanalysisCardIDs = Set(library.cards.filter { card in
                            previous.cards.contains { $0.id == card.id && $0.jobID != card.jobID }
                        }.map(\.id))
                    }
                } catch {
                    lastError = "Die gespeicherten Fotos konnten nicht vollständig für die neue Prüfung geladen werden. Deine Sammlung bleibt unverändert."
                }
            } catch { writable = false; lastError = "Sammlung konnte nicht gelesen oder zurückgesetzt werden. Deine Sicherung bleibt erhalten." }
        } catch { disk = nil; writable = false; lastError = "Lokaler Speicher ist nicht verfügbar." }
        #if DEBUG
        if PreviewData.enabled, library.cards.isEmpty, let disk, let preview = try? PreviewData.library(disk: disk) {
            library = preview; try? disk.save(preview)
        }
        #endif
        dashboardValueCache = disk?.loadDashboardValues() ?? DashboardValueCache()
        dashboardValueCache.prune(in: library)
        if let pairing { client = MacClient(pairing) }
        if client == nil { recordPortfolioObservation() }
        recordConnectionStatus("ready")
        recordReanalysisStatus()
    }
    private func recordReanalysisStatus() {
        guard let disk, !reanalysisCardIDs.isEmpty else { return }
        let cards = library.cards.filter { reanalysisCardIDs.contains($0.id) }
        let value: [String: Any] = ["targetedCards": cards.count,
            "pending": cards.filter(\.isAwaitingAnalysis).count,
            "completed": cards.filter { $0.state == "analyzed" }.count,
            "failed": cards.filter { $0.state == "failed" }.count,
            "confirmed": cards.filter { $0.hasCurrentAnalysis && $0.analysis?.identityConfirmed == true && $0.analysis?.confidence == "high" }.count,
            "priced": cards.filter { $0.analysis?.marketSummary != nil }.count,
            "checkedAt": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            try? data.write(to: disk.root.appendingPathComponent("reanalysis-status.json"), options: [.atomic, .completeFileProtection])
        }
    }
    // Connection-only diagnostics. Never include credentials, URLs with query strings,
    // collection records, photo paths, error userInfo or request/response bodies.
    private func recordConnectionStatus(_ stage: String, error: Error? = nil) {
        guard let disk else { return }
        var value: [String: Any] = ["stage": stage, "paired": pairing != nil,
                                  "connected": connected, "canSave": writable,
                                  "checkedAt": ISO8601DateFormatter().string(from: Date())]
        value["host"] = pairing.flatMap { URL(string: $0.baseURL)?.host }
        value["candidateHost"] = pairingCandidate.flatMap { URL(string: $0.baseURL)?.host }
        if let trust = client?.trustDiagnostic {
            value["trustStage"] = trust.stage
            value["trustErrorCode"] = trust.code
        }
        if let error {
            let issue = error as NSError
            value["errorDomain"] = String(issue.domain.prefix(100)); value["errorCode"] = issue.code
        }
        let file = disk.root.appendingPathComponent("connection-status.json")
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            try? data.write(to: file, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
    }
    private func connectionMessage(_ error: Error) -> String {
        let issue = error as NSError
        guard issue.domain == NSURLErrorDomain else { return error.localizedDescription }
        switch issue.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "Keine Netzwerkverbindung. Tailscale und den Netzwerkzugriff für Card Scout prüfen."
        case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return "Server nicht erreichbar. Tailscale einschalten und erneut prüfen."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot:
            return "Die sichere Serververbindung konnte nicht geprüft werden. Verbindungscode erneut scannen."
        default: return "Verbindung fehlgeschlagen (Code \(issue.code)). Erneut prüfen."
        }
    }
    func persist() throws {
        guard writable, let disk else { throw CocoaError(.fileWriteNoPermission) }
        try disk.save(library)
        dashboardValueCache.prune(in: library)
        try? disk.saveDashboardValues(dashboardValueCache)
    }
    func commit(_ update: (inout Library) -> Void) {
        let old = library; update(&library)
        do { try persist() } catch { library = old; lastError = "Speichern fehlgeschlagen. Bitte erneut versuchen." }
    }
    func photoURL(_ name: String?) -> URL? {
        guard let name else { return nil }
        return try? disk?.photoURL(name)
    }
    func add(front: Data, back: Data?) throws {
        guard writable, let disk else { throw CocoaError(.fileWriteNoPermission) }
        library = try disk.addCaptures([CapturePhoto(front: front, back: back)], sessionID: captureSessionID, to: library)
        Task { await sync() }
    }
    @discardableResult func addCapture(_ capture: CapturePhoto) throws -> String {
        guard writable, let disk else { throw CocoaError(.fileWriteNoPermission) }
        library = try disk.addCaptures([capture], sessionID: captureSessionID, to: library, asDraft: true)
        Task { await sync() }
        return library.cards[0].id
    }
    var pendingCapturePair: OwnedCard? { library.cards.first { $0.awaitingBack == true } }
    @discardableResult func beginCapturePair(_ capture: CapturePhoto, mode: ScanCaptureMode = .single) throws -> String {
        guard writable, let disk else { throw CocoaError(.fileWriteNoPermission) }
        library = try disk.beginCapturePair(capture, sessionID: captureSessionID, in: library, mode: mode)
        return library.cards[0].id
    }
    func finishCapturePair(_ id: String, back: Data?, text: String? = nil) throws {
        guard writable, let disk else { throw CocoaError(.fileWriteNoPermission) }
        library = try disk.finishCapturePair(cardID: id, back: back, text: text, in: library)
        Task { await sync() }
    }
    func collectScan(_ id: String, match: CardMatch?, folderID: String?, newFolderName: String?) -> Bool {
        let previous = library
        do {
            try library.collectScan(cardID: id, match: match, folderID: folderID, newFolderName: newFolderName)
            try persist()
            Task { await sync() }
            return true
        } catch { library = previous; lastError = "Karte konnte nicht einsortiert werden."; return false }
    }
    func correctAssignment(_ id: String, collectionID: String, number: String) -> Bool {
        let old = library
        do { try library.correctAssignment(cardID: id, collectionID: collectionID, number: number); try persist(); Task { await sync() }; return true }
        catch { library = old; lastError = "Zuordnung konnte nicht gespeichert werden."; return false }
    }
    @discardableResult func saveManualBurnValue(_ amountCents: Int?, currency: String) -> Bool {
        let old = library
        do {
            try library.setManualBurnValue(amountCents: amountCents, currency: currency)
            try persist()
            return true
        } catch { library = old; lastError = "Deine Schätzung konnte nicht gespeichert werden."; return false }
    }
    func toggleCollectible(_ id: String) {
        commit { library in
            if let index = library.cards.firstIndex(where: { $0.id == id }), library.cards[index].isScanDraft != true {
                library.cards[index].isCollectible = library.cards[index].isCollectible != true
            }
        }
    }
    func toggleFavorite(_ id: String) {
        commit { library in
            if let index = library.cards.firstIndex(where: { $0.id == id }) { library.cards[index].isFavorite = library.cards[index].isFavorite != true }
        }
    }
    @discardableResult func savePurchase(_ purchase: CardPurchase) -> Bool {
        guard purchase.isValid else { return false }
        let previous = library
        var purchases = library.purchases ?? []
        if let index = purchases.firstIndex(where: { $0.id == purchase.id }) { purchases[index] = purchase }
        else { purchases.append(purchase) }
        library.purchases = purchases
        do { try persist(); return true }
        catch { library = previous; lastError = "Kauf konnte nicht gespeichert werden."; return false }
    }
    @discardableResult func deletePurchase(_ id: String) -> Bool {
        let previous = library
        library.purchases?.removeAll { $0.id == id }
        do { try persist(); return true }
        catch { library = previous; lastError = "Kauf konnte nicht entfernt werden."; return false }
    }
    func saveMetadata(_ id: String, location: String, notes: String, folderIDs: Set<String>? = nil, newFolderName: String? = nil) -> Bool {
        let old = library
        do {
            guard let index = library.cards.firstIndex(where: { $0.id == id }), location.count <= 200, notes.count <= 5000 else { throw StoreError.invalidResult }
            if let folderIDs { try library.setFolders(cardID: id, folderIDs: folderIDs, newFolderName: newFolderName) }
            library.cards[index].storageLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
            library.cards[index].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            try persist(); return true
        } catch { library = old; lastError = "Notizen konnten nicht gespeichert werden."; return false }
    }
    func receivePairing(_ url: URL) {
        do { pairingCandidate = try Pairing.parse(url); showSettings = true; recordConnectionStatus("candidate") }
        catch { lastError = "Dieser Verbindungscode ist ungültig." }
    }
    func receiveURL(_ url: URL) {
        if let product = MarketSnapshot.deepLinkProduct(url) {
            commit { $0.selectedChaseProductID = product }
            selectedTab = 4
            showMarketRanking = true
        } else { receivePairing(url) }
    }
    func recordMarketView(_ snapshot: MarketSnapshot) {
        // A local delivery receipt for install diagnostics, not provider data or telemetry.
        // No names, prices, images, photos, searches or credentials are written here.
        guard snapshot.isFresh, snapshot.status == "ready",
              let folder = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return }
        let receipt: [String: Any] = ["build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            "productID": snapshot.productID, "revision": snapshot.revision, "pricedCards": snapshot.cards.count,
            "checkedCards": snapshot.checkedCards, "loadedAt": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONSerialization.data(withJSONObject: receipt, options: .sortedKeys) {
            try? data.write(to: folder.appendingPathComponent("cardscout-market-view.json"), options: .atomic)
        }
    }
    func retakePhotos(_ id: String, front: Data?, back: Data?) throws {
        guard writable, let disk else { throw CocoaError(.fileWriteNoPermission) }
        library = try disk.retakePhotos(cardID: id, front: front, back: back, in: library)
        Task { await sync() }
    }
    @discardableResult
    func startUnclearCardQueue() -> Bool {
        guard writable, let disk else { return false }
        var updated = library
        if var queue = updated.unclearCardQueue, queue.currentID != nil {
            queue.reconcile(cards: updated.cards); updated.unclearCardQueue = queue
        } else { updated.unclearCardQueue = UnclearCardQueue(cards: updated.cards) }
        do { try disk.save(updated); library = updated; return true }
        catch { lastError = "Die Liste konnte nicht gespeichert werden. Deine Karten bleiben unverändert."; return false }
    }
    @discardableResult
    func advanceUnclearCardQueue(skipping cardID: String? = nil) -> Bool {
        guard writable, let disk, var queue = library.unclearCardQueue else { return false }
        if let cardID, !queue.skip(cardID: cardID) { return false }
        queue.reconcile(cards: library.cards)
        guard queue != library.unclearCardQueue else { return true }
        var updated = library; updated.unclearCardQueue = queue
        do { try disk.save(updated); library = updated; return true }
        catch { lastError = "Der Fortschritt konnte nicht gespeichert werden. Bitte erneut versuchen."; return false }
    }
    func reanalyze(_ id: String) {
        guard writable, let disk else { return }
        do {
            library = try disk.reanalyze(cardID: id, in: library)
            Task { await sync() }
        } catch { lastError = "Bewertung konnte nicht gestartet werden. Deine Fotos bleiben unverändert." }
    }
    func confirmPairing() {
        guard let candidate = pairingCandidate else { return }
        do { try PairingKeychain.save(candidate); pairing = candidate; client = MacClient(candidate); pairingCandidate = nil; recordConnectionStatus("paired"); Task { await sync() } }
        catch { lastError = "Verbindung konnte nicht sicher gespeichert werden." }
    }
    func retry(_ id: String) {
        guard let client else { showSettings = true; return }
        guard let card = library.cards.first(where: { $0.id == id }) else { return }
        let jobID = card.jobID
        Task {
            do {
                let _: MacJob = try await client.request("/v1/jobs/\(jobID)/retry", method: "POST", body: Data("{}".utf8))
                commit { l in if let i = l.cards.firstIndex(where: { $0.id == id && $0.jobID == jobID }) { l.cards[i].state = "queued"; l.cards[i].error = nil } }
                await sync()
            } catch { lastError = error.localizedDescription }
        }
    }
    func addHunt(_ entry: ChecklistCard, collection: CardCollection) {
        guard !library.hunts.contains(where: { $0.id == collection.id + ":" + entry.number }) else { return }
        commit { $0.hunts.append(HuntCard(id: collection.id + ":" + entry.number, label: "#\(entry.number) \(entry.player)", productName: "\(collection.year) \(collection.name)", player: entry.player, imageURL: entry.imageURL, sourceURL: collection.sourceURL)) }
    }
    func addHunt(_ hot: HotCard) {
        guard !library.hunts.contains(where: { $0.id == hot.id }) else { return }
        commit { $0.hunts.append(HuntCard(id: hot.id, label: hot.label, productName: hot.productName, player: hot.player, imageURL: hot.imageUrl, sourceURL: hot.imageSourceUrl)) }
    }
    func addHunt(_ card: ChaseCard, product: ChaseProduct) {
        commit { _ = $0.addChaseHunt(card, product: product) }
    }
    func refreshChases(revision: String?, force: Bool = false) async {
        let needsMetadataRepair = library.chaseCatalog?.products.contains(where: \.needsOfficialScopeRepair) == true
        guard writable, let client, let revision, !revision.isEmpty,
              force || ((library.chaseCatalog?.revision != revision || needsMetadataRepair) && Date().timeIntervalSince(lastChaseAttempt) > 60)
        else { return }
        lastChaseAttempt = Date()
        do {
            let incoming: ChaseCatalog = try await client.request("/v1/chases")
            guard incoming.revision == revision else { throw StoreError.invalidResult }
            var updated = library; try updated.applyChaseCatalog(incoming)
            let old = library; library = updated
            do { try persist() } catch { library = old; throw error }
            chaseError = nil
        } catch { chaseError = "Preiskatalog gerade nicht aktualisierbar." }
    }
    func reloadChases() async {
        guard let client else { showSettings = true; return }
        do {
            let capabilities: [String: String] = try await client.request("/v1/ping")
            await refreshChases(revision: capabilities["chaseRevision"], force: true)
        } catch { chaseError = "Preiskatalog offline · letzter Stand bleibt gespeichert." }
    }
    func loadMarket(_ productID: String) async {
        guard MarketSnapshot.productIDs.contains(productID), !loadingMarkets.contains(productID) else { return }
        guard let client else { marketErrors[productID] = "Mac oder Server verbinden, um Marktpreise zu laden."; return }
        loadingMarkets.insert(productID)
        defer { loadingMarkets.remove(productID) }
        marketErrors[productID] = nil
        let path = "/v1/market/\(productID)"
        do {
            var snapshot: MarketSnapshot = try await client.request(path)
            try snapshot.validate(for: productID)
            if ["empty", "error"].contains(snapshot.status) {
                snapshot = try await client.request(path, method: "POST", body: Data("{}".utf8))
            }
            let deadline = Date().addingTimeInterval(600)
            while true {
                try snapshot.validate(for: productID)
                markets[productID] = snapshot
                guard snapshot.status == "refreshing" else { break }
                if Date() > deadline { marketErrors[productID] = "Prüfung läuft noch. Zum Aktualisieren herunterziehen."; break }
                try await Task.sleep(for: .seconds(4))
                snapshot = try await client.request(path)
            }
        } catch is CancellationError { }
        catch { marketErrors[productID] = "Marktpreise nicht erreichbar. Verbindung prüfen und erneut laden." }
    }
    func syncLoop() async {
        while !Task.isCancelled {
            await sync()
            do { try await Task.sleep(for: .seconds(library.cards.contains(where: \.isAwaitingAnalysis) ? 2 : 12)) } catch { return }
        }
    }
    func sync() async {
        guard !syncing else { return }
        guard writable, let disk else { return }
        guard let client else { recordConnectionStatus("notPaired"); return }
        for index in library.cards.indices { library.cards[index].analysis = library.cards[index].analysis?.currentPricing() }
        syncing = true; defer { syncing = false; recordReanalysisStatus() }
        recordConnectionStatus("checking")
        do {
            let capabilities: [String: String] = try await client.request("/v1/ping")
            connected = true
            connectionError = nil
            recordConnectionStatus("reachable")
            if !library.importedLegacy {
                let bootstrap: Bootstrap = try await client.request("/v1/bootstrap")
                var incoming: [OwnedCard] = []
                for item in bootstrap.cards where !library.cards.contains(where: { $0.id == item.record.id }) {
                    guard let front = Data(base64Encoded: item.front), UIImage(data: front) != nil else { throw StoreError.missingFront }
                    var card = item.record; card.frontFile = card.id + "-front.jpg"
                    try disk.writePhoto(front, name: card.frontFile)
                    if let encoded = item.back {
                        guard let back = Data(base64Encoded: encoded), UIImage(data: back) != nil else { throw StoreError.missingFront }
                        card.backFile = card.id + "-back.jpg"; try disk.writePhoto(back, name: card.backFile!)
                    }
                    incoming.append(card)
                }
                let old = library
                library.cards.append(contentsOf: incoming)
                library.pendingAcknowledgments = Array(Set((library.pendingAcknowledgments ?? []) + incoming.filter { $0.state == "analyzed" }.map(\.jobID)))
                for set in bootstrap.collections where !library.collections.contains(where: { $0.id == set.id }) { library.collections.append(set) }
                for hunt in bootstrap.hunts where !library.hunts.contains(where: { $0.id == hunt.id }) { library.hunts.append(hunt) }
                library.hotCards = bootstrap.hotCards; library.hotCheckedAt = bootstrap.hotCheckedAt; library.importedLegacy = true
                do { try persist() } catch { library = old; throw error }
            }
            if capabilities["matchPipelineVersion"] == "1" && (!loadedMatchChecklists || loadedReferenceRevision != capabilities["referenceImagesRevision"] || loadedCatalogRevision != capabilities["catalogRevision"]) {
                let checklists: [CardCollection] = try await client.request("/v1/checklists")
                let previous = library
                for checklist in checklists {
                    if let index = library.collections.firstIndex(where: { $0.id == checklist.id }) {
                        if !library.collections[index].checklistComplete || checklist.checklistComplete { library.collections[index] = checklist }
                    } else { library.collections.append(checklist) }
                }
                do { try persist(); loadedMatchChecklists = true; loadedReferenceRevision = capabilities["referenceImagesRevision"]; loadedCatalogRevision = capabilities["catalogRevision"] } catch { library = previous; throw error }
            }
            // One-time upgrade of older assessments, with stable card IDs and unchanged photo files.
            if (Int(capabilities["analysisVersion"] ?? "1") ?? 1) >= OwnedCard.currentAnalysisVersion {
                for id in library.cards.filter(\.needsInsightUpgrade).map(\.id) {
                    library = try disk.reanalyze(cardID: id, in: library)
                }
            }
            for jobID in library.supersededJobIDs ?? [] {
                let _: [String: String] = try await client.request("/v1/jobs/\(jobID)/discard", method: "POST", body: Data("{}".utf8))
                commit { $0.supersededJobIDs?.removeAll { $0 == jobID } }
            }
            // Snapshot IDs only. Main-actor operations may interleave with camera imports or retakes.
            // A failed job may have been repaired/retried by the worker. Fetch
            // its current state without automatically submitting another scan.
            let waiting = library.cards.filter { $0.isAwaitingAnalysis || $0.state == "failed" }
            let fastSupported = capabilities["fastPipelineVersion"] == "1"
            let matchSupported = capabilities["matchPipelineVersion"] == "1"
            // Three requests at a time. All results still commit on the main actor.
            // A broken card cannot starve the rest of a hundred-card capture session.
            for offset in stride(from: 0, to: waiting.count, by: 3) {
                let batch = Array(waiting[offset..<min(offset + 3, waiting.count)])
                let responses = await withTaskGroup(of: (OwnedCard, Result<MacJob, Error>).self) { group in
                    for card in batch {
                        group.addTask {
                            do {
                                let job: MacJob
                                if card.state == "queued" && card.uploadedJobID != card.jobID { job = try await client.submit(card, disk: disk, fastSupported: fastSupported, matchSupported: matchSupported) }
                                else {
                                    do { job = try await client.request("/v1/jobs/\(card.jobID)") }
                                    catch where card.state != "failed" && (error as NSError).domain == "CardScout" && (error as NSError).code == 404 {
                                        job = try await client.submit(card, disk: disk, fastSupported: fastSupported, matchSupported: matchSupported)
                                    }
                                }
                                return (card, .success(job))
                            } catch { return (card, .failure(error)) }
                        }
                    }
                    var results: [(OwnedCard, Result<MacJob, Error>)] = []
                    for await value in group { results.append(value) }
                    return results
                }
                var offline = false
                for (card, response) in responses {
                    switch response {
                    case .success(let job):
                        guard job.id == card.jobID else { throw StoreError.invalidResult }
                        guard let current = library.cards.first(where: { $0.id == card.id && $0.jobID == card.jobID }) else { continue }
                        let changed = current.uploadedJobID != job.id || current.state != job.status ||
                            (job.analysis != nil && current.analysis != job.analysis) || current.error != job.error || current.matchSuggestions != job.matches || current.matchNotice != job.matchNotice ||
                            (job.collection != nil && !library.collections.contains(job.collection!))
                        guard changed else { continue }
                        let old = library
                        guard try library.applyJobResult(cardID: card.id, jobID: card.jobID, status: job.status, analysis: job.analysis, collection: job.collection, error: job.error) else { continue }
                        if let index = library.cards.firstIndex(where: { $0.id == card.id }) { library.cards[index].uploadedJobID = job.id; library.cards[index].matchSuggestions = job.matches; library.cards[index].matchNotice = job.matchNotice }
                        do { try persist() } catch { library = old; throw error }
                    case .failure(let error):
                        let failure = error as NSError
                        if failure.domain == NSURLErrorDomain { offline = true; connected = false }
                        else if failure.code != 429 && library.cards.first(where: { $0.id == card.id && $0.jobID == card.jobID })?.error != error.localizedDescription {
                            commit { library in
                                if let index = library.cards.firstIndex(where: { $0.id == card.id && $0.jobID == card.jobID }) { library.cards[index].error = error.localizedDescription }
                            }
                        }
                    }
                }
                if offline { break }
            }
            // Retry cleanup after interruptions, but only for analyses already persisted on the phone.
            for id in library.pendingAcknowledgments ?? [] {
                let _: [String: String] = try await client.request("/v1/jobs/\(id)/ack", method: "POST", body: Data("{}".utf8))
                commit { $0.pendingAcknowledgments?.removeAll { $0 == id } }
            }
            // Fill missing estimates in the background, once per job per session.
            // The worker reuses fresh results and enforces shared provider limits.
            let priceSlots = max(0, 6 - loadingCardPrices.count)
            for card in library.cards.filter({ $0.hasCurrentAnalysis && !dashboardValueCache.isFresh($0) && (!hydratedCardPriceJobs.contains($0.jobID) || (nextPriceChecks[$0.jobID].map { $0 <= Date() } ?? false)) }).prefix(priceSlots) {
                hydratedCardPriceJobs.insert(card.jobID)
                nextPriceChecks.removeValue(forKey: card.jobID)
                Task { await loadCardPrices(card.id) }
            }
            // Reference refresh is optional and never blocks photo submission or result persistence.
            await refreshChases(revision: capabilities["chaseRevision"])
            recordPortfolioObservation()
        } catch {
            connected = false
            connectionError = connectionMessage(error)
            recordConnectionStatus("failed", error: error)
            // An offline Mac is normal; uploads remain durable and are retried on foreground.
            if (error as NSError).domain != NSURLErrorDomain { lastError = error.localizedDescription }
        }
    }

    private func recordPortfolioObservation() {
        guard writable, loadingCardPrices.isEmpty,
              client == nil || library.collectedCards.filter({ $0.hasCurrentAnalysis && $0.analysis?.identityConfirmed == true && $0.analysis?.knownIdentityConflict == nil }).allSatisfy({ observedPriceJobs.contains($0.jobID) || dashboardValueCache.isFresh($0) }) else { return }
        let old = library.portfolioHistory
        guard library.recordPortfolioObservation(cachedValues: dashboardValueCache.portfolioValues(in: library)) else { return }
        do { try persist() }
        catch { library.portfolioHistory = old; lastError = "Wertverlauf konnte nicht gespeichert werden." }
    }

    func loadCardPrices(_ cardID: String, cachedOnly: Bool = false) async {
        guard let client, let card = library.cards.first(where: { $0.id == cardID }), card.hasCurrentAnalysis,
              loadingCardPrices.insert(card.jobID).inserted else { return }
        defer {
            loadingCardPrices.remove(card.jobID)
            recordPortfolioObservation()
        }
        do {
            var job: MacJob
            if cachedOnly { job = try await client.request("/v1/jobs/\(card.jobID)") }
            else { job = try await client.request("/v1/jobs/\(card.jobID)/prices", method: "POST", body: Data("{}".utf8)) }
            priceStates[card.jobID] = job.priceStatus ?? "empty"
            for _ in 0..<25 where !cachedOnly && job.priceStatus == "refreshing" {
                try await Task.sleep(for: .seconds(1))
                job = try await client.request("/v1/jobs/\(card.jobID)")
            }
            priceStates[card.jobID] = job.priceStatus ?? "empty"
            if ["no_match", "unavailable"].contains(job.priceStatus ?? "") {
                // Refresh the cached view as the peer-price pool grows. The server's
                // 24-hour result cache prevents another external lookup.
                nextPriceChecks[card.jobID] = Date().addingTimeInterval(60)
            }
            if job.priceStatus == "refreshing" {
                hydratedCardPriceJobs.remove(card.jobID)
                return
            }
            guard !Task.isCancelled, job.id == card.jobID, job.status == "analyzed",
                  let incoming = job.analysis, incoming.identityConfirmed == true,
                  let index = library.cards.firstIndex(where: { $0.id == cardID && $0.jobID == card.jobID }),
                  let current = library.cards[index].analysis,
                  current.player == incoming.player, current.year == incoming.year, current.setName == incoming.setName,
                  current.subset == incoming.subset, current.cardNumber == incoming.cardNumber,
                  current.parallel == incoming.parallel, current.serialNumber == incoming.serialNumber else { return }
            observedPriceJobs.insert(card.jobID)
            // Only pricing changes here. Identity, photos and saved assessment stay intact.
            var updated = current
            updated.comparableEstimate = incoming.comparableEstimate
            let expiries = (incoming.insights?.marketReferences.compactMap(\.expiresAt) ?? []) + [incoming.comparableEstimate?.expiresAt].compactMap { $0 }
            if let expiry = expiries.min(), ["ready", "estimate"].contains(job.priceStatus ?? "") {
                nextPriceChecks[card.jobID] = Date(timeIntervalSince1970: expiry + 1)
            }
            if let info = incoming.insights, var existing = updated.insights {
                existing.marketReferences = info.marketReferences
                existing.marketBullets = info.marketBullets
                existing.sourceChecks = info.sourceChecks
                updated.insights = existing
                updated.marketCheckedAt = incoming.marketCheckedAt
                updated.marketLowCents = incoming.marketLowCents; updated.marketHighCents = incoming.marketHighCents
                updated.marketSources = incoming.marketSources
                library.cards[index].analysis = updated.currentPricing()
                // Delivery-only diagnostics: no card IDs, prices, source URLs,
                // names, photos or credentials. Not part of the saved library.
                if let disk {
                    let counts = library.cards.map { card in
                        card.analysis?.insights?.marketReferences.filter { ["CardSight", "Slabline", "Midpoint"].contains($0.provider) && $0.isFresh() }.count ?? 0
                    }
                    let receipt: [String: Any] = ["build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                        "cardsWithFreshPrices": counts.filter { $0 > 0 }.count, "referenceCount": counts.reduce(0, +),
                        "ownedCards": library.collectedCards.count,
                        "priceStates": Dictionary(grouping: priceStates.values, by: { $0 }).mapValues(\.count),
                        "attemptedPriceJobs": hydratedCardPriceJobs.count,
                        "cardsNeedingIdentityReview": library.collectedCards.filter { ReviewIssue.identity($0) != nil }.count,
                        "cardsWithComparisonEstimates": library.collectedCards.filter { $0.analysis?.marketSummary?.isComparable == true }.count,
                        "cardsWithGuideEstimates": library.cards.filter { card in
                            card.analysis?.insights?.marketReferences.contains { ["Slabline", "Midpoint"].contains($0.provider) && $0.kind == "guide" && $0.isFresh() } == true
                        }.count,
                        "checkedAt": ISO8601DateFormatter().string(from: Date())]
                    if let bytes = try? JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]) {
                        try? bytes.write(to: disk.root.appendingPathComponent("card-price-status.json"), options: [.atomic, .completeFileProtection])
                    }
                }
            } else { library.cards[index].analysis = updated.currentPricing() }
            if ["ready", "estimate", "no_match"].contains(job.priceStatus ?? "") {
                // A failed connection never clears the last displayed amount.
                // A completed empty result can remove a previous estimate.
                let value = CollectionStatistics(library: library).values.first { $0.cardID == cardID }
                dashboardValueCache.update(card: library.cards[index], value: value,
                    refreshAfter: nextPriceChecks[card.jobID] ?? Date().addingTimeInterval(86400),
                    portfolioValue: library.portfolioValues().first { $0.cardID == cardID })
                try? disk?.saveDashboardValues(dashboardValueCache)
            }
        } catch {
            // A transport failure is not a completed lookup. Retry after a short
            // delay, including when the phone was locked during hydration.
            priceStates[card.jobID] = "unavailable"
            nextPriceChecks[card.jobID] = Date().addingTimeInterval(30)
        }
    }
}
