import Foundation

public enum CardPhotoSide: String, Identifiable, Sendable {
    case front, back
    public var id: String { rawValue }
}

/// Explain stored uncertainty without turning a suggested identity into a confirmed one.
public struct CardIdentityReview: Sendable {
    public let missingFields: [String]
    public let uncertainties: [String]
    public let recommendedSide: CardPhotoSide
    public let photoGuidance: String?

    public init(card: OwnedCard) {
        let a = card.analysis
        func missing(_ value: String?) -> Bool { value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }
        var fields: [String] = []
        if missing(a?.player) { fields.append("Spielername") }
        if a?.year == nil { fields.append("Jahrgang") }
        if missing(a?.setName) || missing(a?.brand) { fields.append("Kartenset / Produkt") }
        if missing(a?.cardNumber) { fields.append("Kartennummer") }
        if a?.licenseScope == nil || ["unknown", "unlicensed"].contains(a?.licenseScope ?? "") { fields.append("Lizenz / Produktnachweis") }
        var seen: Set<String> = []
        let notes = (a?.uncertainties ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        if fields.isEmpty && notes.isEmpty && a?.identityConfirmed != true {
            fields.append("Genaue Variante / Abgleich mit der Checkliste")
        }
        missingFields = fields
        uncertainties = notes
        let limits = (notes + (a?.insights?.conditionLimitations ?? [])).joined(separator: " ").lowercased()
        let obscured = ["unscharf", "nicht lesbar", "unlesbar", "spiegel", "reflex", "glare", "blur", "verdeckt", "beschnitten"].contains { limits.contains($0) }
        if card.backFile == nil { recommendedSide = .back }
        else if limits.contains("nummerierung") || limits.contains("seriennummer") { recommendedSide = .back }
        else if missing(a?.player) { recommendedSide = .front }
        else if a?.year == nil || missing(a?.cardNumber) { recommendedSide = .back }
        else { recommendedSide = .front }

        if card.state == "failed" || card.matchNotice == "catalog_missing" {
            photoGuidance = nil
        } else if card.backFile == nil {
            photoGuidance = "Rückseite ergänzen: Kartennummer, Jahr und Variantenmerkmale müssen lesbar sein."
        } else if missing(a?.player) {
            photoGuidance = "Spielername nicht sicher gelesen. Den gedruckten Namen auf der Vorderseite scharf und ohne Spiegelung aufnehmen."
        } else if a?.year == nil || missing(a?.cardNumber) {
            photoGuidance = "Rückseite prüfen: Kartennummer oder Jahr wurden nicht sicher gelesen. Nur diese Seite bei Bedarf neu aufnehmen."
        } else if obscured {
            photoGuidance = recommendedSide == .back
                ? "Die Nummerierung ist nicht klar lesbar. Rückseite leicht kippen, bis die Spiegelung verschwindet."
                : "Die Oberfläche ist nicht klar sichtbar. Vorderseite leicht kippen und Spiegelungen vermeiden."
        } else {
            photoGuidance = nil
        }
    }
}
