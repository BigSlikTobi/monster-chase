import SwiftUI
import CardScoutCore

struct ScanMatchView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardID: String
    var onNext: (() -> Void)? = nil
    @State private var query = ""
    @State private var selection: CardMatch?
    @State private var folderID = ""
    @State private var newFolder = ""
    @State private var noneFits = false
    @State private var saved = false
    @State private var retaking = false
    @State private var inspectingExample = false
    @State private var inspectingReference: CardReferenceImage?
    @State private var expanded = false
    @State private var showBack = false
    private var card: OwnedCard? { store.library.cards.first { $0.id == cardID } }

    var body: some View {
        ScrollView {
            if let card {
                VStack(alignment: .leading, spacing: 20) {
                    if card.awaitingBack == true {
                        Text(tr("Vorderseite gespeichert")).font(.title2.bold())
                        Text(tr("Nimm unter Scannen die Rückseite derselben Karte auf. Danach startet die Treffersuche."))
                        Button(tr("Fotopaar fortsetzen")) { store.selectedTab = 3; dismiss() }
                            .buttonStyle(ScoutPrimaryButtonStyle())
                    } else if saved || card.isScanDraft != true {
                        Label(tr("In deiner Sammlung"), systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(Color.scoutAccent)
                        Text(tr("Analyse läuft")).foregroundStyle(Color.scoutMuted)
                        NavigationLink("Karte ansehen") { CardDetailView(cardID: cardID) }
                        Button(tr("Nächste Karte scannen")) { store.selectedTab = 3; if let onNext { onNext() } else { dismiss() } }.buttonStyle(ScoutPrimaryButtonStyle())
                    } else {
                        HStack(spacing: 18) {
                            Button { expanded = true } label: {
                                OwnedPhoto(name: showBack ? card.backFile : card.frontFile, maxPixel: 800, original: true).frame(width: 105, height: 148)
                            }.buttonStyle(.plain).accessibilityLabel(tr("Dein Foto vergrößern"))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(tr("Karte zuordnen")).font(.title.bold())
                                Text(tr("Vergleiche Nummer, Jahr und Oberfläche.")).foregroundStyle(Color.scoutMuted)
                                Text(tr("Entwurf gespeichert")).font(.caption).foregroundStyle(Color.scoutAccent)
                                if card.backFile != nil { Button(trDisplay(showBack ? "Vorderseite ansehen" : "Rückseite ansehen")) { showBack.toggle() }.font(.caption) }
                            }
                        }
                        if card.analysis == nil && card.isAwaitingAnalysis {
                            HStack { ProgressView(); Text(trDisplay(store.connected ? "Treffer werden gesucht …" : "Offline · Suche geht später weiter")) }.font(.subheadline)
                        }
                        if card.matchNotice == "unknown" {
                            Label(tr("Variante nicht eindeutig. Bitte selbst vergleichen."), systemImage: "questionmark.circle").font(.subheadline).foregroundStyle(Color.scoutGold)
                        } else if ["unavailable", "catalog"].contains(card.matchNotice ?? "") {
                            Text(tr("Vorschläge aus der Checkliste · ohne zusätzlichen Bildabgleich")).font(.caption).foregroundStyle(Color.scoutMuted)
                        }
                        TextField(tr("Spieler, Nummer oder Set suchen"), text: $query)
                            .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        let matches = store.library.matches(for: card, query: query, limit: query.isEmpty ? 5 : 60)
                        if matches.isEmpty {
                            Text(trDisplay(card.backFile == nil ? "Noch kein passender Treffer. Die Rückseite kann Nummer und Jahr ergänzen." : "Kein passender Katalogtreffer. Beide Fotos sind gespeichert; eine neue Aufnahme ist nicht automatisch nötig.")).font(.subheadline).foregroundStyle(Color.scoutMuted)
                        }
                        ForEach(matches) { match in
                            if let collection = store.library.collections.first(where: { $0.id == match.collectionID }),
                               let entry = collection.cards.first(where: { $0.number == match.number }) {
                                Button { selection = match; noneFits = false } label: {
                                    HStack(alignment: .center, spacing: 12) {
                                        reference(entry: entry, collection: collection)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(entry.player).font(.headline)
                                            Text(tr("\(String(collection.year)) · \(collection.name)")).font(.subheadline)
                                            Text(trDisplay(["#" + entry.number, collection.subset == "Base" ? nil : collection.subset, collection.parallel ?? "Base"].compactMap { $0 }.joined(separator: " · "))).font(.subheadline.weight(.semibold)).foregroundStyle(Color.scoutAccent)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: selection == match ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.scoutAccent)
                                    }.padding(12).background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selection == match ? Color.scoutAccent : .clear, lineWidth: 2) }
                                }.buttonStyle(.plain).accessibilityAddTraits(selection == match ? .isSelected : [])
                                if let exact = entry.exactReference(in: collection) {
                                    Button { inspectingExample = false; inspectingReference = exact } label: { Label(tr("Foto vergleichen"), systemImage: "arrow.up.left.and.arrow.down.right") }.font(.caption)
                                } else if let example = collection.validReferenceExample {
                                    Button { inspectingExample = true; inspectingReference = example } label: {
                                        Label(tr("Variantenbeispiel · \(example.player) #\(example.number)"), systemImage: "photo")
                                    }.font(.caption).foregroundStyle(Color.scoutMuted)
                                }
                            }
                        }

                        Button(tr("Keine passt")) { noneFits = true; selection = nil }
                            .foregroundStyle(Color.scoutGold)
                        if noneFits {
                            Text(tr("Ohne Zuordnung sammeln")).font(.subheadline)
                        }
                        if let guidance = CardIdentityReview(card: card).photoGuidance {
                            Text(trDisplay(guidance)).font(.subheadline).foregroundStyle(Color.scoutGold)
                        }
                        Button(tr("Fotos prüfen oder ersetzen")) { retaking = true }.font(.subheadline)
                        if card.state == "failed" { Button(tr("Treffersuche erneut starten")) { store.retry(cardID) } }
                        Divider()
                        Text(tr("In Ordner ablegen")).font(.headline)
                        Picker(tr("Ordner"), selection: $folderID) {
                            Text(tr("Nur Sammlung")).tag("")
                            ForEach(store.library.folders ?? []) { Text(trDisplay($0.name)).tag($0.id) }
                            Text(tr("Neuer Ordner …")).tag("new")
                        }.pickerStyle(.menu)
                        if folderID == "new" {
                            TextField(tr("Ordnername"), text: $newFolder).textFieldStyle(.roundedBorder)
                        }
                        Button(tr("Zur Sammlung hinzufügen")) {
                            if store.collectScan(cardID, match: selection, folderID: folderID == "new" || folderID.isEmpty ? nil : folderID,
                                                 newFolderName: folderID == "new" ? newFolder : nil) { saved = true }
                        }.buttonStyle(ScoutPrimaryButtonStyle())
                            .disabled((selection == nil && !noneFits) || (folderID == "new" && newFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                    }
                }.padding(20)
            }
        }.background(Color.scoutCanvas).navigationTitle(tr("Treffer vergleichen")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task {
                folderID = store.library.lastUsedFolderID ?? ""
                while !Task.isCancelled && !saved && card?.isScanDraft == true && card?.awaitingBack != true {
                    await store.sync()
                    do { try await Task.sleep(for: .seconds(2)) } catch { break }
                }
            }
            .onChange(of: card?.jobID) { _, _ in selection = nil; noneFits = false }
            .sheet(item: $inspectingReference) { ReferenceComparisonSheet(reference: $0, cardID: cardID, variantExample: inspectingExample) }
            .sheet(isPresented: $retaking) { AddCardView(cardID: cardID) }
            .sheet(isPresented: $expanded) {
                if let card { ScrollView {
                    LocalCardPhoto(name: showBack ? card.backFile : card.frontFile, maxPixel: 2400, original: true) { image, loading in
                        if let image { Image(uiImage: image).resizable().scaledToFit() }
                        else if loading { ProgressView() }
                        else { Label(tr("Foto nicht verfügbar"), systemImage: "photo") }
                    }
                }.presentationDragIndicator(.visible) }
            }
    }

    private func reference(entry: ChecklistCard, collection: CardCollection) -> some View {
        Group {
            if let exact = entry.exactReference(in: collection) { ReferenceImageView(url: exact.frontURL) }
            else if let example = collection.validReferenceExample {
                VStack(spacing: 3) { ReferenceImageView(url: example.frontURL); Text(tr("Beispiel")).font(.system(size: 9)).foregroundStyle(Color.scoutMuted) }
            } else { missingReference }
        }.frame(width: 72, height: 100)
    }
    private var missingReference: some View {
        VStack(spacing: 5) { Image(systemName: "rectangle.portrait"); Text(tr("Referenzbild fehlt")).font(.system(size: 9)).multilineTextAlignment(.center) }
            .foregroundStyle(Color.scoutMuted)
    }
}

struct FolderContentsView: View {
    @Environment(AppStore.self) private var store
    let folderID: String
    var body: some View {
        let folder = store.library.folders?.first { $0.id == folderID }
        List {
            ForEach(store.library.collectedCards.filter { folder?.cardIDs.contains($0.id) == true }) { card in
                NavigationLink { CardDetailView(cardID: card.id) } label: {
                    HStack { OwnedPhoto(name: card.frontFile, number: "").frame(width: 45, height: 64); Text(cardTitle(card)) }
                }
            }
        }.navigationTitle(trDisplay(folder?.name ?? "Ordner"))
    }
}

struct ScanDraftsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        List(store.library.scanDrafts) { card in
            NavigationLink { ScanMatchView(cardID: card.id) } label: {
                HStack { OwnedPhoto(name: card.frontFile, number: "").frame(width: 48, height: 68); Text(cardTitle(card)) }
            }
        }.navigationTitle(tr("Scans vergleichen"))
    }
}
