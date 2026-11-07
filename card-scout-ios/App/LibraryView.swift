import SwiftUI
import PhotosUI
import CardScoutCore

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileWidth = 108.0
    @State private var adding = false
    @State private var finishingUnclear = false
    @State private var search = ""
    @State private var filter = "Binder"
    @State private var sort = "Neueste"
    private var pending: [OwnedCard] { store.library.cards.filter(\.isAwaitingAnalysis) }
    private var review: [OwnedCard] { store.library.cards.filter { !$0.isAwaitingAnalysis && collectorNeedsAttention($0) } }
    private var visible: [OwnedCard] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var cards = store.library.collectedCards.filter { card in
            if filter == "Favoriten" && card.isFavorite != true { return false }
            if filter == "Collectibles" && card.isCollectible != true { return false }
            if filter == "Offen" && !collectorNeedsAttention(card) { return false }
            let a = card.analysis
            return query.isEmpty || [card.title, a?.team, a?.year.map(String.init), a?.brand, a?.setName, a?.parallel, a?.cardNumber, card.storageLocation, card.notes]
                .compactMap { $0 }.joined(separator: " ").localizedStandardContains(query)
        }
        if sort == "Spieler" { cards.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
        else if sort == "Wert" {
            cards.sort { left, right in
                let a = left.hasDisplayableAnalysis ? left.analysis?.marketSummary : nil
                let b = right.hasDisplayableAnalysis ? right.analysis?.marketSummary : nil
                // Prices in different currencies cannot be compared without an exchange rate.
                if a?.primary.currency != b?.primary.currency { return (a?.primary.currency ?? "~") < (b?.primary.currency ?? "~") }
                if a?.orderingValueCents != b?.orderingValueCents { return (a?.orderingValueCents ?? -1) > (b?.orderingValueCents ?? -1) }
                return left.createdAt > right.createdAt
            }
        } else { cards.sort { $0.createdAt > $1.createdAt } }
        return cards
    }
    private var collections: [CardCollection] {
        store.library.collections.sorted { $0.year == $1.year ? $0.name < $1.name : $0.year > $1.year }
    }

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            NavigationStack {
                ClubhouseHomeView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { store.showSettings = true } label: { Image(systemName: "gearshape").frame(width: 32, height: 32) }
                                .accessibilityLabel(tr("Verbindung und Einstellungen"))
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { store.selectedTab = 3 } label: { Image(systemName: "viewfinder").frame(width: 32, height: 32) }
                                .accessibilityLabel(tr("Karte scannen"))
                        }
                    }
            }.tabItem { Label(tr("Clubhaus"), systemImage: "house.fill") }.tag(0)
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        #if DEBUG
                        if PreviewData.enabled { Text(tr("DESIGN-VORSCHAU · DEMODATEN")).font(.caption2.monospaced()).foregroundStyle(Color.scoutMuted) }
                        #endif
                        HStack {
                                Text(tr("\(store.library.collectedCards.count) Karten · \(store.library.binders.count) Binder")).font(.subheadline).foregroundStyle(Color.scoutMuted)
                                Spacer()
                                Menu {
                                    Picker(tr("Sortieren"), selection: $sort) { Text(tr("Neueste zuerst")).tag("Neueste"); Text(tr("Spieler A–Z")).tag("Spieler"); Text(tr("Preis · je Währung")).tag("Wert") }
                                } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44) }
                                    .accessibilityLabel(tr("Sammlung sortieren"))
                            }
                        nextSteps
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(["Binder", "Alle", "Collectibles", "Favoriten", "Ordner", "Offen"], id: \.self) { value in
                                    Button { filter = value } label: { ScoutChip(trDisplay(value), selected: filter == value) }.buttonStyle(.plain)
                                }
                            }
                        }.scrollIndicators(.hidden)
                        if filter == "Ordner" {
                            if (store.library.folders ?? []).isEmpty { Text(tr("Wähle nach dem Scan einen Ordner oder lege einen neuen an.")).foregroundStyle(Color.scoutMuted) }
                            ForEach(store.library.folders ?? []) { folder in
                                NavigationLink { FolderContentsView(folderID: folder.id) } label: {
                                    Label(tr("\(folder.name) · \(store.library.collectedCards.filter { folder.cardIDs.contains($0.id) }.count)"), systemImage: "folder")
                                        .padding(.vertical, 12)
                                }
                            }
                        } else if filter == "Binder" && search.isEmpty {
                            if collections.isEmpty { ScoutEmptyState(symbol: "books.vertical", title: tr("Keine Binder"), message: tr("")) }
                            else {
                                LazyVStack(spacing: 14) {
                                    ForEach(store.library.binders) { binder in
                                        NavigationLink { BinderContentsView(binderID: binder.id) } label: { BinderCover(binder: binder) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        } else if visible.isEmpty {
                            ScoutEmptyState(symbol: filter == "Collectibles" ? "trophy" : filter == "Favoriten" ? "star" : "rectangle.stack", title: search.isEmpty ? (filter == "Collectibles" ? "Deine Collectibles." : filter == "Favoriten" ? "Deine Favoriten." : "Keine Karten") : "Keine Treffer.", message: search.isEmpty ? (filter == "Collectibles" ? "Markiere deine Lieblingsstücke mit der Trophäe in den Kartendetails." : "Scanne deine erste Karte oder wähle Fotos aus.") : nil)
                            if search.isEmpty && filter != "Collectibles" && filter != "Favoriten" { Button { store.selectedTab = 3 } label: { Label(tr("Karten scannen"), systemImage: "viewfinder") }.buttonStyle(ScoutPrimaryButtonStyle()) }
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: filter == "Collectibles" ? max(tileWidth, 160) : tileWidth), spacing: 12, alignment: .top)], alignment: .leading, spacing: 24) {
                                ForEach(Array(visible.enumerated()), id: \.element.id) { index, card in
                                    NavigationLink(value: card.id) {
                                        if filter == "Collectibles" { ShowcaseCard(card: card, position: index + 1) }
                                        else { OwnedTile(card: card) }
                                    }.buttonStyle(.plain)
                                        .contextMenu {
                                            Button { store.toggleCollectible(card.id) } label: { Label(trDisplay(card.isCollectible == true ? "Aus Collectibles entfernen" : "Zu Collectibles hinzufügen"), systemImage: "trophy") }
                                            Button { store.toggleFavorite(card.id) } label: { Label(trDisplay(card.isFavorite == true ? "Favorit entfernen" : "Als Favorit merken"), systemImage: "star") }
                                        }
                                        .accessibilityAction(named: trDisplay(card.isFavorite == true ? "Favorit entfernen" : "Als Favorit merken")) { store.toggleFavorite(card.id) }
                                }
                            }
                        }
                        if !review.isEmpty && filter != "Offen" {
                            Button { filter = "Offen" } label: {
                                HStack { Text(tr("\(review.count) Zuordnungen prüfen")); Spacer(); Image(systemName: "arrow.right") }
                                    .font(.subheadline).padding(.vertical, 16)
                            }.foregroundStyle(Color.scoutGold)
                        }
                    }.padding(.horizontal, 20).padding(.bottom, 28)
                }
                .background(Color.scoutCanvas)
                .navigationTitle(tr("Sammlung"))
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: tr("Spieler, Set, Team oder Box"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { store.showSettings = true } label: { Image(systemName: store.connected ? "desktopcomputer" : "wifi.slash").foregroundStyle(Color.scoutMuted).frame(width: 32, height: 32) }
                            .accessibilityLabel(tr("Verbindung und Einstellungen"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(tr("Mehrere Karten scannen"), systemImage: "viewfinder") { store.selectedTab = 3 }
                            Button(tr("Vorder- und Rückseite"), systemImage: "rectangle.on.rectangle") { adding = true }
                        } label: { Image(systemName: "plus").frame(width: 32, height: 32) }
                            .accessibilityLabel(tr("Karten hinzufügen"))
                    }
                }
                .navigationDestination(for: String.self) { CardDetailView(cardID: $0) }
                .refreshable { await store.sync() }
            }.tabItem { Label(tr("Sammlung"), systemImage: "square.grid.2x2") }.tag(5)
            NavigationStack { FastScanView() }.tabItem { Label(tr("Scannen"), systemImage: "viewfinder") }.tag(3)
            NavigationStack { CollectionStatisticsView() }.tabItem { Label(tr("Insights"), systemImage: "chart.bar.xaxis") }.tag(4)
        }
        .tint(.scoutAccent)
        .sheet(isPresented: $adding) { AddCardView() }
        .sheet(isPresented: $store.showMarketRanking) {
            NavigationStack {
                HotListView().toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { store.showMarketRanking = false } } }
            }
        }
        .sheet(isPresented: $finishingUnclear) { UnclearCardQueueView() }
        .sheet(isPresented: $store.showSettings) { ConnectionView() }
        .alert(tr("Bitte prüfen"), isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button(tr("OK")) { store.lastError = nil }
        } message: { Text(trDisplay(store.lastError ?? "")) }
    }

    private var nextSteps: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                if !store.library.scanDrafts.isEmpty {
                    NavigationLink { ScanDraftsView() } label: {
                        Label(tr("\(store.library.scanDrafts.count) Scans vergleichen"), systemImage: "rectangle.stack.badge.plus")
                            .font(.headline).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                if !pending.isEmpty { progressStrip }
                NavigationLink { ReviewQueueView() } label: {
                    Label(tr("Nächste Schritte · Zuordnung & Preise"), systemImage: "checklist")
                        .font(.headline).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                if store.library.unclearCardQueue?.currentID != nil || store.library.cards.contains(where: UnclearCardQueue.isEligible) {
                    Button {
                        if store.startUnclearCardQueue() { finishingUnclear = true }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "rectangle.stack.badge.plus").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trDisplay(store.library.unclearCardQueue?.currentID == nil ? "Offene Karten fertigstellen" : "Offene Karten fortsetzen")).font(.subheadline.weight(.semibold))
                                Text(tr("Fotos, Checkliste oder Variante prüfen · Karte für Karte")).font(.caption).foregroundStyle(Color.scoutMuted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(16).background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).foregroundStyle(Color.scoutAccent)
                }
            }.padding(.top, 12)
        } label: {
            Label(tr("Eingang & nächste Schritte · \(pending.count + review.count + store.library.scanDrafts.count)"), systemImage: "tray")
                .font(.subheadline.weight(.medium))
        }
    }

    private var progressStrip: some View {
        NavigationLink { CardInboxView() } label: {
            HStack(spacing: 12) {
                if store.connected { ProgressView().controlSize(.small).tint(.scoutAccent) }
                else { Image(systemName: "tray").foregroundStyle(Color.scoutMuted) }
                VStack(alignment: .leading, spacing: 3) {
                    let known = pending.filter { $0.hasProvisionalAnalysis == true }.count
                    Text(trDisplay(store.connected ? "\(pending.count) Karten in Arbeit" : "\(pending.count) Karten gespeichert")).font(.subheadline.weight(.medium))
                    Text(trDisplay(!store.connected ? "Analyse startet mit deinem Mac oder Server." : known > 0 ? "\(known) vorläufig geprüft · Analyse läuft" : "Deine Fotos sind gespeichert.")).font(.caption).foregroundStyle(Color.scoutMuted)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.scoutMuted)
            }.padding(14).background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}

private func collectorNeedsAttention(_ card: OwnedCard) -> Bool {
    card.isAwaitingAnalysis || ReviewIssue.identity(card) != nil || card.analysis?.collectionID == nil || (card.analysis?.needsReview == true && card.manualAssignment != true)
}

private func collectorStatus(_ card: OwnedCard) -> String {
    switch card.state {
    case "queued": "Analyse vorgemerkt"
    case "processing": "Wird erkannt"
    case "identified": card.analysis?.identityConfirmed == true ? "Erkannt · Preis folgt" : "Zuordnung prüfen · vorläufig"
    case "enriching": "Preis wird geprüft"
    case "failed": "Analyse erneut starten"
    default: card.analysis?.identityConfirmed != true ? "Zuordnung prüfen" : card.analysis?.needsReview == true ? "Bewertung prüfen" : "In deiner Sammlung"
    }
}

private struct CardInboxView: View {
    @Environment(AppStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var tileWidth = 145.0
    private var cards: [OwnedCard] { store.library.cards.filter(collectorNeedsAttention).sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScoutSectionHeader(tr("Noch offen"), subtitle: tr("\(cards.count) \(trDisplay(cards.count == 1 ? "Karte" : "Karten"))"))
                if cards.isEmpty {
                    ScoutEmptyState(symbol: "checkmark.circle", title: tr("Alles einsortiert."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 16, alignment: .top)], spacing: 24) {
                        ForEach(cards) { card in NavigationLink { CardDetailView(cardID: card.id) } label: { OwnedTile(card: card) }.buttonStyle(.plain) }
                    }
                }
            }.padding(20)
        }.background(Color.scoutCanvas).navigationTitle(tr("Eingang")).navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.sync() }
    }
}

struct CollectionCover: View {
    @Environment(AppStore.self) private var store
    let collection: CardCollection
    private var count: Int { collection.ownedCount(in: store.library.cards) }
    private var cover: OwnedCard? { store.library.collectedCards.first { $0.analysis?.collectionID == collection.id && $0.analysis?.identityConfirmed == true } }
    var body: some View {
        HStack(spacing: 16) {
            if cover == nil, let reference = collection.validReferenceExample {
                VStack(spacing: 2) {
                    ReferenceImageView(url: reference.frontURL).frame(width: 62, height: 80)
                    Text(tr("Beispiel")).font(.system(size: 8)).foregroundStyle(Color.scoutMuted)
                }
            } else {
                OwnedPhoto(name: cover?.frontFile, number: "").frame(width: 62, height: 88)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("\(String(collection.year)) · \(collection.brand)")).font(.caption).foregroundStyle(Color.scoutMuted)
                Text(trDisplay(collection.parallel ?? collection.subset)).font(.system(.title3, design: .rounded, weight: .heavy)).foregroundStyle(Color.scoutInk)
                Text(collection.name).font(.caption).foregroundStyle(Color.scoutMuted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 7) {
                Text(trDisplay(collection.checklistComplete ? "\(count) / \(collection.cards.count)" : "\(count) Motive")).font(.caption.monospacedDigit()).foregroundStyle(Color.scoutInk)
                if collection.checklistComplete { ProgressView(value: Double(count), total: Double(max(collection.cards.count, 1))).tint(.scoutAccent).frame(width: 66) }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.scoutMuted)
            }
        }.padding(16)
            .background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.scoutLine.opacity(0.5)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tr("\(String(collection.year)) \(collection.name), \(collection.parallel ?? collection.subset). \(count) gesammelt\(collection.checklistComplete ? " von \(collection.cards.count)" : ", Checkliste offen"). Binder öffnen"))
    }
}

struct PhotoCard: View {
    var image: UIImage?
    var number: String
    var owned: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(owned ? Color.scoutSurface : Color.scoutElevated)
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(4).saturation(owned ? 1 : 0).opacity(owned ? 1 : 0.3)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.portrait").font(.system(size: 30, weight: .ultraLight))
                    if !number.isEmpty { Text(tr("#\(number)")).font(.system(.title3, design: .rounded).weight(.medium)).lineLimit(2) }
                }.padding(8).foregroundStyle(Color.scoutMuted.opacity(owned ? 0.6 : 0.4))
            }
        }
        .aspectRatio(5 / 7, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.scoutLine.opacity(owned ? 0.65 : 0.35)))
        .accessibilityHidden(true)
    }
}

struct OwnedTile: View {
    @Environment(AppStore.self) private var store
    var card: OwnedCard
    var photoHeight: CGFloat? = nil
    private var needsAttention: Bool { collectorNeedsAttention(card) }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            OwnedPhoto(name: card.frontFile, number: card.analysis?.cardNumber ?? "")
                .frame(height: photoHeight)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if card.isCollectible == true { Image(systemName: "trophy.fill").font(.system(size: 9)).foregroundStyle(Color.scoutGold).accessibilityLabel(tr("Collectible")) }
                if card.isFavorite == true { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color.scoutAccent).accessibilityLabel(tr("Favorit")) }
                Text(cardTitle(card)).font(.caption.weight(.semibold)).foregroundStyle(Color.scoutInk).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let a = card.analysis {
                Text(trDisplay([a.cardNumber.map { "#" + $0 }, a.parallel ?? a.subset, a.rookie == true ? "RC" : nil].compactMap { $0 }.joined(separator: " · ")))
                    .font(.caption).foregroundStyle(Color.scoutMuted).lineLimit(2)
            }
            if card.hasCurrentAnalysis, let summary = card.analysis?.marketSummary {
                Text(trDisplay(summary.valueLabel)).font(.subheadline.weight(.bold)).foregroundStyle(Color.scoutAccent)
                Text(trDisplay(summary.basisLabel)).font(.caption2).foregroundStyle(Color.scoutMuted).lineLimit(2)
            }
            if needsAttention { Text(trDisplay(collectorStatus(card))).font(.caption2).foregroundStyle(Color.scoutMuted).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityHint(tr("Kartendetails öffnen"))
    }
}

struct CollectionView: View {
    @Environment(AppStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var tileWidth = 145.0
    var collectionID: String
    @State private var search = ""
    @State private var filter = "Alle"
    @State private var missing: ChecklistCard?
    @State private var inspectingReference: CardReferenceImage?
    var body: some View {
        if let collection = store.library.collections.first(where: { $0.id == collectionID }) {
            let owned = collection.ownedCount(in: store.library.cards)
            let filtered = collection.cards.filter { card in
                let have = !collection.owned(for: card.number, in: store.library.cards).isEmpty
                return (filter == "Alle" || (filter == "Besitze ich" ? have : !have)) && (search.isEmpty || "\(card.number) \(card.player) \(card.team)".localizedCaseInsensitiveContains(search))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    collectionHeader(collection, owned: owned)
                    if let product = store.library.chaseCatalog?.products.first(where: { $0.matches(collection) }) {
                        NavigationLink { HotListView(initialProductID: product.id) } label: {
                            HStack {
                                Label(tr("Wertvollste Karten"), systemImage: "chart.bar.xaxis")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.font(.subheadline.weight(.semibold)).padding(16).background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).foregroundStyle(Color.scoutAccent)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        Picker(tr("Karten"), selection: $filter) {
                            Text(tr("Alle")).tag("Alle")
                            Text(tr("Meine · \(owned)")).tag("Besitze ich")
                            Text(tr("Fehlen · \(max(collection.cards.count - owned, 0))")).tag("Fehlen")
                        }.pickerStyle(.segmented)
                        HStack {
                            Text(tr("\(filtered.count) \(trDisplay(filtered.count == 1 ? "Karte" : "Karten"))")).font(.caption.weight(.medium)).foregroundStyle(Color.scoutMuted)
                            Spacer()
                            if !collection.checklistComplete { Text(tr("Teilcheckliste")).font(.caption).foregroundStyle(Color.scoutGold) }
                        }
                        if filtered.isEmpty {
                            ScoutEmptyState(symbol: filter == "Fehlen" && search.isEmpty ? "checkmark.seal" : "magnifyingglass", title: filter == "Fehlen" && search.isEmpty ? "Alle erfasst." : "Keine Karten gefunden.", message: filter == "Fehlen" && !collection.checklistComplete ? "Deine aktuelle Teilcheckliste ist komplett." : nil)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 16, alignment: .top)], spacing: 26) {
                                ForEach(filtered) { entry in
                                    let ownedCards = collection.owned(for: entry.number, in: store.library.cards)
                                    if let card = ownedCards.first {
                                        NavigationLink { CardDetailView(cardID: card.id) } label: {
                                            LocalCardPhoto(name: card.frontFile) { image, _ in
                                                ChecklistTile(entry: entry, image: image, copies: ownedCards.count, market: card.hasCurrentAnalysis ? card.analysis?.marketSummary : nil)
                                            }
                                        }.buttonStyle(.plain)
                                    } else {
                                        Button { missing = entry } label: { ChecklistTile(entry: entry, image: nil, copies: 0, reference: entry.exactReference(in: collection)) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    if let source = collection.sourceURL, let url = URL(string: source) {
                        Link(destination: url) { Label(tr("Checkliste ansehen"), systemImage: "arrow.up.right.square").font(.caption).frame(minHeight: 44) }.foregroundStyle(Color.scoutMuted)
                    }
                }.padding(20)
            }
            .background(Color.scoutCanvas).navigationTitle(collection.name).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: tr("Spieler, Team oder Nummer"))
            .sheet(item: $missing) { entry in missingSheet(entry, collection: collection) }
        } else {
            ScoutEmptyState(symbol: "books.vertical", title: tr("Binder nicht verfügbar.")).background(Color.scoutCanvas)
        }
    }

    private func collectionHeader(_ collection: CardCollection, owned: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ScoutEyebrow(tr("\(collection.year) · \(collection.brand)"))
            Text(trDisplay(collection.parallel ?? collection.subset)).font(.largeTitle.weight(.bold))
            HStack(alignment: .firstTextBaseline) {
                Text(tr("\(owned)")).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                Text(trDisplay(collection.checklistComplete ? "von \(collection.cards.count) gesammelt" : "gesammelt")).font(.subheadline).foregroundStyle(Color.scoutMuted)
                Spacer(minLength: 0)
            }.accessibilityElement(children: .combine)
            Text(tr("\(collection.cards.filter { $0.exactReference(in: collection) != nil }.count) von \(collection.cards.count) mit exaktem Referenzfoto"))
                .font(.caption).foregroundStyle(Color.scoutMuted)
            if let example = collection.validReferenceExample {
                NavigationLink { ReferenceComparisonView(reference: example, variantExample: true) } label: {
                    Label(tr("Variantenbeispiel ansehen"), systemImage: "photo.on.rectangle.angled").font(.subheadline.weight(.semibold))
                }.foregroundStyle(Color.scoutAccent)
            }
            if collection.checklistComplete {
                ProgressView(value: Double(owned), total: Double(max(collection.cards.count, 1))).tint(.scoutAccent)
                HStack {
                    Text(trDisplay((Double(owned) / Double(max(collection.cards.count, 1))).formatted(.percent.precision(.fractionLength(0...1))) + " komplett"))
                    Spacer()
                    Text(tr("\(max(collection.cards.count - owned, 0)) fehlen"))
                }.font(.caption.weight(.medium)).foregroundStyle(Color.scoutMuted)
            } else {
                Label(tr("Checkliste noch nicht vollständig"), systemImage: "circle.dotted").font(.caption).foregroundStyle(Color.scoutGold)
            }
        }
    }

    private func missingSheet(_ entry: ChecklistCard, collection: CardCollection) -> some View {
        let isHunting = store.library.hunts.contains { $0.id == collection.id + ":" + entry.number }
        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let exact = entry.exactReference(in: collection) {
                        Button { inspectingReference = exact } label: { ReferenceImageView(url: exact.frontURL).frame(height: 300) }.buttonStyle(.plain)
                        if let source = URL(string: exact.sourceURL) { Link(tr("Bildquelle ansehen"), destination: source).font(.caption) }
                    }
                    else { PhotoCard(image: nil, number: entry.number, owned: false).frame(height: 240) }
                    VStack(spacing: 6) {
                        ScoutEyebrow(tr("FEHLT IN DEINEM BINDER"))
                        Text(entry.player).font(.title2.bold()).multilineTextAlignment(.center)
                        Text(tr("#\(entry.number) · \(entry.team)")).font(.subheadline).foregroundStyle(Color.scoutMuted).multilineTextAlignment(.center)
                        Text(tr("\(String(collection.year)) \(collection.name) · \(collection.parallel ?? collection.subset)")).font(.caption).foregroundStyle(Color.scoutMuted).multilineTextAlignment(.center)
                    }
                    Button {
                        store.addHunt(entry, collection: collection)
                        missing = nil
                    } label: { Label(trDisplay(isHunting ? "Schon im Lookout" : "Zum Lookout hinzufügen"), systemImage: isHunting ? "checkmark" : "scope").frame(maxWidth: .infinity) }
                        .buttonStyle(ScoutPrimaryButtonStyle()).disabled(isHunting)
                }.padding(24)
            }.background(Color.scoutCanvas).navigationTitle(tr("Fehlende Karte")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { missing = nil } } }
        }.presentationDetents([.large]).sheet(item: $inspectingReference) { ReferenceComparisonSheet(reference: $0) }
    }
}

struct ChecklistTile: View {
    let entry: ChecklistCard
    let image: UIImage?
    let copies: Int
    var market: RawMarketSummary? = nil
    var reference: CardReferenceImage? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if image == nil, let reference { ReferenceImageView(url: reference.frontURL).aspectRatio(5.0 / 7.0, contentMode: .fit) }
                else { PhotoCard(image: image, number: entry.number, owned: copies > 0) }
            }
            .overlay(alignment: .topTrailing) {
                if copies > 0 {
                    Group {
                        if copies == 1 { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        else { Text(tr("×\(copies)")).font(.caption.bold()) }
                    }.foregroundStyle(Color.white).frame(minWidth: 27, minHeight: 27).background(Color.scoutButtonFill, in: Capsule()).padding(8)
                }
            }
            Text(entry.player).font(.subheadline.weight(.semibold)).foregroundStyle(copies > 0 ? Color.scoutInk : Color.scoutMuted).lineLimit(2)
            Text(tr("#\(entry.number)\(entry.rookie ? " · RC" : "")\(trDisplay(copies == 0 ? " · Fehlt" : ""))")).font(.caption).foregroundStyle(Color.scoutMuted)
            if let market {
                Text(trDisplay(market.valueLabel)).font(.subheadline.weight(.bold)).foregroundStyle(Color.scoutAccent)
                Text(trDisplay(market.basisLabel)).font(.caption2).foregroundStyle(Color.scoutMuted).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tr("\(entry.player), Nummer \(entry.number), \(copies > 0 ? "\(copies) vorhanden" : "fehlt")\(market.map { ", \($0.valueLabel), \($0.basisLabel)" } ?? "")"))
            .accessibilityHint(trDisplay(copies > 0 ? "Kartendetails öffnen" : "Karte im Lookout vormerken"))
    }
}

struct CardDetailView: View {
    @Environment(AppStore.self) private var store
    let cardID: String
    var body: some View {
        if store.library.cards.first(where: { $0.id == cardID })?.isScanDraft == true { ScanMatchView(cardID: cardID) }
        else { CollectedCardDetailView(cardID: cardID) }
    }
}

private struct CollectedCardDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cardID: String
    @State private var side = "Vorne"
    @State private var correcting = false
    @State private var reviewingIdentity = false
    @State private var retaking = false
    @State private var photoExpanded = false
    @State private var editingMetadata = false
    var body: some View {
        if let card = store.library.cards.first(where: { $0.id == cardID }) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        photoStage(card)
                        Button { store.toggleCollectible(card.id) } label: {
                            Label(trDisplay(card.isCollectible == true ? "In deinen Collectibles" : "Zu Collectibles hinzufügen"), systemImage: card.isCollectible == true ? "trophy.fill" : "trophy")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(ScoutSecondaryButtonStyle())
                        if card.hasDisplayableAnalysis, let analysis = card.analysis {
                            if !card.hasCurrentAnalysis { statusPanel(card, previous: true) }
                            if analysis.identityConfirmed != true {
                                Button { reviewingIdentity = true } label: {
                                    Label(tr("Zuordnung prüfen"), systemImage: "rectangle.and.pencil.and.ellipsis").frame(maxWidth: .infinity)
                                }.buttonStyle(ScoutSecondaryButtonStyle())
                            }
                            if let collection = store.library.collections.first(where: { $0.id == analysis.collectionID }) {
                                if let entry = collection.cards.first(where: { $0.number == analysis.cardNumber && $0.player == analysis.player }), let reference = entry.exactReference(in: collection) {
                                    NavigationLink { ReferenceComparisonView(reference: reference, cardID: card.id) } label: {
                                        Label(tr("Mit Referenzfoto vergleichen"), systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity)
                                    }.buttonStyle(ScoutSecondaryButtonStyle())
                                } else if let reference = collection.validReferenceExample {
                                    NavigationLink { ReferenceComparisonView(reference: reference, cardID: card.id, variantExample: true) } label: {
                                        Label(tr("Variantenbeispiel vergleichen"), systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity)
                                    }.buttonStyle(ScoutSecondaryButtonStyle())
                                }
                            }
                            AnalysisCardsView(analysis: analysis, provisional: card.hasProvisionalAnalysis == true, pricingPaused: card.state == "failed" || !store.connected, assessmentCleared: card.manualAssignment == true && analysis.insights == nil) { section in
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(section, anchor: .top) }
                            }
                            VStack(spacing: 10) {
                                Button { store.reanalyze(card.id) } label: {
                                    Label(tr("Neu bewerten"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                                }.buttonStyle(ScoutSecondaryButtonStyle()).disabled(card.isAwaitingAnalysis)
                                Button(tr("Zuordnung korrigieren")) { correcting = true }.font(.subheadline).foregroundStyle(Color.scoutMuted).frame(minHeight: 44)
                            }
                        } else { statusPanel(card, previous: false) }
                        VStack(alignment: .leading, spacing: 8) {
                            if let location = card.storageLocation, !location.isEmpty { Label(trDisplay(location), systemImage: "archivebox").font(.subheadline) }
                            if let notes = card.notes, !notes.isEmpty { Text(notes).font(.subheadline).foregroundStyle(Color.scoutMuted) }
                            Button(tr("Aufbewahrung & Notizen")) { editingMetadata = true }.font(.subheadline).frame(minHeight: 44)
                        }
                    }.padding(20).padding(.bottom, 16)
                }
                .background(Color.scoutCanvas).navigationTitle(tr("Deine Karte")).navigationBarTitleDisplayMode(.inline)
                .task(id: card.jobID) { await store.loadCardPrices(card.id) }
                .sheet(isPresented: $correcting) { CorrectCardView(cardID: card.id) }
                .sheet(isPresented: $reviewingIdentity) { IdentityReviewView(cardID: card.id) }
                .sheet(isPresented: $retaking) { AddCardView(cardID: card.id).tint(.scoutAccent) }
                .sheet(isPresented: $editingMetadata) { CardMetadataView(cardID: card.id) }
                .fullScreenCover(isPresented: $photoExpanded) { CardPhotoViewer(cardID: card.id, initialBack: side == "Hinten") }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { store.toggleFavorite(card.id) } label: { Image(systemName: card.isFavorite == true ? "star.fill" : "star").frame(width: 44, height: 44) }
                            .accessibilityLabel(trDisplay(card.isFavorite == true ? "Favorit entfernen" : "Als Favorit merken"))
                    }
                }
            }
        } else {
            ScoutEmptyState(symbol: "rectangle.portrait.slash", title: tr("Karte nicht verfügbar.")).background(Color.scoutCanvas)
        }
    }

    private func photoStage(_ card: OwnedCard) -> some View {
        VStack(spacing: 18) {
            Button { photoExpanded = true } label: {
                OwnedPhoto(name: side == "Vorne" ? card.frontFile : card.backFile, maxPixel: 2600, number: "")
                    .frame(height: 350).frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 26)
                            .fill(Color.scoutSurface)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.semibold)).padding(12).foregroundStyle(Color.scoutMuted)
                    }
            }.buttonStyle(.plain).accessibilityLabel(tr("Karte vergrößern. \(trDisplay(side == "Vorne" ? "Vorderseite" : "Rückseite")) von \(card.title)"))
            HStack(spacing: 14) {
                if card.backFile != nil {
                    Picker(tr("Kartenseite"), selection: $side) { Text(tr("Vorne")).tag("Vorne"); Text(tr("Hinten")).tag("Hinten") }.pickerStyle(.segmented)
                } else { Text(tr("Vorderseite")).font(.caption).foregroundStyle(Color.scoutMuted); Spacer() }
                Button { retaking = true } label: { Image(systemName: "camera.rotate").font(.title3).frame(width: 44, height: 44).background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 12)) }
                    .accessibilityLabel(tr("Foto neu aufnehmen"))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(cardTitle(card)).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                if let team = card.analysis?.team { Text(trDisplay(team)).font(.subheadline).foregroundStyle(Color.scoutMuted) }
                if let a = card.analysis {
                    Text(trDisplay([a.year.map(String.init), a.setName, a.cardNumber.map { "#" + $0 }, a.parallel ?? a.subset]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")))
                        .font(.caption).foregroundStyle(Color.scoutMuted).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusPanel(_ card: OwnedCard, previous: Bool) -> some View {
        ScoutPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if card.isAwaitingAnalysis { ProgressView().tint(.scoutAccent) }
                    else { Image(systemName: "exclamationmark.circle").foregroundStyle(Color.scoutGold) }
                    Text(trDisplay(collectorStatus(card))).font(.headline)
                }
                if previous && card.hasProvisionalAnalysis != true { Text(tr("Bisherige Bewertung")).font(.caption).foregroundStyle(Color.scoutMuted) }
                if card.state == "queued" && !store.connected {
                    Text(tr("Gespeichert. Die Analyse startet, sobald dein Mac oder Server verbunden ist.")).font(.subheadline).foregroundStyle(Color.scoutMuted)
                    Button(tr("Verbindung öffnen")) { store.showSettings = true }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                if let error = card.error { Text(trDisplay(error)).font(.subheadline).foregroundStyle(Color.scoutMuted) }
                if card.state == "unidentified" {
                    Text(tr("Ohne Zuordnung gespeichert. Ergänze Fotos oder lass nach der Karte suchen.")).font(.subheadline)
                    Button(tr("Karte erkennen lassen")) { store.reanalyze(card.id) }.buttonStyle(ScoutPrimaryButtonStyle())
                }
                if card.state == "failed" {
                    Button(tr("Erneut analysieren")) { store.retry(card.id) }.buttonStyle(ScoutPrimaryButtonStyle())
                }
            }
        }
    }
}

struct CorrectCardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardID: String
    @State private var setID = ""
    @State private var number = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Kartenset & Nummer")) {
                    Text(tr("Nur speichern, wenn Jahrgang, Set, Variante und Kartennummer sicher übereinstimmen. Diese Auswahl bestätigt die Identität."))
                        .font(.footnote).foregroundStyle(Color.scoutMuted)
                    Picker(tr("Kartenset"), selection: $setID) {
                        Text(tr("Wählen")).tag("")
                        ForEach(store.library.collections) { Text(tr("\(String($0.year)) \($0.name) · \($0.parallel ?? $0.subset)")).tag($0.id) }
                    }
                    TextField(tr("Kartennummer"), text: $number).textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
                if let set = store.library.collections.first(where: { $0.id == setID }), let entry = set.cards.first(where: { $0.number.localizedCaseInsensitiveCompare(number.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) {
                    Section(tr("Deine Zuordnung")) {
                        Text(entry.player).font(.headline)
                        Text(trDisplay(entry.team)).foregroundStyle(Color.scoutMuted)
                        Button(tr("Zuordnung speichern")) {
                            if store.correctAssignment(cardID, collectionID: set.id, number: entry.number) { dismiss() }
                        }
                    }
                } else if !setID.isEmpty && !number.isEmpty {
                    Section { Label(tr("Diese Nummer fehlt in der aktuellen Checkliste."), systemImage: "magnifyingglass").font(.subheadline).foregroundStyle(Color.scoutMuted) }
                }
            }
            .scrollContentBackground(.hidden).background(Color.scoutCanvas)
            .navigationTitle(tr("Zuordnung")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Schließen")) { dismiss() } } }
            .onAppear {
                if let a = store.library.cards.first(where: { $0.id == cardID })?.analysis { setID = a.collectionID ?? ""; number = a.cardNumber ?? "" }
            }
        }
    }
}

struct HuntListView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    private var hunting: [HuntCard] { matching.filter { $0.status != "found" } }
    private var found: [HuntCard] { matching.filter { $0.status == "found" } }
    private var matching: [HuntCard] {
        store.library.hunts.filter { search.isEmpty || "\($0.label) \($0.productName) \($0.player ?? "")".localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {

                    HStack(spacing: 12) {
                        ScoutChip(tr("\(store.library.hunts.filter { $0.status != "found" }.count) gesucht"), systemImage: "scope", selected: true)
                        ScoutChip(tr("\(store.library.hunts.filter { $0.status == "found" }.count) gefunden"), systemImage: "checkmark")
                    }
                }
                if store.library.hunts.isEmpty {
                    ScoutEmptyState(symbol: "scope", title: tr("Keine Wunschkarten"), message: tr(""))
                    NavigationLink { HotListView() } label: { Label(tr("Rangliste entdecken"), systemImage: "arrow.up.right").frame(maxWidth: .infinity) }.buttonStyle(ScoutPrimaryButtonStyle())
                } else if matching.isEmpty {
                    ScoutEmptyState(symbol: "magnifyingglass", title: tr("Kein Treffer."), message: tr("Suche nach Spieler oder Sammlung."))
                } else {
                    if !hunting.isEmpty { huntSection("Auf der Suche", cards: hunting) }
                    if !found.isEmpty { huntSection("Gefunden", cards: found) }
                }
            }.padding(20).padding(.bottom, 16)
        }.background(Color.scoutCanvas).navigationTitle(tr("Lookout")).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: tr("Spieler oder Sammlung"))
    }
    private func huntSection(_ title: String, cards: [HuntCard]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ScoutSectionHeader(trDisplay(title), trailing: tr("\(cards.count)"))
            LazyVStack(spacing: 12) {
                ForEach(cards) { hunt in
                    ScoutPanel(padding: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            Group {
                                if let url = hunt.imageURL { CachedPhoto(url: url) }
                                else { PhotoCard(image: nil, number: "", owned: true) }
                            }.frame(width: 68, height: 95)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(hunt.label).font(.subheadline.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                                Text(hunt.productName).font(.caption).foregroundStyle(Color.scoutMuted)
                                if let source = hunt.sourceURL, let url = URL(string: source) {
                                    Link(destination: url) { Label(tr("Quelle"), systemImage: "arrow.up.right").font(.caption.weight(.medium)).frame(minHeight: 44) }.foregroundStyle(Color.scoutAccent)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                store.commit { library in
                                    if let index = library.hunts.firstIndex(where: { $0.id == hunt.id }) { library.hunts[index].status = hunt.status == "found" ? "hunting" : "found" }
                                }
                            } label: {
                                Image(systemName: hunt.status == "found" ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundStyle(hunt.status == "found" ? Color.scoutAccent : Color.scoutMuted)
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(trDisplay(hunt.status == "found" ? "\(hunt.label) wieder als gesucht markieren" : "\(hunt.label) als gefunden markieren"))
                        }
                    }
                }
            }
        }
    }
}
