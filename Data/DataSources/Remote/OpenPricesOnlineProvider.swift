import Foundation

/// Online observations do not require or imply a physical store or the user's ZIP.
struct OpenPricesOnlineProvider: OfferProvider {
    let client: any HTTPClient
    var maxPages: Int = 10
    func lookup(_ barcode: Barcode) async throws -> CatalogLookup {
        let formatter = Self.dateFormatter()
        var records: [OnlineOffer] = []
        for page in 1...max(1, maxPages) {
            let request = try makeRequest("https://prices.openfoodfacts.org/api/v1/prices", query: [
                .init(name: "product_code__in", value: barcode.queryVariants.joined(separator: ",")),
                .init(name: "currency", value: "USD"), .init(name: "location__type", value: "ONLINE"),
                .init(name: "date__lte", value: formatter.string(from: Date())),
                .init(name: "duplicate_of__isnull", value: "true"),
                .init(name: "order_by", value: "-date,-id"), .init(name: "size", value: "100"), .init(name: "page", value: String(page))])
            do {
                let data = try await client.data(for: request)
                let result = try JSONDecoder().decode(OpenPricesResponse.self, from: data)
                records += Self.map(result.items, barcode: barcode)
                if page >= result.pages || result.items.isEmpty { return lookupResult(records) }
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                if page == 1 { throw error }
                return lookupResult(records, partial: true)
            }
        }
        return lookupResult(records, partial: true)
    }
    private func lookupResult(_ records: [OnlineOffer], partial: Bool = false) -> CatalogLookup {
        CatalogLookup(product: nil, offers: OnlinePriceHistoryUseCase().latestListings(records), priceHistory: records,
            notices: partial ? ["Open Prices: only part of the online price history could be loaded."] : [])
    }
    static func map(_ items: [OpenPricesItem], barcode: Barcode, now: Date = Date()) -> [OnlineOffer] {
        let formatter = dateFormatter()
        return items.compactMap { item in
            guard item.duplicate_of == nil, let code = item.product_code, (try? Barcode(code).identity) == barcode.identity,
                  let amount = item.price, amount > 0, item.currency?.uppercased() == "USD",
                  item.price_per == nil || item.price_per == "UNIT", let location = item.location, location.type == "ONLINE",
                  let url = location.website_url?.secureURL, let host = url.host,
                  let rawDate = item.date, let date = formatter.date(from: rawDate), formatter.string(from: date) == rawDate,
                  rawDate <= formatter.string(from: now) else { return nil }
            return OnlineOffer(id: "openprices-online:\(item.id)", barcode: barcode,
                merchant: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host,
                title: "Recorded online price · GTIN \(barcode.identity)", money: Money(amount: amount, currency: "USD"),
                url: url, updatedAt: date.addingTimeInterval(12 * 3600), availability: nil, provider: "Open Prices",
                priceQualifier: item.price_is_discounted == true ? (item.discount_type ?? "Discounted price").replacingOccurrences(of: "_", with: " ").lowercased() : nil)
        }
    }
    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

struct CombinedOfferProvider: OfferProvider {
    let primary: any OfferProvider
    let secondary: any OfferProvider
    func lookup(_ barcode: Barcode) async throws -> CatalogLookup {
        async let first = fetchResult("UPCitemdb") { try await primary.lookup(barcode) }
        async let second = fetchResult("Open Prices online") { try await secondary.lookup(barcode) }
        let (a, b) = try await (first, second)
        guard a.value != nil || b.value != nil else { throw NetworkError.invalidResponse }
        return CatalogLookup(product: a.value?.product ?? b.value?.product,
            offers: (a.value?.offers ?? []) + (b.value?.offers ?? []),
            priceHistory: (a.value?.priceHistory ?? []) + (b.value?.priceHistory ?? []),
            notices: (a.value?.notices ?? []) + (b.value?.notices ?? []) + [a.failure, b.failure].compactMap { $0 })
    }
}
