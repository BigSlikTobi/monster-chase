import SwiftUI
import PhotosUI
import Observation
@preconcurrency import AVFoundation
import Vision
import CardScoutCore

private func capturePhoto(_ bytes: Data) -> CapturePhoto? {
    guard let jpeg = normalizedJPEG(bytes) else { return nil }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    try? VNImageRequestHandler(data: jpeg).perform([request])
    let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    return CapturePhoto(front: jpeg, text: text.map { String($0.prefix(2000)) })
}

private final class CaptureDriver: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "cardscout.capture", qos: .userInitiated)
    private let photo = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var lastFocusChange = 0.0
    private var configured = false
    private var busy = false
    private var automatic = false
    private var pendingManual = false
    private var manualDeadline = 0.0
    private var gate = CaptureGate()
    private var lastDetection = 0.0
    var received: (@Sendable (Data) -> Void)?
    var failed: (@Sendable (String) -> Void)?
    var guidance: (@Sendable (ScanCardFrame?, CGSize, Bool, Bool, CaptureReadiness) -> Void)?
    var capturing: (@Sendable () -> Void)?
    var cancelled: (@Sendable () -> Void)?
    var started: (@Sendable () -> Void)?
    var torchChanged: (@Sendable (Bool, Bool) -> Void)?

    private func reportTorch() {
        torchChanged?(device?.hasTorch == true && device?.isTorchAvailable == true,
                      device?.isTorchActive == true)
    }
    func setTorch(_ enabled: Bool) {
        queue.async { [self] in
            guard let device, session.isRunning, !busy else { reportTorch(); return }
            guard device.hasTorch, device.isTorchModeSupported(enabled ? .on : .off),
                  !enabled || device.isTorchAvailable else {
                reportTorch(); failed?("Lampe ist gerade nicht verfügbar."); return
            }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if enabled { try device.setTorchModeOn(level: 0.35) }
                else { device.torchMode = .off }
                lastFocusChange = ProcessInfo.processInfo.systemUptime
            } catch { failed?("Lampe konnte nicht umgeschaltet werden.") }
            reportTorch()
        }
    }

    func start() {
        queue.async { [self] in
            if !configured {
                // A virtual camera can switch to the close-focusing ultra-wide lens.
                let selected = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                guard let camera = selected,
                      let input = try? AVCaptureDeviceInput(device: camera) else { failed?("Kamera nicht verfügbar."); return }
                session.beginConfiguration(); session.sessionPreset = .photo
                guard session.canAddInput(input), session.canAddOutput(photo) else { session.commitConfiguration(); failed?("Kamera konnte nicht starten."); return }
                session.addInput(input); session.addOutput(photo)
                device = camera
                do {
                    try camera.lockForConfiguration()
                    defer { camera.unlockForConfiguration() }
                    if camera.isFocusModeSupported(.continuousAutoFocus) { camera.focusMode = .continuousAutoFocus }
                    if camera.isFocusPointOfInterestSupported { camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
                    if camera.isExposureModeSupported(.continuousAutoExposure) { camera.exposureMode = .continuousAutoExposure }
                    if camera.isAutoFocusRangeRestrictionSupported { camera.autoFocusRangeRestriction = .near }
                    if camera.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported {
                        camera.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
                    }
                    if let wide = camera.virtualDeviceSwitchOverVideoZoomFactors.first {
                        camera.videoZoomFactor = min(camera.maxAvailableVideoZoomFactor, max(camera.minAvailableVideoZoomFactor, CGFloat(truncating: wide)))
                    }
                } catch { session.commitConfiguration(); failed?("Kamera konnte nicht fokussieren."); return }
                photo.maxPhotoQualityPrioritization = .quality
                if let connection = photo.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                let video = AVCaptureVideoDataOutput(); video.alwaysDiscardsLateVideoFrames = true
                if session.canAddOutput(video) {
                    session.addOutput(video); video.setSampleBufferDelegate(self, queue: queue)
                    if let connection = video.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
                }
                session.commitConfiguration(); configured = true
            }
            if !session.isRunning { session.startRunning(); lastFocusChange = ProcessInfo.processInfo.systemUptime }
            reportTorch()
            started?()
        }
    }
    func stop() { queue.async { [self] in
        if pendingManual { pendingManual = false; cancelled?() }
        if let device, device.hasTorch {
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            } catch { }
        }
        if session.isRunning { session.stopRunning() }
        torchChanged?(false, false)
    } }
    // Keep the removal latch across front/back and mode switches. Otherwise the
    // just-captured back can become the next card's front automatically.
    func setAutomatic(_ enabled: Bool) { queue.async { [self] in automatic = enabled } }
    func resume() { queue.async { [self] in busy = false } }
    func focus(at point: CGPoint) {
        queue.async { [self] in
            guard let device, !busy, device.isFocusPointOfInterestSupported else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                device.focusPointOfInterest = point
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
                lastFocusChange = ProcessInfo.processInfo.systemUptime
            } catch { }
        }
    }
    func capture() {
        queue.async { [self] in
            guard configured, session.isRunning else { failed?("Kamera startet noch. Bitte gleich erneut aufnehmen."); return }
            guard !busy, !pendingManual else { return }
            if !takePhoto() { pendingManual = true; manualDeadline = ProcessInfo.processInfo.systemUptime + 3 }
        }
    }
    private func focusReady(at time: Double) -> Bool {
        guard let device else { return false }
        return !device.isAdjustingFocus && time - lastFocusChange >= 0.12
    }
    @discardableResult private func takePhoto() -> Bool {
        guard configured, session.isRunning, !busy, focusReady(at: ProcessInfo.processInfo.systemUptime) else { return false }
        busy = true; gate.didCapture()
        capturing?()
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.flashMode = .off; settings.photoQualityPrioritization = .quality
        photo.capturePhoto(with: settings, delegate: self)
        return true
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let bytes = photo.fileDataRepresentation() else { failed?("Foto konnte nicht aufgenommen werden."); resume(); return }
        received?(bytes)
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = ProcessInfo.processInfo.systemUptime
        // isAdjustingFocus already blocks the shutter while the lens moves.
        // Do not add another cooldown after every continuous-autofocus pulse.
        let settled = focusReady(at: time)
        if pendingManual {
            if time >= manualDeadline { pendingManual = false; failed?("Fokus findet die Karte nicht. Etwas mehr Abstand halten und erneut tippen.") }
            else if settled, takePhoto() { pendingManual = false }
        }
        guard !busy, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard time - lastDetection > 0.12 else { return }; lastDetection = time
        reportTorch()
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8; request.minimumConfidence = 0.7
        request.minimumAspectRatio = 0.3; request.maximumAspectRatio = 0.95
        request.minimumSize = 0.18; request.quadratureTolerance = 30
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let candidates = (request.results ?? []).map { ScanCardFrame(corners: [$0.topLeft, $0.topRight, $0.bottomRight, $0.bottomLeft]) }
        let card = ScanCardFrame.best(candidates, imageSize: size)
        let readiness = CaptureReadiness.evaluate(frame: card, focusReady: settled)
        let framingReady = card.map { $0.bounds.width * $0.bounds.height >= 0.18 } ?? false
        let capture = automatic && !pendingManual && gate.update(rect: card?.bounds, at: time, focusReady: settled, qualityReady: framingReady)
        guidance?(card, size, !gate.isArmed, !settled, readiness)
        if capture, !takePhoto() { gate = CaptureGate() }
    }
}

@MainActor @Observable private final class CaptureCamera {
    var torchAvailable = false
    var torchOn = false
    var ready = false
    var saving = false
    var automatic = UserDefaults.standard.object(forKey: "scoutAutomaticCapture") as? Bool ?? true
    var cardDetected = false
    var needsNewCard = false
    var detectedFrame: ScanCardFrame?
    var imageSize = CGSize(width: 3, height: 4)
    var focusing = false
    var readiness = CaptureReadiness.missingCard
    var error: String?
    private var wantsCamera = false
    private var lastStatusWrite = 0.0

    // Local, bounded troubleshooting receipt. No images, OCR, card identity,
    // coordinates, credentials or network traffic.
    private func recordCaptureStatus(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastStatusWrite >= 1 else { return }
        lastStatusWrite = now
        guard let root = try? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false).appendingPathComponent("CardScout") else { return }
        let status: [String: Any] = ["build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            "automatic": automatic, "cameraRunning": ready, "saving": saving,
            "cardDetected": cardDetected, "waitingForRemoval": needsNewCard,
            "focusing": focusing, "readiness": String(describing: readiness),
            "checkedAt": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("capture-status.json"),
                            options: [.atomic, .completeFileProtection])
        }
    }
    @ObservationIgnored let driver = CaptureDriver()
    @ObservationIgnored var save: ((CapturePhoto) throws -> Void)?
    init(automatic: Bool? = nil) {
        if let automatic { self.automatic = automatic }
        driver.setAutomatic(self.automatic)
        driver.started = { [weak self] in Task { @MainActor in
            guard let self else { return }
            guard self.wantsCamera else { self.driver.stop(); return }
            self.ready = true
            UIApplication.shared.isIdleTimerDisabled = true
        } }
        driver.torchChanged = { [weak self] available, enabled in
            Task { @MainActor in self?.torchAvailable = available; self?.torchOn = enabled }
        }
        driver.received = { [weak self] bytes in
            Task { @MainActor [weak self] in
                guard let self else { return }; self.saving = true
                self.recordCaptureStatus(force: true)
                let capture = await Task.detached(priority: .userInitiated) { capturePhoto(bytes) }.value
                do {
                    guard let capture else { throw StoreError.missingFront }
                    try self.save?(capture); self.error = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } catch { self.error = "Foto nicht gespeichert. Bitte erneut aufnehmen." }
                self.saving = false; self.driver.resume()
                self.recordCaptureStatus(force: true)
            }
        }
        driver.failed = { [weak self] message in Task { @MainActor in self?.error = message; self?.saving = false } }
        driver.capturing = { [weak self] in Task { @MainActor in self?.saving = true; self?.error = nil } }
        driver.cancelled = { [weak self] in Task { @MainActor in self?.saving = false } }
        driver.guidance = { [weak self] frame, size, changed, focusing, readiness in
            Task { @MainActor in
                self?.detectedFrame = frame; self?.imageSize = size; self?.cardDetected = frame != nil
                self?.needsNewCard = changed; self?.focusing = focusing
                self?.readiness = readiness
                self?.recordCaptureStatus()
            }
        }
    }
    func start() async {
        wantsCamera = true
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard wantsCamera else { return }
        guard allowed else { error = "Kamerazugriff in den iPhone-Einstellungen erlauben."; return }
        driver.start()
    }
    func stop() {
        wantsCamera = false; ready = false
        UIApplication.shared.isIdleTimerDisabled = false
        driver.stop()
        recordCaptureStatus(force: true)
    }
    func capture() { guard ready, !saving else { return }; saving = true; driver.capture() }
    func setAutomatic(_ enabled: Bool) {
        automatic = enabled; UserDefaults.standard.set(enabled, forKey: "scoutAutomaticCapture"); driver.setAutomatic(enabled)
    }
}

private final class PreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let frame: ScanCardFrame?
    let imageSize: CGSize
    let focus: (CGPoint) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(focus: focus) }
    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface(); view.preview.session = session; view.preview.videoGravity = .resizeAspect
        context.coordinator.view = view
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return view
    }
    func updateUIView(_ view: PreviewSurface, context: Context) {
        // The sensor is landscape-native. Match the portrait photo and Vision outputs.
        if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        guard let frame, view.bounds.width > 0, view.bounds.height > 0 else { return }
        let points = frame.previewPoints(imageSize: imageSize, viewSize: view.bounds.size, aspectFill: false)
        guard points.count == 4 else { return }
        let centre = CGPoint(x: points.map(\.x).reduce(0, +) / 4, y: points.map(\.y).reduce(0, +) / 4)
        context.coordinator.focus(at: centre, force: false)
    }
    final class Coordinator: NSObject {
        weak var view: PreviewSurface?
        let applyFocus: (CGPoint) -> Void
        var lastTarget: CGPoint?
        var lastChange = 0.0
        init(focus: @escaping (CGPoint) -> Void) { applyFocus = focus }
        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }; focus(at: recognizer.location(in: view), force: true)
        }
        func focus(at point: CGPoint, force: Bool) {
            guard let view else { return }
            let target = view.preview.captureDevicePointConverted(fromLayerPoint: point)
            let now = ProcessInfo.processInfo.systemUptime
            if !force, let lastTarget {
                guard hypot(target.x - lastTarget.x, target.y - lastTarget.y) > 0.12, now - lastChange > 1 else { return }
            }
            lastTarget = target; lastChange = now; applyFocus(target)
        }
    }
}

struct PortraitCameraView: View {
    @Environment(\.scenePhase) private var phase
    @State private var camera = CaptureCamera(automatic: false)
    @State private var captured: Data?
    @State private var capturedRevision = UUID()
    let completed: (Data?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        Color.scoutPhotoBackdrop
                        if let captured {
                            StableImage(request: .preview(captured, revision: capturedRevision)) { image, loading in
                                if let image { Image(uiImage: image).resizable().scaledToFit() }
                                else if loading { ProgressView().tint(.white) }
                                else { Label(tr("Foto nicht verfügbar"), systemImage: "photo") }
                            }
                        } else if camera.ready {
                            CameraPreview(session: camera.driver.session, frame: nil, imageSize: camera.imageSize) {
                                camera.driver.focus(at: $0)
                            }
                        } else { ProgressView().tint(.white) }
                    }
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    Text(tr("iPhone hochkant halten. Alle vier Ecken und den Text scharf aufnehmen."))
                        .font(.footnote).foregroundStyle(Color.scoutMuted)
                    if let error = camera.error { Text(trDisplay(error)).font(.footnote).foregroundStyle(Color.scoutGold) }
                    if let captured {
                        Button(tr("Foto verwenden")) { completed(captured) }.buttonStyle(ScoutPrimaryButtonStyle())
                        Button(tr("Erneut aufnehmen")) { self.captured = nil; Task { await camera.start() } }
                            .buttonStyle(ScoutSecondaryButtonStyle())
                    } else {
                        Button { camera.capture() } label: {
                            Label(trDisplay(camera.saving ? "Wird aufgenommen …" : "Foto aufnehmen"), systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(ScoutPrimaryButtonStyle()).disabled(!camera.ready || camera.saving)
                    }
                }.padding(20)
            }
            .background(Color.scoutCanvas).navigationTitle(tr("Karte fotografieren")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Abbrechen")) { completed(nil) } } }
        }
        .task {
            camera.save = { capture in capturedRevision = UUID(); captured = capture.front; camera.stop() }
            await camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: phase) { _, value in
            if value == .active && captured == nil { Task { await camera.start() } }
            else { camera.stop() }
        }
    }
}

struct FastScanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var camera = CaptureCamera()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var progress = 0
    @State private var importTotal = 0
    @State private var importedErrors = 0
    @State private var sessionCards: [String] = []
    @State private var lastCapture: String?
    @State private var addingDetailed = false
    @State private var comparing: String?
    @State private var skipBack = false
    @AppStorage("scoutScanMode") private var scanMode = ScanCaptureMode.single.rawValue
    private var mode: ScanCaptureMode { ScanCaptureMode(rawValue: scanMode) ?? .single }
    private var pendingPair: OwnedCard? { store.pendingCapturePair }
    private var captures: [OwnedCard] { sessionCards.reversed().compactMap { id in store.library.cards.first { $0.id == id } } }
    private var summary: ScanSessionSummary { ScanSessionSummary(cards: captures) }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker(tr("Scan-Modus"), selection: $scanMode) {
                        Text(tr("Einzeln")).tag(ScanCaptureMode.single.rawValue)
                        Text(tr("Stapel")).tag(ScanCaptureMode.stack.rawValue)
                    }.pickerStyle(.segmented).disabled(pendingPair != nil || camera.saving)
                    Text(trDisplay(mode == .stack
                         ? "Vorne → hinten → nächste Karte. Zuordnung und Preise folgen im Hintergrund."
                         : "Vorder- und Rückseite aufnehmen. Danach Treffer vergleichen."))
                        .font(.footnote).foregroundStyle(Color.scoutMuted)
                    if let pair = pendingPair {
                        HStack(alignment: .top, spacing: 14) {
                            OwnedPhoto(name: pair.frontFile, maxPixel: 600, original: true).frame(width: 65, height: 90)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(tr("2 · Rückseite derselben Karte")).font(.headline)
                                Text(trDisplay(camera.automatic
                                     ? "Vorderseite gespeichert. Nimm die Karte kurz aus dem Bild und drehe sie um. Die Rückseite wird automatisch aufgenommen."
                                     : "Vorderseite gespeichert. Drehe diese Karte um und tippe auf den Auslöser für die Rückseite."))
                                    .font(.subheadline).foregroundStyle(Color.scoutMuted)
                                if pair.captureMode != ScanCaptureMode.stack.rawValue {
                                    Button(tr("Ohne Rückseite weiter")) { skipBack = true }.font(.caption).disabled(camera.saving)
                                }
                            }
                        }
                    } else {
                        Text(tr("1 · Vorderseite aufnehmen")).font(.headline)
                    }
                    viewfinder(previewHeight: max(160, min((viewport.size.width - 40) * 0.9, viewport.size.height - (pendingPair == nil ? 320 : 390))))
                    Text(tr("Eine Karte vollständig ins Bild halten. Sie darf schräg liegen. Wir schneiden den Hintergrund automatisch weg."))
                        .font(.footnote).foregroundStyle(Color.scoutMuted)
                    if !store.connected {
                        Label(tr("Offline · Fotos bleiben gespeichert. Erkennung startet mit Verbindung bei geöffneter App."), systemImage: "wifi.slash")
                            .font(.footnote).foregroundStyle(Color.scoutGold)
                    }
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 200, matching: .images) {
                            Label(tr("Vorderseiten wählen"), systemImage: "photo.stack").frame(maxWidth: .infinity)
                        }.buttonStyle(ScoutSecondaryButtonStyle()).disabled(importing || pendingPair != nil || mode == .stack)
                        Button { addingDetailed = true } label: { Image(systemName: "rectangle.portrait.on.rectangle.portrait").frame(width: 44, height: 44) }
                            .accessibilityLabel(tr("Eine Karte mit Vorder- und Rückseite hinzufügen"))
                            .disabled(pendingPair != nil || mode == .stack)
                    }
                    if importing || importTotal > 0 {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(trDisplay(importing ? "\(progress) / \(importTotal) gespeichert" : "\(progress) Fotos gespeichert"))
                                Spacer(); if importing { ProgressView().controlSize(.small) }
                            }.font(.subheadline)
                            if importing { ProgressView(value: Double(progress + importedErrors), total: Double(max(importTotal, 1))).tint(.scoutAccent) }
                            if importedErrors > 0 { Text(tr("\(importedErrors) Fotos konnten nicht gelesen werden. Erneut auswählen.")).font(.caption).foregroundStyle(Color.scoutGold) }
                        }
                    }
                    if !captures.isEmpty {
                        Text(tr("\(summary.saved) gespeichert · \(summary.identified) erkannt · \(summary.processing) in Arbeit · \(summary.review) prüfen"))
                            .font(.caption.monospacedDigit()).foregroundStyle(Color.scoutMuted)
                        HStack {
                            Text(tr("Deine Session")).font(.headline)
                            Spacer()
                            Button(tr("Sammlung öffnen")) { store.selectedTab = 5 }.font(.caption.weight(.medium))
                        }
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 10) {
                                ForEach(Array(captures.prefix(24))) { card in
                                    NavigationLink { if card.isScanDraft == true { ScanMatchView(cardID: card.id) } else { CardDetailView(cardID: card.id) } } label: { OwnedTile(card: card).frame(width: 108) }.buttonStyle(.plain)
                                }
                            }
                        }.scrollIndicators(.hidden)
                    } else {
                        Text(tr("Starte mit der Vorderseite. Für Nummer, Jahr oder Variante kann die Rückseite nötig sein."))
                            .font(.footnote).foregroundStyle(Color.scoutMuted)
                    }
                    if let error = camera.error { Text(trDisplay(error)).font(.footnote).foregroundStyle(Color.scoutGold) }
                }.padding(20)
            }
        }
        .background(Color.scoutCanvas)
        .navigationTitle(tr("Scannen")).navigationBarTitleDisplayMode(.inline)
        .task {
            if let pair = pendingPair {
                if let session = pair.captureSessionID { store.captureSessionID = session }
                scanMode = pair.captureMode ?? ScanCaptureMode.single.rawValue
            }
            sessionCards = store.library.cards.filter { $0.captureSessionID == store.captureSessionID }.reversed().map(\.id)
            camera.save = { capture in
                guard comparing == nil else { return }
                if let pair = pendingPair {
                    try store.finishCapturePair(pair.id, back: capture.front, text: capture.text)
                    if pair.captureMode != ScanCaptureMode.stack.rawValue {
                        comparing = pair.id; camera.stop()
                    }
                } else {
                    let id = try store.beginCapturePair(capture, mode: mode); sessionCards.append(id); lastCapture = id
                }
            }
            camera.driver.setAutomatic(camera.automatic)
            if store.selectedTab == 3 && !addingDetailed && comparing == nil { await camera.start() }
        }
        .alert(tr("Ohne Rückseite suchen?"), isPresented: $skipBack) {
            Button(tr("Rückseite aufnehmen"), role: .cancel) { }
            Button(tr("Nur Vorderseite verwenden")) {
                guard let pair = pendingPair else { return }
                do {
                    try store.finishCapturePair(pair.id, back: nil)
                    comparing = pair.id; camera.stop()
                } catch { camera.error = "Vorderseite konnte nicht freigegeben werden. Bitte erneut versuchen." }
            }
        } message: { Text(tr("Nummer und Variante können offen bleiben. Deine Vorderseite bleibt gespeichert.")) }
        .onDisappear { camera.stop() }
        .onChange(of: phase) { _, value in
            if value == .active && store.selectedTab == 3 && !addingDetailed && comparing == nil { Task { await camera.start() } }
            else { camera.stop() }
        }
        .onChange(of: store.selectedTab) { _, tab in
            if tab == 3 && phase == .active && !addingDetailed && comparing == nil { Task { await camera.start() } }
            else { camera.stop() }
        }
        .onChange(of: selectedPhotos) { _, items in if !items.isEmpty { Task { await importPhotos(items) } } }
        .onChange(of: addingDetailed) { _, presented in
            if !presented && store.selectedTab == 3 && phase == .active { Task { await camera.start() } }
            else { camera.stop() }
        }
        .sheet(isPresented: $addingDetailed) { AddCardView() }
        .sheet(isPresented: Binding(get: { comparing != nil }, set: { if !$0 { comparing = nil } }), onDismiss: {
            if store.selectedTab == 3 && phase == .active { Task { await camera.start() } }
        }) {
            NavigationStack {
                if let comparing { ScanMatchView(cardID: comparing).toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("Später")) { self.comparing = nil } }
                } }
            }
        }
    }

    private var viewfinderStatus: String {
        if camera.saving { return "Wird aufgenommen" }
        if !camera.ready { return camera.error == nil ? "Kamera startet" : "Kamera nicht verfügbar" }
        if pendingPair != nil {
            if !camera.automatic { return "Rückseite · Auslöser antippen" }
            if camera.needsNewCard { return "Rückseite · Karte kurz aus dem Bild nehmen" }
            return "Rückseite · " + camera.readiness.guidance
        }
        if camera.automatic && camera.needsNewCard { return "Gespeichert · Karte kurz aus dem Bild nehmen" }
        return camera.readiness.guidance
    }

    private func viewfinder(previewHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(trDisplay(viewfinderStatus)).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 0)
                if camera.ready {
                    Button { camera.driver.setTorch(!camera.torchOn) } label: {
                        Label(trDisplay(camera.torchOn ? "Licht an" : "Licht aus"),
                              systemImage: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(camera.torchOn ? Color.scoutButtonFill : .white.opacity(0.12), in: Capsule())
                    }
                    .disabled(!camera.torchAvailable || camera.saving)
                    .accessibilityLabel(trDisplay(camera.torchOn ? "Handy-Lampe ausschalten" : "Handy-Lampe einschalten"))
                    .accessibilityValue(camera.torchOn ? "An" : "Aus")
                }
                if camera.ready && pendingPair == nil {
                    Button { camera.setAutomatic(!camera.automatic) } label: {
                        Text(trDisplay(camera.automatic ? "Auto an" : "Auto aus")).font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(camera.automatic ? Color.scoutButtonFill : .white.opacity(0.12), in: Capsule())
                    }.accessibilityLabel(trDisplay(camera.automatic ? "Automatisch aufnehmen ausschalten" : "Automatisch aufnehmen einschalten"))
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
            if pendingPair != nil && camera.readiness != .ready {
                Text(trDisplay(camera.readiness.guidance)).font(.caption).padding(.horizontal, 16).padding(.bottom, 8)
            }
            ZStack {
                if camera.ready {
                    CameraPreview(session: camera.driver.session, frame: camera.detectedFrame, imageSize: camera.imageSize) {
                        camera.driver.focus(at: $0)
                    }
                }
                else { Color.scoutPhotoBackdrop }
                GeometryReader { geometry in
                    if let frame = camera.detectedFrame {
                        let points = frame.previewPoints(imageSize: camera.imageSize, viewSize: geometry.size, aspectFill: false)
                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: first)
                            for point in points.dropFirst() { path.addLine(to: point) }
                            path.closeSubpath()
                        }
                        .stroke(camera.focusing ? Color.scoutEditorialGold : Color(red: 114/255, green: 202/255, blue: 160/255),
                                style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
                if !camera.ready {
                    Image(systemName: "viewfinder").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.white.opacity(0.5))
                }
            }.frame(height: previewHeight).clipped()
            HStack {
                if let card = captures.first {
                    LocalCardPhoto(name: card.frontFile, maxPixel: 180) { image, loading in
                        if let image { Image(uiImage: image).resizable().scaledToFill() }
                        else if loading { ProgressView().tint(.white) }
                        else { Image(systemName: "photo").foregroundStyle(.white) }
                    }.frame(width: 38, height: 52).clipped().clipShape(RoundedRectangle(cornerRadius: 4))
                } else { Color.clear.frame(width: 38, height: 52) }
                Spacer()
                Button { camera.capture() } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 2).frame(width: 70, height: 70)
                        Circle().fill(.white).frame(width: 58, height: 58)
                        if camera.saving { ProgressView().tint(.scoutPhotoBackdrop) }
                    }
                }.disabled(!camera.ready || camera.saving || importing).accessibilityLabel(trDisplay(pendingPair == nil ? "Vorderseite speichern" : "Rückseite derselben Karte speichern"))
                    .accessibilityHint(tr("Ohne Ausrichten an einem Rahmen. Die Kamera wartet kurz auf den Fokus."))
                Spacer()
                Text(tr("\(sessionCards.count)")).font(.headline.monospacedDigit()).frame(width: 38)
            }.padding(12)
        }.foregroundStyle(.white).background(Color.scoutPhotoBackdrop)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !importing, pendingPair == nil else { return }
        importing = true; progress = 0; importedErrors = 0; importTotal = items.count
        defer { importing = false; selectedPhotos = [] }
        // Read, normalize and save one image at a time, never 100 full-size images in RAM.
        for item in items {
            do {
                guard let bytes = try await item.loadTransferable(type: Data.self),
                      let capture = await Task.detached(priority: .userInitiated, operation: { capturePhoto(bytes) }).value else { throw StoreError.missingFront }
                let id = try store.addCapture(capture); sessionCards.append(id); progress += 1
            } catch { importedErrors += 1 }
        }
    }
}
