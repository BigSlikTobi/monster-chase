import Foundation

public struct CardReferenceImage: Codable, Hashable, Identifiable, Sendable {
    public var collectionID: String
    public var year: Int
    public var brand: String
    public var product: String
    public var subset: String
    public var parallel: String?
    public var number: String
    public var player: String
    public var frontURL: String
    public var backURL: String?
    public var sourceURL: String
    public var sourceTitle: String
    public var reviewedAt: String
    public var sha256: String
    public var id: String { collectionID + "|" + number + "|" + sha256 }

    public func matches(_ collection: CardCollection, entry: ChecklistCard) -> Bool {
        collectionID == collection.id && year == collection.year && brand == collection.brand && product == collection.name &&
        subset == collection.subset && parallel == collection.parallel && number == entry.number && player == entry.player &&
        !reviewedAt.isEmpty && sha256.count == 64 && sha256.allSatisfy(\.isHexDigit) &&
        Self.allowed(frontURL, image: true) && (backURL == nil || Self.allowed(backURL!, image: true)) && Self.allowed(sourceURL, image: false)
    }

    private static func allowed(_ value: String, image: Bool) -> Bool {
        guard let url = URLComponents(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.fragment == nil, let host = url.host else { return false }
        if image {
            return ["i.ebayimg.com", "images.production.sportscardinvestor.com"].contains(host) ||
                (host == "storage.googleapis.com" && url.path.hasPrefix("/images.pricecharting.com/")) ||
                (host == "cdn.shopify.com" && ["/s/files/1/0791/7515/6005/", "/s/files/1/0649/1019/6902/"].contains(where: url.path.hasPrefix)) ||
                (["www.freshdcards.com", "shopwaynecollection.com"].contains(host) && url.path.hasPrefix("/cdn/shop/files/"))
        }
        return ["www.ebay.com", "www.ebay.co.uk", "www.ebay.com.au", "www.sportscardspro.com", "www.sportscardinvestor.com", "www.freshdcards.com", "shopwaynecollection.com"].contains(host)
    }
}

extension ChecklistCard {
    public func exactReference(in collection: CardCollection) -> CardReferenceImage? {
        referenceImage.flatMap { $0.matches(collection, entry: self) ? $0 : nil }
    }
}

extension CardCollection {
    public var validReferenceExample: CardReferenceImage? {
        guard let referenceExample, let entry = cards.first(where: { $0.number == referenceExample.number }),
              referenceExample.matches(self, entry: entry) else { return nil }
        return referenceExample
    }
}
