import SwiftUI
import CardScoutCore

private enum ToppsRankingView: String {
    case chases
    case market
}

private enum ToppsPriceState: String, CaseIterable {
    case all
    case priced
    case open

    var label: String {
        switch self {
        case .all: "Alle"
        case .priced: "Mit Preis"
        case .open: "Preis offen"
        }
    }
}

struct HotListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var initialProductID: String? = nil
    @State private var detail: RankedChase?
    @State private var didSelectInitial = false
    @State private var query = ""
    @State private var customFilter = false
    @State private var choosingProduct = false
    @State private var limit = 60
    @State private var unknownLimit = 60
    @State private var showingUnknown = true
    @State private var ranking: ChaseRanking?
    @State private var rankingContextID: String?
    @State private var toppsView: ToppsRankingView = .chases
    @State private var toppsFamily: ToppsChaseFamily = .all
    @State private var toppsPriceState: ToppsPriceState = .all

    private var products: [ChaseProduct] {
        (store.library.chaseCatalog?.products ?? []).map { original in
            guard MarketSnapshot.productIDs.contains(original.id) else { return original }
            let marketCards = store.markets[original.id]?.usableCards ?? []
            if original.hasOfficialChaseChecklist { return original.mergingMarketCards(marketCards) }
            var marketProduct = original
            marketProduct.cards = marketCards
            return marketProduct
        }
    }
    private var selected: ChaseProduct? {
        products.first { $0.id == store.library.selectedChaseProductID } ?? products.first
    }
    private var rankingTaskID: String {
        guard let product = selected else { return "none" }
        return "\(rankingContext(for: product))|\(store.library.chaseCatalog?.revision ?? "")|\(store.markets[product.id]?.revision ?? "")"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let product = selected {
                    productSelector(product)
                    filters(product)
                    results(product)
                    collectionNotes(product)
                } else {
                    ScoutEmptyState(symbol: "scope", title: tr("Chase"), message: tr("Wähle dein Set. Entdecke die Chase-Karten."))
                        .padding(.top, 32)
                    Button(tr("Sets laden")) { Task { await store.reloadChases() } }
                        .buttonStyle(ScoutPrimaryButtonStyle())
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 32)
        }
        .background(Color.scoutCanvas)
        .navigationTitle(tr("Rangliste"))
        .searchable(text: $query, prompt: tr("Spieler, Variante oder Nummer"))
        .refreshable {
            if let product = selected, MarketSnapshot.productIDs.contains(product.id) { await store.loadMarket(product.id) }
            else { await store.reloadChases() }
        }
        .task {
            if !didSelectInitial, let initialProductID {
                store.commit { $0.selectedChaseProductID = initialProductID }; didSelectInitial = true
            }
            if products.isEmpty { await store.reloadChases() }
        }
        .task(id: selected?.id) {
            guard let product = selected else { return }
            if product.hasOfficialChaseChecklist {
                toppsView = .chases
                toppsFamily = .all
                toppsPriceState = .all
            }
            let id = product.id
            await store.loadMarket(id)
            while MarketSnapshot.productIDs.contains(id) && !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                if let market = store.markets[id], !market.isFresh, market.status == "ready" {
                    store.markets[id] = nil
                    await store.loadMarket(id)
                }
            }
        }
        .task(id: "artwork-\(selected?.id ?? "none")") {
            guard let id = selected?.id,
                  let original = store.library.chaseCatalog?.products.first(where: { $0.id == id }),
                  original.hasOfficialChaseChecklist else { return }
            let urls = original.officialChaseCards().compactMap { card -> String? in
                guard let reference = original.imageReference(for: card), reference.isRepresentative else { return nil }
                return reference.url
            }
            await ImagePipeline.shared.prefetch(urls)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let id = selected?.id { Task { await store.loadMarket(id) } }
        }
        .task(id: rankingTaskID) {
            guard let product = selected else { return }
            let contextID = rankingContext(for: product)
            let cards = rankingCards(for: product)
            ranking = nil; rankingContextID = nil; limit = 60; unknownLimit = 60; showingUnknown = true
            let calculated = await Task.detached(priority: .userInitiated) {
                ChaseRanking(cards: cards, sold: MarketSnapshot.productIDs.contains(product.id))
            }.value
            guard !Task.isCancelled else { return }
            ranking = calculated; rankingContextID = contextID
            if let snapshot = store.markets[product.id] { store.recordMarketView(snapshot) }
        }
        .onChange(of: query) { _, _ in limit = 60; unknownLimit = 60 }
        .sheet(isPresented: $choosingProduct) {
            ChaseProductPicker(products: products, selectedID: selected?.id) { id in
                store.commit { $0.selectedChaseProductID = id }
                query = ""
            }
        }
        .sheet(isPresented: $customFilter) {
            if let product = selected {
                ChaseThresholdSheet(current: store.library.chaseFilter(for: product.id).minimumCents) { cents in setMinimum(cents, product: product) }
            }
        }
        .sheet(item: $detail) { entry in
            if let product = products.first(where: { $0.cards.contains(where: { $0.id == entry.id }) }) {
                ChaseDetailView(card: entry.card, rank: entry.rank, product: product)
            }
        }
    }

    private func productSelector(_ product: ChaseProduct) -> some View {
        Button { choosingProduct = true } label: {
            ScoutPanel {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        ScoutEyebrow(tr("\(product.year)"))
                        Text(product.name).font(.title2.weight(.bold)).foregroundStyle(Color.scoutInk)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Text(tr("Set wechseln")).font(.caption.weight(.medium)).foregroundStyle(Color.scoutAccent)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "rectangle.stack")
                        .font(.title2.weight(.light)).foregroundStyle(Color.scoutAccent)
                        .frame(width: 54, height: 66)
                        .background(Color.scoutAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Color.scoutMuted)
                }
            }
        }.buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(tr("Set: \(product.title). Set wechseln"))
            .accessibilityIdentifier("chase-product-picker")
    }

    private func filters(_ product: ChaseProduct) -> some View {
        let filter = store.library.chaseFilter(for: product.id)
        let usesSales = MarketSnapshot.productIDs.contains(product.id)
        let marketCount = soldMarketCards(in: product).count
        return VStack(alignment: .leading, spacing: 12) {
            if product.hasOfficialChaseChecklist {
                ScoutEyebrow(tr("WAS WILLST DU SEHEN?"))
                HStack(spacing: 10) {
                    toppsModeButton(
                        title: tr("Chase-Karten"),
                        subtitle: tr("\(product.officialChaseCards().count) Karten"),
                        systemImage: "sparkles",
                        view: .chases
                    )
                    toppsModeButton(
                        title: "Marktpreise",
                        subtitle: marketCount > 0 ? "\(marketCount) Werte" : "90 Tage",
                        systemImage: "chart.line.uptrend.xyaxis",
                        view: .market
                    )
                }
                if toppsView == .chases {
                    toppsChaseFilters(product)
                } else {
                    valueFilters(filter, product: product)
                    Text(tr("Raw-Verkäufe · 90 Tage · ohne Versand"))
                        .font(.caption).foregroundStyle(Color.scoutMuted)
                }
            } else {
                HStack {
                    ScoutEyebrow(tr("KARTENWERT · USD"))
                    Spacer()
                    Text(trDisplay(usesSales ? "Verkäufe · 90 Tage" : "Richtwerte"))
                        .font(.caption).foregroundStyle(Color.scoutMuted)
                }
                valueFilters(filter, product: product)
                Text(trDisplay(usesSales ? "Basis & Inserts · ohne Parallels\nRaw · ohne Versand" : "\(trDisplay(product.coverageLabel))\nRaw · ohne Versand"))
                    .font(.caption).foregroundStyle(Color.scoutMuted)
            }
        }
    }

    private func toppsModeButton(title: String, subtitle: String, systemImage: String, view: ToppsRankingView) -> some View {
        let selected = toppsView == view
        return Button {
            toppsView = view
            limit = 60
            unknownLimit = 60
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Label(trDisplay(title), systemImage: systemImage).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(trDisplay(subtitle)).font(.caption2.weight(.medium)).monospacedDigit().opacity(selected ? 0.72 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(selected ? Color.white : Color.scoutMuted)
            .background(selected ? Color.scoutButtonFill : Color.scoutSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(.white.opacity(selected ? 0 : 0.065)))
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(tr("\(title), \(subtitle)"))
        .accessibilityIdentifier(view == .chases ? "topps-view-chases" : "topps-view-market")
    }

    private func toppsChaseFilters(_ product: ChaseProduct) -> some View {
        let familyCards = product.officialChaseCards(family: toppsFamily)
        let pricedCount = familyCards.filter(hasSoldValue).count
        let openCount = familyCards.count - pricedCount
        return VStack(alignment: .leading, spacing: 12) {
            ScoutEyebrow(tr("CHASE-TYP"))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ToppsChaseFamily.allCases, id: \.rawValue) { family in
                        let count = product.officialChaseCards(family: family).count
                        Button {
                            toppsFamily = family
                            limit = 60
                            unknownLimit = 60
                        } label: {
                            ScoutChip(tr("\(family.label) · \(count)"), selected: toppsFamily == family)
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(toppsFamily == family ? .isSelected : [])
                        .accessibilityIdentifier("topps-family-\(family.rawValue)")
                    }
                }
            }.scrollIndicators(.hidden)
            ScoutEyebrow(tr("PREIS"))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(ToppsPriceState.allCases, id: \.rawValue) { state in
                        let count = switch state {
                        case .all: familyCards.count
                        case .priced: pricedCount
                        case .open: openCount
                        }
                        Button {
                            toppsPriceState = state
                            limit = 60
                            unknownLimit = 60
                        } label: {
                            ScoutChip(tr("\(state.label) · \(count)"), selected: toppsPriceState == state)
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(toppsPriceState == state ? .isSelected : [])
                        .accessibilityIdentifier("topps-price-\(state.rawValue)")
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private func valueFilters(_ filter: ChaseFilter, product: ChaseProduct) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach([0, 5000, 10000, 20000], id: \.self) { cents in
                    Button { setMinimum(cents, product: product) } label: {
                        ScoutChip(trDisplay(cents == 0 ? "Alle" : "> \(cents / 100) $"), selected: filter.minimumCents == cents)
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(filter.minimumCents == cents ? .isSelected : [])
                        .accessibilityLabel(trDisplay(cents == 0 ? "Alle Karten mit Preis" : "Karten über \(cents / 100) US-Dollar"))
                        .accessibilityIdentifier("chase-minimum-\(cents)")
                }
                Button { customFilter = true } label: {
                    ScoutChip(trDisplay([0, 5000, 10000, 20000].contains(filter.minimumCents) ? "Eigener" : filter.label),
                              systemImage: "slider.horizontal.3", selected: ![0, 5000, 10000, 20000].contains(filter.minimumCents))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(tr("Eigenen Mindestwert eingeben"))
            }
        }.scrollIndicators(.hidden)
    }

    @ViewBuilder private func results(_ product: ChaseProduct) -> some View {
        let usesSales = MarketSnapshot.productIDs.contains(product.id)
        let market = store.markets[product.id]
        let showsMarketStatus = usesSales && (!product.hasOfficialChaseChecklist || toppsView == .market)
        if showsMarketStatus, market?.status == "refreshing" {
            ScoutPanel(padding: 16) {
                HStack(spacing: 12) {
                    ProgressView().tint(Color.scoutAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Verkäufe werden geprüft")).font(.subheadline.weight(.semibold))
                        if let market, market.totalCards > 0 {
                            Text(tr("\(market.checkedCards) von \(market.totalCards) Einträgen"))
                                .font(.caption.monospacedDigit()).foregroundStyle(Color.scoutMuted)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        if showsMarketStatus, let message = store.marketErrors[product.id] ?? market?.message, market?.status != "refreshing" {
            ScoutPanel(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(trDisplay(message), systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(Color.scoutGold)
                    Button(tr("Erneut laden")) { Task { await store.loadMarket(product.id) } }
                        .buttonStyle(ScoutSecondaryButtonStyle())
                }
            }
        }
        if rankingContextID == rankingContext(for: product), let ranking {
            if product.hasOfficialChaseChecklist, toppsView == .chases {
                officialChaseResults(ranking, product: product)
            } else {
                pricedResults(ranking, product: product, usesSales: usesSales, market: market)
            }
        } else { loadingState("Rangliste laden") }
    }

    private func officialChaseResults(_ ranking: ChaseRanking, product: ChaseProduct) -> some View {
        let priced = ranking.matching(ChaseFilter(), query: query)
        let open = ranking.unknownMatching(query: query)
        let showsPriced = toppsPriceState != .open
        let showsOpen = toppsPriceState != .priced
        let resultCount = (showsPriced ? priced.count : 0) + (showsOpen ? open.count : 0)
        return LazyVStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("\(resultCount) \(trDisplay(resultCount == 1 ? "Chase-Karte" : "Chase-Karten"))"))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .accessibilityIdentifier("chase-result-count")
                Spacer(minLength: 8)
                Text(trDisplay(toppsFamily.label)).font(.caption.weight(.medium)).foregroundStyle(Color.scoutMuted)
            }
            if showsPriced, !priced.isEmpty {
                if toppsPriceState == .all { ScoutSectionHeader(tr("Mit Preis"), trailing: tr("\(priced.count)")) }
                ForEach(Array(priced.prefix(limit))) { entry in
                    ChaseRow(card: entry.card, rank: entry.rank, product: product) { detail = entry }
                }
                if priced.count > limit {
                    Button { limit += 60 } label: {
                        Text(tr("Weitere \(min(60, priced.count - limit)) anzeigen")).frame(maxWidth: .infinity)
                    }.buttonStyle(ScoutSecondaryButtonStyle()).accessibilityIdentifier("chase-load-more")
                }
            }
            if showsOpen, !open.isEmpty {
                if toppsPriceState == .all { ScoutSectionHeader(tr("Preis offen"), trailing: tr("\(open.count)")) }
                ForEach(Array(open.prefix(unknownLimit))) { entry in
                    ChaseRow(card: entry.card, rank: nil, product: product) { detail = entry }
                }
                if open.count > unknownLimit {
                    Button { unknownLimit += 60 } label: {
                        Text(tr("Weitere \(min(60, open.count - unknownLimit)) anzeigen")).frame(maxWidth: .infinity)
                    }.buttonStyle(ScoutSecondaryButtonStyle()).accessibilityIdentifier("chase-open-load-more")
                }
            }
            if resultCount == 0 {
                ScoutEmptyState(symbol: "sparkles", title: tr("Keine Chase-Karte gefunden"), message: tr("Anderen Chase-Typ wählen oder die Suche löschen."))
                Button(tr("Alle Chase-Karten")) { resetToppsChaseFilters() }
                    .buttonStyle(ScoutSecondaryButtonStyle())
            }
        }
    }

    private func pricedResults(_ ranking: ChaseRanking, product: ChaseProduct, usesSales: Bool, market: MarketSnapshot?) -> some View {
        let filter = store.library.chaseFilter(for: product.id)
        let matches = ranking.matching(filter, query: query)
        let unknown = ranking.unknownMatching(query: query)
        return Group {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("\(matches.count) \(trDisplay(matches.count == 1 ? "Karte" : "Karten"))"))
                        .font(.title2.weight(.bold).monospacedDigit()).accessibilityIdentifier("chase-result-count")
                    Spacer()
                    Label(tr("Wert"), systemImage: "arrow.down").font(.caption.weight(.medium)).foregroundStyle(Color.scoutMuted)
                        .accessibilityLabel(tr("Nach Wert absteigend sortiert"))
                }
                ForEach(Array(matches.prefix(limit))) { entry in
                    ChaseRow(card: entry.card, rank: entry.rank, product: product) { detail = entry }
                }
                if matches.count > limit {
                    Button { limit += 60 } label: {
                        Text(tr("Weitere \(min(60, matches.count - limit)) anzeigen")).frame(maxWidth: .infinity)
                    }.buttonStyle(ScoutSecondaryButtonStyle()).accessibilityIdentifier("chase-load-more")
                }
                if matches.isEmpty && unknown.isEmpty && (!usesSales || market?.status == "ready") {
                    ScoutEmptyState(symbol: "line.3.horizontal.decrease", title: tr("Noch kein Treffer"), message: tr("Mindestwert senken oder nach einem anderen Spieler suchen."))
                    if filter.minimumCents > 0 || !query.isEmpty {
                        Button(tr("Alle Karten zeigen")) { query = ""; setMinimum(0, product: product) }
                            .buttonStyle(ScoutSecondaryButtonStyle())
                    }
                } else if usesSales && market == nil && store.marketErrors[product.id] == nil {
                    loadingState("Marktpreise laden")
                }
            }
            if !unknown.isEmpty {
                DisclosureGroup(isExpanded: $showingUnknown) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Text(tr("Nicht nach Wert einordenbar")).font(.caption).foregroundStyle(Color.scoutMuted)
                        ForEach(Array(unknown.prefix(unknownLimit))) { entry in
                            ChaseRow(card: entry.card, rank: nil, product: product) { detail = entry }
                        }
                        if unknown.count > unknownLimit {
                            Button(tr("Weitere ohne Preis anzeigen")) { unknownLimit += 60 }.buttonStyle(ScoutSecondaryButtonStyle())
                        }
                    }.padding(.top, 12)
                } label: {
                    Text(tr("Ohne Preis · \(unknown.count)")).font(.subheadline.weight(.semibold))
                }.tint(Color.scoutMuted)
            }
        }
    }

    private func loadingState(_ title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().tint(Color.scoutAccent)
            Text(trDisplay(title)).font(.subheadline).foregroundStyle(Color.scoutMuted)
        }.frame(maxWidth: .infinity).padding(.vertical, 36)
    }

    private func collectionNotes(_ product: ChaseProduct) -> some View {
        let usesSales = MarketSnapshot.productIDs.contains(product.id)
        let market = store.markets[product.id]
        return VStack(alignment: .leading, spacing: 16) {
            if usesSales, let market, market.isFresh {
                VStack(alignment: .leading, spacing: 5) {
                    Label(tr("\(market.matchedCards) mit Preis · \(market.checkedCards) geprüft"), systemImage: "checkmark.seal")
                        .font(.caption.monospacedDigit())
                    if product.hasOfficialChaseChecklist, let count = product.coverage?.cardCount {
                        Text(tr("\(count) offizielle Chase-Karten · Topps Checkliste")).font(.caption2)
                    }
                    Text(tr("CardSight · eBay · \(chaseDisplayDate(market.checkedAt)) · ohne Versand")).font(.caption2)
                    if market.capped { Text(tr("Die \(market.cards.count) höchsten Werte")).font(.caption2) }
                }.foregroundStyle(Color.scoutMuted)
            } else if !usesSales, let catalog = store.library.chaseCatalog {
                VStack(alignment: .leading, spacing: 5) {
                    if product.coverage?.status != "imported" {
                        Label(tr("Preiskatalog noch unvollständig"), systemImage: "circle.lefthalf.filled").font(.caption)
                    }
                    Text(tr("SportsCardsPro · \(chaseDisplayDate(catalog.checkedAt)) · ohne Versand")).font(.caption2)
                }.foregroundStyle(Color.scoutMuted)
            }
            ScoutPanel(padding: 16) {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(product.boxSummary, id: \.self) { Text(trDisplay($0)).font(.subheadline) }
                        Text(trDisplay(product.oddsNote)).font(.caption).foregroundStyle(Color.scoutMuted)
                        if let url = URL(string: product.sourceURL) {
                            Link(destination: url) { Label(tr("Hersteller & Box-Inhalt"), systemImage: "arrow.up.right") }
                                .font(.subheadline.weight(.medium)).padding(.vertical, 8)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                } label: {
                    Label(tr("In der Box · Hobby"), systemImage: "shippingbox").font(.subheadline.weight(.semibold))
                }.tint(Color.scoutAccent)
            }
            if let error = store.chaseError { Text(trDisplay(error)).font(.caption).foregroundStyle(Color.scoutGold) }
        }
    }

    private func rankingContext(for product: ChaseProduct) -> String {
        guard product.hasOfficialChaseChecklist else { return product.id }
        let family = toppsView == .chases ? toppsFamily.rawValue : "all"
        return "\(product.id)|\(toppsView.rawValue)|\(family)"
    }

    private func rankingCards(for product: ChaseProduct) -> [ChaseCard] {
        guard product.hasOfficialChaseChecklist else { return product.cards }
        switch toppsView {
        case .chases: return product.officialChaseCards(family: toppsFamily)
        case .market: return soldMarketCards(in: product)
        }
    }

    private func soldMarketCards(in product: ChaseProduct) -> [ChaseCard] {
        product.cards.filter(hasSoldValue)
    }

    private func hasSoldValue(_ card: ChaseCard) -> Bool {
        ["sold_median", "single_sale"].contains(card.priceKind ?? "") &&
        card.currency == "USD" && (card.priceCents ?? 0) > 0
    }

    private func resetToppsChaseFilters() {
        query = ""
        toppsFamily = .all
        toppsPriceState = .all
        limit = 60
        unknownLimit = 60
    }

    private func setMinimum(_ cents: Int, product: ChaseProduct) {
        store.commit { $0.setChaseFilter(ChaseFilter(minimumCents: cents), for: product.id) }
        limit = 60
    }
}

private struct ChaseProductPicker: View {
    @Environment(\.dismiss) private var dismiss
    let products: [ChaseProduct]
    let selectedID: String?
    let select: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScoutEyebrow(tr("WAS SAMMELST DU?"))
                    ForEach(products) { product in
                        Button {
                            select(product.id)
                            dismiss()
                        } label: {
                            ScoutPanel(padding: 16) {
                                HStack(spacing: 16) {
                                    if let card = product.cards.first(where: { $0.imageURL != nil }) ?? product.cards.first {
                                        ChaseArtwork(card: card, product: product, showsBadge: false)
                                            .frame(width: 58, height: 82).accessibilityHidden(true)
                                    } else {
                                        Image(systemName: "rectangle.stack")
                                            .font(.title2.weight(.light)).foregroundStyle(Color.scoutAccent)
                                            .frame(width: 58, height: 82)
                                            .background(Color.scoutAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(tr("\(product.brand.uppercased()) · \(String(product.year))"))
                                            .font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Color.scoutMuted)
                                        Text(product.name).font(.headline).foregroundStyle(Color.scoutInk)
                                        Text(trDisplay(product.hasOfficialChaseChecklist
                                             ? "Verkäufe + offizielle Chase-Liste"
                                             : MarketSnapshot.productIDs.contains(product.id) ? "Verkäufe · Basis & Inserts" : product.coverageLabel))
                                            .font(.caption).foregroundStyle(Color.scoutMuted)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: product.id == selectedID ? "checkmark.circle.fill" : "chevron.right")
                                        .font(product.id == selectedID ? .title3 : .caption.weight(.bold))
                                        .foregroundStyle(product.id == selectedID ? Color.scoutAccent : Color.scoutMuted)
                                }
                            }
                        }.buttonStyle(.plain).multilineTextAlignment(.leading)
                            .accessibilityLabel(trDisplay(product.title)).accessibilityValue(product.id == selectedID ? "Ausgewählt" : "")
                            .accessibilityIdentifier("chase-product-\(product.id)")
                    }
                }.padding(20)
            }.background(Color.scoutCanvas).navigationTitle(tr("Deine Sets")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { dismiss() } } }
        }.tint(Color.scoutAccent).presentationDragIndicator(.visible)
    }
}

private struct ChaseThresholdSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    let save: (Int) -> Void
    init(current: Int, save: @escaping (Int) -> Void) {
        _input = State(initialValue: NSDecimalNumber(decimal: Decimal(current) / 100).stringValue)
        self.save = save
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScoutEyebrow(tr("KARTEN ÜBER"))
                    ScoutPanel {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(tr("$")).foregroundStyle(Color.scoutMuted)
                            TextField(tr("0"), text: $input).keyboardType(.decimalPad)
                                .accessibilityLabel(tr("Mindestwert in US-Dollar")).accessibilityIdentifier("chase-custom-minimum")
                            Text(tr("USD")).font(.caption.weight(.semibold)).foregroundStyle(Color.scoutMuted)
                        }.font(.largeTitle.weight(.bold).monospacedDigit())
                    }
                    Text(tr("Nur Karten über diesem Betrag. Karten ohne Preis bleiben separat sichtbar."))
                        .font(.subheadline).foregroundStyle(Color.scoutMuted)
                    if ChaseFilter.parseDollars(input) == nil {
                        Text(tr("Betrag mit höchstens zwei Nachkommastellen eingeben.")).font(.caption).foregroundStyle(Color.scoutGold)
                    }
                    Button {
                        if let cents = ChaseFilter.parseDollars(input) { save(cents); dismiss() }
                    } label: { Text(tr("Mindestwert übernehmen")).frame(maxWidth: .infinity) }
                        .buttonStyle(ScoutPrimaryButtonStyle()).disabled(ChaseFilter.parseDollars(input) == nil)
                }.padding(24)
            }.background(Color.scoutCanvas).navigationTitle(tr("Dein Mindestwert")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .tint(Color.scoutAccent)
    }
}

private struct ChaseArtwork: View {
    let card: ChaseCard
    let product: ChaseProduct
    var showsBadge = true
    private var reference: ChaseImageReference? { product.imageReference(for: card) }
    private var accessibilityText: String {
        if let reference, reference.isRepresentative {
            return "Offizielles Design-Beispiel für \(card.variant), nicht die konkrete Karte"
        }
        return reference == nil ? "Kartenfoto nicht verfügbar" : "Kartenfoto"
    }

    var body: some View {
        CachedPhoto(url: reference?.url ?? "", number: card.number)
            .overlay(alignment: .bottomLeading) {
                if showsBadge, reference?.isRepresentative == true {
                    Text(tr("BEISPIEL"))
                        .font(.system(size: 9, weight: .black)).tracking(0.6)
                        .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 5)
                        .background(Color.scoutPhotoBackdrop.opacity(0.88), in: Capsule()).padding(7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(trDisplay(accessibilityText))
    }
}

private struct ChaseRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicType
    let card: ChaseCard
    let rank: Int?
    let product: ChaseProduct
    var open: () -> Void
    private var hunted: Bool { store.library.hasChaseHunt(card, product: product) }

    var body: some View {
        let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            Button(action: open) {
                ChaseArtwork(card: card, product: product)
                    .frame(width: dynamicType.isAccessibilitySize ? 136 : 104, height: dynamicType.isAccessibilitySize ? 184 : 150)
                    .overlay(alignment: .topLeading) {
                        if let rank {
                            Text(trDisplay(String(format: "%02d", rank))).font(.caption.weight(.black).monospacedDigit())
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 8).frame(minWidth: 31, minHeight: 28)
                                .background(rank <= 3 ? Color.scoutButtonFill : Color.scoutPhotoBackdrop.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                                .padding(5)
                        }
                    }
            }.buttonStyle(.plain).accessibilityLabel(tr("\(card.label) öffnen"))
            VStack(alignment: .leading, spacing: 10) {
                Button(action: open) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(trDisplay(card.variant)).font(.caption.weight(.semibold)).foregroundStyle(Color.scoutAccent)
                        Text(card.player).font(.headline).foregroundStyle(Color.scoutInk)
                        Text(tr("#\(card.number)")).font(.caption).foregroundStyle(Color.scoutMuted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).multilineTextAlignment(.leading)
                VStack(alignment: .leading, spacing: 4) {
                    if let value = card.valueLabel {
                        Text(trDisplay(value)).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(Color.scoutInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(trDisplay(card.priceLabel)).font(.caption2).foregroundStyle(Color.scoutMuted)
                    } else { Text(tr("Preis offen")).font(.subheadline).foregroundStyle(Color.scoutMuted) }
                }
                Button { store.addHunt(card, product: product) } label: {
                    Label(trDisplay(hunted ? "Auf Lookout" : "Merken"), systemImage: hunted ? "checkmark" : "plus")
                        .font(.caption.weight(.semibold)).foregroundStyle(hunted ? Color.scoutMuted : Color.scoutAccent)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(Color.scoutElevated, in: Capsule())
                }.buttonStyle(.plain).disabled(hunted)
                    .accessibilityLabel(trDisplay(hunted ? "\(card.player) ist auf Lookout" : "\(card.label) auf Lookout setzen"))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(rank == 1 ? Color.scoutAccent.opacity(0.32) : Color.scoutLine.opacity(0.7), lineWidth: 1)
            }
    }
}

private struct ChaseDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let card: ChaseCard
    let rank: Int?
    let product: ChaseProduct
    private var hunted: Bool { store.library.hasChaseHunt(card, product: product) }
    private var officialChase: Bool { product.officialChaseCards().contains { $0.id == card.id } }
    private var imageReference: ChaseImageReference? { product.imageReference(for: card) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 28).fill(Color.scoutSurface)
                        ChaseArtwork(card: card, product: product)
                            .frame(height: 330).frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 16)
                        if let rank { ScoutChip(tr("#\(rank)"), systemImage: rank <= 3 ? "trophy" : nil, selected: true).padding(16) }
                    }
                    if let imageReference, imageReference.isRepresentative {
                        Text(tr("\(imageReference.label) · nicht die konkrete Karte"))
                            .font(.caption2).foregroundStyle(Color.scoutMuted)
                    } else if card.imageKind == "preview" {
                        Text(tr("Hersteller-Vorschau")).font(.caption2).foregroundStyle(Color.scoutMuted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ScoutEyebrow(tr("\(product.name) · \(product.year)"))
                        Text(card.player).font(.largeTitle.weight(.bold))
                        Text(tr("\(card.variant) · #\(card.number)")).font(.subheadline).foregroundStyle(Color.scoutAccent)
                    }
                    ScoutPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            ScoutEyebrow(trDisplay(card.priceCents == nil && officialChase ? "OFFIZIELLE CHASE-KARTE" : card.priceCents == nil ? "PREIS OFFEN" : card.sales == nil ? "RICHTWERT" : "MARKTWERT · 90 TAGE"))
                            Text(trDisplay(card.valueLabel ?? "Preis offen")).font(.largeTitle.weight(.bold).monospacedDigit())
                            Text(trDisplay(card.priceCents == nil ? "Noch kein passender Raw-Verkauf" : "\(trDisplay(card.priceLabel)) · ohne Versand"))
                                .font(.caption).foregroundStyle(Color.scoutMuted)
                            if let low = card.saleLowCents, let high = card.saleHighCents, low != high {
                                Divider().overlay(Color.scoutMuted.opacity(0.1)).padding(.vertical, 2)
                                HStack(alignment: .firstTextBaseline) {
                                    Text(tr("Verkaufsspanne")).font(.caption).foregroundStyle(Color.scoutMuted)
                                    Spacer(minLength: 8)
                                    Text(tr("\(chaseMoney(low)) – \(chaseMoney(high))"))
                                        .font(.caption.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ScoutPanel {
                        VStack(alignment: .leading, spacing: 18) {
                            ScoutSectionHeader(tr("Die Karte"))
                            detailFact("Seltenheit", text: card.rarity, symbol: "sparkles")
                            detailFact("Zu finden in", text: card.packLabel, symbol: "shippingbox")
                            if !card.reason.isEmpty { detailFact("Im Fokus", text: card.reason, symbol: "scope") }
                            if let odds = card.odds { detailFact("Pack-Odds", text: odds, symbol: "chart.bar") }
                        }
                    }
                    if let sales = card.sales, !sales.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ScoutSectionHeader(tr("Letzte Verkäufe"), subtitle: tr("Raw · eBay · ohne Versand"))
                            ScoutPanel(padding: 16) {
                                VStack(spacing: 0) {
                                    ForEach(Array(sales.enumerated()), id: \.element.url) { index, sale in
                                        if let url = URL(string: sale.url) {
                                            Link(destination: url) {
                                                HStack(spacing: 12) {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(trDisplay(chaseDisplayDate(sale.date))).font(.subheadline)
                                                        Text(tr("Verkaufsbeleg")).font(.caption2).foregroundStyle(Color.scoutMuted)
                                                    }
                                                    Spacer(minLength: 12)
                                                    Text(trDisplay(chaseMoney(sale.priceCents))).font(.subheadline.weight(.bold).monospacedDigit())
                                                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Color.scoutAccent)
                                                }.foregroundStyle(Color.scoutInk).padding(.vertical, 12)
                                            }
                                            if index < sales.count - 1 { Divider().overlay(Color.scoutMuted.opacity(0.1)) }
                                        }
                                    }
                                }
                            }
                            if (card.saleCount ?? 0) > sales.count {
                                Text(tr("\(sales.count) neueste Belege · \(card.saleCount ?? 0) im Preis berücksichtigt"))
                                    .font(.caption).foregroundStyle(Color.scoutMuted)
                            }
                        }
                    }
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            if let url = URL(string: card.sourceURL) {
                                sourceLink(officialChase ? "Offizielle Topps Checkliste" : "Karte & Bild", url: url)
                            }
                            if let imageReference, imageReference.isRepresentative, let url = URL(string: imageReference.sourceURL) {
                                sourceLink("Design-Beispiel · Topps", url: url)
                            }
                            if let source = card.priceSourceURL, let url = URL(string: source) {
                                sourceLink("\(card.sales == nil ? "SportsCardsPro" : "CardSight · eBay") · \(chaseDisplayDate(card.priceCheckedAt ?? ""))", url: url)
                            }
                            if let source = card.oddsSourceURL, let url = URL(string: source) { sourceLink("Offizielle Pack-Odds", url: url) }
                        }.padding(.top, 8)
                    } label: { Text(tr("Quellen & Stand")).font(.subheadline.weight(.medium)) }
                        .tint(Color.scoutMuted)
                }.padding(20).padding(.bottom, 16)
            }.background(Color.scoutCanvas).navigationTitle(tr("Kartendetail")).navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    Button { store.addHunt(card, product: product) } label: {
                        Label(trDisplay(hunted ? "Auf deinem Lookout" : "Auf Lookout setzen"), systemImage: hunted ? "checkmark" : "plus")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(ScoutPrimaryButtonStyle()).disabled(hunted)
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                        .background(Color.scoutSurface.opacity(0.97))
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { dismiss() } } }
        }.tint(Color.scoutAccent).presentationDragIndicator(.visible)
    }

    private func detailFact(_ title: String, text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(Color.scoutAccent).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(trDisplay(title)).font(.caption).foregroundStyle(Color.scoutMuted)
                Text(trDisplay(text)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sourceLink(_ title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(trDisplay(title))
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.right")
            }.font(.caption).frame(minHeight: 44)
        }
    }
}

private func chaseMoney(_ cents: Int) -> String {
    (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
}

private func chaseDisplayDate(_ raw: String) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: raw) else { return raw }
    return date.formatted(.dateTime.day().month(.abbreviated).year().locale(ScoutLocalization.locale))
}
