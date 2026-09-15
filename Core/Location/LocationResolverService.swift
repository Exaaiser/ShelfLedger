import Foundation

struct ZIPResponse: Decodable {
    let places: [ZIPPlace]
}
struct ZIPPlace: Decodable {
    let name: String
    let latitude: String
    let longitude: String
    let state: String
    enum CodingKeys: String, CodingKey { case name = "place name", latitude, longitude; case state = "state abbreviation" }
}

struct LocationResolverService: Sendable {
    let client: any HTTPClient
    func resolve(zipCode: String) async throws -> LocationContext {
        let code = zipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 5, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw ValidationError.invalidZIP }
        let data = try await client.data(for: makeRequest("https://api.zippopotam.us/us/\(code)"))
        let response = try JSONDecoder().decode(ZIPResponse.self, from: data)
        guard let place = response.places.first, let lat = Double(place.latitude), let lon = Double(place.longitude) else { throw NetworkError.invalidResponse }
        let coordinate = GeoPoint(latitude: lat, longitude: lon)
        guard coordinate.isValid else { throw NetworkError.invalidResponse }
        return LocationContext(coordinate: coordinate, label: "\(place.name), \(place.state) \(code)", postalCode: code, updatedAt: Date(), city: place.name, countryCode: "US")
    }
}
