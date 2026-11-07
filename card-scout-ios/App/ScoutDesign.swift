import CardScoutCore
import SwiftUI
import UIKit

/// Tackle4Loss mobile palette, adapted from flutter_app/lib/design_tokens.dart.
/// Original card photos and market evidence always lead.
enum ScoutAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "Wie iPhone"; case .light: "Hell"; case .dark: "Dunkel" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

extension Color {
    private static func scoutColor(_ light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let scoutCanvas = scoutColor(0xF4F4F4, dark: 0x0F1010)
    static let scoutInk = scoutColor(0x111111, dark: 0xE0E0E0)
    static let scoutSurface = scoutColor(0xFFFFFF, dark: 0x1A1C1C)
    static let scoutElevated = scoutColor(0xE8EDEA, dark: 0x25332D)
    static let scoutLine = scoutColor(0xE0E0E0, dark: 0x414845)
    // T4L's active green keeps links readable against charcoal surfaces.
    static let scoutAccent = scoutColor(0x0F3D2E, dark: 0x72CAA0)
    static let scoutButtonFill = Color(red: 15/255, green: 61/255, blue: 46/255)
    static let scoutBrandLight = Color(red: 19/255, green: 84/255, blue: 62/255)
    static let scoutPhotoBackdrop = Color(red: 15/255, green: 16/255, blue: 16/255)
    static let scoutRed = scoutColor(0x991B1B, dark: 0xF18A8A)
    static let scoutMuted = scoutColor(0x696972, dark: 0xA1A1AA)
    static let scoutEditorialGold = Color(red: 201/255, green: 162/255, blue: 86/255)
    static let scoutGold = scoutColor(0x7E6027, dark: 0xC9A256)
}

struct ScoutPanel<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.scoutLine.opacity(0.7)))
    }
}

struct ScoutEyebrow: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(trDisplay(title.uppercased())).font(.caption2.weight(.bold)).tracking(1.7)
            .foregroundStyle(Color.scoutMuted).fixedSize(horizontal: false, vertical: true)
    }
}

struct ScoutSectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: String?
    init(_ title: String, subtitle: String? = nil, trailing: String? = nil) {
        self.title = title; self.subtitle = subtitle; self.trailing = trailing
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(trDisplay(title)).font(.title3.weight(.bold))
                if let subtitle, !subtitle.isEmpty { Text(trDisplay(subtitle)).font(.caption).foregroundStyle(Color.scoutMuted) }
            }
            Spacer(minLength: 0)
            if let trailing, !trailing.isEmpty { Text(trDisplay(trailing)).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Color.scoutMuted) }
        }.accessibilityAddTraits(.isHeader)
    }
}

struct ScoutChip: View {
    let title: String
    var systemImage: String?
    var selected = false
    init(_ title: String, systemImage: String? = nil, selected: Bool = false) {
        self.title = title; self.systemImage = systemImage; self.selected = selected
    }
    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(trDisplay(title))
        }.font(.caption.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 10)
            .foregroundStyle(selected ? Color.white : Color.scoutMuted)
            .background(selected ? Color.scoutButtonFill : Color.scoutElevated, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ScoutPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.bold))
            .frame(minHeight: 48).frame(maxWidth: .infinity).padding(.horizontal, 18)
            .foregroundStyle(Color.white)
            .background(LinearGradient(colors: [.scoutBrandLight, .scoutButtonFill], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.38)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ScoutSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .frame(minHeight: 44).padding(.horizontal, 15)
            .foregroundStyle(Color.scoutAccent)
            .background(Color.scoutElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ScoutEmptyState: View {
    let symbol: String
    let title: String
    var message: String?
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.scoutAccent).frame(width: 76, height: 76)
                .background(Color.scoutElevated, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.scoutEditorialGold.opacity(0.55)))
                .accessibilityHidden(true)
            Text(trDisplay(title)).font(.title3.bold())
            if let message, !message.isEmpty { Text(trDisplay(message)).font(.subheadline).foregroundStyle(Color.scoutMuted).fixedSize(horizontal: false, vertical: true) }
        }.multilineTextAlignment(.center).padding(.vertical, 28).frame(maxWidth: .infinity)
    }
}
