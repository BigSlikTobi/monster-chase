import Foundation
import Security
import CryptoKit
import CardScoutCore
import ImageIO
import UniformTypeIdentifiers

final class PinnedSession: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let pairing: Pairing
    private let statusLock = NSLock()
    private var trustStage = "notChallenged"
    private var trustCode: Int?
    var diagnostic: (stage: String, code: Int?) {
        statusLock.lock(); defer { statusLock.unlock() }
        return (trustStage, trustCode)
    }
    private func record(_ stage: String, code: Int? = nil) {
        statusLock.lock(); defer { statusLock.unlock() }
        trustStage = stage; trustCode = code
    }
    init(_ pairing: Pairing) { self.pairing = pairing }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        record("challenged")
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == URL(string: pairing.baseURL)?.host?.lowercased(),
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = certificate.first else {
            record("hostOrCertificateMissing"); completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let hash = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        guard hash == pairing.certificateSHA256 else { record("pinMismatch"); completionHandler(.cancelAuthenticationChallenge, nil); return }
        // Trust only this explicitly paired leaf. Never fall back to accepting another certificate.
        SecTrustSetAnchorCertificates(trust, [leaf] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            record("trustRejected", code: error.map { CFErrorGetCode($0) })
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        record("accepted")
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct MacJob: Decodable, Sendable { var id: String; var status: String; var analysis: CardAnalysis?; var collection: CardCollection?; var error: String?; var priceStatus: String?; var matches: [CardMatch]?; var matchNotice: String? }
struct Bootstrap: Decodable {
    struct Card: Decodable { var record: OwnedCard; var front: String; var back: String? }
    var cards: [Card]; var collections: [CardCollection]; var hunts: [HuntCard]; var hotCards: [HotCard]; var hotCheckedAt: String?
}

final class MacClient: @unchecked Sendable {
    let pairing: Pairing
    private let session: URLSession
    private let verifier: PinnedSession
    var trustDiagnostic: (stage: String, code: Int?) { verifier.diagnostic }
    init(_ pairing: Pairing) {
        self.pairing = pairing
        verifier = PinnedSession(pairing)
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 90
        config.httpShouldSetCookies = false; config.urlCache = nil
        session = URLSession(configuration: config, delegate: verifier, delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let url = URL(string: pairing.baseURL + path), url.scheme == "https",
              url.host == URL(string: pairing.baseURL)?.host, url.user == nil, url.password == nil
        else { throw StoreError.invalidPairing }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + pairing.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"] ?? "Analyse-Dienst antwortet mit Fehler \(http.statusCode)."
            throw NSError(domain: "CardScout", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func submit(_ card: OwnedCard, disk: DiskStore, fastSupported: Bool = false, matchSupported: Bool = false) async throws -> MacJob {
        // File I/O, image decoding and base64 encoding stay off the UI thread.
        let data = try await Task.detached(priority: .utility) {
            func transport(_ file: String) throws -> Data {
                let original = try Data(contentsOf: disk.photoURL(file))
                // Use the same deterministic derivative on every upload and refresh.
                // Originals stay on the phone; the Mac's digest remains stable.
                guard card.fastPipeline == true,
                      let source = CGImageSourceCreateWithData(original as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1800
                      ] as CFDictionary) else { return original }
                let encoded = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else { return original }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
                return CGImageDestinationFinalize(destination) ? encoded as Data : original
            }
            var body: [String: Any] = ["id": card.jobID, "front": try transport(card.frontFile).base64EncodedString()]
            if let previous = card.refreshOfJobID { body["refreshOf"] = previous }
            if let file = card.backFile { body["back"] = try transport(file).base64EncodedString() }
            if fastSupported && card.fastPipeline != false { body["pipeline"] = "fast" }
            if matchSupported && card.isScanDraft == true { body["pipeline"] = "match" }
            if let text = card.captureText { body["captureText"] = text }
            if card.manualAssignment == true, let collectionID = card.analysis?.collectionID, let number = card.analysis?.cardNumber {
                body["assignment"] = ["collectionID": collectionID, "number": number]
            }
            return try JSONSerialization.data(withJSONObject: body)
        }.value
        return try await request("/v1/jobs", method: "POST", body: data)
    }
}

enum PairingKeychain {
    static let service = "com.tobiaslatta.cardscout.mac"
    static func load() -> Pairing? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pairing", kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }
    static func save(_ pairing: Pairing) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pairing"]
        let data = try JSONEncoder().encode(pairing)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw URLError(.userAuthenticationRequired) }
        } else if update != errSecSuccess { throw URLError(.userAuthenticationRequired) }
    }
}
