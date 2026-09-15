import Foundation

struct CatalogResult: Sendable {
    let product: Product?
    let offers: [OnlineOffer]
    let notices: [String]
    let offersFailed: Bool
    var priceHistory: [OnlineOffer] = []
}

struct ProductCatalogService: Sendable {
    let catalog: any CatalogProvider
    let offers: any OfferProvider
    func lookup(_ barcode: Barcode) async throws -> CatalogResult {
        async let identity = fetchResult("Product lookup") { try await catalog.lookup(barcode) }
        async let listings = fetchResult("Online offers") { try await offers.lookup(barcode) }
        let (first, second) = try await (identity, listings)
        return CatalogResult(product: first.value.flatMap { $0 } ?? second.value?.product,
            offers: second.value?.offers ?? [], notices: [first.failure, second.failure].compactMap { $0 } + (second.value?.notices ?? []), offersFailed: second.failure != nil,
            priceHistory: second.value?.priceHistory ?? [])
    }
}
