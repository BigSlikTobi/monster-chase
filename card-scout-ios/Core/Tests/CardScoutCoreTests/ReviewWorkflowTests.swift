import XCTest
@testable import CardScoutCore

final class ReviewWorkflowTests: XCTestCase {
    func testStackPairSurvivesRestartAndContinuesWithoutManualSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        _ = try disk.beginCapturePair(CapturePhoto(front: Data([1])), sessionID: "stack", in: Library(), mode: .stack)
        let restored = try disk.load()
        let card = try XCTUnwrap(restored.cards.first)
        XCTAssertTrue(restored.collectedCards.isEmpty)
        XCTAssertEqual(card.captureMode, "stack")
        XCTAssertThrowsError(try disk.finishCapturePair(cardID: card.id, back: nil, in: restored))
        let finished = try disk.finishCapturePair(cardID: card.id, back: Data([2]), in: restored)
        XCTAssertEqual(finished.collectedCards.count, 1)
        XCTAssertEqual(finished.cards[0].fastPipeline, true)
        XCTAssertEqual(finished.cards[0].state, "queued")
        XCTAssertNil(finished.cards[0].analysis)
        let next = try disk.beginCapturePair(CapturePhoto(front: Data([3])), sessionID: "stack", in: finished, mode: .stack)
        XCTAssertEqual(next.cards.count, 2)
        XCTAssertEqual(ScanSessionSummary(cards: next.cards).saved, 1)
        XCTAssertEqual(ScanSessionSummary(cards: next.cards).processing, 1)
        XCTAssertEqual(ScanSessionSummary(cards: next.cards).identified, 0)
    }

    func testSessionSummarySeparatesProcessingFromActualReview() {
        var queued = OwnedCard(state: "queued")
        let failed = OwnedCard(state: "failed")
        var draft = OwnedCard(state: "identified"); draft.isScanDraft = true
        var confirmed = OwnedCard(state: "analyzed")
        confirmed.analysis = CardAnalysis(recommendation: "Keep", marketCheckedAt: "", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        confirmed.analysis?.identityConfirmed = true
        var summary = ScanSessionSummary(cards: [queued, failed, draft, confirmed])
        XCTAssertEqual(summary.saved, 4); XCTAssertEqual(summary.processing, 1)
        XCTAssertEqual(summary.identified, 1); XCTAssertEqual(summary.review, 2)
        queued.awaitingBack = true
        summary = ScanSessionSummary(cards: [queued])
        XCTAssertEqual(summary.saved, 0)
    }
    func testConfirmedFlagDoesNotHideSerialOrMembershipConflict() {
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        a.identityConfirmed = true; a.year = 2025; a.brand = "Panini"; a.setName = "Donruss Optic"
        a.subset = "Base"; a.parallel = "Orange"; a.serialNumber = "20/79"; a.cardNumber = "257"
        var card = OwnedCard(state: "analyzed", frontFile: "f", backFile: "b", analysis: a)
        XCTAssertEqual(ReviewIssue.identity(card)?.kind, .conflict)
        XCTAssertTrue(UnclearCardQueue.isEligible(card))
        card.analysis?.parallel = "Orange Scope"
        XCTAssertNil(ReviewIssue.identity(card))
        card.analysis?.parallel = "Blue Hyper"; card.analysis?.serialNumber = nil; card.analysis?.cardNumber = "84"
        XCTAssertEqual(ReviewIssue.identity(card)?.kind, .conflict)
    }

    func testExistingBackOffersComparisonInsteadOfDemandingAnotherPhoto() {
        var card = OwnedCard(state: "unidentified", frontFile: "f")
        XCTAssertEqual(ReviewIssue.identity(card)?.kind, .back)
        card.backFile = "b"
        XCTAssertEqual(ReviewIssue.identity(card)?.kind, .compare)
        XCTAssertTrue(UnclearCardQueue.isEligible(card))
        card.state = "processing"
        XCTAssertNil(ReviewIssue.identity(card))
    }

    func testPairSurvivesRestartAndNeverUploadsTheFrontAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        let started = try disk.beginCapturePair(CapturePhoto(front: Data([1]), text: "front"), sessionID: "batch", in: Library())
        let restored = try disk.load()
        let card = try XCTUnwrap(restored.cards.first)
        XCTAssertEqual(card.id, started.cards.first?.id)
        XCTAssertEqual(card.state, "awaiting_back")
        XCTAssertFalse(card.isAwaitingAnalysis)
        XCTAssertTrue(restored.collectedCards.isEmpty)
        XCTAssertThrowsError(try disk.beginCapturePair(CapturePhoto(front: Data([2])), sessionID: "batch", in: restored))
        XCTAssertThrowsError(try disk.finishCapturePair(cardID: "wrong", back: Data([2]), in: restored))
        let finished = try disk.finishCapturePair(cardID: card.id, back: Data([2]), text: "back", in: restored)
        XCTAssertEqual(finished.cards.count, 1)
        XCTAssertEqual(finished.cards[0].frontFile, card.frontFile)
        XCTAssertEqual(finished.cards[0].state, "queued")
        XCTAssertTrue(finished.cards[0].captureText?.contains("front") == true)
        XCTAssertTrue(finished.cards[0].captureText?.contains("back") == true)
        XCTAssertThrowsError(try disk.finishCapturePair(cardID: card.id, back: Data([3]), in: finished))
        XCTAssertEqual(try disk.load().cards[0].backFile, finished.cards[0].backFile)
    }

    func testExplicitFrontOnlyChoicePreservesSavedPhotoAndAllowsNextPair() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try DiskStore(root: root)
        let first = try disk.beginCapturePair(CapturePhoto(front: Data([1])), sessionID: "batch", in: Library())
        XCTAssertThrowsError(try disk.finishCapturePair(cardID: first.cards[0].id, back: Data(), in: first))
        let skipped = try disk.finishCapturePair(cardID: first.cards[0].id, back: nil, in: first)
        XCTAssertNil(skipped.cards[0].backFile)
        XCTAssertEqual(skipped.cards[0].state, "queued")
        let next = try disk.beginCapturePair(CapturePhoto(front: Data([2])), sessionID: "batch", in: skipped)
        XCTAssertEqual(next.cards.count, 2)
        XCTAssertNotEqual(next.cards[0].id, next.cards[1].id)
    }

    func testComparisonRangeIsExplicitTransientAndExpires() throws {
        let now = Date()
        let refs = [100, 200, 300].map { cents in
            MarketReference(provider: "CardSight", url: "https://example.com/\(cents)", kind: "sold", grade: "raw",
                condition: nil, matchQuality: "near", lowCents: cents, highCents: cents, currency: "USD",
                saleDate: "2026-10-20", checkedAt: "2026-10-20", shipping: "unknown",
                expiresAt: now.timeIntervalSince1970 + 300)
        }
        let estimate = ComparableEstimate(lowCents: 100, highCents: 300, currency: "USD", shipping: "unknown",
            cardCount: 3, confidence: "low", scopeLabel: "2025 Optic Base", checkedAt: "2026-10-20",
            expiresAt: now.timeIntervalSince1970 + 200, references: refs)
        XCTAssertTrue(estimate.isFresh(asOf: now))
        XCTAssertFalse(estimate.isFresh(asOf: now.addingTimeInterval(201)))
        var a = CardAnalysis(recommendation: "Keep", marketCheckedAt: "", marketSources: [], confidence: "high", conditionNotes: "", rationale: "", needsReview: false)
        a.identityConfirmed = true; a.comparableEstimate = estimate
        XCTAssertTrue(a.marketSummary?.isComparable == true)
        XCTAssertTrue(a.marketSummary?.isEstimate == true)
        XCTAssertNil(a.withoutTransientPricing().comparableEstimate)
        XCTAssertNil(a.currentPricing(asOf: now.addingTimeInterval(201)).comparableEstimate)
        var mixed = estimate; mixed.references[0].currency = "EUR"
        XCTAssertFalse(mixed.isFresh(asOf: now))
        var duplicate = estimate; duplicate.references[1] = duplicate.references[0]
        XCTAssertFalse(duplicate.isFresh(asOf: now))
        a.identityConfirmed = false
        XCTAssertNil(a.marketSummary)
    }
}
