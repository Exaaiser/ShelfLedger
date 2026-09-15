import Foundation

struct OpenPricesResponse: Decodable {
    let items: [OpenPricesItem]
    let page: Int
    let pages: Int
    let total: Int
}
struct OpenPricesItem: Decodable {
    let id: Int
    let product_code: String?
    let price: Decimal?
    let currency: String?
    let date: String?
    let location: OpenPricesLocation?
    let proof_id: Int?
    let duplicate_of: Int?
    let price_is_discounted: Bool?
    let discount_type: String?
    let price_per: String?
}
struct OpenPricesLocation: Decodable {
    let id: Int
    let type: String?
    let osm_id: Int64?
    let osm_type: String?
    let osm_name: String?
    let osm_lat: Double?
    let osm_lon: Double?
    let osm_address_postcode: String?
    let osm_address_city: String?
    let osm_address_country_code: String?
    let website_url: String?
}
protocol PriceProvider: Sendable {
    func history(_ barcode: Barcode, near location: GeoPoint?) async throws -> PricePage
    func history(_ barcode: Barcode, context: LocationContext?) async throws -> PricePage
}
extension PriceProvider {
    func history(_ barcode: Barcode, context: LocationContext?) async throws -> PricePage {
        try await history(barcode, near: context?.coordinate)
    }
}

struct OpenPricesProvider: PriceProvider {
    let client: any HTTPClient
    let maxPages: Int
    let areaResolver: any PriceAreaResolving
    init(client: any HTTPClient, maxPages: Int = 10, areaResolver: any PriceAreaResolving = PriceAreaResolver()) {
        self.client = client; self.maxPages = max(1, maxPages); self.areaResolver = areaResolver
    }
    func history(_ barcode: Barcode, context: LocationContext?) async throws -> PricePage {
        guard let context else { return PricePage(observations: [], isTruncated: false) }
        let nearby = try await history(barcode, near: context.coordinate)
        guard nearby.observations.isEmpty, !nearby.isTruncated else { return nearby }
        let area = await areaResolver.resolve(context)
        try Task.checkCancellation()
        guard let country = area.countryCode?.uppercased() else {
            var result = nearby
            result.notices.append("The country for this area couldn't be determined. Set a ZIP or update your location to search beyond nearby stores.")
            return result
        }
        do {
            let broader = try await fetch(barcode, near: nil)
            let countryRecords = PriceHistoryUseCase().matchingObservations(broader.observations, barcode: barcode).filter { $0.store.countryCode?.uppercased() == country }
            if let city = area.city?.nonEmpty {
                let cityRecords = countryRecords.filter { $0.store.city?.compare(city, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                if !cityRecords.isEmpty {
                    return PricePage(observations: cityRecords, isTruncated: broader.isTruncated,
                        coverage: PriceCoverage(scope: .city, label: city))
                }
            }
            return PricePage(observations: countryRecords, isTruncated: broader.isTruncated,
                coverage: PriceCoverage(scope: .country, label: Locale(identifier: "en_US").localizedString(forRegionCode: country) ?? country))
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            var result = nearby
            result.notices.append("Nearby search finished, but the wider-area price search failed. Try again.")
            result.isTruncated = true
            return result
        }
    }
    func history(_ barcode: Barcode, near location: GeoPoint?) async throws -> PricePage {
        guard let location else { return PricePage(observations: [], isTruncated: false) }
        let page = try await fetch(barcode, near: location)
        return PricePage(observations: PriceHistoryUseCase().localObservations(page.observations, barcode: barcode, near: location),
            isTruncated: page.isTruncated, coverage: page.coverage, notices: page.notices)
    }
    private func fetch(_ barcode: Barcode, near location: GeoPoint?) async throws -> PricePage {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        var values: [PriceObservation] = []
        for page in 1...maxPages {
            var query: [URLQueryItem] = [
                .init(name: "product_code__in", value: barcode.queryVariants.joined(separator: ",")),
                .init(name: "currency", value: "USD"), .init(name: "location__type", value: "OSM"),
                .init(name: "date__lte", value: formatter.string(from: Date())), .init(name: "order_by", value: "-date,-id"),
                .init(name: "duplicate_of__isnull", value: "true"), .init(name: "size", value: "100"), .init(name: "page", value: String(page))]
            if let location {
                query += [.init(name: "lat", value: String(location.latitude)), .init(name: "lon", value: String(location.longitude)), .init(name: "radius_km", value: "25")]
            }
            do {
                let data = try await client.data(for: makeRequest("https://prices.openfoodfacts.org/api/v1/prices", query: query))
                let response = try JSONDecoder().decode(OpenPricesResponse.self, from: data)
                values.append(contentsOf: Self.map(response.items, barcode: barcode))
                if page >= response.pages || response.items.isEmpty { return PricePage(observations: values, isTruncated: false, coverage: location == nil ? nil : PriceCoverage(scope: .nearby, label: "Within 25 km")) }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if page == 1 { throw error }
                return PricePage(observations: values, isTruncated: true)
            }
        }
        return PricePage(observations: values, isTruncated: true)
    }
    static func map(_ items: [OpenPricesItem], barcode: Barcode) -> [PriceObservation] {
        let dateParser = DateFormatter()
        dateParser.locale = Locale(identifier: "en_US_POSIX")
        dateParser.timeZone = TimeZone(secondsFromGMT: 0)
        dateParser.dateFormat = "yyyy-MM-dd"
        dateParser.isLenient = false
        return items.compactMap { item in
            guard item.duplicate_of == nil, let code = item.product_code, let matched = try? Barcode(code), matched.identity == barcode.identity,
                  let amount = item.price, amount > 0, let currency = item.currency?.nonEmpty,
                  let dateString = item.date, let day = dateParser.date(from: dateString), dateParser.string(from: day) == dateString,
                  let location = item.location, location.type == "OSM", let osmID = location.osm_id, let osmType = location.osm_type,
                  let name = location.osm_name?.nonEmpty, let lat = location.osm_lat, let lon = location.osm_lon,
                  item.price_per == nil || item.price_per == "UNIT" else { return nil }
            let coordinate = GeoPoint(latitude: lat, longitude: lon)
            guard coordinate.isValid else { return nil }
            let store = Store(id: "osm:\(osmType.lowercased()):\(osmID)", name: name, coordinate: coordinate,
                postalCode: location.osm_address_postcode, address: location.osm_address_city, city: location.osm_address_city, countryCode: location.osm_address_country_code?.uppercased())
            return PriceObservation(id: "openprices:\(item.id)", barcode: barcode, money: Money(amount: amount, currency: currency.uppercased()),
                observedAt: day.addingTimeInterval(12 * 3600), store: store, source: .openPrices,
                proofURL: item.proof_id.flatMap { URL(string: "https://prices.openfoodfacts.org/proofs/\($0)") },
                isDiscounted: item.price_is_discounted ?? false, priceBasis: item.discount_type)
        }
    }
}
