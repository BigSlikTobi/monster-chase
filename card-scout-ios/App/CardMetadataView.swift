import SwiftUI
import CardScoutCore

struct CardMetadataView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardID: String
    @State private var location = ""
    @State private var notes = ""
    @State private var folderIDs: Set<String> = []
    @State private var newFolder = ""
    @State private var purchase: CardPurchase?
    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Ordner")) {
                    ForEach(store.library.folders ?? []) { folder in
                        Toggle(folder.name, isOn: Binding(get: { folderIDs.contains(folder.id) }, set: { enabled in
                            if enabled { folderIDs.insert(folder.id) } else { folderIDs.remove(folder.id) }
                        }))
                    }
                    TextField(tr("Neuer Ordner"), text: $newFolder)
                    Text(tr("Eine Karte kann in mehreren Ordnern liegen. Sie zählt einmal.")).font(.caption).foregroundStyle(Color.scoutMuted)
                }
                Section(tr("Aufbewahrung")) { TextField(tr("Zum Beispiel: Binder 2 · Seite 8"), text: $location) }
                Section(tr("Deine Notizen")) { TextField(tr("Kauf, Tausch oder persönliche Geschichte"), text: $notes, axis: .vertical).lineLimit(4...10) }
                Section(tr("Kauf")) {
                    Button(tr("Einzelkarten-Kauf erfassen")) {
                        purchase = CardPurchase(title: store.library.cards.first(where: { $0.id == cardID })?.title ?? "Einzelkarte",
                            category: .card, purchasedOn: PurchaseEditorView.dateString(Date()), cardID: cardID)
                    }
                    Text(tr("Nur separat gekaufte Karten buchen. Pack- und Boxkäufe erfasst du einmal unter Stats."))
                        .font(.caption).foregroundStyle(Color.scoutMuted)
                }
            }
            .scrollContentBackground(.hidden).background(Color.scoutCanvas)
            .navigationTitle(tr("Deine Karte")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(tr("Speichern")) { if store.saveMetadata(cardID, location: location, notes: notes, folderIDs: folderIDs, newFolderName: newFolder) { dismiss() } }.fontWeight(.semibold) }
            }
            .onAppear {
                folderIDs = Set((store.library.folders ?? []).filter { $0.cardIDs.contains(cardID) }.map(\.id))
                if let card = store.library.cards.first(where: { $0.id == cardID }) { location = card.storageLocation ?? ""; notes = card.notes ?? "" }
            }
            .sheet(item: $purchase) { PurchaseEditorView(purchase: $0) }
        }
    }
}
