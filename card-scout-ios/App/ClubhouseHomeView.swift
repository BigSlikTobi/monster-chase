import SwiftUI
import CardScoutCore

struct ClubhouseHomeView: View {
    @Environment(AppStore.self) private var store
    @State private var editingPurchase: CardPurchase?
    @State private var selectedCurrency = ""
    var body: some View {
        let stats = store.dashboardStatistics
        let currencies = Array(Set(stats.spendingCurrencies + stats.valueCurrencies + Array((store.library.burnManualValues ?? [:]).keys))).sorted()
        let currency = currencies.contains(selectedCurrency) ? selectedCurrency : (currencies.contains(preferredBurnCurrency(stats)) ? preferredBurnCurrency(stats) : currencies.first ?? "EUR")
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                #if DEBUG
                if PreviewData.enabled { Text(tr("DESIGN-VORSCHAU · DEMODATEN")).font(.caption2.monospaced()).foregroundStyle(Color.scoutMuted) }
                #endif
                ClubhouseIdentityHeader()
                if currencies.count > 1 {
                    HStack {
                        Spacer()
                        Menu(currency) { ForEach(currencies, id: \.self) { value in Button(trDisplay(value)) { selectedCurrency = value } } }
                            .font(.caption.bold()).accessibilityLabel(tr("Burn Count Währung wählen"))
                    }
                }
                BurnCountCard(burn: BurnCount(statistics: stats, currency: currency, manualValueCents: store.library.currentManualBurnValue(currency: currency)?.amountCents)) {
                    editingPurchase = newCardPurchase(currency: currency)
                }
                HStack {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(Color.scoutGold)
                        .frame(width: 40, height: 40).background(Color.scoutEditorialGold.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                        .accessibilityHidden(true)
                    Text(tr("Collectibles")).font(.system(.title2, design: .rounded, weight: .heavy))
                    Spacer(minLength: 0)
                    NavigationLink { CollectiblesView() } label: { Image(systemName: "arrow.up.right").frame(width: 44, height: 44).background(Color.scoutElevated, in: Circle()) }
                        .accessibilityLabel(tr("Deine Collectibles öffnen"))
                }
                if store.library.collectibles.isEmpty {
                    NavigationLink { ShowcasePickerView() } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "trophy.fill").font(.title).foregroundStyle(Color.scoutEditorialGold)
                            Label(tr("Karte auswählen"), systemImage: "plus").font(.subheadline.bold()).foregroundStyle(Color.scoutEditorialGold)
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                            .background { CardArena() }.clipShape(RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(CollectorPressStyle())
                } else {
                    ShowcaseDeck(cards: store.library.collectibles)
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
        }.background(Color.scoutCanvas).navigationTitle(tr("Clubhaus")).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingPurchase) { PurchaseEditorView(purchase: $0) }
            .refreshable { await store.sync() }
    }

}

/// A compact club identity rather than another dashboard panel.
private struct ClubhouseIdentityHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Image("ScoutFlameLogo").resizable().scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.scoutEditorialGold.opacity(0.3)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("BURN COUNT"))
                    .font(.system(.title, design: .rounded, weight: .black)).italic().tracking(-1)
                    .foregroundStyle(Color.scoutInk)
            }
            Spacer(minLength: 0)
        }.padding(.top, 4).padding(.bottom, 2)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

func preferredBurnCurrency(_ stats: CollectionStatistics) -> String {
    let currencies = Array(Set(stats.spendingCurrencies + stats.valueCurrencies)).sorted()
    return currencies.first(where: { $0 == "EUR" }) ?? currencies.first ?? "EUR"
}

@MainActor func newCardPurchase(currency: String) -> CardPurchase {
    CardPurchase(title: tr("Kartenkauf"), category: .pack, currency: currency, purchasedOn: PurchaseEditorView.dateString(Date()))
}

struct BurnCountCard: View {
    let burn: BurnCount
    let addPurchase: () -> Void
    var showDetailLink = true
    @State private var editingValue = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Text(trDisplay(burn.isIndicative ? "Burn Count · ca." : "Burn Count")).font(.system(.title2, design: .rounded, weight: .black)).foregroundStyle(Color.scoutEditorialGold)
                        if burn.performance == .excellent {
                            Image(systemName: "sparkles").font(.caption.bold()).foregroundStyle(resultColor).accessibilityHidden(true)
                        }
                    }.accessibilityAddTraits(.isHeader)
                    Text(tr("Bezahlt − Wert")).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                    Group {
                        if let low = burn.burnLowCents, let high = burn.burnHighCents {
                            AnimatedMoneyText(low: low, high: high, currency: burn.currency, color: resultColor, showsDirection: false)
                        } else { Text(trDisplay("—")) }
                    }
                        .font(.system(.largeTitle, design: .rounded, weight: resultWeight))
                        .italic(burn.performance == .excellent)
                        .foregroundStyle(resultColor)
                        .shadow(color: burn.performance == .excellent ? resultColor.opacity(0.35) : .clear, radius: 12)
                        .accessibilityLabel(tr("Burn Count: \(headline). \(resultDescription)"))
                        .minimumScaleFactor(0.4).lineLimit(1).contentTransition(.numericText())
                }.frame(maxWidth: .infinity, alignment: .leading)
                BurnMascot(mood: burn.mood).frame(width: 125, height: 155)
            }
            HStack(spacing: 18) {
                burnMetric(tr("Bezahlt"), text: burn.spentCents.map(money) ?? "—")
                Spacer(minLength: 0)
                Button { editingValue = true } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(trDisplay(burn.isManualValue ? "Eigene Schätzung" : "Geschätzter Kartenwert"))
                                .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                            if let low = burn.valueLowCents, let high = burn.valueHighCents {
                                AnimatedMoneyText(low: low, high: high, currency: burn.currency).font(.subheadline.bold())
                            } else { Text(trDisplay("—")).font(.subheadline.bold()).foregroundStyle(.white) }
                        }
                        Image(systemName: "pencil").font(.caption).foregroundStyle(Color.scoutEditorialGold)
                    }
                }.buttonStyle(.plain).fixedSize(horizontal: true, vertical: false).disabled(burn.totalCards == 0)
                    .accessibilityLabel(tr("Kartenwert bearbeiten"))
            }
            HStack {
                Button {
                    if needsValue { editingValue = true } else { addPurchase() }
                } label: {
                    Label(trDisplay(needsValue ? "Wert eintragen" : "Kauf eintragen"), systemImage: "plus")
                        .font(.caption.bold()).padding(.horizontal, 13).padding(.vertical, 10)
                        .foregroundStyle(Color.scoutButtonFill).background(Color.scoutEditorialGold, in: Capsule())
                }
                    .buttonStyle(CollectorPressStyle())
                Spacer(minLength: 4)
                if showDetailLink {
                    NavigationLink { BurnCountDetailView(initialCurrency: burn.currency) } label: {
                        Label(tr("Bilanz"), systemImage: "arrow.up.right").font(.caption.bold()).foregroundStyle(.white.opacity(0.85)).frame(minHeight: 44)
                    }.accessibilityLabel(tr("Burn Count und Ausgaben im Detail"))
                }
            }
        }.padding(20).background { CardArena(color: Color(red: 0.15, green: 0.23, blue: 0.17)) }
            .overlay { FoilSweep() }.clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.scoutEditorialGold.opacity(0.4)))
            .sheet(isPresented: $editingValue) { ManualBurnValueEditor(currency: burn.currency) }
    }
    private var resultColor: Color {
        switch burn.performance {
        case .excellent: Color(red: 0.38, green: 0.95, blue: 0.65)
        case .ahead: Color(red: 0.55, green: 0.88, blue: 0.68)
        case .behind: Color(red: 1, green: 0.70, blue: 0.36)
        case .heavyBurn: Color(red: 1, green: 0.48, blue: 0.43)
        case .breakEven, .uncertain: .scoutEditorialGold
        case .unknown: .white.opacity(0.65)
        }
    }
    private var resultWeight: Font.Weight {
        switch burn.performance {
        case .excellent, .heavyBurn: .black
        default: .bold
        }
    }
    private var resultDescription: String {
        switch burn.performance {
        case .excellent: tr("Stark im Plus")
        case .ahead: tr("Im Plus")
        case .behind: tr("Im Minus")
        case .heavyBurn: tr("Hoher Burn")
        case .breakEven: tr("Ausgeglichen")
        case .uncertain: tr("Gewinn oder Verlust noch offen")
        case .unknown: tr("Angaben fehlen")
        }
    }
    private var needsValue: Bool { burn.spentCents != nil && burn.valueLowCents == nil && burn.totalCards > 0 }
    private var headline: String {
        guard let high = burn.burnHighCents, let low = burn.burnLowCents else { return "—" }
        if low == 0 && high == 0 { return money(0) }
        return low == high ? money(high) : "\(money(low)) – \(money(high))"
    }
    private var valueLabel: String {
        guard let low = burn.valueLowCents, let high = burn.valueHighCents else { return "—" }
        return low == high ? money(low) : "\(money(low))–\(money(high))"
    }
    private func burnMetric(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(trDisplay(title)).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text(trDisplay(text)).font(.subheadline.bold()).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func money(_ cents: Int) -> String { CollectionCardValue.money(cents, currency: burn.currency) }
}

struct BurnMascot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let mood: BurnMood
    @State private var tapped = false
    var body: some View {
        Group {
            if reduceMotion || scenePhase != .active { character }
            else {
                PhaseAnimator([false, true]) { floating in
                    character.offset(y: floating ? -4 : 3).rotationEffect(.degrees(floating ? 2 : -2))
                } animation: { _ in .easeInOut(duration: 2.2) }
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: mood.rawValue)
            .scaleEffect(tapped && !reduceMotion ? 1.12 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.45), value: tapped)
            .onTapGesture {
                tapped = true
                Task { try? await Task.sleep(for: .milliseconds(200)); tapped = false }
            }
            .accessibilityLabel(trDisplay(mood == .proud ? "Scout freut sich" : mood == .roasted ? "Scout schaut verlegen" : "Scout zählt nach"))
    }
    private var character: some View {
        Image("BurnMascot-\(mood.rawValue)").resizable().scaledToFit().id(mood.rawValue).transition(.opacity)
    }
}

struct BurnCountDetailView: View {
    @Environment(AppStore.self) private var store
    let initialCurrency: String
    @State private var selectedCurrency = ""
    @State private var editingPurchase: CardPurchase?
    @State private var editingValue = false
    var body: some View {
        let stats = store.dashboardStatistics
        let currencies = Array(Set(stats.spendingCurrencies + stats.valueCurrencies + [initialCurrency])).sorted()
        let currency = currencies.contains(selectedCurrency) ? selectedCurrency : initialCurrency
        let burn = BurnCount(statistics: stats, currency: currency, manualValueCents: store.library.currentManualBurnValue(currency: currency)?.amountCents)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if currencies.count > 1 {
                    Picker(tr("Währung · ohne Umrechnung"), selection: Binding(get: { currency }, set: { selectedCurrency = $0 })) {
                        ForEach(currencies, id: \.self) { Text(trDisplay($0)).tag($0) }
                    }.pickerStyle(.segmented)
                }
                BurnCountCard(burn: burn, addPurchase: { editingPurchase = newCardPurchase(currency: currency) }, showDetailLink: false)
                Button { editingValue = true } label: {
                    Label(trDisplay(store.library.currentManualBurnValue(currency: currency) == nil ? "Wert eintragen" : "Wert bearbeiten"), systemImage: "pencil.line")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(ScoutPrimaryButtonStyle()).disabled(store.library.collectedCards.isEmpty)
                if let value = store.library.currentManualBurnValue(currency: currency) {
                    Text(tr("Stand: \(value.recordedAt.scoutFormatted(date: .abbreviated, time: .omitted)) · bei Bestandsänderung erneut bestätigen"))
                        .font(.caption).foregroundStyle(Color.scoutMuted)
                }
                Text(tr("So zählt der Burn Count")).font(.title3.bold())
                Text(tr("Karten, Packs und Boxen minus geschätzter Kartenwert. Versand und Gebühren inklusive; Zubehör ausgeschlossen."))
                    .font(.subheadline).foregroundStyle(Color.scoutMuted)
                Text(tr("Positiv: verbrannt. Negativ: Kartenwert über Ausgaben. Ohne vollständigen Kartenwert bleibt die Bilanz offen; du kannst eine eigene Schätzung eintragen."))
                    .font(.caption).foregroundStyle(Color.scoutMuted)
                NavigationLink { PurchaseLedgerView() } label: { Label(tr("Kaufbuch"), systemImage: "book.closed") }.buttonStyle(ScoutSecondaryButtonStyle())
                NavigationLink { CollectionStatisticsView() } label: { Label(tr("Wertentwicklung & Top-Karten"), systemImage: "chart.xyaxis.line") }.buttonStyle(ScoutSecondaryButtonStyle())
            }.padding(20)
        }.background(Color.scoutCanvas).navigationTitle(tr("Burn Count")).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingPurchase) { PurchaseEditorView(purchase: $0) }
            .sheet(isPresented: $editingValue) { ManualBurnValueEditor(currency: currency) }
    }
}

struct ShowcasePickerView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    var body: some View {
        let cards = store.library.collectedCards.filter { search.isEmpty || $0.title.localizedStandardContains(search) }
        List {
            if cards.isEmpty { Text(tr("Scanne zuerst eine Karte für deine Sammlung.")).foregroundStyle(Color.scoutMuted) }
            ForEach(cards) { card in
                Button { store.toggleCollectible(card.id) } label: {
                    HStack(spacing: 14) {
                        OwnedPhoto(name: card.frontFile, maxPixel: 300, number: "").frame(width: 45, height: 64)
                        Text(cardTitle(card)).foregroundStyle(Color.scoutInk)
                        Spacer()
                        Image(systemName: card.isCollectible == true ? "trophy.fill" : "plus.circle").foregroundStyle(Color.scoutGold)
                    }
                }.accessibilityLabel(tr("\(card.title), \(trDisplay(card.isCollectible == true ? "aus Collectibles entfernen" : "zu Collectibles hinzufügen"))"))
            }
        }.navigationTitle(tr("Deine Lieblingsstücke")).searchable(text: $search, prompt: tr("Spieler suchen"))
    }
}


struct ManualBurnValueEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let currency: String
    @State private var amount = ""
    private var cents: Int? {
        let clean = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["0", "0,00", "0.00"].contains(clean) { return 0 }
        return CardPurchase.parseAmount(clean)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(tr("0,00"), text: $amount).keyboardType(.decimalPad).accessibilityLabel(tr("Eigener Kartenwert"))
                } header: { Text(tr("Dein geschätzter Gesamtwert · \(currency)")) } footer: {
                    Text(tr("Nur für Burn Count. Marktpreise und Wertverlauf bleiben unverändert."))
                }
                Section {
                    Button(tr("Schätzung speichern")) {
                        if let cents, store.saveManualBurnValue(cents, currency: currency) { dismiss() }
                    }.buttonStyle(ScoutPrimaryButtonStyle()).disabled(cents == nil)
                }
                if store.library.currentManualBurnValue(currency: currency) != nil {
                    Button(tr("Wieder recherchierte Preise verwenden")) {
                        if store.saveManualBurnValue(nil, currency: currency) { dismiss() }
                    }
                }
            }.navigationTitle(tr("Deine Schätzung")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Speichern")) { if let cents, store.saveManualBurnValue(cents, currency: currency) { dismiss() } }.disabled(cents == nil)
                    }
                }
                .onAppear {
                    if let value = store.library.currentManualBurnValue(currency: currency) {
                        amount = decimalInput(value.amountCents)
                    }
                }
        }
    }
}


/// Interpolates the actual amounts, so a large change counts through intermediate values.
/// The saved amount is the starting point; opening a screen never resets it to zero.
struct AnimatedMoneyText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let low: Int
    let high: Int
    let currency: String
    var color: Color = .white
    var showsDirection = true
    @State private var direction = 0
    var body: some View {
        CountingMoneyText(low: Double(low), high: Double(high), currency: currency)
            .monospacedDigit()
            .foregroundStyle(showsDirection && direction != 0 ? (direction > 0 ? Color.green : Color.orange) : color)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1), value: low)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1), value: high)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: direction)
            .onChange(of: low) { old, new in
                direction = reduceMotion || !showsDirection ? 0 : (new > old ? 1 : -1)
            }
            .onChange(of: currency) { direction = 0 }
            .task(id: low) {
                do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
                direction = 0
            }
            .accessibilityLabel(low == high ? CollectionCardValue.money(low, currency: currency) :
                "\(CollectionCardValue.money(low, currency: currency)) – \(CollectionCardValue.money(high, currency: currency))")
            .id(currency)
    }
}

private struct CountingMoneyText: View, Animatable {
    var low: Double
    var high: Double
    let currency: String
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(low, high) }
        set { low = newValue.first; high = newValue.second }
    }
    var body: some View {
        let first = CollectionCardValue.money(Int(low.rounded()), currency: currency)
        let last = CollectionCardValue.money(Int(high.rounded()), currency: currency)
        Text(low.rounded() == high.rounded() ? first : "\(first) – \(last)")
    }
}
