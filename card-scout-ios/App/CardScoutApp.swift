import SwiftUI
import CardScoutCore

@main struct CardScoutApp: App {
    @State private var store = AppStore()
    @AppStorage("scoutAppearance") private var appearance = ScoutAppearance.system.rawValue
    @AppStorage("scoutLanguage") private var language = "system"
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            LibraryView().environment(store).environment(\.locale, Locale(identifier: ScoutLocalization.resolve(preference: language, preferredLanguages: Locale.preferredLanguages))).preferredColorScheme((ScoutAppearance(rawValue: appearance) ?? .system).colorScheme)
                .onChange(of: language) { _, value in AppLanguage.shared.preference = value }
                .onOpenURL { store.receiveURL($0) }
                .task {
                    #if DEBUG
                    if PreviewData.enabled && ProcessInfo.processInfo.arguments.contains("--preview-settings") { store.showSettings = true }
                    #endif
                    await store.syncLoop()
                }
                .onChange(of: phase) { _, value in if value == .active { Task { await store.sync() } } }
        }
    }
}
