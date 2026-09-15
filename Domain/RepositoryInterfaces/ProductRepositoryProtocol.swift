import Foundation

@MainActor
protocol ProductRepositoryProtocol {
    func lookup(_ barcode: Barcode, near location: LocationContext?, refresh: Bool) async throws -> ProductSnapshot
    func search(_ query: String) async throws -> [Product]
    func lastObservation(for product: Product, near location: LocationContext?) throws -> PriceObservation?
    func recentProducts() throws -> [Product]
    func save(_ observation: PriceObservation, product: Product) throws
}

protocol StoreRepositoryProtocol: Sendable {
    func resolve(zipCode: String) async throws -> LocationContext
    func stores(near location: GeoPoint) async throws -> [Store]
}
