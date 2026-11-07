#if DEBUG
import UIKit
import CardScoutCore

/// Layout fixtures exist only in the separate preview bundle. They never seed
/// the real app, call a model, or claim to be card photos or price evidence.
@MainActor enum PreviewData {
    static var enabled: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".preview") == true && ProcessInfo.processInfo.arguments.contains("--collector-preview")
    }
    static func library(disk: DiskStore) throws -> Library {
        let players = ["Daunte Culpepper", "Jayden Daniels", "C.J. Stroud", "Patrick Mahomes", "Josh Allen", "Justin Jefferson", "Caleb Williams", "Joe Burrow", "Lamar Jackson", "CeeDee Lamb", "Michael Penix Jr.", "Jalen Hurts"]
        let tones: [UIColor] = [UIColor(red: 0.16, green: 0.37, blue: 0.40, alpha: 1), UIColor(red: 0.70, green: 0.25, blue: 0.19, alpha: 1), UIColor(red: 0.27, green: 0.33, blue: 0.48, alpha: 1)]
        for (index, player) in players.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 700)).image { context in
                UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 500, height: 700))
                let color = tones[index % tones.count]
                color.setFill(); context.fill(CGRect(x: 22, y: 22, width: 456, height: 520))
                UIBezierPath(rect: CGRect(x: 38, y: 38, width: 424, height: 486)).stroke()
                UIImage(systemName: "figure.american.football")?.withTintColor(.white.withAlphaComponent(0.85), renderingMode: .alwaysOriginal).draw(in: CGRect(x: 108, y: 125, width: 284, height: 340))
                ("DESIGN DEMO" as NSString).draw(at: CGPoint(x: 46, y: 58), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 16, weight: .medium), .foregroundColor: UIColor.white])
                ("\(index + 1)" as NSString).draw(at: CGPoint(x: 370, y: 455), withAttributes: [.font: UIFont.systemFont(ofSize: 48, weight: .bold), .foregroundColor: UIColor.white])
                (player as NSString).draw(in: CGRect(x: 26, y: 565, width: 450, height: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 31, weight: .semibold), .foregroundColor: UIColor.black])
                ("LAYOUT-TEST · KEIN KARTENFOTO" as NSString).draw(at: CGPoint(x: 26, y: 662), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: color])
            }
            try disk.writePhoto(image.jpegData(compressionQuality: 0.9)!, name: "demo-\(index).jpg")
        }
        let entries = players.enumerated().map { index, player in
            ["number": String(index + 1), "player": player, "team": "Design-Vorschau", "rookie": false] as [String: Any]
        }
        let collection: [String: Any] = ["id": "preview-binder", "name": "Donruss Optic", "year": 2025, "brand": "Panini", "subset": "Base", "cards": entries, "checklistComplete": false]
        var bowmanBase = collection
        bowmanBase["id"] = "preview-bowman-base"; bowmanBase["name"] = "Bowman Football"; bowmanBase["brand"] = "Topps"
        var bowmanChrome = bowmanBase
        bowmanChrome["id"] = "preview-bowman-chrome"; bowmanChrome["name"] = "Bowman Chrome"; bowmanChrome["subset"] = "Chrome"
        var donrussBase = collection
        donrussBase["id"] = "preview-donruss-base"; donrussBase["name"] = "Donruss"
        let sets = [collection, bowmanBase, bowmanChrome, donrussBase]
        let cards: [[String: Any]] = (0..<100).map { index in
            let item = index % players.count
            var card: [String: Any] = ["id": String(format: "%08x-1111-4111-a111-111111111111", index + 1), "createdAt": String(format: "2026-10-13T12:%02d:%02dZ", index / 60, index % 60), "state": index > 95 ? "queued" : "analyzed", "frontFile": "demo-\(item).jpg", "isFavorite": index.isMultiple(of: 9), "requestedAnalysisVersion": 3]
            card["isCollectible"] = index < 3
            let set = sets[index % sets.count]
            if index <= 95 {
                card["analysis"] = ["player": players[item], "year": 2025, "brand": set["brand"]!, "setName": set["name"]!, "subset": set["subset"]!, "cardNumber": String(item + 1), "recommendation": "Keep", "marketCheckedAt": "2026-10-13", "marketSources": [], "confidence": "high", "conditionNotes": "Design-Vorschau", "rationale": "Design-Vorschau", "needsReview": false, "identityConfirmed": true, "collectionID": set["id"]!] as [String: Any]
            }
            return card
        }
        let object: [String: Any] = ["version": 1, "cards": cards, "collections": sets, "hunts": [], "hotCards": [], "importedLegacy": true]
        var library = try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: object))
        let now = Date()
        let checked = ISO8601DateFormatter().string(from: now.addingTimeInterval(-14 * 86400)).prefix(10)
        for index in 0..<24 {
            let amount = [48500, 24800, 17900, 9500, 6200, 4100, 2900, 1800, 1200, 900, 700, 500][index % 12]
            let reference: [String: Any] = ["provider": "Design-Vorschau", "url": "https://example.invalid/demo", "kind": "guide", "grade": "raw", "matchQuality": "exact", "lowCents": amount, "highCents": amount + amount / 5, "currency": "EUR", "checkedAt": String(checked), "shipping": "not_applicable"]
            let insights: [String: Any] = ["rarityTier": "parallel", "rarityBullets": [], "conditionStatus": "no_obvious_damage", "conditionIssues": [], "conditionLimitations": ["Design-Vorschau"], "marketBullets": [], "marketReferences": [reference], "sourceChecks": [], "actionReason": index % 3 == 0 ? "Demo: interessante Variante. Oberfläche, Zentrierung und Grading-Kosten vor einer Einreichung prüfen." : "Demo: vorhandene Analyse mit Sammlerempfehlung."]
            library.cards[index].analysis?.insights = try JSONDecoder().decode(CardInsights.self, from: JSONSerialization.data(withJSONObject: insights))
            library.cards[index].analysis?.recommendation = ["Grade", "Keep", "Sell"][index % 3]
        }
        let originals = library.cards
        for day in (0...13).reversed() {
            for index in 0..<24 {
                let base = originals[index].analysis!.insights!.marketReferences[0]
                library.cards[index].analysis?.insights?.marketReferences[0].lowCents = base.lowCents - day * (base.lowCents / 100)
                library.cards[index].analysis?.insights?.marketReferences[0].highCents = base.highCents - day * (base.highCents / 100)
            }
            library.recordPortfolioObservation(asOf: now.addingTimeInterval(Double(-day * 86400)))
        }
        return library
    }
}
#endif
