import SwiftUI
import CardScoutCore

struct UnclearCardQueueView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    // Keep the displayed guide stable while its photo sheet closes. Durable progress
    // already moved in the same transaction that saved the replacement photo.
    @State private var displayedCardID: String?
    @State private var ready = false

    var body: some View {
        Group {
            if let id = displayedCardID, let queue = store.library.unclearCardQueue {
                IdentityReviewView(cardID: id,
                    queueProgress: "Karte \(min(queue.visited + 1, queue.total)) von \(queue.total)",
                    onSkip: {
                        if store.advanceUnclearCardQueue(skipping: id) { showNext() }
                    },
                    onPhotoSaved: { showNext() },
                    onContinue: {
                        if store.advanceUnclearCardQueue() { showNext() }
                    })
                    .id(id)
            } else if ready {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Label(tr("Durchgang beendet"), systemImage: "checkmark.circle").font(.title2.bold())
                            if let queue = store.library.unclearCardQueue {
                                Text(tr("Für \(queue.photoSavedIDs.count) Karten neue Fotos gespeichert."))
                                if !queue.skippedIDs.isEmpty { Text(tr("\(queue.skippedIDs.count) Karten übersprungen. Sie bleiben offen.")) }
                                if !queue.noLongerNeededIDs.isEmpty {
                                    Text(tr("\(queue.noLongerNeededIDs.count) Karten sind inzwischen zugeordnet, werden geprüft oder sind nicht mehr vorhanden."))
                                }
                            }
                            Text(tr("Analyse läuft bei Verbindung weiter."))
                                .font(.subheadline).foregroundStyle(Color.scoutMuted)
                            Button(tr("Zur Sammlung")) { dismiss() }.buttonStyle(ScoutPrimaryButtonStyle())
                        }.padding(20)
                    }.background(Color.scoutCanvas).navigationTitle(tr("Offene Karten fertigstellen")).navigationBarTitleDisplayMode(.inline)
                }
            } else { ProgressView() }
        }
        .task { if !ready { showNext(); ready = true } }
    }
    private func showNext() { displayedCardID = store.library.unclearCardQueue?.currentID }
}
