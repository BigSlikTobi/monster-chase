import SwiftUI
import CardScoutCore

struct IdentityReviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardID: String
    var queueProgress: String? = nil
    var onSkip: (() -> Void)? = nil
    var onPhotoSaved: (() -> Void)? = nil
    var onContinue: (() -> Void)? = nil
    @State private var captureSide: CardPhotoSide?
    @State private var manualAssignment = false
    @State private var savedPhoto = false
    @State private var photoExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let card = store.library.cards.first(where: { $0.id == cardID }) {
                    let review = CardIdentityReview(card: card)
                    let issue = ReviewIssue.identity(card)
                    VStack(alignment: .leading, spacing: 24) {
                        if let queueProgress { Text(trDisplay(queueProgress)).font(.subheadline.monospacedDigit()).foregroundStyle(Color.scoutAccent).accessibilityAddTraits(.updatesFrequently) }
                        HStack(alignment: .center, spacing: 16) {
                            Button { photoExpanded = true } label: {
                                OwnedPhoto(name: card.frontFile, maxPixel: 600, number: "")
                                    .frame(width: 100, height: 140)
                            }.buttonStyle(.plain).accessibilityLabel(tr("Gespeicherte Vorderseite vergrößern"))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(cardTitle(card)).font(.headline)
                                if let a = card.analysis {
                                    Text(trDisplay([a.year.map(String.init), a.setName, a.cardNumber.map { "#" + $0 }].compactMap { $0 }.joined(separator: " · ")))
                                        .font(.caption).foregroundStyle(Color.scoutMuted)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("Zuordnung")).font(.largeTitle.weight(.bold))
                        }
                        if card.isAwaitingAnalysis {
                            ScoutPanel {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack { ProgressView(); Text(tr("Neue Zuordnung wird geprüft")).font(.headline) }
                                    Text(trDisplay(store.connected ? "Die neuen Fotos werden gespeichert und analysiert. Du kannst diese Ansicht schließen." : "Deine Fotos sind gespeichert. Die Analyse geht weiter, sobald die Verbindung wieder da ist."))
                                        .font(.subheadline).foregroundStyle(Color.scoutMuted)
                                }
                            }
                        } else if issue == nil && card.analysis?.identityConfirmed == true {
                            Label(tr("Die Karte ist jetzt zugeordnet."), systemImage: "checkmark.circle.fill")
                                .font(.headline).foregroundStyle(Color.scoutAccent)
                            Button(trDisplay(onContinue == nil ? "Fertig" : "Nächste Karte")) {
                                if let onContinue { onContinue() } else { dismiss() }
                            }.buttonStyle(ScoutPrimaryButtonStyle())
                        } else {
                            ScoutPanel {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(tr("Was noch fehlt")).font(.headline)
                                    if let issue {
                                        Text(trDisplay(issue.title)).font(.subheadline.weight(.semibold))
                                        Text(trDisplay(issue.detail)).font(.subheadline).foregroundStyle(Color.scoutGold)
                                    }
                                    if card.backFile == nil {
                                        Label(tr("Die Rückseite ist noch nicht fotografiert."), systemImage: "rectangle.portrait.rotate")
                                            .font(.subheadline)
                                    }
                                    ForEach(review.missingFields, id: \.self) { field in
                                        Label(trDisplay(field), systemImage: "questionmark.circle").font(.subheadline)
                                    }
                                    ForEach(review.uncertainties, id: \.self) { note in
                                        Text(trDisplay(note)).font(.subheadline).foregroundStyle(Color.scoutMuted)
                                    }
                                }
                            }
                            VStack(alignment: .leading, spacing: 14) {
                                Text(tr("So geht’s weiter")).font(.headline)
                                Button(tr("Passende Checklisten-Einträge vergleichen")) { manualAssignment = true }
                                    .buttonStyle(ScoutPrimaryButtonStyle())
                                if card.backFile != nil || card.state == "failed" {
                                    Button(tr("Vorhandene Fotos erneut prüfen")) { store.reanalyze(cardID) }
                                        .buttonStyle(ScoutSecondaryButtonStyle())
                                }
                                if let guidance = review.photoGuidance {
                                    Text(trDisplay(guidance)).font(.subheadline).foregroundStyle(Color.scoutGold)
                                    if review.recommendedSide == .back { backAction(card) } else { frontAction }
                                } else {
                                    Text(tr("Zuerst mit den gespeicherten Fotos und den Katalogeinträgen prüfen. Ein neues Foto ist hier nicht automatisch nötig."))
                                        .font(.subheadline).foregroundStyle(Color.scoutMuted)
                                }
                                DisclosureGroup(tr("Foto trotzdem ersetzen")) { frontAction; backAction(card) }
                                Text(trDisplay(onPhotoSaved == nil ? "Nach dem Speichern prüfen wir die Karte automatisch neu. Nur die gewählte Seite wird ersetzt; die Karte bleibt in deiner Sammlung." : "Speichern startet die neue Analyse und öffnet die nächste Karte. Nur die gewählte Seite wird ersetzt."))
                                    .font(.footnote).foregroundStyle(Color.scoutMuted)
                            }
                            if card.state == "failed" {
                                Text(tr("Die letzte Analyse ist fehlgeschlagen. Starte sie mit den vorhandenen Fotos erneut."))
                                    .font(.subheadline).foregroundStyle(Color.scoutGold)
                            }
                            Text(tr("Solange die genaue Karte nicht bestätigt ist, bleibt der Preis offen. Deine Karte ist trotzdem gespeichert."))
                                .font(.footnote).foregroundStyle(Color.scoutMuted)
                            Button(tr("Ich kenne die genaue Karte")) { manualAssignment = true }
                                .font(.subheadline).frame(minHeight: 44)
                                .accessibilityHint(tr("Öffnet die freiwillige manuelle Auswahl von Kartenset und Nummer"))
                        }
                    }.padding(20)
                } else {
                    ScoutEmptyState(symbol: "rectangle.portrait.slash", title: tr("Karte nicht verfügbar."))
                }
            }
            .background(Color.scoutCanvas).navigationTitle(tr("Zuordnung prüfen")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Schließen")) { dismiss() } } }
            .toolbar {
                if let onSkip {
                    ToolbarItem(placement: .topBarTrailing) { Button(tr("Überspringen"), action: onSkip) }
                }
            }
            .sheet(item: $captureSide, onDismiss: {
                if savedPhoto { savedPhoto = false; onPhotoSaved?() }
            }) { side in
                AddCardView(cardID: cardID, side: side, onSaved: { savedPhoto = true }).tint(.scoutAccent)
            }
            .sheet(isPresented: $manualAssignment) { ReviewMatchesView(cardID: cardID) }
            .fullScreenCover(isPresented: $photoExpanded) { CardPhotoViewer(cardID: cardID, initialBack: false) }
        }
    }

    private func backAction(_ card: OwnedCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { captureSide = .back } label: {
                Label(trDisplay(card.backFile == nil ? "Rückseite ergänzen" : "Rückseite neu aufnehmen"), systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(ScoutSecondaryButtonStyle())
            Text(tr("Die ganze Rückseite, mit lesbarer Kartennummer und kleiner Schrift."))
                .font(.caption).foregroundStyle(Color.scoutMuted)
        }
    }
    private var frontAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { captureSide = .front } label: {
                Label(tr("Vorderseite neu aufnehmen"), systemImage: "camera.rotate").frame(maxWidth: .infinity)
            }.buttonStyle(ScoutSecondaryButtonStyle())
            Text(tr("Spielername und Oberfläche scharf zeigen. Spiegelungen vermeiden."))
                .font(.caption).foregroundStyle(Color.scoutMuted)
        }
    }
}

private struct ReviewMatchesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardID: String
    @State private var query = ""
    @State private var selected: CardMatch?
    var body: some View {
        NavigationStack {
            List {
                Text(tr("Nur bestätigen, wenn Nummer, Jahr und Oberfläche zu deinen Fotos passen. Die Auswahl ändert die Zuordnung und startet eine neue Prüfung."))
                    .font(.footnote).foregroundStyle(Color.scoutMuted)
                if let card = store.library.cards.first(where: { $0.id == cardID }) {
                    NavigationLink("Gespeicherte Vorder- und Rückseite ansehen") { CardPhotoViewer(cardID: cardID, initialBack: false) }
                    ForEach(store.library.matches(for: card, query: query, limit: query.isEmpty ? 12 : 60)) { match in
                        if let c = store.library.collections.first(where: { $0.id == match.collectionID }),
                           let entry = c.cards.first(where: { $0.number == match.number }) {
                            Button { selected = match } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.player).font(.headline)
                                    Text(tr("\(String(c.year)) · \(c.name) · #\(entry.number)"))
                                    Text(tr("\(c.subset) · \(c.parallel ?? "Base")")).foregroundStyle(Color.scoutAccent)
                                    if selected == match { Label(tr("Ausgewählt"), systemImage: "checkmark.circle.fill").foregroundStyle(Color.scoutAccent) }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.navigationTitle(tr("Eintrag auswählen")).searchable(text: $query, prompt: tr("Spieler, Nummer, Variante"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Schließen")) { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    Button(tr("Zuordnung bestätigen & prüfen")) {
                        if let selected, store.correctAssignment(cardID, collectionID: selected.collectionID, number: selected.number) {
                            store.reanalyze(cardID); dismiss()
                        }
                    }.buttonStyle(ScoutPrimaryButtonStyle()).disabled(selected == nil).padding().background(Color.scoutCanvas)
                }
        }
    }
}
