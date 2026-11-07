import AppKit
import SwiftUI
import CoreImage.CIFilterBuiltins

@main struct CardScoutMac: App {
    @NSApplicationDelegateAdaptor(CompanionDelegate.self) var delegate
    var body: some Scene {
        Window("Card Scout", id: "pairing") {
            PairingView().preferredColorScheme(.light)
        }.windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
    }
}

final class CompanionDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct PairingView: View {
    @State private var code: String?
    @State private var qr: NSImage?
    @State private var ready = false
    @State private var copied = false
    @State private var queued = 0
    @State private var analyzing = 0
    @State private var pricing = 0
    @State private var failed = 0
    private let paper = Color(red: 244 / 255, green: 244 / 255, blue: 244 / 255)
    private let ink = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
    private let accent = Color(red: 15 / 255, green: 61 / 255, blue: 46 / 255)
    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CardScoutMac")
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack").font(.system(size: 28)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Card Scout").font(.system(size: 27, weight: .bold))
                    Label(ready ? "Mac bereit" : "Mac nicht gestartet", systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(ready ? accent : Color(red: 126 / 255, green: 96 / 255, blue: 39 / 255)).font(.subheadline)
                }
                Spacer()
            }
            if queued + analyzing + pricing > 0 {
                HStack(spacing: 0) {
                    queueCount(queued, label: "Warten")
                    queueCount(analyzing, label: "Analyse")
                    queueCount(pricing, label: "Preise")
                }.padding(.vertical, 16).background(.white, in: RoundedRectangle(cornerRadius: 10))
                Text("Deine Karten. Dein Tempo. Der Mac prüft die Fotos im Hintergrund.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if failed > 0 {
                Text("\(failed) Prüfungen pausieren. Auf dem iPhone erneut starten.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let qr {
                Image(nsImage: qr).interpolation(.none).resizable().scaledToFit().padding(18).background(.white, in: RoundedRectangle(cornerRadius: 12)).frame(width: 252, height: 252).accessibilityLabel("Privater Verbindungscode für dein iPhone")
                Text("iPhone verbinden").font(.title3.weight(.semibold))
                Text("Sammlung → Mac-Symbol → Code scannen").font(.subheadline).foregroundStyle(.secondary)
                Button(copied ? "Kopiert" : "Verbindungslink kopieren") {
                    guard let code else { return }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string); copied = true
                }.buttonStyle(.bordered)
            } else {
                ContentUnavailableView("Verbindung noch nicht eingerichtet", systemImage: "laptopcomputer")
            }
            HStack {
                Button("Status prüfen") { refresh() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                if !ready { Button("Starten") { start(); refresh() } }
            }.font(.caption)
        }.padding(28).frame(width: 400).foregroundStyle(ink).tint(accent).background(paper)
            .task {
                while !Task.isCancelled {
                    refresh()
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                }
            }
    }
    private func queueCount(_ count: Int, label: String) -> some View {
        VStack(spacing: 5) {
            Text("\(count)").font(.title2.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    private func refresh() {
        code = try? String(contentsOf: root.appendingPathComponent("pairing.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        if let code {
            let filter = CIFilter.qrCodeGenerator(); filter.message = Data(code.utf8); filter.correctionLevel = "M"
            if let result = filter.outputImage, let cg = CIContext().createCGImage(result, from: result.extent) { qr = NSImage(cgImage: cg, size: NSSize(width: result.extent.width, height: result.extent.height)) }
        }
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/launchctl"); task.arguments = ["print", "gui/\(getuid())/com.tobiaslatta.cardscout"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do { try task.run(); let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""; task.waitUntilExit(); ready = task.terminationStatus == 0 && output.contains("state = running") } catch { ready = false }
        // Local counts only. The companion never reads or displays photos or card records.
        let database = root.appendingPathComponent("queue.sqlite3")
        if FileManager.default.fileExists(atPath: database.path) {
            let query = Process(); query.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            query.arguments = ["-readonly", database.path, "SELECT status, COUNT(*) FROM jobs GROUP BY status;"]
            let output = Pipe(); query.standardOutput = output; query.standardError = FileHandle.nullDevice
            do {
                try query.run()
                let rows = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                query.waitUntilExit()
                if query.terminationStatus == 0 {
                    var counts: [String: Int] = [:]
                    for row in rows.split(separator: "\n") {
                        let fields = row.split(separator: "|")
                        if fields.count == 2, let count = Int(fields[1]) { counts[String(fields[0])] = count }
                    }
                    queued = counts["queued", default: 0]; analyzing = counts["processing", default: 0]
                    pricing = counts["identified", default: 0] + counts["enriching", default: 0]; failed = counts["failed", default: 0]
                }
            } catch { }
        }
    }
    private func start() {
        let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootstrap", "gui/\(getuid())", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.tobiaslatta.cardscout.plist").path]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit() } catch { ready = false }
    }
}
