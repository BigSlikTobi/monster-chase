import SwiftUI
import PhotosUI
@preconcurrency import AVFoundation
import ImageIO
import CardScoutCore

struct AddCardView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let cardID: String?
    let focusedSide: CardPhotoSide?
    let onSaved: (() -> Void)?
    init(cardID: String? = nil, side: CardPhotoSide? = nil, onSaved: (() -> Void)? = nil) {
        self.cardID = cardID; focusedSide = side; self.onSaved = onSaved
    }
    private var existingCard: OwnedCard? { store.library.cards.first { $0.id == cardID } }
    @State private var matchCardID: String?
    @State private var front: Data?
    @State private var back: Data?
    @State private var frontSelection: PhotosPickerItem?
    @State private var backSelection: PhotosPickerItem?
    @State private var cameraSide: String?
    @State private var loadingCount = 0
    @State private var frontImageRevision = UUID()
    @State private var backImageRevision = UUID()
    @State private var frontLoadID = UUID()
    @State private var backLoadID = UUID()
    private var loading: Bool { loadingCount > 0 }
    @State private var error: String?
    @State private var confirmFrontOnly = false
    private var canSave: Bool { !loading && (cardID == nil ? front != nil : front != nil || back != nil) }
    private var selectedCount: Int { (front != nil ? 1 : 0) + (back != nil ? 1 : 0) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let existingCard { Text(cardTitle(existingCard)).font(.title2.bold()) }
                        if cardID != nil {
                            Text(trDisplay(focusedSide == .back ? "Zeige die ganze Rückseite. Kartennummer, Jahr und kleine Schrift müssen lesbar sein." : focusedSide == .front ? "Zeige die ganze Vorderseite. Spielername und Oberfläche müssen klar erkennbar sein." : "Ersetze die Vorder- oder Rückseite."))
                                .font(.subheadline).foregroundStyle(Color.scoutMuted)
                        }
                    }
                    let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                    layout {
                        if focusedSide != .back {
                            capture("Vorderseite", number: "01", required: true, data: front, revision: frontImageRevision, savedFile: existingCard?.frontFile, selection: $frontSelection)
                        }
                        if focusedSide != .front {
                            capture("Rückseite", number: "02", required: false, data: back, revision: backImageRevision, savedFile: existingCard?.backFile, selection: $backSelection)
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "viewfinder").font(.title3).foregroundStyle(Color.scoutAccent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Alle vier Ecken im Bild.")).font(.subheadline.weight(.semibold))
                        }
                    }.padding(.horizontal, 3)
                    if let error {
                        Label(trDisplay(error), systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Color.scoutGold)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }.padding(20)
            }.background(Color.scoutCanvas).navigationTitle(trDisplay(cardID == nil ? "Karte hinzufügen" : "Fotos ersetzen")).navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom, spacing: 0) { if matchCardID == nil { saveFooter } }
                .navigationDestination(isPresented: Binding(get: { matchCardID != nil }, set: { if !$0 { matchCardID = nil } })) {
                    if let matchCardID { ScanMatchView(cardID: matchCardID, onNext: { onSaved?(); dismiss() }) }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { dismiss() } } }
                .alert(tr("Nur die Vorderseite verwenden?"), isPresented: $confirmFrontOnly) {
                    Button(tr("Rückseite ergänzen"), role: .cancel) { }
                    Button(tr("Ohne Rückseite fortfahren")) { save() }
                } message: { Text(tr("Für Kartennummer und genaue Variante wird oft die Rückseite benötigt. Die Karte kann trotzdem gespeichert werden.")) }
                .task {
                    if let focusedSide, UIImagePickerController.isSourceTypeAvailable(.camera) {
                        await openCamera(focusedSide == .front ? "Vorderseite" : "Rückseite")
                    }
                }
                .onChange(of: frontSelection) { _, item in Task { await load(item, frontSide: true) } }
                .onChange(of: backSelection) { _, item in Task { await load(item, frontSide: false) } }
                .fullScreenCover(isPresented: Binding(get: { cameraSide != nil }, set: { if !$0 { cameraSide = nil } })) {
                    PortraitCameraView { data in
                        if let data {
                            if cameraSide == "Vorderseite" { frontLoadID = UUID(); frontImageRevision = UUID(); front = data }
                            else { backLoadID = UUID(); backImageRevision = UUID(); back = data }
                            error = nil
                        }
                        cameraSide = nil
                    }.ignoresSafeArea()
                }
        }
    }
    private var saveFooter: some View {
        VStack(spacing: 10) {
            if loading {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(tr("Foto wird geladen …")) }
                    .font(.caption).foregroundStyle(Color.scoutMuted)
            } else if cardID != nil {
                Text(trDisplay(selectedCount == 0 ? "Wähle mindestens ein neues Foto." : selectedCount == 1 ? "1 Foto wird ersetzt." : "Beide Fotos werden ersetzt."))
                    .font(.caption).foregroundStyle(Color.scoutMuted)
            } else if front == nil {
                Text(tr("Starte mit der Vorderseite.")).font(.caption).foregroundStyle(Color.scoutMuted)
            } else if back == nil {
                Text(tr("Ergänze die Rückseite derselben Karte für Nummer und Variante.")).font(.caption).foregroundStyle(Color.scoutGold)
            }
            Button(action: {
                if cardID == nil && back == nil { confirmFrontOnly = true } else { save() }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: cardID == nil ? "sparkle.viewfinder" : "arrow.triangle.2.circlepath")
                    Text(trDisplay(cardID == nil ? "Treffer vergleichen" : "Speichern & neu analysieren"))
                        .multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity)
            }.buttonStyle(ScoutPrimaryButtonStyle()).disabled(!canSave)
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
        .background(Color.scoutCanvas.opacity(0.98))
        .overlay(alignment: .top) { Rectangle().fill(Color.scoutMuted.opacity(0.13)).frame(height: 1) }
    }
    private func save() {
        guard canSave else { return }
        do {
            if let cardID { try store.retakePhotos(cardID, front: front, back: back) }
            else if let front { matchCardID = try store.addCapture(CapturePhoto(front: front, back: back)); return }
            else { return }
            onSaved?()
            dismiss()
        } catch { self.error = "Fotos konnten nicht gespeichert werden. Bitte erneut versuchen." }
    }
    private func capture(_ title: String, number: String, required: Bool, data: Data?, revision: UUID, savedFile: String?, selection: Binding<PhotosPickerItem?>) -> some View {
        let request = AppImageRequest.preview(data, revision: revision)
            ?? store.photoURL(savedFile).map { AppImageRequest(source: .file($0, artwork: false), maxPixel: 1600) }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trDisplay(number)).font(.caption2.monospaced().weight(.bold)).foregroundStyle(Color.scoutMuted)
                Text(trDisplay(title)).font(.subheadline.weight(.bold))
                Text(trDisplay(focusedSide != nil ? "Neues Foto für diese Prüfung" : required ? "Erforderlich" : "Optional"))
                    .font(.caption).foregroundStyle(Color.scoutMuted)
            }.accessibilityElement(children: .combine)
            PhotosPicker(selection: selection, matching: .images) {
                StableImage(request: request) { image, loading in
                    ZStack(alignment: .bottom) {
                        PhotoCard(image: image, number: "", owned: true)
                        if request == nil {
                            VStack(spacing: 10) {
                                Image(systemName: "plus").font(.title2.weight(.light))
                                Text(tr("Foto hinzufügen")).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                            }.foregroundStyle(Color.scoutMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.scoutSurface, in: RoundedRectangle(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.scoutMuted.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 5])) }
                        } else if loading {
                            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if image != nil {
                            Label(trDisplay(data != nil ? (savedFile == nil ? "Hinzugefügt" : "Neues Foto") : "Vorhanden"), systemImage: data != nil ? "checkmark.circle.fill" : "checkmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(Color.scoutPhotoBackdrop.opacity(0.92), in: Capsule()).padding(9)
                        }
                    }
                }
            }.buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(trDisplay(request == nil ? "Foto der \(title) hinzufügen" : "Foto der \(title) ersetzen"))
                .accessibilityHint(tr("Öffnet die Mediathek"))
            VStack(spacing: 8) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { Task { await openCamera(title) } } label: {
                        Label(tr("Kamera"), systemImage: "camera").frame(maxWidth: .infinity)
                    }.buttonStyle(ScoutSecondaryButtonStyle())
                        .accessibilityLabel(tr("\(title) fotografieren"))
                }
                PhotosPicker(selection: selection, matching: .images) {
                    Label(tr("Mediathek"), systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }.buttonStyle(ScoutSecondaryButtonStyle())
                    .accessibilityLabel(tr("\(title) aus der Mediathek wählen"))
            }.font(.subheadline.weight(.semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func openCamera(_ side: String) async {
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        if allowed { cameraSide = side }
        else { error = "Bitte Kamerazugriff in den iPhone-Einstellungen erlauben." }
    }
    private func load(_ item: PhotosPickerItem?, frontSide: Bool) async {
        guard let item else { return }
        let loadID = UUID()
        if frontSide { frontLoadID = loadID } else { backLoadID = loadID }
        loadingCount += 1; defer { loadingCount -= 1 }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let normalized = normalizedJPEG(data) else { throw CocoaError(.fileReadCorruptFile) }
            guard loadID == (frontSide ? frontLoadID : backLoadID) else { return }
            if frontSide { frontImageRevision = UUID(); front = normalized } else { backImageRevision = UUID(); back = normalized }
            error = nil
        } catch { if loadID == (frontSide ? frontLoadID : backLoadID) { self.error = "Foto konnte nicht geladen werden. Bitte erneut wählen." } }
    }
}

func normalizedJPEG(_ data: Data) -> Data? {
    CardPhotoEncoding.jpeg(data)
}

struct ConnectionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("scoutAppearance") private var appearance = ScoutAppearance.system.rawValue
    @AppStorage("scoutLanguage") private var language = "system"
    @State private var code = ""
    @State private var scanning = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: store.connected ? "checkmark.circle" : "laptopcomputer")
                            .font(.title2).foregroundStyle(store.connected ? Color.scoutAccent : Color.scoutMuted)
                            .frame(width: 48, height: 48).background(Color.scoutElevated, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(trDisplay(store.connected ? "Verbunden" : "Offline")).font(.headline)
                            if let pairing = store.pairing {
                                Text(trDisplay(URL(string: pairing.baseURL)?.host ?? "Mac")).font(.caption).foregroundStyle(Color.scoutMuted)
                            } else {
                                Text(tr("Noch kein Mac oder Server gekoppelt")).font(.caption).foregroundStyle(Color.scoutMuted)
                            }
                        }
                    }.padding(.vertical, 6)
                    Button { Task { await store.sync() } } label: {
                        HStack {
                            Label(tr("Verbindung prüfen"), systemImage: "arrow.clockwise")
                            Spacer()
                            if store.syncing { ProgressView() }
                        }
                    }.disabled(store.pairing == nil || store.syncing)
                    if let message = store.connectionError {
                        Label(trDisplay(message), systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Color.scoutAccent)
                            .accessibilityLabel(trDisplay("Verbindungsfehler: " + message))
                    }
                }
                if let candidate = store.pairingCandidate {
                    Section(tr("Diese Verbindung verwenden?")) {
                        Text(trDisplay(URL(string: candidate.baseURL)?.host ?? "Mac"))
                        Button(tr("Verbinden")) { store.confirmPairing() }.fontWeight(.semibold)
                        Button(tr("Abbrechen"), role: .cancel) { store.pairingCandidate = nil }
                    }
                } else {
                    Section(tr("Mac oder Server verbinden")) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { Button(tr("Verbindungscode scannen")) { scanning = true } }
                        TextField(tr("Verbindungslink einfügen"), text: $code, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        Button(tr("Code öffnen")) { if let url = URL(string: code) { store.receivePairing(url); code = "" } }.disabled(code.isEmpty)
                    }
                }
                Section {
                    Picker(tr("Sprache"), selection: $language) {
                        Text(tr("Wie iPhone")).tag("system")
                        Text("Deutsch").tag("de")
                        Text("English").tag("en")
                    }.pickerStyle(.menu)
                }
                Section(tr("Darstellung")) {
                    Picker(tr("Design"), selection: $appearance) {
                        ForEach(ScoutAppearance.allCases) { mode in Text(trDisplay(mode.title)).tag(mode.rawValue) }
                    }.pickerStyle(.segmented)
                }
            }.scrollContentBackground(.hidden).background(Color.scoutCanvas)
                .navigationTitle(tr("Einstellungen")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fertig")) { dismiss() } } }
                .sheet(isPresented: $scanning) { QRScanner { value in scanning = false; if let url = URL(string: value) { store.receivePairing(url) } } }
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    let completed: (String) -> Void
    func makeUIViewController(context: Context) -> QRController { QRController(completed: completed) }
    func updateUIViewController(_ controller: QRController, context: Context) {}
}

final class QRController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    let completed: (String) -> Void
    let session = AVCaptureSession()
    var preview: AVCaptureVideoPreviewLayer?
    var delivered = false
    init(completed: @escaping (String) -> Void) { self.completed = completed; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unsupported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        Task { @MainActor in
            guard await AVCaptureDevice.requestAccess(for: .video), let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput(); guard session.canAddOutput(output) else { return }; session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session); layer.videoGravity = .resizeAspectFill; layer.frame = view.bounds; view.layer.addSublayer(layer); preview = layer
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); session.stopRunning() }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered, let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let value = object.stringValue, value.hasPrefix("cardscout://pair?") else { return }
        delivered = true; session.stopRunning(); completed(value)
    }
}
