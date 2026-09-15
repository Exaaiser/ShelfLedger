import Foundation
import CryptoKit

struct OnlinePriceHistoryUseCase {
    func seriesID(_ offer: OnlineOffer) -> String {
        // Keep seller, package title, currency and discount terms separate. Do not compare unlike listings.
        digest([offer.barcode.identity, offer.sourceName, offer.merchant.lowercased(), offer.url.absoluteString,
                offer.title, offer.money.currency, offer.priceQualifier ?? ""].joined(separator: "\u{001F}"))
    }
    func merge(_ existing: [OnlineOffer], _ incoming: [OnlineOffer], barcode: Barcode, now: Date = Date()) -> [OnlineOffer] {
        var seen = Set<String>()
        return (existing + incoming).compactMap { offer in
            guard offer.barcode.identity == barcode.identity, offer.money.currency == "USD", offer.money.amount > 0,
                  offer.isAvailable, let date = offer.updatedAt, date.timeIntervalSince1970 > 0,
                  Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: now) else { return nil }
            let id = "online-history:" + digest("\(seriesID(offer)):\(date.timeIntervalSince1970):\(offer.money.amount)")
            guard seen.insert(id).inserted else { return nil }
            var value = offer.withID(id)
            value.provider = offer.sourceName
            return value
        }.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt! < $1.updatedAt! }
    }
    func latestListings(_ offers: [OnlineOffer]) -> [OnlineOffer] {
        var seen = Set<String>()
        return offers.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .filter { seen.insert(seriesID($0)).inserted }
    }
    func observation(on day: Date, in values: [OnlineOffer], policy: ObservationDatePolicy) -> OnlineOffer? {
        let calendar = Calendar.current
        return values.filter {
            guard let date = $0.updatedAt else { return false }
            return policy == .exactDay ? calendar.isDate(date, inSameDayAs: day) : calendar.startOfDay(for: date) <= calendar.startOfDay(for: day)
        }.max { $0.updatedAt! < $1.updatedAt! }
    }
    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
