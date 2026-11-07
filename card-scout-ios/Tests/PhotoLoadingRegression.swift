// Runs the real pipeline/views in an isolated simulator app. URLProtocol blocks live downloads.
import SwiftUI
import UIKit
import CryptoKit
import Observation
import CardScoutCore

private struct Fixture {
    let data: Data
    var status = 200
    var delay = 0.02
}

private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var fixtures: [String: Fixture] = [:]
    private static var counts: [String: Int] = [:]
    private let stopLock = NSLock()
    private var stopped = false
    static func set(_ url: String, _ fixture: Fixture) {
        lock.lock(); defer { lock.unlock() }; fixtures[url] = fixture
    }
    static func count(_ url: String) -> Int {
        lock.lock(); defer { lock.unlock() }; return counts[url, default: 0]
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = request.url!.absoluteString
        Self.lock.lock()
        Self.counts[key, default: 0] += 1
        let fixture = Self.fixtures[key] ?? Fixture(data: Data(), status: 404)
        Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + fixture.delay) { [self] in
            stopLock.lock(); defer { stopLock.unlock() }
            guard !stopped else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: fixture.status,
                                           httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: fixture.data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stopLock.lock(); stopped = true; stopLock.unlock() }
}

@MainActor @Observable private final class PhotoProbe {
    var request: AppImageRequest?
    var tick = 0
    @ObservationIgnored var image: UIImage?
    @ObservationIgnored var loading = true
}

private struct ProbeView: View {
    let probe: PhotoProbe
    var body: some View {
        StableImage(request: probe.request) { image, loading in
            let _ = probe.tick
            let _ = { probe.image = image; probe.loading = loading }()
            Color.clear
        }
    }
}

@main struct PhotoLoadingRegressionApp: App {
    var body: some Scene {
        WindowGroup { Color.clear.task { await runChecks() } }
    }

    @MainActor private func runChecks() async {
        var checks: [String] = []
        var failure: String?
        do {
            let store = AppStore()
            guard let disk = store.disk else { throw CheckFailure("No fixture disk") }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [FixtureURLProtocol.self]
            let session = URLSession(configuration: config)
            defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
            let pipeline = ImagePipeline(session: session, directory: directory)
            let prefix = UUID().uuidString
            let front = prefix + "-front.jpg", back = prefix + "-back.jpg"
            func fixture(_ color: UIColor) -> Data {
                UIGraphicsImageRenderer(size: CGSize(width: 240, height: 336)).image { context in
                    color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 336))
                }.pngData()!
            }
            let red = fixture(.red), blue = fixture(.blue)
            try disk.writePhoto(red, name: front); try disk.writePhoto(blue, name: back)
            let frontRequest = AppImageRequest(source: .file(try disk.photoURL(front), artwork: true), maxPixel: 300)
            let backRequest = AppImageRequest(source: .file(try disk.photoURL(back), artwork: true), maxPixel: 300)
            async let a = pipeline.image(for: frontRequest)
            async let b = pipeline.image(for: frontRequest)
            let (first, second) = await (a, b)
            try require(first != nil && first === second, "Local requests did not share a render")
            try require(max(first!.size.width, first!.size.height) <= 300, "Thumbnail exceeded its pixel budget")
            let original = AppImageRequest(source: .file(try disk.photoURL(front), artwork: false), maxPixel: 180)
            let raw = await pipeline.image(for: original)
            try require(raw != nil && max(raw!.size.width, raw!.size.height) <= 180 && original != frontRequest,
                        "Original/artwork or size cache keys collided")
            checks.append("Local artwork and originals share requests, respect pixel budgets and use distinct keys")

            // A real card-shaped rectangle on a table: remove the table, retain the paper border.
            let cutoutName = prefix + "-cutout.jpg"
            let cardFixture = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1400)).image { context in
                UIColor(white: 0.2, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 1400))
                UIColor.white.setFill(); context.fill(CGRect(x: 200, y: 280, width: 600, height: 840))
                UIColor.red.setFill(); context.fill(CGRect(x: 240, y: 330, width: 520, height: 700))
            }.pngData()!
            try disk.writePhoto(cardFixture, name: cutoutName)
            let cutoutURL = try disk.photoURL(cutoutName)
            let cutout = AppImageRequest(source: .cutout(cutoutURL), maxPixel: 300)
            let cutoutOriginal = AppImageRequest(source: .file(cutoutURL, artwork: false), maxPixel: 300)
            let cutoutArtwork = AppImageRequest(source: .file(cutoutURL, artwork: true), maxPixel: 300)
            try require(Set([cutout.diskKey, cutoutOriginal.diskKey, cutoutArtwork.diskKey]).count == 3,
                        "Cutout, original and artwork cache identities collided")
            async let cutoutA = pipeline.image(for: cutout)
            async let cutoutB = pipeline.image(for: cutout)
            let (cleanA, cleanB) = await (cutoutA, cutoutB)
            try require(cleanA != nil && cleanA === cleanB && max(cleanA!.size.width, cleanA!.size.height) <= 300,
                        "Cutout rendering was duplicated or exceeded the pixel budget")
            let border = try pixel(cleanA!, x: 0.03, y: 0.5)
            let center = try pixel(cleanA!, x: 0.5, y: 0.5)
            try require(border[0] > 220 && border[1] > 220 && border[2] > 220,
                        "Cutout retained the table or removed the physical card border")
            try require(center[0] > 220 && center[1] < 40 && center[2] < 40,
                        "Cutout altered the printed card artwork")
            let unchangedSource = try Data(contentsOf: cutoutURL)
            try require(unchangedSource == cardFixture, "Display crop modified the original photo")
            await pipeline.clearMemoryCache()
            try FileManager.default.removeItem(at: cutoutURL)
            let cutoutRestart = ImagePipeline(session: session, directory: directory)
            let restoredCutout = await cutoutRestart.image(for: cutout)
            try require(restoredCutout != nil && restoredCutout?.size == cleanA?.size,
                        "Cutout cache did not survive a loader restart")
            let fallback = await pipeline.image(for: AppImageRequest(source: .cutout(try disk.photoURL(front)), maxPixel: 120))
            try require(fallback != nil && max(fallback!.size.width, fallback!.size.height) <= 120,
                        "An undetectable card lost its original-photo fallback")
            checks.append("Cutouts remove the table, preserve paper borders/artwork, respect pixel budgets, deduplicate and persist without modifying originals")

            let probe = PhotoProbe(); probe.request = frontRequest
            let host = UIHostingController(rootView: ProbeView(probe: probe).environment(\.imagePipeline, pipeline))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
            let window = UIWindow(windowScene: scene); window.frame = scene.coordinateSpace.bounds
            func snapshot(_ name: String) {
                window.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let target = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(name + ".png")
                try? image.pngData()?.write(to: target)
            }
            window.rootViewController = host; window.makeKeyAndVisible()
            try await waitUntil { probe.image != nil && !probe.loading }
            let visible = probe.image
            await pipeline.clearMemoryCache()
            _ = await pipeline.image(for: backRequest)
            probe.tick += 1
            try await Task.sleep(for: .milliseconds(150))
            try require(probe.image === visible && !probe.loading, "Visible photo disappeared after cache eviction/redraw")
            checks.append("Visible image survives memory-cache eviction and unrelated render/redraw")
            probe.request = backRequest
            try await waitUntil { probe.image != nil && probe.image !== visible && !probe.loading }
            probe.request = AppImageRequest(source: .file(try disk.photoURL(prefix + "-missing.jpg"), artwork: false), maxPixel: 300)
            try await waitUntil { probe.image == nil && !probe.loading }
            checks.append("Changed/missing filenames never retain the previous side")

            await pipeline.clearMemoryCache()
            try FileManager.default.removeItem(at: disk.photoURL(front))
            let persisted = await pipeline.image(for: frontRequest)
            try require(persisted != nil && persisted?.size == first?.size, "Processed local photo failed to reload from disk")
            try disk.writePhoto(red, name: front)
            checks.append("Processed local artwork reloads from disk without the source")

            let officialURL = "https://fixtures.cardscout.test/official.png"
            FixtureURLProtocol.set(officialURL, Fixture(data: red, delay: 0.15))
            let official = AppImageRequest.remote(officialURL)!
            async let remoteA = pipeline.image(for: official)
            async let remoteB = pipeline.image(for: official)
            let (imageA, imageB) = await (remoteA, remoteB)
            try require(imageA != nil && imageA === imageB && FixtureURLProtocol.count(officialURL) == 1,
                        "Remote requests were not deduplicated")
            await pipeline.clearMemoryCache()
            let diskRemote = await pipeline.image(for: official)
            try require(diskRemote != nil && FixtureURLProtocol.count(officialURL) == 1, "Official reference was downloaded again after eviction")
            let freshPipeline = ImagePipeline(session: session, directory: directory)
            let afterRestart = await freshPipeline.image(for: official)
            try require(afterRestart != nil && FixtureURLProtocol.count(officialURL) == 1, "Official disk cache did not survive a fresh pipeline")
            checks.append("Remote references share downloads and persist across cache eviction and fresh loader instances")

            let legacyURL = "https://fixtures.cardscout.test/legacy-" + prefix + ".png"
            let legacyKey = SHA256.hash(data: Data(legacyURL.utf8)).map { String(format: "%02x", $0) }.joined()
            let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let oldFile = cacheRoot.appendingPathComponent("reference-" + legacyKey)
            try red.write(to: oldFile)
            let migrationPipeline = ImagePipeline(session: session)
            let migrated = await migrationPipeline.image(for: AppImageRequest.remote(legacyURL)!)
            try require(migrated != nil && FixtureURLProtocol.count(legacyURL) == 0 && !FileManager.default.fileExists(atPath: oldFile.path),
                        "Legacy offline reference was discarded instead of migrated")
            let budgetFolder = directory.appendingPathComponent("tiny-budget")
            let boundedPipeline = ImagePipeline(session: session, directory: budgetFolder, diskLimit: 1)
            _ = await boundedPipeline.image(for: official)
            let budgetFiles = (try? FileManager.default.contentsOfDirectory(atPath: budgetFolder.path)) ?? []
            try require(budgetFiles.isEmpty, "Disk cache ignored its size limit")
            checks.append("Legacy reference images migrate without network access; the disk cache enforces its size limit")

            let listingURL = "https://i.ebayimg.com/images/fixture.png"
            FixtureURLProtocol.set(listingURL, Fixture(data: blue))
            let listing = AppImageRequest.remote(listingURL)!
            _ = await pipeline.image(for: listing)
            _ = await pipeline.image(for: listing)
            try require(FixtureURLProtocol.count(listingURL) == 1, "Market photo was not cached in memory")
            await pipeline.clearMemoryCache()
            _ = await pipeline.image(for: listing)
            try require(FixtureURLProtocol.count(listingURL) == 2 && !FileManager.default.fileExists(atPath: directory.appendingPathComponent(listing.diskKey + ".png").path),
                        "Market listing image persisted to disk")
            checks.append("Market listing images share memory caching and never persist to disk")

            let failURL = "https://fixtures.cardscout.test/retry.png"
            let failed = AppImageRequest.remote(failURL)!
            FixtureURLProtocol.set(failURL, Fixture(data: red, status: 503))
            let missing = await pipeline.image(for: failed)
            FixtureURLProtocol.set(failURL, Fixture(data: red))
            let throttled = await pipeline.image(for: failed)
            try require(missing == nil && throttled == nil && FixtureURLProtocol.count(failURL) == 1,
                        "Failed requests retried on redraw")
            let recovered = await pipeline.image(for: failed, retry: true)
            try require(recovered != nil && FixtureURLProtocol.count(failURL) == 2, "Explicit retry did not recover")
            let corruptURL = "https://fixtures.cardscout.test/not-an-image.png"
            FixtureURLProtocol.set(corruptURL, Fixture(data: Data("not an image".utf8)))
            let corrupt = await pipeline.image(for: AppImageRequest.remote(corruptURL)!)
            try require(corrupt == nil && AppImageRequest.remote("http://invalid.test/x") == nil && AppImageRequest.remote("") == nil,
                        "Corrupt/invalid sources were accepted")
            checks.append("Failures do not loop; explicit retry recovers; corrupt images and invalid URLs fail cleanly")

            let slowURL = "https://fixtures.cardscout.test/slow.png", fastURL = "https://fixtures.cardscout.test/fast.png"
            FixtureURLProtocol.set(slowURL, Fixture(data: red, delay: 0.6))
            FixtureURLProtocol.set(fastURL, Fixture(data: blue))
            probe.request = .remote(slowURL)
            try await waitUntil { FixtureURLProtocol.count(slowURL) == 1 }
            probe.request = .remote(fastURL)
            try await waitUntil { probe.image != nil && !probe.loading }
            let fastImage = probe.image
            try await Task.sleep(for: .milliseconds(800))
            try require(probe.image === fastImage && !probe.loading, "Late/cancelled result replaced the current image")
            let sharedURL = "https://fixtures.cardscout.test/shared-cancel.png"
            FixtureURLProtocol.set(sharedURL, Fixture(data: red, delay: 0.2))
            let shared = AppImageRequest.remote(sharedURL)!
            let cancelled = Task { await pipeline.image(for: shared) }
            let survivor = Task { await pipeline.image(for: shared) }
            cancelled.cancel()
            let survivorImage = await survivor.value
            try require(survivorImage != nil && FixtureURLProtocol.count(sharedURL) == 1, "One cancelled view cancelled another view's download")
            checks.append("Late results cannot replace a new source; cancelling one waiter preserves shared downloads")

            probe.request = .preview(red, revision: UUID(), maxPixel: 200)
            try await waitUntil { probe.image != nil && !probe.loading }
            let previewImage = probe.image
            probe.request = .preview(blue, revision: UUID(), maxPixel: 200)
            try await waitUntil { probe.image != nil && probe.image !== previewImage && !probe.loading }
            checks.append("New capture/retake revisions replace preview images without reusing stale pixels")

            // The real reference and card-tile wrappers must share the exact same remote request.
            let wrappersURL = "https://fixtures.cardscout.test/wrappers.png"
            FixtureURLProtocol.set(wrappersURL, Fixture(data: blue))
            let wrappers = UIHostingController(rootView: VStack {
                ReferenceImageView(url: wrappersURL).frame(width: 100, height: 140)
                CachedPhoto(url: wrappersURL).frame(width: 100, height: 140)
                OwnedPhoto(name: front, maxPixel: 300).frame(width: 100, height: 140)
            }.environment(store).environment(\.imagePipeline, pipeline))
            window.rootViewController = wrappers; window.makeKeyAndVisible()
            try await waitUntil { FixtureURLProtocol.count(wrappersURL) == 1 }
            try await Task.sleep(for: .milliseconds(200))
            await pipeline.clearMemoryCache()
            store.selectedTab = 1
            try await Task.sleep(for: .milliseconds(150))
            try require(FixtureURLProtocol.count(wrappersURL) == 1, "Reference and tile wrappers did not share stable loading")
            snapshot("centralized-image-wrappers")
            checks.append("Reference, Chase/Lookout tile and owned-photo wrappers share the centralized lifecycle")

            store.library = try disk.addCaptures([CapturePhoto(front: red, back: blue)], sessionID: prefix, to: store.library)
            let card = store.library.cards.first!
            let viewer = UIHostingController(rootView: CardPhotoViewer(cardID: card.id).environment(store).environment(\.imagePipeline, pipeline))
            window.rootViewController = viewer; window.makeKeyAndVisible()
            viewer.view.frame = window.bounds; viewer.view.layoutIfNeeded()
            func photoScroll(_ view: UIView) -> UIScrollView? {
                if let scroll = view as? UIScrollView, scroll.maximumZoomScale == 5 { return scroll }
                return view.subviews.lazy.compactMap { photoScroll($0) }.first
            }
            try await waitUntil { photoScroll(viewer.view) != nil }
            let scroll = photoScroll(viewer.view)!
            scroll.setZoomScale(2, animated: false)
            await pipeline.clearMemoryCache()
            _ = await pipeline.image(for: backRequest)
            if let index = store.library.cards.firstIndex(where: { $0.id == card.id }) { store.library.cards[index].notes = "Force detail refresh" }
            try await Task.sleep(for: .milliseconds(200))
            try require(photoScroll(viewer.view) === scroll && abs(scroll.zoomScale - 2) < 0.01,
                        "Full-screen image/zoom reset after eviction/update")
            checks.append("Full-screen image and zoom survive eviction and library updates")
            snapshot("centralized-fullscreen-image")
            window.isHidden = true
        } catch { failure = String(describing: error) }
        let result: [String: Any] = ["passed": failure == nil, "checks": checks, "failure": failure ?? ""]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("photo-regression.json")
        try! data.write(to: file)
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(message) }
}

@MainActor private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<150 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw CheckFailure("Timed out waiting for photo/view")
}

private func pixel(_ image: UIImage, x: CGFloat, y: CGFloat) throws -> [UInt8] {
    guard let cgImage = image.cgImage else { throw CheckFailure("No pixels for cutout check") }
    var bytes = [UInt8](repeating: 0, count: 4)
    let success = bytes.withUnsafeMutableBytes { data -> Bool in
        guard let context = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
        context.interpolationQuality = .none
        context.translateBy(x: -CGFloat(cgImage.width) * x, y: -CGFloat(cgImage.height) * y)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return true
    }
    guard success else { throw CheckFailure("No pixel context for cutout check") }
    return bytes
}
