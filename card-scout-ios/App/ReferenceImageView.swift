import SwiftUI
import CardScoutCore

struct ReferenceImageView: View {
    let url: String
    var body: some View {
        StableImage(request: .remote(url)) { image, loading in
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else if loading { ProgressView().accessibilityLabel(tr("Referenzbild wird geladen")) }
            else { Label(tr("Referenz gerade nicht erreichbar"), systemImage: "wifi.slash").font(.caption).multilineTextAlignment(.center).foregroundStyle(Color.scoutMuted) }
        }
    }
}

struct ReferenceComparisonView: View {
    @Environment(AppStore.self) private var store
    let reference: CardReferenceImage
    var cardID: String? = nil
    var variantExample = false
    @State private var back = false
    var body: some View {
        // Pushed destinations use their parent's stack. Nesting another stack
        // here breaks the collection's navigation after opening a comparison.
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if variantExample { Label(tr("Variantenbeispiel · andere Karte"), systemImage: "info.circle").font(.headline).foregroundStyle(Color.scoutGold) }
                    Text(trDisplay(reference.player)).font(.title2.bold())
                    Text(tr("\(String(reference.year)) · \(reference.product) · #\(reference.number) · \(reference.parallel ?? reference.subset)")).font(.subheadline).foregroundStyle(Color.scoutMuted)
                    if let cardID, let card = store.library.cards.first(where: { $0.id == cardID }) {
                        Text(tr("Dein Foto")).font(.headline)
                        LocalCardPhoto(name: back && card.backFile != nil ? card.backFile : card.frontFile, maxPixel: 2400, original: true) { image, loading in
                            if let image { Image(uiImage: image).resizable().scaledToFit() }
                            else if loading { ProgressView() }
                            else { Label(tr("Foto nicht verfügbar"), systemImage: "photo") }
                        }
                    }
                    Text(trDisplay(back ? "Referenz · Rückseite" : "Referenz · Vorderseite")).font(.headline)
                    if reference.backURL != nil {
                        Picker(tr("Kartenseite"), selection: $back) { Text(tr("Vorne")).tag(false); Text(tr("Hinten")).tag(true) }.pickerStyle(.segmented)
                    }
                    ReferenceImageView(url: back ? reference.backURL ?? reference.frontURL : reference.frontURL).frame(minHeight: 320)
                    if let source = URL(string: reference.sourceURL) {
                        Link(tr("Bildquelle ansehen"), destination: source).font(.subheadline)
                    }
                    Text(trDisplay(variantExample ? "Dieses Foto zeigt die Oberfläche und das Design dieser Variante an einer anderen Karte. Es ist kein exaktes Spielerbild für deinen Treffer." : "Ein anderes Exemplar derselben Karte und Variante. Glanz und Farbe ändern sich mit dem Licht.")).font(.caption).foregroundStyle(Color.scoutMuted)
                }.padding(20)
        }.background(Color.scoutCanvas).navigationTitle(tr("Karten vergleichen")).navigationBarTitleDisplayMode(.inline)
    }
}

/// Modal callers supply a stack; pushed callers use ReferenceComparisonView directly.
struct ReferenceComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reference: CardReferenceImage
    var cardID: String? = nil
    var variantExample = false
    var body: some View {
        NavigationStack {
            ReferenceComparisonView(reference: reference, cardID: cardID, variantExample: variantExample)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { dismiss() } } }
        }
    }
}
