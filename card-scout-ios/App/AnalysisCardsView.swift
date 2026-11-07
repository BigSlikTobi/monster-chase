import SwiftUI
import CardScoutCore

struct AnalysisCardsView: View {
    let analysis: CardAnalysis
    var provisional = false
    var pricingPaused = false
    var assessmentCleared = false
    let jump: (String) -> Void
    private var a: CardAnalysis { analysis.currentPricing() }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if a.identityConfirmed != true {
                Label(tr("Zuordnung prüfen"), systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.scoutGold)
            } else if ["unknown", "unlicensed"].contains(a.licenseScope ?? "unknown") {
                Label(tr("Lizenz prüfen"), systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.scoutGold)
            }

            marketPanel.id("market")

            InsightPanel(title: tr("Variante"), icon: "rectangle.stack", tint: .scoutGold, badge: a.discoveryRarity) {
                if a.rarityFacts.isEmpty {
                    Text(tr("Variante noch offen")).font(.subheadline).foregroundStyle(Color.scoutMuted)
                } else {
                    InsightBullets(items: a.rarityFacts)
                }
            }.id("rarity")

            InsightPanel(title: tr("Zustand"), icon: "viewfinder", tint: a.insights?.conditionStatus == "visible_damage" ? .scoutGold : .scoutAccent) {
                if let info = a.insights {
                    Text(trDisplay(info.conditionLabel)).font(.headline)
                    InsightBullets(items: info.conditionIssues)
                    Text(tr("Foto-Check · keine Benotung")).font(.caption).foregroundStyle(Color.scoutMuted)
                    if !info.conditionLimitations.isEmpty {
                        DisclosureGroup {
                            InsightBullets(items: info.conditionLimitations).padding(.top, 10)
                        } label: {
                            Label(tr("Foto-Details"), systemImage: "info.circle").font(.subheadline)
                        }.tint(Color.scoutMuted)
                    }
                } else {
                    Text(tr("Foto-Check noch offen")).font(.subheadline).foregroundStyle(Color.scoutMuted)
                }
            }.id("condition")

            if !provisional && !assessmentCleared { ScoutPanel {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: recommendationSymbol)
                        .font(.title2).foregroundStyle(Color.scoutAccent)
                        .frame(width: 46, height: 46)
                        .background(Color.scoutAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(trDisplay(a.actionLabel)).font(.title3.weight(.bold))
                        if let info = a.insights, !info.actionReason.isEmpty {
                            DisclosureGroup(tr("Begründung")) {
                                Text(info.actionReason).font(.subheadline).foregroundStyle(Color.scoutMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.font(.caption)
                        }
                    }
                }
            } }

            ScoutPanel {
                DisclosureGroup {
                    cardData.padding(.top, 16)
                } label: {
                    Label(tr("Kartendaten & Quellen"), systemImage: "rectangle.and.text.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }.tint(Color.scoutMuted)
            }
        }
    }

    private func insightShortcut(_ title: String, symbol: String, target: String) -> some View {
        Button { jump(target) } label: {
            ScoutChip(trDisplay(title), systemImage: symbol)
                .frame(minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityHint(tr("Springt zum Abschnitt \(title)"))
    }

    private var marketPanel: some View {
        InsightPanel(title: tr("Markt"), icon: "chart.bar.xaxis", tint: .scoutAccent) {
            if provisional {
                HStack(spacing: 12) {
                    if pricingPaused { Image(systemName: "pause.circle").foregroundStyle(Color.scoutMuted) }
                    else { ProgressView().controlSize(.small) }
                    Text(trDisplay(pricingPaused ? "Preisprüfung pausiert" : "Preis folgt")).font(.headline)
                }
                Text(trDisplay(pricingPaused ? "Die Karte ist gespeichert. Die Analyse wurde unterbrochen. Starte sie oben erneut; deine gespeicherten Fotos werden verwendet." : "Die Karte ist gespeichert. Verkäufe werden im Hintergrund geprüft.")).font(.footnote).foregroundStyle(Color.scoutMuted)
            } else if assessmentCleared {
                Text(tr("Bewertung offen")).font(.title2.weight(.semibold))
                Text(tr("Deine Zuordnung ist gespeichert. „Neu bewerten“ prüft Zustand und Verkäufe.")).font(.footnote).foregroundStyle(Color.scoutMuted)
            } else if let info = a.insights {
                if let summary = a.marketSummary {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(trDisplay(summary.valueLabel))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.scoutAccent)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(trDisplay(summary.basisLabel)).font(.subheadline.weight(.semibold))
                        Text(tr("Ungegradet · \(summary.primary.currency) · \(trDisplay(summary.primary.matchLabel))"))
                            .font(.caption).foregroundStyle(Color.scoutMuted)
                        if let range = summary.rangeLabel {
                            Text(tr("\(trDisplay(summary.isComparable ? "Vergleichsspanne" : "Verkaufsspanne")): \(range)")).font(.caption).foregroundStyle(Color.scoutMuted)
                        }
                        if summary.isGuide {
                            Text(tr("Schätzung aus Preisguide · kein bestätigter Verkauf"))
                                .font(.caption).foregroundStyle(Color.scoutGold)
                        }
                        if let comparison = summary.comparison {
                            Text(tr("Grobe Orientierung aus \(comparison.cardCount) anderen Spielern · \(trDisplay(comparison.scopeLabel)). Spielerwert kann stark abweichen."))
                                .font(.caption).foregroundStyle(Color.scoutGold)
                            Text(tr("Kein Preisbeleg für deine konkrete Karte."))
                                .font(.caption).foregroundStyle(Color.scoutGold)
                            DisclosureGroup(tr("Vergleichskarten & Quellen")) {
                                ForEach(Array(comparison.references.enumerated()), id: \.offset) { _, reference in
                                    MarketReferenceView(reference: reference)
                                }
                            }.font(.subheadline)
                        }
                        if !summary.isComparable && summary.primary.provider == "CardSight" {
                            Text(tr("CardSight · gemeldete Auktionen · 24 Stunden verfügbar"))
                                .font(.caption).foregroundStyle(Color.scoutMuted)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trDisplay(summary.primary.shippingLabel))
                            Text(trDisplay(summary.dateLabel))
                        }.font(.caption).foregroundStyle(Color.scoutMuted)
                        if !summary.isComparable, let url = URL(string: summary.primary.url) {
                            Link(destination: url) {
                                Label(trDisplay(summary.primary.provider), systemImage: "arrow.up.right")
                                    .font(.caption.weight(.semibold)).padding(.vertical, 4)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(tr("Preis noch offen")).font(.title2.weight(.bold))
                        Text(tr("Kein passender Raw-Preis verfügbar.")).font(.subheadline).foregroundStyle(Color.scoutMuted)
                    }
                }
                if !info.marketBullets.isEmpty {
                    InsightBullets(items: Array(info.marketBullets.prefix(2)))
                    if info.marketBullets.count > 2 {
                        DisclosureGroup(tr("Mehr zum Markt")) {
                            InsightBullets(items: Array(info.marketBullets.dropFirst(2))).padding(.top, 10)
                        }.font(.subheadline).tint(Color.scoutMuted)
                    }
                }
                if !info.marketReferences.isEmpty {
                    Divider().overlay(Color.scoutMuted.opacity(0.1))
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(info.marketReferences.enumerated()), id: \.offset) { _, reference in
                                MarketReferenceView(reference: reference)
                            }
                        }.padding(.top, 12)
                    } label: {
                        HStack(spacing: 8) {
                            Text(tr("Preisbelege")).font(.subheadline.weight(.semibold))
                            Text(tr("\(info.marketReferences.count)"))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.scoutElevated, in: Capsule())
                        }
                    }.tint(Color.scoutAccent)
                }
                if !info.sourceChecks.isEmpty {
                    DisclosureGroup(tr("Recherche-Status")) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(info.sourceChecks, id: \.provider) { check in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(trDisplay(check.provider)).font(.caption.weight(.semibold))
                                    Text(trDisplay(check.statusLabel)).font(.caption).foregroundStyle(Color.scoutMuted)
                                }.accessibilityElement(children: .combine)
                            }
                        }.padding(.top, 10)
                    }.font(.subheadline).tint(Color.scoutMuted)
                }
            } else {
                Text(trDisplay(a.marketLabel)).font(.title2.weight(.bold))
                Text(tr("Letzte gespeicherte Recherche")).font(.caption).foregroundStyle(Color.scoutMuted)
            }
            if !provisional && !assessmentCleared { Text(tr("Geprüft: \(a.marketCheckedAt.prefix(10))")).font(.caption2).foregroundStyle(Color.scoutMuted) }
        }
    }

    private var cardData: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(trDisplay([a.year.map(String.init), a.setName, a.cardNumber.map { "#" + $0 }].compactMap { $0 }.joined(separator: " · ")))
                .font(.subheadline.weight(.semibold))
            if let team = a.team { Text(trDisplay(team)).font(.caption).foregroundStyle(Color.scoutMuted) }
            LabeledContent(tr("Hersteller"), value: trDisplay(a.brand ?? "Offen"))
            LabeledContent(tr("Variante"), value: trDisplay(a.parallel ?? a.subset ?? "Offen"))
            LabeledContent(tr("Rookie"), value: trDisplay(a.rookie.map { $0 ? "Ja" : "Nein" } ?? "Offen"))
            LabeledContent(tr("Nummerierung"), value: trDisplay(a.serialNumber ?? "Keine erkennbar"))
            LabeledContent(tr("Lizenz"), value: trDisplay(["nfl_and_nflpa": "NFL + NFLPA", "nfl": "NFL", "nflpa": "NFLPA", "college": "College", "unlicensed": "Nicht lizenziert"][a.licenseScope ?? ""] ?? "Offen"))
            if let info = a.insights {
                ForEach(info.sourceChecks, id: \.provider) { check in
                    if let value = check.url, let url = URL(string: value) {
                        Link(destination: url) { Label(trDisplay(check.provider), systemImage: "arrow.up.right").padding(.vertical, 4) }
                    }
                }
            }
            if let uncertainties = a.uncertainties, !uncertainties.isEmpty {
                Text(tr("Noch offen")).font(.caption.weight(.semibold)).foregroundStyle(Color.scoutGold)
                InsightBullets(items: uncertainties)
            }
            if a.insights == nil {
                DisclosureGroup(tr("Bisherige Einschätzung")) {
                    InsightBullets(items: legacyBullets(a.conditionNotes + "\n" + a.rationale)).padding(.top, 10)
                }
                ForEach(Array(a.marketSources.enumerated()), id: \.offset) { _, source in
                    if let url = URL(string: source.url) { Link(trDisplay(source.title), destination: url) }
                }
            }
        }.font(.subheadline)
    }

    private var recommendationSymbol: String {
        switch a.recommendation {
        case "Sell": "arrow.up.right.circle"
        case "Grade": "checkmark.seal"
        case "Bulk": "square.stack.3d.up"
        default: "bookmark"
        }
    }

    private func legacyBullets(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\n", with: ". ").components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

private struct InsightPanel<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var badge: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScoutPanel {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        panelTitle
                        Spacer(minLength: 4)
                        if let badge { badgeView(badge) }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        panelTitle
                        if let badge { badgeView(badge) }
                    }
                }
                content()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var panelTitle: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text(trDisplay(title)).foregroundStyle(Color.scoutMuted)
        }.font(.subheadline.weight(.semibold)).fixedSize()
    }

    private func badgeView(_ title: String) -> some View {
        Text(trDisplay(title)).font(.caption.weight(.semibold))
            .foregroundStyle(tint).padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.10), in: Capsule()).fixedSize(horizontal: true, vertical: false)
    }
}

private struct InsightBullets: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 9) {
                    Circle().fill(Color.scoutMuted.opacity(0.6)).frame(width: 4, height: 4).padding(.top, 8).accessibilityHidden(true)
                    Text((try? AttributedString(markdown: item)) ?? AttributedString(item))
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(Color.scoutMuted).accessibilityElement(children: .combine)
            }
        }
    }
}

private struct MarketReferenceView: View {
    let reference: MarketReference
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    referenceValue
                    Spacer(minLength: 8)
                    Text(trDisplay(reference.gradeLabel)).font(.caption.weight(.semibold)).fixedSize()
                }
                VStack(alignment: .leading, spacing: 5) {
                    referenceValue
                    Text(trDisplay(reference.gradeLabel)).font(.caption.weight(.semibold))
                }
            }
            Text(tr("\(trDisplay(reference.kindLabel)) · \(reference.currency) · \(trDisplay(reference.matchLabel))"))
                .font(.caption.weight(.medium))
                .foregroundStyle(reference.matchQuality == "exact" ? Color.scoutMuted : Color.scoutGold)
            if let title = reference.title { Text(trDisplay(title)).font(.caption).fixedSize(horizontal: false, vertical: true) }
            if reference.grade != "raw" {
                Text(tr("Gegradeter Vergleich · kein Wert deiner ungegradeten Karte")).font(.caption).foregroundStyle(Color.scoutGold)
            }
            if let condition = reference.condition { Text(tr("Zustand laut Quelle: \(condition)")).font(.caption) }
            Text(trDisplay(reference.shippingLabel)).font(.caption)
            if let date = reference.saleDate { Text(tr("Verkauft: \(date)")).font(.caption) }
            if let url = URL(string: reference.url) {
                Link(destination: url) { Label(trDisplay(reference.provider), systemImage: "arrow.up.right").padding(.vertical, 4) }
                    .font(.caption.weight(.semibold))
            }
            if let value = reference.listingURL, let url = URL(string: value) {
                Link(destination: url) { Label(tr("eBay-Verkauf"), systemImage: "arrow.up.right").padding(.vertical, 4) }
                    .font(.caption.weight(.semibold))
            }
        }.foregroundStyle(Color.scoutMuted).padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.scoutElevated, in: RoundedRectangle(cornerRadius: 16))
    }
    private var referenceValue: some View {
        Text(trDisplay(reference.valueLabel)).font(.title3.weight(.bold)).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
