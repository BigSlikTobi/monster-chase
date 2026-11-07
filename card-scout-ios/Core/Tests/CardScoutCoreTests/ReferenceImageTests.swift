import XCTest
@testable import CardScoutCore

final class ReferenceImageTests: XCTestCase {
    func fixture() -> (CardCollection, ChecklistCard, CardReferenceImage) {
        let entry = ChecklistCard(number: "267", player: "Trey Amos", team: "Washington Commanders")
        let collection = CardCollection(id: "optic-blue", name: "Donruss Optic", year: 2025, brand: "Panini", parallel: "Blue Hyper", cards: [entry])
        let ref = CardReferenceImage(collectionID: collection.id, year: 2025, brand: "Panini", product: "Donruss Optic", subset: "Base", parallel: "Blue Hyper", number: "267", player: "Trey Amos", frontURL: "https://i.ebayimg.com/images/g/test/s-l1600.jpg", sourceURL: "https://www.ebay.com/itm/123", sourceTitle: "Exact source", reviewedAt: "2026-10-16", sha256: String(repeating: "a", count: 64))
        return (collection, entry, ref)
    }

    func testExactIdentityRequiredAcrossYearProductNumberAndFinish() {
        let (collection, entry, ref) = fixture()
        XCTAssertTrue(ref.matches(collection, entry: entry))
        var wrong = collection; wrong.parallel = "Fire"
        XCTAssertFalse(ref.matches(wrong, entry: entry))
        wrong = collection; wrong.year = 2024
        XCTAssertFalse(ref.matches(wrong, entry: entry))
        wrong = collection; wrong.name = "Donruss"
        XCTAssertFalse(ref.matches(wrong, entry: entry))
        var other = entry; other.number = "369"
        XCTAssertFalse(ref.matches(collection, entry: other))
        other = entry; other.player = "Dont'e Thornton Jr."
        XCTAssertFalse(ref.matches(collection, entry: other))
    }

    func testVariantExampleMustResolveToAnActualRowInTheSameBinder() {
        var (collection, _, ref) = fixture()
        collection.referenceExample = ref
        XCTAssertNotNil(collection.validReferenceExample)
        collection.parallel = "Holo"
        XCTAssertNil(collection.validReferenceExample)
        collection.parallel = "Blue Hyper"; collection.cards = []
        XCTAssertNil(collection.validReferenceExample)
    }

    func testReferencePersistsWithoutChangingOwnershipOrLegacyPhotoFields() throws {
        var (collection, entry, ref) = fixture()
        entry.referenceImage = ref; collection.cards = [entry]
        var library = Library(); library.collections = [collection]
        let restored = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.collections[0].cards[0].exactReference(in: collection), ref)
        XCTAssertNil(restored.collections[0].cards[0].imageURL)
        XCTAssertTrue(restored.cards.isEmpty)
        XCTAssertEqual(restored.collections[0].ownedCount(in: restored.cards), 0)
        let old = Data(#"{"number":"267","player":"Trey Amos","team":"Commanders","rookie":true}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ChecklistCard.self, from: old).referenceImage)
    }

    func testUnsafeOrUnscopedSourcesAreNotDisplayable() {
        let (collection, entry, original) = fixture()
        for url in ["http://i.ebayimg.com/a.jpg", "https://127.0.0.1/a.jpg", "https://i.ebayimg.com@evil.test/a.jpg", "https://cdn.shopify.com/unknown-account/a.jpg"] {
            var ref = original; ref.frontURL = url
            XCTAssertFalse(ref.matches(collection, entry: entry))
        }
        var ref = original; ref.reviewedAt = ""
        XCTAssertFalse(ref.matches(collection, entry: entry))
    }

    func testPlainAnalysisChecklistDoesNotEraseValidReferences() throws {
        var (collection, entry, ref) = fixture()
        entry.referenceImage = ref; collection.cards = [entry]
        var library = Library(); library.collections = [collection]
        var incoming = collection; incoming.cards[0].referenceImage = nil
        let analysis = CardAnalysis(recommendation: "Keep", marketCheckedAt: "", marketSources: [], confidence: "low", conditionNotes: "", rationale: "", needsReview: true)
        let card = OwnedCard(frontFile: "own-photo.jpg")
        library.cards = [card]
        XCTAssertTrue(try library.applyJobResult(cardID: card.id, jobID: card.jobID, status: "identified", analysis: analysis, collection: incoming, error: nil))
        XCTAssertEqual(library.collections[0].cards[0].referenceImage, ref)
        XCTAssertEqual(library.cards[0].frontFile, "own-photo.jpg")
    }
}
