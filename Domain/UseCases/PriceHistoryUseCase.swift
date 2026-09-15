import Foundation

struct PriceHistoryUseCase {
    let radiusMeters: Double = 25_000
    func localObservations(_ values: [PriceObservation], barcode: Barcode, near location: GeoPoint?, now: Date = Date()) -> [PriceObservation] {
        guard let location, location.isValid else { return [] }
        return matchingObservations(values, barcode: barcode, now: now).filter { location.distance(to: $0.store.coordinate) <= radiusMeters }
    }
    func matchingObservations(_ values: [PriceObservation], barcode: Barcode, now: Date = Date()) -> [PriceObservation] {
        var ids = Set<String>()
        return values.filter {
            $0.barcode.identity == barcode.identity && $0.money.currency == "USD" && $0.money.amount > 0 &&
            $0.store.coordinate.isValid && Calendar.current.startOfDay(for: $0.observedAt) <= Calendar.current.startOfDay(for: now) && ids.insert($0.id).inserted
        }.sorted { $0.observedAt == $1.observedAt ? $0.id < $1.id : $0.observedAt < $1.observedAt }
    }
    func nearestStores(in observations: [PriceObservation], to location: GeoPoint, limit: Int = 3) -> [Store] {
        let stores = Dictionary(observations.map { ($0.store.id, $0.store) }, uniquingKeysWith: { _, latest in latest }).values
        return Array(stores.sorted {
            let lhs = location.distance(to: $0.coordinate), rhs = location.distance(to: $1.coordinate)
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }.prefix(limit))
    }
    func observations(on date: Date, in values: [PriceObservation], calendar: Calendar = .current) -> [PriceObservation] {
        values.filter { calendar.isDate($0.observedAt, inSameDayAs: date) }
    }
    func preferredOffer(in offers: [OnlineOffer], barcode: Barcode, now: Date = Date()) -> OnlineOffer? {
        availableOffers(in: offers, barcode: barcode, now: now).first
    }
    func availableOffers(in offers: [OnlineOffer], barcode: Barcode, now: Date = Date()) -> [OnlineOffer] {
        offers.filter { $0.barcode.identity == barcode.identity && $0.money.currency == "USD" && $0.money.amount > 0 && $0.isAvailable }
            .sorted {
                if $0.isStale(at: now) != $1.isStale(at: now) { return !$0.isStale(at: now) }
                if $0.updatedAt != $1.updatedAt { return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                return $0.id < $1.id
            }
    }
}
