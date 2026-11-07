import SwiftUI
import CardScoutCore

/// A presentation-only deck. Swiping never changes ownership or collectibles.
struct ShowcaseDeck: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cards: [OwnedCard]
    var immersive = false
    @State private var selectedID: String?
    @State private var drag = CGSize.zero
    @State private var flipped = false
    @State private var departing = false
    @State private var transitionTask: Task<Void, Never>?
    @State private var showingRoom = false

    init(cards: [OwnedCard], immersive: Bool = false, initialCardID: String? = nil) {
        self.cards = cards
        self.immersive = immersive
        _selectedID = State(initialValue: initialCardID)
    }
    private var index: Int { cards.firstIndex { $0.id == selectedID } ?? 0 }
    private var active: OwnedCard? { cards.indices.contains(index) ? cards[index] : nil }
    private var nextCards: [OwnedCard] {
        guard cards.count > 1 else { return [] }
        return (1...min(2, cards.count - 1)).map { cards[(index + $0) % cards.count] }
    }
    var body: some View {
        if let card = active {
            VStack(spacing: immersive ? 8 : 12) {
                if !immersive { deckHeader }
                artwork(card)
                cardInfo(card)
                controls(card)
            }
            .padding(.vertical, immersive ? 0 : 4)
            .sensoryFeedback(.selection, trigger: selectedID)
            .sensoryFeedback(.selection, trigger: flipped)
            .fullScreenCover(isPresented: $showingRoom) {
                ShowcaseRoom(initialCardID: card.id)
            }
            .onChange(of: cards.map(\.id)) { _, _ in
                transitionTask?.cancel()
                departing = false; drag = .zero; flipped = false
                if !cards.contains(where: { $0.id == selectedID }) { selectedID = cards.first?.id }
            }
            .onDisappear {
                transitionTask?.cancel()
                departing = false; drag = .zero
            }
        }
    }
    private var deckHeader: some View {
        HStack {
            Text(tr("\(index + 1) / \(cards.count)")).font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(Color.scoutMuted).accessibilityLabel(tr("Karte \(index + 1) von \(cards.count)"))
            Spacer()
            if !immersive {
                Button { showingRoom = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }.accessibilityLabel(trDisplay("Showcase im Vollbild"))
            }
        }.foregroundStyle(Color.scoutGold).frame(height: 30)
    }
    private func artwork(_ card: OwnedCard) -> some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - (immersive ? 0 : 8))
            ZStack {
                if !immersive {
                    ForEach(Array(nextCards.enumerated().reversed()), id: \.element.id) { offset, behind in
                        ShowcaseDeckSurface(card: behind, back: false)
                            .frame(width: width, height: width * 1.4)
                            .scaleEffect(1 - CGFloat(offset + 1) * 0.055)
                            .rotationEffect(.degrees(Double(offset == 0 ? 4 : -6)))
                            .offset(x: CGFloat(offset == 0 ? 4 : -5), y: CGFloat(offset + 1) * 6)
                            .opacity(offset == 0 ? 0.45 : 0.2)
                            .accessibilityHidden(true).allowsHitTesting(false)
                    }
                }
                ShowcaseFlippingCard(card: card, flipped: flipped, light: reduceMotion ? .zero : CGSize(width: max(-1, min(1, drag.width / 150)), height: max(-1, min(1, drag.height / 120))))
                    .frame(width: width, height: width * 1.4)
                    .modifier(ShowcaseFloat(enabled: drag == .zero && !departing))
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width / 22)))
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(max(-16, min(16, drag.width / 10)))), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(max(-8, min(8, -drag.height / 12)))), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
                    .offset(x: drag.width, y: drag.height * 0.15)
                    .contentShape(Rectangle())
                    .onTapGesture { flip(card) }
                    .simultaneousGesture(swipe)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cardTitle(card))
                    .accessibilityValue(trDisplay(flipped ? "Rückseite" : "Vorderseite"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { flip(card) }
                    .accessibilityAction(named: Text(trDisplay("Nächste Karte"))) { advance(-1) }
                    .accessibilityAction(named: Text(trDisplay("Vorherige Karte"))) { advance(1) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.aspectRatio(5 / 7, contentMode: .fit).frame(maxWidth: immersive ? 680 : 460)
    }
    private func cardInfo(_ card: OwnedCard) -> some View {
        VStack(spacing: 6) {
            Text(cardTitle(card)).font(.system(.title2, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.scoutInk).multilineTextAlignment(.center).lineLimit(2)
            let metadata = [card.analysis?.year.map(String.init), card.analysis?.setName,
                            card.analysis?.parallel ?? card.analysis?.subset, card.analysis?.serialNumber]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !metadata.isEmpty {
                Text(trDisplay(metadata)).font(.caption).foregroundStyle(Color.scoutMuted)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            if let value = store.dashboardStatistics.values.first(where: { $0.cardID == card.id }) {
                Text(trDisplay(value.label)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(Color.scoutGold)
            }
        }.frame(maxWidth: .infinity)
    }
    private func controls(_ card: OwnedCard) -> some View {
        HStack(spacing: 0) {
            action("arrow.left", label: "Vorherige Karte", enabled: cards.count > 1) { advance(1) }
            Spacer(minLength: 4)
            action(card.isFavorite == true ? "heart.fill" : "heart", label: card.isFavorite == true ? "Favorit entfernen" : "Als Favorit merken", highlighted: card.isFavorite == true) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) {
                    store.toggleFavorite(card.id)
                }
            }
            Spacer(minLength: 4)
            action("arrow.triangle.2.circlepath", label: "Karte umdrehen", enabled: card.backFile != nil, highlighted: flipped) { flip(card) }
            Spacer(minLength: 4)
            NavigationLink { CardDetailView(cardID: card.id) } label: {
                Image(systemName: "arrow.up.right").frame(width: 46, height: 46)
                    .background(Color.scoutElevated, in: Circle())
            }.accessibilityLabel(tr("Kartendetails öffnen"))
            Spacer(minLength: 4)
            action("arrow.right", label: "Nächste Karte", enabled: cards.count > 1) { advance(-1) }
        }.font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.scoutInk)
            .buttonStyle(CollectorPressStyle())
            .disabled(departing)
    }
    private func action(_ symbol: String, label: String, enabled: Bool = true, highlighted: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).contentTransition(.symbolEffect(.replace)).frame(width: 46, height: 46)
                .foregroundStyle(highlighted ? Color.scoutGold : Color.scoutInk)
                .background(highlighted ? Color.scoutGold.opacity(0.17) : Color.scoutElevated, in: Circle())
        }.disabled(!enabled).opacity(enabled ? 1 : 0.25).accessibilityLabel(trDisplay(label))
    }
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard !departing, abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                // One-card decks still tilt, then spring back.
                drag = CGSize(width: value.translation.width, height: value.translation.height)
            }
            .onEnded { value in
                guard !departing else { return }
                let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.2
                if cards.count > 1 && horizontal && (abs(value.translation.width) > 75 || abs(value.predictedEndTranslation.width) > 150) {
                    advance(value.translation.width < 0 ? -1 : 1)
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }
    private func flip(_ card: OwnedCard) {
        guard card.backFile != nil, !departing else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) { flipped.toggle() }
    }
    private func advance(_ direction: Int) {
        guard cards.count > 1, !departing else { return }
        let next = cards[(index + (direction < 0 ? 1 : cards.count - 1)) % cards.count].id
        if reduceMotion {
            selectedID = next; flipped = false; drag = .zero
            return
        }
        departing = true
        withAnimation(.easeIn(duration: 0.22)) { drag = CGSize(width: CGFloat(direction) * 520, height: -30) }
        transitionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(230)) } catch { return }
            guard cards.contains(where: { $0.id == next }) else { departing = false; drag = .zero; return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedID = next; flipped = false; drag = .zero; departing = false
            }
        }
    }
}

private struct ShowcaseFlippingCard: View, Animatable {
    let card: OwnedCard
    var angle: Double
    var light: CGSize
    init(card: OwnedCard, flipped: Bool, light: CGSize) {
        self.card = card; angle = flipped ? 180 : 0; self.light = light
    }
    var animatableData: Double { get { angle } set { angle = newValue } }
    var body: some View {
        ZStack {
            ShowcaseDeckSurface(card: card, back: false, light: light, effects: true).opacity(angle <= 90 ? 1 : 0)
            if card.backFile != nil {
                ShowcaseDeckSurface(card: card, back: true, light: light, effects: true)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(angle > 90 ? 1 : 0)
            }
        }.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }
}

private struct ShowcaseDeckSurface: View {
    let card: OwnedCard
    let back: Bool
    var light = CGSize.zero
    var effects = false
    var body: some View {
        LocalCardPhoto(name: back ? card.backFile : card.frontFile, maxPixel: 2000, cutout: true) { image, loading in
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .overlay {
                        if effects {
                            ShowcaseCardLight(light: light)
                                .mask(Image(uiImage: image).resizable().scaledToFit())
                        }
                    }
                    .shadow(color: .black.opacity(effects ? 0.35 : 0.1), radius: effects ? 14 : 4,
                            x: light.width * -10, y: effects ? 12 + light.height * 5 : 3)
            } else if loading {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo").foregroundStyle(Color.scoutMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// A presentation highlight on the card texture, without a surrounding frame.
private struct ShowcaseCardLight: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let light: CGSize
    var body: some View {
        if !reduceMotion && scenePhase == .active {
            GeometryReader { geometry in
                PhaseAnimator([false, true]) { phase in
                    LinearGradient(colors: [.clear, .white.opacity(0.035), .white.opacity(0.14), .white.opacity(0.035), .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.65, height: geometry.size.height * 2)
                        .rotationEffect(.degrees(-22 + Double(light.width) * 12))
                        .offset(x: (phase ? geometry.size.width * 1.4 : -geometry.size.width) + light.width * geometry.size.width * 0.3,
                                y: -geometry.size.height / 2)
                } animation: { _ in .linear(duration: 3.2).delay(1.8) }
            }.clipped().blendMode(.screen).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

private struct ShowcaseFloat: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let enabled: Bool
    func body(content: Content) -> some View {
        let moving = enabled && !reduceMotion && scenePhase == .active
        content.phaseAnimator(moving ? [false, true] : [false]) { view, phase in
            view.offset(y: moving ? (phase ? -4 : 2) : 0)
                .rotation3DEffect(.degrees(moving ? (phase ? 4 : -4) : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .rotation3DEffect(.degrees(moving ? (phase ? -1.5 : 1.5) : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        } animation: { _ in .easeInOut(duration: 3) }
    }
}

private struct ShowcaseRoom: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let initialCardID: String
    var body: some View {
        NavigationStack {
            ScrollView {
                ShowcaseDeck(cards: store.library.collectibles, immersive: true, initialCardID: initialCardID)
                    .frame(maxWidth: 680).padding(.horizontal, 6).padding(.bottom, 8).frame(maxWidth: .infinity)
            }
            .background(Color.scoutPhotoBackdrop.ignoresSafeArea())
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel(tr("Schließen"))
                }
            }
        }.preferredColorScheme(.dark)
    }
}
