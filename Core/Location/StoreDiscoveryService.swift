import Foundation

struct OverpassResponse: Decodable { let elements: [OverpassElement] }
struct OverpassElement: Decodable {
    let id: Int64
    let type: String
    let lat: Double?
    let lon: Double?
    let center: OverpassCenter?
    let tags: [String: String]?
}
struct OverpassCenter: Decodable { let lat: Double; let lon: Double }

struct StoreDiscoveryService: Sendable {
    let client: any HTTPClient
    func discover(near coordinate: GeoPoint) async throws -> [Store] {
        guard coordinate.isValid else { throw ValidationError.invalidStore }
        let query = "[out:json][timeout:15];nwr[\"shop\"~\"^(supermarket|convenience|grocery)$\"](around:25000,\(coordinate.latitude),\(coordinate.longitude));out center tags;"
        var request = try makeRequest("https://overpass-api.de/api/interpreter")
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [.init(name: "data", value: query)]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let response = try JSONDecoder().decode(OverpassResponse.self, from: await client.data(for: request))
        return Self.map(response.elements, near: coordinate)
    }
    static func map(_ elements: [OverpassElement], near coordinate: GeoPoint) -> [Store] {
        var seen = Set<String>()
        return elements.compactMap { element -> Store? in
            guard let tags = element.tags, let name = tags["name"]?.nonEmpty,
                  let lat = element.lat ?? element.center?.lat, let lon = element.lon ?? element.center?.lon else { return nil }
            let point = GeoPoint(latitude: lat, longitude: lon)
            let id = "osm:\(element.type.lowercased()):\(element.id)"
            guard point.isValid, coordinate.distance(to: point) <= 25_000, seen.insert(id).inserted else { return nil }
            let address = [tags["addr:housenumber"], tags["addr:street"], tags["addr:city"]].compactMap { $0?.nonEmpty }.joined(separator: " ")
            return Store(id: id, name: name, coordinate: point, postalCode: tags["addr:postcode"]?.nonEmpty, address: address.nonEmpty)
        }.sorted {
            let lhs = coordinate.distance(to: $0.coordinate), rhs = coordinate.distance(to: $1.coordinate)
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    }
}

struct StoreRepository: StoreRepositoryProtocol {
    let resolver: LocationResolverService
    let discovery: StoreDiscoveryService
    func resolve(zipCode: String) async throws -> LocationContext { try await resolver.resolve(zipCode: zipCode) }
    func stores(near location: GeoPoint) async throws -> [Store] { try await discovery.discover(near: location) }
}
