import Foundation
import Observation
import CardScoutCore

/// Observable UI dependency refreshes open sheets without replacing navigation or form state.
@MainActor @Observable final class AppLanguage {
    static let shared = AppLanguage()
    var preference = UserDefaults.standard.string(forKey: ScoutLocalization.preferenceKey) ?? "system"
}

@MainActor func tr(_ value: ScoutText) -> String {
    _ = AppLanguage.shared.preference
    return ScoutLocalization.text(value)
}
@MainActor func trDisplay(_ value: String) -> String {
    _ = AppLanguage.shared.preference
    return ScoutLocalization.display(value)
}
@MainActor func cardTitle(_ card: OwnedCard) -> String {
    card.analysis?.player == nil ? trDisplay(card.title) : card.title
}
func decimalInput(_ cents: Int) -> String {
    let separator = ScoutLocalization.language == "de" ? "," : "."
    return String(cents / 100) + separator + String(format: "%02d", cents % 100)
}
