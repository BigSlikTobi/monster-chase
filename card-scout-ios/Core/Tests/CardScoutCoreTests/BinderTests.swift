import XCTest
@testable import CardScoutCore

final class BinderTests: XCTestCase {
    private func collection(_ id: String, _ name: String, year: Int = 2025, subset: String = "Base") -> CardCollection {
        CardCollection(id: id, name: name, year: year, brand: "Fixture", subset: subset, cards: [])
    }

    func testFamiliesContainYearsAndTypesWithoutChangingChecklistIdentity() {
        let sets = [collection("base", "Bowman Football"), collection("chrome", "Bowman Chrome", subset: "Chrome"),
                    collection("old", "Bowman Football", year: 2024), collection("optic", "Donruss Optic"),
                    collection("donruss", "Donruss"), collection("select", "Select"), collection("prizm", "Prizm")]
        let binders = CollectionBinder.group(sets)
        XCTAssertEqual(binders.count, 4)
        let bowman = binders.first { $0.name == "Bowman Football" }!
        XCTAssertEqual(Set(bowman.collections.map(\.id)), ["base", "chrome", "old"])
        XCTAssertEqual(bowman.collections.last?.year, 2024)
        XCTAssertEqual(binders.first { $0.name == "Donruss" }?.collections.count, 2)
        XCTAssertEqual(CollectionBinder.group(sets.reversed()).map(\.id), binders.map(\.id))
    }

    func testCountsKeepCopiesAndExcludeDraftsAndUnassignedCards() {
        var library = Library()
        library.collections = [collection("base", "Bowman Football")]
        var analysis = CardAnalysis(recommendation: "Keep", marketCheckedAt: "", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        analysis.collectionID = "base"
        let first = OwnedCard(analysis: analysis)
        var draft = OwnedCard(analysis: analysis); draft.isScanDraft = true
        library.cards = [first, OwnedCard(analysis: analysis), draft, OwnedCard()]
        XCTAssertEqual(library.binders[0].cards(in: library).count, 2)
    }

    func testCollectiblesPersistIndependentlyOfFavoritesAndSurviveAnalysisUpdate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        var card = OwnedCard(); card.isCollectible = true; card.isFavorite = false
        var draft = OwnedCard(); draft.isCollectible = true; draft.isScanDraft = true
        var library = Library(); library.cards = [card, draft]
        let analysis = CardAnalysis(recommendation: "Keep", marketCheckedAt: "", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        try library.applyJobResult(cardID: card.id, jobID: card.jobID, status: "analyzed", analysis: analysis, collection: nil, error: nil)
        try disk.save(library)
        let reloaded = try disk.load()
        XCTAssertEqual(reloaded.collectibles.map(\.id), [card.id])
        XCTAssertEqual(reloaded.cards[0].isFavorite, false)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(card)) as! [String: Any]
        object.removeValue(forKey: "isCollectible")
        XCTAssertNil(try JSONDecoder().decode(OwnedCard.self, from: JSONSerialization.data(withJSONObject: object)).isCollectible)
    }
}
