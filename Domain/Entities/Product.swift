import Foundation

struct Barcode: Hashable, Codable, Sendable {
    let value: String
    init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard [8, 12, 13, 14].contains(value.count), value.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw ValidationError.invalidBarcode }
        let digits = value.compactMap(\.wholeNumberValue)
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        guard (10 - sum % 10) % 10 == digits.last else { throw ValidationError.invalidBarcode }
        self.value = value
    }
    private enum CodingKeys: String, CodingKey { case value }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(container.decode(String.self, forKey: .value))
    }
    var identity: String { String(repeating: "0", count: 14 - value.count) + value }
    var catalogCode: String { value.count == 12 ? "0" + value : value }
    var queryVariants: [String] {
        var values = Set([value, catalogCode, identity])
        if identity.hasPrefix("00") { values.insert(String(identity.suffix(12))) }
        if identity.hasPrefix("0") { values.insert(String(identity.suffix(13))) }
        return values.sorted()
    }
}

struct Product: Identifiable, Hashable, Codable, Sendable {
    var id: String { barcode.identity }
    let barcode: Barcode
    let name: String
    let brand: String?
    let quantity: String?
    let imageURL: URL?
    let source: String
}

struct Money: Hashable, Codable, Sendable {
    let amount: Decimal
    let currency: String
    var chartValue: Double { NSDecimalNumber(decimal: amount).doubleValue }
    var formatted: String { amount.formatted(.currency(code: currency).locale(Locale(identifier: "en_US"))) }
}

struct GeoPoint: Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    func distance(to other: GeoPoint) -> Double {
        let radians = Double.pi / 180
        let a = pow(sin((other.latitude - latitude) * radians / 2), 2) + cos(latitude * radians) * cos(other.latitude * radians) * pow(sin((other.longitude - longitude) * radians / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(min(1, a)), sqrt(max(0, 1 - a)))
    }
}

struct Store: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let coordinate: GeoPoint
    let postalCode: String?
    let address: String?
    var city: String? = nil
    var countryCode: String? = nil
    var displayName: String { postalCode.map { "\(name) (\($0))" } ?? name }
}

struct LocationContext: Hashable, Codable, Sendable {
    let coordinate: GeoPoint
    let label: String
    let postalCode: String?
    let updatedAt: Date
    var city: String? = nil
    var countryCode: String? = nil
}

enum ObservationSource: String, Codable, Sendable {
    case openPrices, personal
    var label: String { self == .personal ? "Your record · saved on this device" : "Community price observation" }
}

struct PriceObservation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let barcode: Barcode
    let money: Money
    let observedAt: Date
    let store: Store
    let source: ObservationSource
    let proofURL: URL?
    let isDiscounted: Bool
    let priceBasis: String?
}

struct OnlineOffer: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let barcode: Barcode
    let merchant: String
    let title: String
    let money: Money
    let url: URL
    let updatedAt: Date?
    let availability: String?
    var provider: String? = nil
    var priceQualifier: String? = nil
    var sourceName: String { provider ?? (id.hasPrefix("openprices-online:") ? "Open Prices" : "UPCitemdb") }
    func withID(_ id: String) -> OnlineOffer {
        OnlineOffer(id: id, barcode: barcode, merchant: merchant, title: title, money: money, url: url,
            updatedAt: updatedAt, availability: availability, provider: provider, priceQualifier: priceQualifier)
    }
    var isAvailable: Bool { !(availability ?? "").lowercased().contains("out of stock") }
    func isStale(at date: Date) -> Bool {
        guard let updatedAt else { return true }
        return date.timeIntervalSince(updatedAt) > 30 * 86_400
    }
}

enum PriceScope: String, Codable, Sendable { case nearby, city, country }
struct PriceCoverage: Codable, Sendable {
    let scope: PriceScope
    let label: String
}
enum HistoryFetchStatus: String, Codable, Sendable { case loaded, partial, failed, noArea }

struct ProductSnapshot: Codable, Sendable {
    let product: Product
    var observations: [PriceObservation]
    let offers: [OnlineOffer]
    let fetchedAt: Date
    var notices: [String]
    var isCached: Bool = false
    var coverage: PriceCoverage? = nil
    var historyStatus: HistoryFetchStatus? = nil
    var onlineHistory: [OnlineOffer]? = nil
}

struct PricePage: Sendable {
    let observations: [PriceObservation]
    var isTruncated: Bool
    var coverage: PriceCoverage? = nil
    var notices: [String] = []
}

enum ValidationError: LocalizedError {
    case invalidBarcode, invalidPrice, invalidStore, invalidDate, invalidZIP
    var errorDescription: String? {
        switch self {
        case .invalidBarcode: return "Enter a valid 8, 12, 13 or 14-digit product barcode."
        case .invalidPrice: return "Enter a price between $0.01 and $9,999.99, with at most two decimal places."
        case .invalidStore: return "Choose the store where you saw this price."
        case .invalidDate: return "Choose today or an earlier date within the last two years."
        case .invalidZIP: return "Enter a five-digit US ZIP code."
        }
    }
}
