import Foundation

enum ProductError: LocalizedError {
    case notFound, unavailable
    var errorDescription: String? {
        switch self {
        case .notFound: return "No product matched this barcode. Check the barcode and try again."
        case .unavailable: return "Product services could not be reached. Try again when you're online."
        }
    }
}

@MainActor
final class ProductRepository: ProductRepositoryProtocol {
    private let catalog: ProductCatalogService
    private let pricing: any PriceProvider
    private let store: SwiftDataStore
    private var searches: [String: (Date, [Product])] = [:]
    init(catalog: ProductCatalogService, pricing: any PriceProvider, store: SwiftDataStore) {
        self.catalog = catalog; self.pricing = pricing; self.store = store
    }
    static func cacheKey(_ barcode: Barcode, _ location: LocationContext?) -> String {
        let place = location.map { String(format: "%.5f,%.5f", $0.coordinate.latitude, $0.coordinate.longitude) } ?? "no-location"
        return "history-v4:\(barcode.identity):\(place)"
    }
    func lookup(_ barcode: Barcode, near location: LocationContext?, refresh: Bool) async throws -> ProductSnapshot {
        let key = Self.cacheKey(barcode, location)
        let currentCached = try store.snapshot(key: key)
        // Previous caches contain valid observations but may have only two years of history.
        // Refresh them online; preserve them as a truthful offline fallback.
        let cached = try currentCached ?? store.snapshot(key: key.replacingOccurrences(of: "history-v4:", with: "history-v3:")) ?? store.snapshot(key: String(key.dropFirst("history-v4:".count)))
        if !refresh, var cached = currentCached, Date().timeIntervalSince(cached.fetchedAt) < 300 {
            cached.observations = merge(cached.observations, try store.personalObservations(barcode: barcode))
            cached.isCached = true
            attachOnlineHistory(to: &cached, incoming: cached.offers)
            return cached
        }
        async let catalogResult = catalog.lookup(barcode)
        async let priceResult = fetchResult("Local price history") { try await pricing.history(barcode, context: location) }
        let (identity, price) = try await (catalogResult, priceResult)
        try Task.checkCancellation()
        guard let product = identity.product ?? cached?.product else {
            throw identity.notices.isEmpty ? ProductError.notFound : ProductError.unavailable
        }
        var notices = identity.notices + (price.value?.notices ?? [])
        if let failure = price.failure { notices.append(failure) }
        if price.value?.isTruncated == true { notices.append("Only part of the price history could be loaded. Pull to refresh and try again.") }
        let useCachedPrices = price.value == nil && cached != nil
        if useCachedPrices { notices.append("Showing saved price observations while the price service is unavailable.") }
        let observations = merge(price.value?.observations ?? cached?.observations ?? [], try store.personalObservations(barcode: barcode))
        var snapshot = ProductSnapshot(product: product, observations: observations,
            offers: identity.offersFailed ? (cached?.offers ?? []) : identity.offers,
            fetchedAt: useCachedPrices ? cached!.fetchedAt : Date(), notices: notices, isCached: useCachedPrices)
        snapshot.coverage = price.value?.coverage ?? (useCachedPrices ? cached?.coverage : nil)
        snapshot.historyStatus = location == nil ? .noArea : price.failure != nil ? .failed : price.value?.isTruncated == true ? .partial : .loaded
        attachOnlineHistory(to: &snapshot, incoming: identity.priceHistory + snapshot.offers + (cached?.offers ?? []))
        do { try store.saveSnapshot(snapshot, key: key) }
        catch {
            var unsaved = snapshot
            unsaved.notices.append("These results could not be saved for offline use.")
            return unsaved
        }
        return snapshot
    }
    private func attachOnlineHistory(to snapshot: inout ProductSnapshot, incoming: [OnlineOffer]) {
        let records = (snapshot.onlineHistory ?? []) + incoming
        do { snapshot.onlineHistory = try store.saveOnlinePriceHistory(records, barcode: snapshot.product.barcode) }
        catch {
            snapshot.onlineHistory = OnlinePriceHistoryUseCase().merge([], records, barcode: snapshot.product.barcode)
            snapshot.notices.append("Online price history couldn't be saved on this device.")
        }
    }
    private func merge(_ remote: [PriceObservation], _ personal: [PriceObservation]) -> [PriceObservation] {
        var ids = Set<String>()
        return (personal + remote).filter { ids.insert($0.id).inserted }
    }
    func search(_ query: String) async throws -> [Product] {
        let key = query.lowercased()
        if let cached = searches[key], Date().timeIntervalSince(cached.0) < 900 { return cached.1 }
        let products = try await catalog.catalog.search(query)
        try Task.checkCancellation()
        searches[key] = (Date(), products)
        return products
    }
    func lastObservation(for product: Product, near location: LocationContext?) throws -> PriceObservation? {
        guard let location else { return nil }
        let cached = try store.snapshot(key: Self.cacheKey(product.barcode, location))
        let observations = merge(cached?.observations ?? [], try store.personalObservations(barcode: product.barcode))
        let history = PriceHistoryUseCase()
        let local = history.localObservations(observations, barcode: product.barcode, near: location.coordinate)
        guard let nearest = history.nearestStores(in: local, to: location.coordinate).first else { return nil }
        return local.last { $0.store.id == nearest.id }
    }
    func recentProducts() throws -> [Product] { try store.recentProducts() }
    func save(_ observation: PriceObservation, product: Product) throws { try store.saveObservation(observation) }
}
