import SwiftUI
import Charts
import CardScoutCore

struct CollectionStatisticsView: View {
    @State private var section = "Wert"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker(tr("Insights"), selection: $section) {
                    Text(tr("Wert")).tag("Wert")
                    Text(tr("Moves")).tag("Moves")
                    Text(tr("Entdecken")).tag("Entdecken")
                }.pickerStyle(.segmented)
                if section == "Wert" {
                    PortfolioDashboardContent(section: .value)
                    NavigationLink { PurchaseLedgerView() } label: {
                        Label(tr("Kaufbuch & Ausgaben"), systemImage: "book.closed").frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(ScoutSecondaryButtonStyle())
                } else if section == "Moves" {
                    PortfolioDashboardContent(section: .moves)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(tr("Chase")).font(.system(.largeTitle, design: .rounded, weight: .black))

                        NavigationLink { HotListView() } label: {
                            insightDoor(tr("Chase-Ranglisten"), detail: "Sets, Varianten & Marktpreise", symbol: "sparkles")
                        }.buttonStyle(CollectorPressStyle())
                        NavigationLink { HuntListView() } label: {
                            insightDoor(tr("Dein Lookout"), detail: "Die Karten, die dir noch fehlen", symbol: "scope")
                        }.buttonStyle(CollectorPressStyle())
                    }
                }
            }.padding(20)
        }.background(Color.scoutCanvas).navigationTitle(tr("Insights")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { PurchaseLedgerView() } label: { Image(systemName: "book.closed") }.accessibilityLabel(tr("Kaufbuch")) } }
    }
    private func insightDoor(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.scoutGold).frame(width: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(trDisplay(title)).font(.headline).foregroundStyle(Color.scoutInk)
                Text(trDisplay(detail)).font(.caption).foregroundStyle(Color.scoutMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.scoutMuted)
        }.padding(20).background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct PurchaseLedgerView: View {
    @Environment(AppStore.self) private var store
    @State private var editingPurchase: CardPurchase?
    var body: some View {
        let stats = CollectionStatistics(library: store.library)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text(tr("Ausgaben")).font(.system(.title, design: .rounded, weight: .heavy))
                ForEach(stats.spendingCurrencies, id: \.self) { currency in
                    Text(trDisplay(CollectionCardValue.money(stats.spending(currency: currency), currency: currency)))
                        .font(.system(.title2, design: .rounded, weight: .heavy)).foregroundStyle(Color.scoutAccent)
                }
                Text(tr("Inklusive Zubehör. Burn Count zählt nur Karten, Packs und Boxen."))
                    .font(.caption).foregroundStyle(Color.scoutMuted)
                if stats.purchases.isEmpty {
                    ScoutEmptyState(symbol: "book.closed", title: tr("Keine Käufe"), message: tr(""))
                }
                ForEach(stats.purchases) { purchase in
                    Button { editingPurchase = purchase } label: {
                        HStack(spacing: 12) {
                            Image(systemName: purchase.category.symbol).foregroundStyle(Color.scoutGold).frame(width: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(purchase.title).font(.subheadline.bold()).foregroundStyle(Color.scoutInk)
                                Text(tr("\(purchase.category.label) · \(purchase.purchasedOn)")).font(.caption).foregroundStyle(Color.scoutMuted)
                            }
                            Spacer(minLength: 0)
                            Text(trDisplay(CollectionCardValue.money(purchase.amountCents, currency: purchase.currency)))
                                .font(.subheadline.bold()).foregroundStyle(Color.scoutAccent)
                        }.padding(16).background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
                Button { editingPurchase = newCardPurchase(currency: preferredBurnCurrency(stats)) } label: {
                    Label(tr("Kauf eintragen"), systemImage: "plus").frame(maxWidth: .infinity)
                }.buttonStyle(ScoutPrimaryButtonStyle())
                Text(tr("Lokal gespeichert")).font(.caption).foregroundStyle(Color.scoutMuted)
            }.padding(20)
        }.background(Color.scoutCanvas).navigationTitle(tr("Kaufbuch")).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingPurchase) { PurchaseEditorView(purchase: $0) }
    }
}

struct PurchaseEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let purchase: CardPurchase
    @State private var title: String
    @State private var category: PurchaseCategory
    @State private var amount: String
    @State private var currency: String
    @State private var quantity: Int
    @State private var date: Date
    @State private var confirmDelete = false
    init(purchase: CardPurchase) {
        self.purchase = purchase
        _title = State(initialValue: purchase.title); _category = State(initialValue: purchase.category)
        _amount = State(initialValue: purchase.amountCents == 0 ? "" : decimalInput(purchase.amountCents))
        _currency = State(initialValue: purchase.currency); _quantity = State(initialValue: purchase.quantity)
        _date = State(initialValue: Self.formatter.date(from: purchase.purchasedOn) ?? Date())
    }
    private static var formatter: DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }
    static func dateString(_ date: Date) -> String { formatter.string(from: date) }
    private var existing: Bool { store.library.purchases?.contains { $0.id == purchase.id } == true }
    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Kauf")) {
                    TextField(tr("Bezeichnung"), text: $title)
                    Picker(tr("Kategorie"), selection: $category) { ForEach(PurchaseCategory.allCases) { Text(trDisplay($0.label)).tag($0) } }
                    Stepper(tr("\(quantity) Stück"), value: $quantity, in: 1...999)
                    DatePicker(tr("Gekauft am"), selection: $date, in: ...Date(), displayedComponents: .date)
                }
                Section {
                    HStack {
                        TextField(tr("0,00"), text: $amount).keyboardType(.decimalPad).accessibilityLabel(tr("Gesamt bezahlt"))
                        Picker(tr("Währung"), selection: $currency) { ForEach(CardPurchase.currencies, id: \.self) { Text(trDisplay($0)).tag($0) } }.labelsHidden()
                    }
                } header: { Text(tr("Gesamt bezahlt")) } footer: {
                    Text(tr("Gesamtbetrag inklusive Versand und Gebühren. Pack-/Boxkosten nur einmal buchen."))
                }
                if let cardID = purchase.cardID, let card = store.library.cards.first(where: { $0.id == cardID }) {
                    Section(tr("Zugehörige Karte")) { Text(cardTitle(card)) }
                }
                Section {
                    Button(tr("Kauf speichern")) { save() }
                        .buttonStyle(ScoutPrimaryButtonStyle())
                        .disabled(!canSave)
                }.listRowBackground(Color.clear)
                if existing {
                    Section { Button(tr("Kauf entfernen"), role: .destructive) { confirmDelete = true } }
                }
            }.scrollContentBackground(.hidden).background(Color.scoutCanvas)
                .navigationTitle(trDisplay(existing ? "Kauf bearbeiten" : "Kauf erfassen")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Speichern")) { save() }.fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
                .confirmationDialog(tr("Kauf aus den Ausgaben entfernen?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button(tr("Kauf entfernen"), role: .destructive) { if store.deletePurchase(purchase.id) { dismiss() } }
                } message: { Text(tr("Die Karten und Fotos bleiben erhalten.")) }
        }
    }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 200 && CardPurchase.parseAmount(amount) != nil
    }
    private func save() {
        guard let cents = CardPurchase.parseAmount(amount) else { return }
        var updated = purchase
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines); updated.category = category
        updated.amountCents = cents; updated.currency = currency; updated.quantity = quantity; updated.purchasedOn = Self.dateString(date)
        if store.savePurchase(updated) { dismiss() }
    }
}
