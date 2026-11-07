import XCTest
@testable import CardScoutCore

final class LocalizationTests: XCTestCase {
    func testExplicitLanguageWinsOverPhoneAndUnknownPreferenceUsesPhone() {
        XCTAssertEqual(ScoutLocalization.resolve(preference: "de", preferredLanguages: ["en-US"]), "de")
        XCTAssertEqual(ScoutLocalization.resolve(preference: "en", preferredLanguages: ["de-DE"]), "en")
        XCTAssertEqual(ScoutLocalization.resolve(preference: "system", preferredLanguages: ["de-DE", "en"]), "de")
        XCTAssertEqual(ScoutLocalization.resolve(preference: "system", preferredLanguages: ["en-GB", "de"]), "en")
        XCTAssertEqual(ScoutLocalization.resolve(preference: "invalid", preferredLanguages: ["fr-FR", "de_DE"]), "de")
        XCTAssertEqual(ScoutLocalization.resolve(preference: "system", preferredLanguages: ["fr", "es"]), "en")
    }
    func testInterpolationKeepsStableKeysAndDataOutOfTranslationKeys() {
        let text: ScoutText = "\(42) von \(100) Karten · \("USD")"
        XCTAssertEqual(text.key, "%1$@ von %2$@ Karten · %3$@")
        XCTAssertEqual(text.arguments, ["42", "100", "USD"])
        let other: ScoutText = "\(1) von \(5) Karten · \("EUR")"
        XCTAssertEqual(other.key, text.key)
    }
    func testPercentSignsInValuesCannotBecomeFormatDirectives() {
        let text: ScoutText = "50% · \("100% %@")"
        XCTAssertEqual(text.key, "50%% · %1$@")
        XCTAssertEqual(text.arguments, ["100% %@"])
        XCTAssertEqual(ScoutLocalization.text(text), "50% · 100% %@")
    }
    func testUnrecognizedUserAndResearchTextStaysUnchanged() {
        XCTAssertEqual(ScoutLocalization.display("Patrick Mahomes / My own collection"), "Patrick Mahomes / My own collection")
        XCTAssertEqual(ScoutLocalization.display("My original card notes: 100% real"), "My original card notes: 100% real")
    }
}
