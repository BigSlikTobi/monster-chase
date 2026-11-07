import SwiftUI
import CardScoutCore

struct ReviewQueueView: View {
    @Environment(AppStore.self) private var store
    @State private var reviewing: OwnedCard?
    private var identityCards: [OwnedCard] { store.library.collectedCards.filter { ReviewIssue.identity($0) != nil } }
    private var unpriced: [OwnedCard] {
        store.library.collectedCards.filter { $0.hasCurrentAnalysis && ReviewIssue.identity($0) == nil && $0.analysis?.marketSummary == nil }
    }
    var body: some View {
        List {
            Section {

            }
            if let pair = store.pendingCapturePair {
                Section(tr("Fotopaar fortsetzen")) {
                    Button { store.selectedTab = 3 } label: {
                        row(pair, title: tr("Gespeicherte Vorderseite · Rückseite fehlt"),
                            detail: "Unter Scannen dieselbe Karte umdrehen. Keine neue Karte beginnen.")
                    }
                }
            }
            if !identityCards.isEmpty {
                Section(tr("Zuordnung prüfen · \(identityCards.count)")) {
                    ForEach(identityCards) { card in
                        if let issue = ReviewIssue.identity(card) {
                            Button { reviewing = card } label: { row(card, title: issue.title, detail: issue.detail) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !unpriced.isEmpty {
                Section(tr("Karte gespeichert · Preis offen · \(unpriced.count)")) {
                    ForEach(unpriced) { card in
                        NavigationLink { CardDetailView(cardID: card.id) } label: {
                            row(card, title: priceTitle(card), detail: "")
                        }
                    }
                }
            }
            if identityCards.isEmpty && unpriced.isEmpty && store.pendingCapturePair == nil {
                Label(tr("Keine offenen Schritte"), systemImage: "checkmark.circle")
            }
        }.navigationTitle(tr("Nächste Schritte"))
            .sheet(item: $reviewing) { IdentityReviewView(cardID: $0.id) }
            .refreshable { await store.sync() }
    }
    private func priceTitle(_ card: OwnedCard) -> String {
        switch store.priceStates[card.jobID] {
        case "refreshing": "Preis wird geprüft"
        case "unavailable": "Preisquelle pausiert oder nicht erreichbar"
        case "no_match": "Kein passender Preisbeleg gefunden"
        case "unsupported": "Identität oder Variante zuerst prüfen"
        default: "Noch kein Preis geladen"
        }
    }
    private func row(_ card: OwnedCard, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            OwnedPhoto(name: card.frontFile, number: "").frame(width: 45, height: 64)
            VStack(alignment: .leading, spacing: 5) {
                Text(cardTitle(card)).font(.headline)
                Text(trDisplay(title)).font(.subheadline).foregroundStyle(Color.scoutGold)
                if !detail.isEmpty { Text(trDisplay(detail)).font(.caption).foregroundStyle(Color.scoutMuted) }
            }
        }.padding(.vertical, 6)
    }
}
