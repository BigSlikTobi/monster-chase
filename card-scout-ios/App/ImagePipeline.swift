import SwiftUI
import UIKit
import CryptoKit

/// Identity includes the source, display treatment and pixel budget. Preview data uses
/// a revision supplied by its owner, so SwiftUI never hashes megabytes in a view body.
struct AppImageRequest: Hashable {
    enum Source: Hashable {
        case file(URL, artwork: Bool)
        case cutout(URL)
        case remote(URL)
        case preview(UUID, Data)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.file(a, x), .file(b, y)): return a == b && x == y
            case let (.cutout(a), .cutout(b)): return a == b
            case let (.remote(a), .remote(b)): return a == b
            case let (.preview(a, _), .preview(b, _)): return a == b
            default: return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case let .file(url, artwork): hasher.combine(0); hasher.combine(url); hasher.combine(artwork)
            case let .cutout(url): hasher.combine(3); hasher.combine(url)
            case let .remote(url): hasher.combine(1); hasher.combine(url)
            case let .preview(id, _): hasher.combine(2); hasher.combine(id)
            }
        }
    }

    let source: Source
    let maxPixel: Int

    init(source: Source, maxPixel: Int) {
        self.source = source
        self.maxPixel = min(3200, max(1, maxPixel))
    }

    static func remote(_ value: String?, maxPixel: Int = 1600) -> Self? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return Self(source: .remote(url), maxPixel: maxPixel)
    }

    static func preview(_ data: Data?, revision: UUID, maxPixel: Int = 1600) -> Self? {
        data.map { Self(source: .preview(revision, $0), maxPixel: maxPixel) }
    }

    var persists: Bool {
        switch source {
        case .file, .cutout: return true
        case let .remote(url): return !Self.isListingImage(url)
        case .preview: return false
        }
    }

    static func isListingImage(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "ebayimg.com" || host.hasSuffix(".ebayimg.com")
    }

    var diskKey: String {
        let identity: String
        switch source {
        case let .file(url, artwork): identity = "file:\(url.path):\(artwork)"
        case let .cutout(url): identity = "cutout-v1:\(url.path)"
        case let .remote(url): identity = "remote:\(url.absoluteString)"
        case let .preview(id, _): identity = "preview:\(id)"
        }
        return SHA256.hash(data: Data("image-v2:\(identity):\(maxPixel)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

/// The only display-image loader. Shared work survives an individual view's
/// cancellation; each view decides whether a completed result still belongs to it.
actor ImagePipeline {
    static let shared = ImagePipeline()
    private let memory = NSCache<NSString, UIImage>()
    private var tasks: [AppImageRequest: Task<UIImage?, Never>] = [:]
    private var failures: [String: Date] = [:]
    private let session: URLSession
    private let directory: URL?
    private let legacyDirectory: URL?
    private let diskLimit: Int

    init(session: URLSession? = nil, directory: URL? = nil, diskLimit: Int = 256 * 1024 * 1024) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 4
        self.session = session ?? URLSession(configuration: configuration)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        self.directory = directory ?? caches?
            .appendingPathComponent("DisplayImages", isDirectory: true)
        self.legacyDirectory = directory == nil ? caches : nil
        self.diskLimit = diskLimit
        memory.totalCostLimit = 48 * 1024 * 1024
        memory.countLimit = 128
    }

    func image(for request: AppImageRequest, retry: Bool = false) async -> UIImage? {
        let key = request.diskKey as NSString
        if let image = memory.object(forKey: key) { return image }
        if let task = tasks[request] { return await task.value }
        if !retry, let failed = failures[request.diskKey], Date().timeIntervalSince(failed) < 30 { return nil }
        let task = Task { await self.load(request) }
        tasks[request] = task
        let image = await task.value
        tasks[request] = nil
        if let image {
            failures[request.diskKey] = nil
            memory.setObject(image, forKey: key,
                cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        } else {
            failures = failures.filter { Date().timeIntervalSince($0.value) < 30 }
            if failures.count >= 128 { failures.removeAll() }
            failures[request.diskKey] = Date()
        }
        return image
    }

    /// Dropping shared cache entries must never blank an image retained by a view.
    func clearMemoryCache() { memory.removeAllObjects() }

    func prefetch(_ values: [String]) async {
        let requests = Array(Set(values.compactMap { AppImageRequest.remote($0) }))
        // Bound both task count and downloads when a catalog grows.
        for start in stride(from: 0, to: requests.count, by: 4) {
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                for request in requests[start..<min(start + 4, requests.count)] {
                    group.addTask { _ = await self.image(for: request) }
                }
            }
        }
    }

    private func load(_ request: AppImageRequest) async -> UIImage? {
        let file = directory?.appendingPathComponent(request.diskKey + ".png")
        if request.persists, let file, FileManager.default.fileExists(atPath: file.path),
           let image = await CardImageDecoder.shared.image(url: file, maxPixel: request.maxPixel) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return image
        }
        let image: UIImage?
        var persists = request.persists
        let legacy = legacyFile(for: request)
        if let legacy, FileManager.default.fileExists(atPath: legacy.path),
           let cached = await CardImageDecoder.shared.image(url: legacy, maxPixel: request.maxPixel) {
            image = cached
        } else {
            switch request.source {
            case let .file(url, artwork):
                if artwork { image = await CardImageDecoder.shared.artwork(url: url, maxPixel: request.maxPixel) }
                else { image = await CardImageDecoder.shared.image(url: url, maxPixel: request.maxPixel) }
            case let .cutout(url):
                image = await CardImageDecoder.shared.cutout(url: url, maxPixel: request.maxPixel)
            case let .preview(_, data):
                image = await CardImageDecoder.shared.image(data: data, maxPixel: request.maxPixel)
            case let .remote(url):
                guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
                      let (data, response) = try? await session.data(from: url),
                      let http = response as? HTTPURLResponse, http.statusCode == 200,
                      !data.isEmpty, data.count < 15_000_000 else { return nil }
                if let final = response.url, AppImageRequest.isListingImage(final) { persists = false }
                image = await CardImageDecoder.shared.image(data: data, maxPixel: request.maxPixel)
            }
        }
        if let image, persists, let directory, let file, let data = image.pngData() {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                if let legacy { try? FileManager.default.removeItem(at: legacy) }
                trimDiskCache(directory)
            } catch { /* A cache write failure must not hide a successfully loaded image. */ }
        }
        return image
    }

    /// Preserve offline references saved by earlier builds, then retire the old entry.
    private func legacyFile(for request: AppImageRequest) -> URL? {
        guard request.persists, let legacyDirectory else { return nil }
        let value: String
        let folder: URL
        let suffix: String
        switch request.source {
        case let .remote(url):
            value = url.absoluteString; folder = legacyDirectory; suffix = ""
        case let .file(url, artwork) where artwork:
            value = "artwork-v1:\(url.path):\(request.maxPixel)"
            folder = legacyDirectory.appendingPathComponent("CardArtwork"); suffix = ".jpg"
        default: return nil
        }
        let key = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        let prefix = suffix.isEmpty ? "reference-" : ""
        return folder.appendingPathComponent(prefix + key + suffix)
    }

    private func trimDiskCache(_ directory: URL) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        let entries = files.compactMap { file -> (URL, Int, Date)? in
            guard let info = try? file.resourceValues(forKeys: keys) else { return nil }
            return (file, info.fileSize ?? 0, info.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var bytes = entries.reduce(0) { $0 + $1.1 }
        for (file, size, _) in entries where bytes > diskLimit {
            if (try? FileManager.default.removeItem(at: file)) != nil { bytes -= size }
        }
    }
}

private struct ImagePipelineKey: EnvironmentKey {
    static let defaultValue = ImagePipeline.shared
}

extension EnvironmentValues {
    var imagePipeline: ImagePipeline {
        get { self[ImagePipelineKey.self] }
        set { self[ImagePipelineKey.self] = newValue }
    }
}

/// Shared image lifetime, source-change protection, and explicit retry for every screen.
struct StableImage<Content: View>: View {
    @Environment(\.imagePipeline) private var pipeline
    let request: AppImageRequest?
    @ViewBuilder var content: (UIImage?, Bool) -> Content
    @State private var image: UIImage?
    @State private var loadedRequest: AppImageRequest?
    @State private var loading = true
    @State private var attempt = 0
    @State private var runID: UUID?
    private struct WorkID: Hashable { let request: AppImageRequest?; let attempt: Int }

    var body: some View {
        let current = loadedRequest == request
        let visible = current ? image : nil
        let pending = request != nil && (!current || loading)
        content(visible, pending)
            .overlay(alignment: .bottomTrailing) {
                if request != nil && !pending && visible == nil {
                    Button { attempt += 1 } label: {
                        Image(systemName: "arrow.clockwise").font(.caption.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(Color.scoutSurface.opacity(0.9), in: Circle())
                    }.buttonStyle(.plain).foregroundStyle(Color.scoutMuted)
                        .accessibilityLabel(tr("Bild erneut laden"))
                }
            }
            .task(id: WorkID(request: request, attempt: attempt)) {
                let run = UUID(); runID = run
                guard let request else { image = nil; loadedRequest = nil; loading = false; return }
                guard loadedRequest != request || image == nil else { return }
                loading = true
                let result = await pipeline.image(for: request, retry: attempt > 0)
                guard !Task.isCancelled, runID == run else { return }
                image = result; loadedRequest = request; loading = false
            }
            .onDisappear {
                // Lazy containers preserve State offscreen. Do not pin every visited raster.
                runID = nil; image = nil; loadedRequest = nil; loading = true
            }
    }
}

struct LocalCardPhoto<Content: View>: View {
    @Environment(AppStore.self) private var store
    let name: String?
    var maxPixel = 600
    var original = false
    var cutout = false
    @ViewBuilder var content: (UIImage?, Bool) -> Content
    var body: some View {
        StableImage(request: store.photoURL(name).map {
            AppImageRequest(source: cutout ? .cutout($0) : .file($0, artwork: !original), maxPixel: maxPixel)
        }, content: content)
    }
}

struct OwnedPhoto: View {
    let name: String?
    var maxPixel = 600
    var original = false
    var number = ""
    var body: some View {
        LocalCardPhoto(name: name, maxPixel: maxPixel, original: original) { image, loading in
            PhotoCard(image: image, number: number, owned: true)
                .overlay { if image == nil && loading { ProgressView().tint(.scoutMuted) } }
        }
    }
}

struct CachedPhoto: View {
    let url: String
    var owned = true
    var number = ""
    var body: some View {
        StableImage(request: .remote(url)) { image, loading in
            PhotoCard(image: image, number: number, owned: owned)
                .overlay(alignment: .bottomTrailing) {
                    if image == nil {
                        Image(systemName: loading ? "ellipsis" : "photo.badge.exclamationmark")
                            .font(.caption2).foregroundStyle(Color.scoutMuted.opacity(0.65)).padding(10)
                    }
                }
                .accessibilityLabel(trDisplay(image != nil ? "Kartenfoto" : loading ? "Kartenfoto wird geladen" : "Kartenfoto nicht verfügbar"))
        }
    }
}
