import XCTest
@testable import CardScoutCore

final class ChaseTests: XCTestCase {
    func catalog() throws -> ChaseCatalog {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(ChaseCatalog.self, from: Data(contentsOf: root.appendingPathComponent("mac/data/chases.json")))
    }
    func testSeedCombinesFourGuideSelectionsWithOfficialToppsChases() throws {
        let c = try catalog(); try c.validate()
        XCTAssertEqual(c.products.count, 5)
        XCTAssertEqual(c.products.first?.title, "Donruss Optic 2025")
        XCTAssertEqual(c.products[1].title, "Topps Flagship Football 2026")
        XCTAssertEqual(Set(c.products.flatMap(\.cards).map(\.id)).count, 733)
        let topps = c.products[1]
        XCTAssertTrue(topps.hasOfficialChaseChecklist)
        XCTAssertEqual(topps.coverageLabel, "Offizielle Chase-Liste · 693 Karten")
        XCTAssertEqual(topps.cards.count, 693)
        XCTAssertTrue(topps.cards.allSatisfy { $0.valueLabel == nil && $0.imageURL == nil })
        let guideCards = c.products.enumerated().filter { $0.offset != 1 }.flatMap { $0.element.cards }
        XCTAssertEqual(guideCards.count, 40)
        XCTAssertTrue(guideCards.allSatisfy { $0.valueLabel != nil && $0.imageURL != nil })
        XCTAssertNotNil(topps.cards.first { $0.number == "FFS-FM" && $0.player == "Fernando Mendoza" })
        XCTAssertNotNil(topps.cards.first { $0.number == "SBCS-TBRA" && $0.player == "Tom Brady" })
    }
    func testExistingLibrariesDecodeWithoutCatalogOrSelection() throws {
        let data = Data(#"{"version":1,"cards":[],"collections":[],"hunts":[],"hotCards":[],"importedLegacy":true}"#.utf8)
        let library = try JSONDecoder().decode(Library.self, from: data)
        XCTAssertNil(library.chaseCatalog); XCTAssertNil(library.selectedChaseProductID)
    }
    func testCatalogUpdatesPreservePhotosAnalysesJobsAndHuntState() throws {
        var l = Library()
        l.cards = [OwnedCard(state: "processing", frontFile: "original.jpg", backFile: "back.jpg")]
        l.hunts = [HuntCard(id: "existing", label: "Existing", productName: "Existing", status: "found")]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(l.cards), hunts = l.hunts
        let c = try catalog(); try l.applyChaseCatalog(c)
        XCTAssertEqual(try encoder.encode(l.cards), before)
        XCTAssertEqual(l.hunts, hunts)
        XCTAssertEqual(l.selectedChaseProductID, c.products.first?.id)
        XCTAssertEqual(OwnedCard.currentAnalysisVersion, 3)
    }
    func testSelectionAndCatalogSurviveDiskReloadAndRefresh() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        var l = Library(); let c = try catalog(); try l.applyChaseCatalog(c)
        l.selectedChaseProductID = c.products[1].id
        try l.applyChaseCatalog(c); try disk.save(l)
        let loaded = try disk.load()
        XCTAssertEqual(loaded.chaseCatalog, c)
        XCTAssertEqual(loaded.selectedChaseProductID, c.products[1].id)
    }
    func testInvalidSnapshotDoesNotReplaceLastGoodCatalog() throws {
        let c = try catalog(); var l = Library(); try l.applyChaseCatalog(c)
        var bad = c; bad.products[0].cards[1].id = bad.products[0].cards[0].id
        XCTAssertThrowsError(try l.applyChaseCatalog(bad)); XCTAssertEqual(l.chaseCatalog, c)
        bad = c; bad.products[0].cards.removeLast()
        XCTAssertThrowsError(try bad.validate())
        bad = c; bad.products[0].licenseScope = "unlicensed"
        XCTAssertThrowsError(try bad.validate())
        bad = c; bad.products[0].cards[0].priceSourceURL = nil
        XCTAssertThrowsError(try bad.validate())
    }
    func testLookoutIsIdempotentAndDoesNotResetFoundStatus() throws {
        let c = try catalog(); var l = Library(); let product = c.products[0], card = product.cards[0]
        XCTAssertTrue(l.addChaseHunt(card, product: product))
        l.hunts[0].status = "found"
        XCTAssertFalse(l.addChaseHunt(card, product: product))
        XCTAssertEqual(l.hunts.count, 1); XCTAssertEqual(l.hunts[0].status, "found")
        XCTAssertFalse(l.addChaseHunt(card, product: c.products[1]))
    }

    func testOfficialCardRecognizesAnExistingMarketLookoutWithoutMutatingIt() throws {
        let product = try catalog().products[1]
        let official = try XCTUnwrap(product.cards.first { $0.number == "FFS-FM" && $0.variant == "Flagship First Signatures" })
        var library = Library()
        let existing = HuntCard(id: product.id + ":cardsight:legacy", label: official.label,
                                productName: product.title, player: official.player, status: "found")
        library.hunts = [existing]
        XCTAssertTrue(library.hasChaseHunt(official, product: product))
        XCTAssertFalse(library.addChaseHunt(official, product: product))
        XCTAssertEqual(library.hunts, [existing])
    }
    func testCollectionJumpMatchesYearBrandAndProductNotParallel() throws {
        let product = try catalog().products[0]
        var set = CardCollection(id: "any", name: "Donruss Optic", year: 2025, brand: "Panini", parallel: "Holo", cards: [])
        XCTAssertTrue(product.matches(set))
        set.year = 2024; XCTAssertFalse(product.matches(set))
        set.year = 2025; set.name = "Donruss"; XCTAssertFalse(product.matches(set))
    }
    func testRanksDoNotAffectLookoutIdentity() throws {
        var c = try catalog(); let before = Set(c.products[0].cards.map(\.id))
        c.products[0].cards.reverse()
        for i in c.products[0].cards.indices { c.products[0].cards[i].rank = i + 1 }
        try c.validate(); XCTAssertEqual(Set(c.products[0].cards.map(\.id)), before)
    }

    func testOfficialChasesMergeWithSalesWithoutDroppingUnpricedCards() throws {
        let product = try catalog().products[1]
        let official = try XCTUnwrap(product.cards.first { $0.variant == "All Kings" && $0.number == "AK-16" })
        var sold = official
        sold.id = product.id + ":cardsight:sold-all-kings"
        sold.priceCents = 167_500; sold.currency = "USD"; sold.priceKind = "sold_median"
        sold.priceSourceURL = "https://showme.cards/abcde"; sold.priceCheckedAt = "2026-09-12"
        sold.saleCount = 2; sold.saleLowCents = 160_000; sold.saleHighCents = 175_000
        sold.sales = [ChaseSale(priceCents: 160_000, date: "2026-09-10", url: "https://showme.cards/abcde")]
        sold.sourceURL = sold.priceSourceURL!; sold.imageURL = "https://i.ebayimg.com/images/test.jpg"; sold.imageKind = "scan"
        var extra = sold
        extra.id = product.id + ":cardsight:base-extra"; extra.variant = "Base Set"; extra.number = "1"; extra.player = "Marvin Harrison Jr."
        let merged = product.mergingMarketCards([sold, extra])
        XCTAssertEqual(merged.cards.count, 694)
        let overlaid = try XCTUnwrap(merged.cards.first { $0.id == official.id })
        XCTAssertEqual(overlaid.priceCents, 167_500)
        XCTAssertEqual(overlaid.sourceURL, official.sourceURL)
        XCTAssertEqual(overlaid.imageURL, sold.imageURL)
        XCTAssertNotNil(merged.cards.first { $0.id == extra.id })
        let ranking = ChaseRanking(cards: merged.cards, sold: true)
        XCTAssertEqual(ranking.priced.count, 2)
        XCTAssertEqual(ranking.unknown.count, 692)
    }

    func testOfficialChaseFamiliesAreCompleteAndExcludeMarketExtras() throws {
        let product = try catalog().products[1]
        XCTAssertEqual(product.officialChaseCards().count, 693)
        XCTAssertEqual(product.officialChaseCards(family: .goldenMirror).count, 420)
        XCTAssertEqual(product.officialChaseCards(family: .autograph).count, 119)
        XCTAssertEqual(product.officialChaseCards(family: .relic).count, 74)
        XCTAssertEqual(product.officialChaseCards(family: .allKings).count, 30)
        XCTAssertEqual(product.officialChaseCards(family: .rookie1957).count, 50)
        XCTAssertEqual(
            ToppsChaseFamily.allCases.dropFirst().reduce(0) { $0 + product.officialChaseCards(family: $1).count },
            693
        )

        var marketExtra = try XCTUnwrap(product.cards.first)
        marketExtra.id = product.id + ":cardsight:market-only"
        marketExtra.variant = "Base Set"
        marketExtra.number = "999"
        let merged = product.mergingMarketCards([marketExtra])
        XCTAssertEqual(merged.cards.count, 694)
        XCTAssertEqual(merged.officialChaseCards().count, 693)
        XCTAssertFalse(merged.officialChaseCards().contains { $0.id == marketExtra.id })
    }

    func testBuild10ToppsSnapshotWithoutScopeStillOpensChaseView() throws {
        var product = try catalog().products[1]
        product.coverage?.scope = nil

        XCTAssertTrue(product.hasOfficialChaseChecklist)
        XCTAssertTrue(product.needsOfficialScopeRepair)
        XCTAssertEqual(product.officialChaseCards().count, 693)

        product.cards[0].id = product.id + ":legacy:wrong-source"
        XCTAssertFalse(product.hasOfficialChaseChecklist)
        XCTAssertFalse(product.needsOfficialScopeRepair)
    }

    func testEveryOfficialToppsChaseHasHonestVisualArtwork() throws {
        let product = try catalog().products[1]
        let references = product.cards.compactMap { product.imageReference(for: $0) }

        XCTAssertEqual(references.count, 693)
        XCTAssertTrue(references.allSatisfy(\.isRepresentative))
        XCTAssertTrue(references.allSatisfy { URL(string: $0.url)?.host == "images.contentstack.io" })
        XCTAssertTrue(references.allSatisfy { $0.sourceURL == "https://www.topps.com/pages/topps-flagship-football" })
        XCTAssertEqual(Set(references.map(\.url)).count, 9)

        var exact = product.cards[0]
        exact.imageURL = "https://i.ebayimg.com/images/example.jpg"
        exact.imageKind = "scan"
        let exactReference = try XCTUnwrap(product.imageReference(for: exact))
        XCTAssertFalse(exactReference.isRepresentative)
        XCTAssertEqual(exactReference.url, exact.imageURL)
    }

    func testDuplicateOfficialNumbersNeedTheExactPlayerBeforeMerging() throws {
        let product = try catalog().products[1]
        let stafford = try XCTUnwrap(product.cards.first { $0.variant == "League Leaders Golden Mirror Image Variations" && $0.number == "281" && $0.player == "Matthew Stafford" })
        var sold = stafford
        sold.id = product.id + ":cardsight:stafford"; sold.priceCents = 10_000; sold.currency = "USD"; sold.priceKind = "single_sale"
        sold.player = "Different Player"
        let merged = product.mergingMarketCards([sold])
        XCTAssertEqual(merged.cards.count, 694)
        XCTAssertNil(merged.cards.first { $0.id == stafford.id }?.priceCents)
        XCTAssertNotNil(merged.cards.first { $0.id == sold.id })
    }
}
