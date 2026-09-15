import Foundation

struct UPCResponse: Decodable { let items: [UPCItem]? }
struct UPCItem: Decodable {
    let title: String
    let ean: String?
    let upc: String?
    let brand: String?
    let size: String?
    let images: [String]?
    let offers: [UPCOffer]?
}
struct UPCOffer: Decodable {
    let merchant: String
    let title: String?
    let price: Decimal
    let currency: String?
    let link: String?
    let updated_t: Double?
    let availability: String?
}
struct CatalogLookup: Sendable {
    let product: Product?
    let offers: [OnlineOffer]
    var priceHistory: [OnlineOffer] = []
    var notices: [String] = []
}
protocol OfferProvider: Sendable { func lookup(_ barcode: Barcode) async throws -> CatalogLookup }

struct UPCItemDBProvider: OfferProvider {
    let client: any HTTPClient
    func lookup(_ barcode: Barcode) async throws -> CatalogLookup {
        let request = try makeRequest("https://api.upcitemdb.com/prod/trial/lookup", query: [.init(name: "upc", value: barcode.value)])
        return try Self.decode(await client.data(for: request), barcode: barcode)
    }
    static func decode(_ data: Data, barcode: Barcode) throws -> CatalogLookup {
        let response = try JSONDecoder().decode(UPCResponse.self, from: data)
        guard let item = response.items?.first else { return CatalogLookup(product: nil, offers: []) }
        if let code = item.ean?.nonEmpty ?? item.upc?.nonEmpty,
           (try? Barcode(code).identity) != barcode.identity { return CatalogLookup(product: nil, offers: []) }
        let product = item.title.nonEmpty.map { Product(barcode: barcode, name: $0, brand: item.brand?.nonEmpty,
            quantity: item.size?.nonEmpty, imageURL: item.images?.compactMap(\.secureURL).first, source: "UPCitemdb") }
        let offers = (item.offers ?? []).enumerated().compactMap { index, offer -> OnlineOffer? in
            guard offer.price > 0, let url = offer.link?.secureURL, let merchant = offer.merchant.nonEmpty else { return nil }
            // UPCitemdb documents an empty currency as USD. This default is provider-specific.
            let currency = offer.currency?.nonEmpty?.uppercased() ?? "USD"
            return OnlineOffer(id: "upc:\(barcode.identity):\(merchant):\(index)", barcode: barcode,
                merchant: merchant, title: offer.title?.nonEmpty ?? item.title, money: Money(amount: offer.price, currency: currency),
                url: url, updatedAt: offer.updated_t.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }, availability: offer.availability)
        }
        return CatalogLookup(product: product, offers: offers)
    }
}
