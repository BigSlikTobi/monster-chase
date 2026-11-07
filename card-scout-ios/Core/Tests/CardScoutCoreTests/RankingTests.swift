import XCTest
@testable import CardScoutCore

final class RankingTests: XCTestCase {
    func sample(_ id: String, _ cents: Int?, player: String? = nil) throws -> ChaseCard {
        var card = try ChaseTests().catalog().products[0].cards[0]
        card.id = "2025-panini-donruss-optic:" + id
        card.player = player ?? id; card.priceCents = cents
        return card
    }
    func testStrictThresholdsAndNoTenCardLimit() throws {
        let cards = try (1...30).map { try sample("card\($0)", $0 * 1000) }
        let ranking = ChaseRanking(cards: cards)
        XCTAssertEqual(ranking.matching(ChaseFilter()).count, 30)
        XCTAssertEqual(ranking.matching(ChaseFilter(minimumCents: 5000)).count, 25)
        XCTAssertEqual(ranking.matching(ChaseFilter(minimumCents: 10000)).count, 20)
        XCTAssertEqual(ranking.matching(ChaseFilter(minimumCents: 20000)).count, 10)
        XCTAssertEqual(ranking.matching(ChaseFilter(minimumCents: 30000)).count, 0)
    }
    func testCeeDeeIsAboveHunterOnTheSameGuideBasis() throws {
        let lamb = try sample("lamb", 36000, player: "CeeDee Lamb")
        let hunter = try sample("hunter", 33500, player: "Travis Hunter")
        let ranking = ChaseRanking(cards: [hunter, lamb])
        XCTAssertEqual(ranking.priced.map(\.card.player), ["CeeDee Lamb", "Travis Hunter"])
        XCTAssertEqual(ranking.priced.map(\.rank), [1, 2])
    }
    func testUnknownPricesNeverPassAMonetaryThreshold() throws {
        let ranking = ChaseRanking(cards: [try sample("priced", 10000), try sample("unknown", nil)])
        XCTAssertEqual(ranking.matching(ChaseFilter()).count, 1)
        XCTAssertEqual(ranking.matching(ChaseFilter(minimumCents: 10000)).count, 0)
        XCTAssertEqual(ranking.unknown.count, 1)
        XCTAssertNil(ranking.unknown[0].rank)
        XCTAssertEqual(ranking.unknownMatching(query: "unknown").count, 1)
    }
    func testCurrencyOrSoldComparisonsCannotEnterGuideRanking() throws {
        var sold = try sample("sold", 100000); sold.priceKind = "sold"
        var eur = try sample("eur", 200000); eur.currency = "EUR"
        let ranking = ChaseRanking(cards: [sold, eur, try sample("guide", 5000)])
        XCTAssertEqual(ranking.priced.map(\.card.player), ["guide"])
    }
    func testTiesHaveEqualRanksAndDeterministicOrdering() throws {
        let cards = try [sample("b", 5000), sample("a", 5000), sample("c", 1000)]
        let ranking = ChaseRanking(cards: cards)
        XCTAssertEqual(ranking.priced.map(\.card.player), ["a", "b", "c"])
        XCTAssertEqual(ranking.priced.map(\.rank), [1, 1, 3])
        XCTAssertEqual(ChaseRanking(cards: cards.reversed()).priced, ranking.priced)
    }
    func testSearchKeepsTheCatalogRank() throws {
        let ranking = ChaseRanking(cards: [try sample("first", 10000), try sample("second", 8000)])
        XCTAssertEqual(ranking.matching(ChaseFilter(), query: " SECOND ").first?.rank, 2)
    }
    func testDecimalInputIsExactAndRejectsAmbiguousOrInvalidAmounts() {
        for (text, cents) in [("50", 5000), ("99.95", 9995), ("99,95", 9995), (" 200.50 ", 20050), ("0", 0)] {
            XCTAssertEqual(ChaseFilter.parseDollars(text), cents)
        }
        for text in ["-1", "", "NaN", "1e3", "1.001", "1,000", "1,000.00", "10000000", "$50"] {
            XCTAssertNil(ChaseFilter.parseDollars(text), text)
        }
    }
    func testPerProductFiltersSurviveRestartWithoutChangingCards() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root); var library = Library()
        library.cards = [OwnedCard(state: "analyzed", frontFile: "keep.jpg")]
        library.setChaseFilter(ChaseFilter(minimumCents: 5000), for: "optic")
        library.setChaseFilter(ChaseFilter(minimumCents: 20000), for: "flagship")
        library.setChaseFilter(ChaseFilter(minimumCents: -1), for: "optic")
        try disk.save(library); let loaded = try disk.load()
        XCTAssertEqual(loaded.chaseFilter(for: "optic").minimumCents, 5000)
        XCTAssertEqual(loaded.chaseFilter(for: "flagship").minimumCents, 20000)
        XCTAssertEqual(loaded.cards.first?.frontFile, "keep.jpg")
    }
    func testV2CatalogAcceptsMoreThanTenButRequiresCoverage() throws {
        var catalog = try ChaseTests().catalog(); catalog.version = 2
        for i in catalog.products.indices {
            catalog.products[i].coverage = ChaseCoverage(status: "partial", sourceName: "SportsCardsPro", sourceURLs: [catalog.products[i].sourceURL], cardCount: catalog.products[i].cards.count)
        }
        var card = catalog.products[0].cards[0]; card.id += ":extra"; card.rank = 11
        catalog.products[0].cards.append(card); catalog.products[0].coverage?.cardCount = 11
        try catalog.validate()
        catalog.products[0].coverage = nil
        XCTAssertThrowsError(try catalog.validate())
    }
    func testLargeCatalogRanking() throws {
        let template = try sample("template", 100)
        let cards = (0..<15000).map { i -> ChaseCard in
            var card = template; card.id = "entry\(i)"; card.priceCents = i + 1; return card
        }
        let ranking = ChaseRanking(cards: cards)
        XCTAssertEqual(ranking.priced.count, 15000)
        XCTAssertEqual(ranking.matching(ChaseFilter(minimumCents: 10000)).count, 5000)
    }
}
