import Foundation

struct ValidatePriceUseCase {
    func execute(price: String, store: Store?, observedAt: Date, now: Date = Date()) throws -> Money {
        let input = price.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.range(of: #"^\d{1,4}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")), amount > 0, amount < 10_000 else { throw ValidationError.invalidPrice }
        guard let store, !store.id.isEmpty, !store.name.isEmpty, store.coordinate.isValid else { throw ValidationError.invalidStore }
        let calendar = Calendar(identifier: .gregorian)
        let earliest = calendar.date(byAdding: .year, value: -2, to: now)!
        guard calendar.startOfDay(for: observedAt) <= calendar.startOfDay(for: now), observedAt >= earliest else { throw ValidationError.invalidDate }
        return Money(amount: amount, currency: "USD")
    }
}

@MainActor
struct ProductLookupUseCase {
    let repository: any ProductRepositoryProtocol
    func execute(barcode: String, location: LocationContext?, refresh: Bool = false) async throws -> ProductSnapshot {
        try await repository.lookup(Barcode(barcode), near: location, refresh: refresh)
    }
}

@MainActor
struct SearchProductsUseCase {
    let repository: any ProductRepositoryProtocol
    func execute(_ query: String, location: LocationContext?) async throws -> [Product] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty && value.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return [try await repository.lookup(Barcode(value), near: location, refresh: false).product]
        }
        guard value.count >= 3 else { return [] }
        return try await repository.search(value)
    }
}

@MainActor
struct SavePriceObservationUseCase {
    let repository: any ProductRepositoryProtocol
    func execute(id: UUID, product: Product, price: String, store: Store?, date: Date) throws -> PriceObservation {
        let money = try ValidatePriceUseCase().execute(price: price, store: store, observedAt: date)
        guard let store else { throw ValidationError.invalidStore }
        let observation = PriceObservation(id: "personal:\(id)", barcode: product.barcode, money: money,
            observedAt: date, store: store, source: .personal, proofURL: nil, isDiscounted: false, priceBasis: nil)
        try repository.save(observation, product: product)
        return observation
    }
}
