import XCTest
@testable import CardScoutCore

final class CardIdentityReviewTests: XCTestCase {
    func testMissingCatalogAndServiceFailureDoNotRequestRetakes() {
        var card = knownCard(); card.matchNotice = "catalog_missing"
        XCTAssertNil(CardIdentityReview(card: card).photoGuidance)
        XCTAssertEqual(ReviewIssue.identity(card)?.title, "Katalogabgleich offen")
        card.matchNotice = nil; card.state = "failed"
        XCTAssertNil(CardIdentityReview(card: card).photoGuidance)
    }
    func testVariantAmbiguityAloneDoesNotDemandAnotherPhoto() {
        var card = knownCard(); card.analysis?.uncertainties = ["Base oder Holo unklar."]
        XCTAssertNil(CardIdentityReview(card: card).photoGuidance)
        card.analysis?.uncertainties = ["Seriennummer durch Spiegelung nicht lesbar."]
        XCTAssertEqual(CardIdentityReview(card: card).recommendedSide, .back)
        XCTAssertNotNil(CardIdentityReview(card: card).photoGuidance)
    }
    private func knownCard() -> OwnedCard {
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "2026-10-16", marketSources: [], confidence: "medium", conditionNotes: "", rationale: "", needsReview: true)
        a.player = "Jalen Ramsey"; a.year = 2025; a.brand = "Topps"; a.setName = "Topps Chrome"
        a.subset = "Base"; a.cardNumber = "191"; a.licenseScope = "nfl_and_nflpa"; a.identityConfirmed = false
        return OwnedCard(state: "analyzed", frontFile: "front.jpg", backFile: "back.jpg", analysis: a)
    }
    func testMissingBackIsFirstStepWithoutRequiringACollection() {
        var card = knownCard(); card.backFile = nil
        card.analysis?.year = nil; card.analysis?.cardNumber = nil; card.analysis?.collectionID = nil
        let review = CardIdentityReview(card: card)
        XCTAssertEqual(review.recommendedSide, .back)
        XCTAssertEqual(review.missingFields, ["Jahrgang", "Kartennummer"])
        XCTAssertNil(card.analysis?.collectionID)
        XCTAssertEqual(card.analysis?.identityConfirmed, false)
    }
    func testUnreadableNameWithBothPhotosRecommendsFront() {
        var card = knownCard(); card.analysis?.player = "  "
        let review = CardIdentityReview(card: card)
        XCTAssertEqual(review.recommendedSide, .front)
        XCTAssertEqual(review.missingFields, ["Spielername"])
    }
    func testNumberMissingWithBothPhotosRecommendsClearerBack() {
        var card = knownCard(); card.analysis?.cardNumber = nil
        XCTAssertEqual(CardIdentityReview(card: card).recommendedSide, .back)
    }
    func testVariantUncertaintyIsShownWithoutInventingMissingFieldsOrConfirmingIdentity() {
        var card = knownCard()
        card.analysis?.uncertainties = [" Base oder Refractor ist unklar. ", "", "Base oder Refractor ist unklar."]
        let original = card
        let review = CardIdentityReview(card: card)
        XCTAssertEqual(review.recommendedSide, .front)
        XCTAssertTrue(review.missingFields.isEmpty)
        XCTAssertEqual(review.uncertainties, ["Base oder Refractor ist unklar."])
        XCTAssertEqual(card, original)
    }
    func testUnknownReasonOffersHonestGenericExplanation() {
        let card = knownCard()
        XCTAssertEqual(CardIdentityReview(card: card).missingFields, ["Genaue Variante / Abgleich mit der Checkliste"])
        var confirmed = card; confirmed.analysis?.identityConfirmed = true
        XCTAssertTrue(CardIdentityReview(card: confirmed).missingFields.isEmpty)
    }
    func testNoAnalysisListsMissingDetailsWithoutGuessingIdentity() {
        let card = OwnedCard(state: "failed", frontFile: "front.jpg")
        let review = CardIdentityReview(card: card)
        XCTAssertEqual(review.recommendedSide, .back)
        XCTAssertEqual(review.missingFields, ["Spielername", "Jahrgang", "Kartenset / Produkt", "Kartennummer", "Lizenz / Produktnachweis"])
        XCTAssertNil(card.analysis)
    }
}
