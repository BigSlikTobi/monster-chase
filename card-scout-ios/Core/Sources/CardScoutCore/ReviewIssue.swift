import Foundation

public struct ReviewIssue: Sendable {
    public enum Kind: Sendable { case back, conflict, retry, compare }
    public let kind: Kind
    public let title: String
    public let detail: String

    public static func identity(_ card: OwnedCard) -> ReviewIssue? {
        if card.awaitingBack == true {
            return .init(kind: .back, title: "Rückseite dieser Karte aufnehmen",
                         detail: "Die Vorderseite ist gespeichert. Erst das Fotopaar startet die Suche.")
        }
        guard !card.isAwaitingAnalysis else { return nil }
        if let reason = card.analysis?.knownIdentityConflict {
            return .init(kind: .conflict, title: "Zuordnung widerspricht der Checkliste", detail: reason)
        }
        guard card.analysis?.identityConfirmed != true || card.analysis?.confidence != "high" || card.state == "unidentified" else { return nil }
        if card.state == "failed" {
            return .init(kind: .retry, title: "Prüfung erneut starten",
                         detail: "Die letzte Prüfung ist fehlgeschlagen. Vorhandene Fotos können erneut verwendet werden.")
        }
        if card.matchNotice == "catalog_missing" {
            return .init(kind: .compare, title: "Katalogabgleich offen",
                         detail: "Details wurden gelesen, aber ein passender Katalogeintrag fehlt. Neue Fotos lösen diese Lücke nicht. Gespeicherte Angaben vergleichen; nach einer Katalogergänzung erneut prüfen.")
        }
        if card.backFile == nil {
            return .init(kind: .back, title: "Rückseite ergänzen",
                         detail: "Kartennummer, Jahr und Variantenmerkmale sind noch nicht sicher bestätigt.")
        }
        return .init(kind: .compare, title: "Mit der Checkliste vergleichen",
                     detail: "Beide Fotos sind vorhanden. Erst erneut prüfen oder einen passenden Eintrag auswählen; neue Fotos sind nicht automatisch nötig.")
    }
}

extension CardAnalysis {
    /// Reviewed 2025 Optic release facts. A confirmed flag cannot override a contradiction.
    public var knownIdentityConflict: String? {
        guard year == 2025, brand == "Panini", setName == "Donruss Optic", subset == "Base" else { return nil }
        if let number = Int(cardNumber ?? ""), number <= 200, number > 0,
           ["Blue Hyper", "Purple Shock"].contains(parallel ?? "") {
            return "Diese Variante gehört zu den Rated Rookies #201–300. Die gespeicherte Kartennummer passt nicht dazu."
        }
        let expected = ["Orange": 299, "Orange Scope": 79][parallel ?? ""]
        if let expected, let serialNumber, CollectionStatistics.serialLimit(serialNumber) != expected {
            return "\(parallel ?? "") ist /\(expected). Die gespeicherte Nummerierung \(serialNumber) passt nicht dazu. Variante und Rückseite vergleichen."
        }
        return nil
    }
}
