import SwiftUI
import Charts
import CardScoutCore

private func binderColor(_ name: String) -> Color {
    if name.localizedCaseInsensitiveContains("bowman") { return Color(red: 0.13, green: 0.28, blue: 0.50) }
    if name.localizedCaseInsensitiveContains("donruss") { return .scoutBrandLight }
    if name.localizedCaseInsensitiveContains("topps") { return Color(red: 0.47, green: 0.20, blue: 0.17) }
    return Color(red: 0.28, green: 0.23, blue: 0.43)
}

/// Field markings and diagonal foil bands, drawn locally behind the real card photos.
struct CardArena: View {
    var color: Color = .scoutBrandLight
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [color, Color(red: 0.035, green: 0.07, blue: 0.065)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Path { path in
                    for index in 0...7 {
                        let x = CGFloat(index) * geometry.size.width / 6
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x - 65, y: geometry.size.height))
                    }
                }.stroke(.white.opacity(0.07), lineWidth: 1)
                Rectangle().fill(.white.opacity(0.045)).frame(width: 65)
                    .rotationEffect(.degrees(24)).offset(x: geometry.size.width * 0.25)
                Circle().fill(color.opacity(0.6)).blur(radius: 65)
                    .frame(width: 180, height: 180).offset(x: geometry.size.width * 0.4, y: -60)
            }
        }.clipped().accessibilityHidden(true)
    }
}

struct CardFan: View {
    let cards: [OwnedCard]
    var body: some View {
        ZStack {
            ForEach(Array(cards.prefix(3).enumerated()), id: \.element.id) { index, card in
                OwnedPhoto(name: card.frontFile, maxPixel: 700, number: "")
                    .frame(width: 90, height: 126)
                    .background(Color.scoutPhotoBackdrop, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 8)
                    .rotationEffect(.degrees(Double(index - 1) * 13))
                    .offset(x: CGFloat(index - 1) * 25, y: index == 1 ? -9 : 3)
            }
            if cards.isEmpty {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 60, weight: .ultraLight)).foregroundStyle(.white.opacity(0.25))
            }
        }.frame(width: 160, height: 158).accessibilityHidden(true)
    }
}

struct FoilSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        if !reduceMotion && scenePhase == .active {
            GeometryReader { geometry in
                PhaseAnimator([false, true]) { phase in
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.07), Color.scoutEditorialGold.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 90, height: geometry.size.height * 2)
                        .rotationEffect(.degrees(22))
                        .offset(x: phase ? geometry.size.width + 120 : -160, y: -geometry.size.height / 2)
                } animation: { _ in .linear(duration: 3.5).delay(3) }
            }.clipped().allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct BinderCover: View {
    @Environment(AppStore.self) private var store
    let binder: CollectionBinder
    var body: some View {
        let cards = binder.cards(in: store.library).sorted { $0.createdAt > $1.createdAt }
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("\(Set(binder.collections.map { String($0.year) }).sorted().joined(separator: " · "))"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.3).foregroundStyle(.white.opacity(0.65))
                Text(trDisplay(binder.name)).font(.system(.title2, design: .rounded, weight: .black)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tr("\(cards.count) KARTEN  /  \(binder.collections.count) TYPEN"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                Label(tr("Binder öffnen"), systemImage: "arrow.up.right")
                    .font(.caption.weight(.bold)).foregroundStyle(Color.scoutEditorialGold)
            }.frame(maxWidth: .infinity, alignment: .leading)
            CardFan(cards: Array(cards.prefix(3))).frame(width: 120).clipped()
        }.padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 10)
            .background { CardArena(color: binderColor(binder.name)) }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
            .accessibilityElement(children: .combine)
    }
}

struct BinderContentsView: View {
    @Environment(AppStore.self) private var store
    let binderID: String
    @State private var search = ""
    var body: some View {
        if let binder = store.library.binders.first(where: { $0.id == binderID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(tr("\(binder.cards(in: store.library).count) Karten · nach Jahr und Kartentyp sortiert"))
                        .font(.subheadline).foregroundStyle(Color.scoutMuted)
                    ForEach(Array(Set(binder.collections.map(\.year))).sorted(by: >), id: \.self) { year in
                        let types = binder.collections.filter {
                            $0.year == year && (search.isEmpty || "\($0.name) \($0.subset) \($0.parallel ?? "")".localizedStandardContains(search))
                        }
                        if !types.isEmpty {
                            ScoutSectionHeader(trDisplay(String(year)), subtitle: tr("\(types.count) Kartentypen"))
                            ForEach(types) { collection in
                                NavigationLink { CollectionView(collectionID: collection.id) } label: {
                                    CollectionCover(collection: collection)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if !search.isEmpty && !binder.collections.contains(where: {
                        "\($0.name) \($0.subset) \($0.parallel ?? "")".localizedStandardContains(search)
                    }) { ScoutEmptyState(symbol: "magnifyingglass", title: tr("Keine Kartentypen gefunden.")) }
                }.padding(20)
            }.background(Color.scoutCanvas).navigationTitle(trDisplay(binder.name))
                .searchable(text: $search, prompt: tr("Base, Chrome, Optic oder Variante"))
        } else { ScoutEmptyState(symbol: "books.vertical", title: tr("Binder nicht verfügbar.")) }
    }
}

struct ShowcaseCard: View {
    let card: OwnedCard
    var position: Int = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "trophy.fill").foregroundStyle(Color.scoutEditorialGold)
                Spacer(minLength: 0)
            }.foregroundStyle(.white.opacity(0.7)).padding(12)
            OwnedPhoto(name: card.frontFile, maxPixel: 1100, number: card.analysis?.cardNumber ?? "")
                .padding(.horizontal, 18).padding(.bottom, 18)
                .shadow(color: Color.scoutEditorialGold.opacity(0.18), radius: 18, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(cardTitle(card)).font(.system(.headline, design: .rounded, weight: .heavy)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                Text(trDisplay([card.analysis?.year.map(String.init), card.analysis?.setName, card.analysis?.parallel ?? card.analysis?.subset].compactMap { $0 }.joined(separator: " · ")))
                    .font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.045))
        }.background(LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.17), Color(red: 0.05, green: 0.075, blue: 0.065)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { FoilSweep() }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(LinearGradient(colors: [Color.scoutEditorialGold.opacity(0.7), .white.opacity(0.08), Color.scoutEditorialGold.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .accessibilityElement(children: .combine).accessibilityHint(tr("Kartendetails öffnen"))
    }
}

struct CollectorPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

struct CollectiblesView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        ScrollView {
            if store.library.collectibles.isEmpty {
                ScoutEmptyState(symbol: "trophy", title: tr("Deine Collectibles."), message: tr("Markiere deine Lieblingsstücke mit der Trophäe in den Kartendetails.")).padding(20)
            } else {
                ShowcaseDeck(cards: store.library.collectibles).padding(20)
            }
        }.background(Color.scoutCanvas).navigationTitle(tr("Collectibles"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ShowcasePickerView() } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                        .accessibilityLabel(tr("Karte auswählen"))
                }
            }
    }
}
