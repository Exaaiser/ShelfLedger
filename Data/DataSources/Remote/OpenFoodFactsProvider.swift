import Foundation

struct OFFResponse: Decodable {
    let product: OFFProduct?
}
struct OFFProduct: Decodable {
    let code: String?
    let product_name: String?
    let product_name_en: String?
    let brands: String?
    let quantity: String?
    let image_front_url: String?
    let image_url: String?
    func domain(barcode: Barcode) -> Product? {
        if let code, (try? Barcode(code).identity) != barcode.identity { return nil }
        guard let name = product_name_en?.nonEmpty ?? product_name?.nonEmpty else { return nil }
        return Product(barcode: barcode, name: name, brand: brands?.nonEmpty, quantity: quantity?.nonEmpty,
            imageURL: image_front_url?.secureURL ?? image_url?.secureURL, source: "Open Food Facts")
    }
}
struct OFFSearchResponse: Decodable { let products: [OFFProduct]? }

protocol CatalogProvider: Sendable {
    func lookup(_ barcode: Barcode) async throws -> Product?
    func search(_ query: String) async throws -> [Product]
}

actor OpenFoodFactsProvider: CatalogProvider {
    private let client: any HTTPClient
    private var lastSearch: Date = .distantPast
    private var lastLookup: Date = .distantPast
    init(client: any HTTPClient) { self.client = client }
    func lookup(_ barcode: Barcode) async throws -> Product? {
        // Reserve slots before awaiting; concurrent requests cannot bypass the rate limit.
        let slot = max(Date(), lastLookup.addingTimeInterval(4.1))
        lastLookup = slot
        if slot > Date() { try await Task.sleep(for: .seconds(slot.timeIntervalSinceNow)) }
        let request = try makeRequest("https://world.openfoodfacts.org/api/v3.6/product/\(barcode.catalogCode)", query: [
            URLQueryItem(name: "fields", value: "code,product_name,product_name_en,brands,quantity,image_front_url,image_url")])
        do {
            let data = try await client.data(for: request)
            // API 3.6 uses a string status; identity comes from the product object.
            let response = try JSONDecoder().decode(OFFResponse.self, from: data)
            return response.product?.domain(barcode: barcode)
        } catch NetworkError.status(404) { return nil }
    }
    func search(_ query: String) async throws -> [Product] {
        guard Date().timeIntervalSince(lastSearch) >= 6.1 else { throw NetworkError.rateLimited }
        lastSearch = Date()
        // Network text search is explicitly submitted, never fired for every keystroke.
        let request = try makeRequest("https://world.openfoodfacts.org/cgi/search.pl", query: [
            .init(name: "search_terms", value: query), .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"), .init(name: "json", value: "1"),
            .init(name: "page_size", value: "20"), .init(name: "lc", value: "en"),
            .init(name: "tagtype_0", value: "countries"), .init(name: "tag_contains_0", value: "contains"),
            .init(name: "tag_0", value: "united-states"),
            .init(name: "fields", value: "code,product_name,product_name_en,brands,quantity,image_front_url,image_url")])
        let response = try JSONDecoder().decode(OFFSearchResponse.self, from: await client.data(for: request))
        var seen = Set<String>()
        return (response.products ?? []).compactMap { dto in
            guard let code = dto.code, let barcode = try? Barcode(code), seen.insert(barcode.identity).inserted else { return nil }
            return dto.domain(barcode: barcode)
        }
    }
}
