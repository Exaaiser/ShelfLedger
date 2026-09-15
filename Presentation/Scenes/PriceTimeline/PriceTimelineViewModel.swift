import Foundation
import Combine

enum TimeRange: String, CaseIterable {
    case sixMonths = "6M", oneYear = "1Y", twoYears = "2Y", custom = "Custom"
    var months: Int { switch self { case .sixMonths: return 6; case .oneYear: return 12; case .twoYears: return 24; case .custom: return 0 } }
}
@MainActor
final class PriceTimelineViewModel: ObservableObject {
    let barcode: String
    @Published private(set) var snapshot: ProductSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var selectedStores = Set<String>()
    @Published var timeRange: TimeRange = .oneYear
    @Published var customStart = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
    @Published var customEnd = Date()
    @Published var comparisonStart = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @Published var comparisonEnd = Date()
    @Published var comparisonPolicy: ObservationDatePolicy = .exactDay
    @Published private(set) var location: LocationContext?
    @Published private(set) var nearbyStores: [Store] = []
    @Published private(set) var storeNotice: String?
    private let lookup: ProductLookupUseCase
    private let savePrice: SavePriceObservationUseCase
    private let session: SessionManager
    private let analysis = PriceAnalysisUseCase()
    private let history = PriceHistoryUseCase()
    private var generation = 0
    init(barcode: String, lookup: ProductLookupUseCase, savePrice: SavePriceObservationUseCase, session: SessionManager) {
        self.barcode = barcode; self.lookup = lookup; self.savePrice = savePrice; self.session = session
        session.$location.assign(to: &$location)
        session.$nearbyStores.assign(to: &$nearbyStores)
        session.$storeNotice.assign(to: &$storeNotice)
    }
    var localObservations: [PriceObservation] {
        guard let snapshot else { return [] }
        return history.localObservations(snapshot.observations, barcode: snapshot.product.barcode, near: location?.coordinate)
    }
    var analysisObservations: [PriceObservation] {
        if !localObservations.isEmpty { return localObservations }
        guard let snapshot, let scope = snapshot.coverage?.scope, scope != .nearby else { return [] }
        return history.matchingObservations(snapshot.observations.filter { $0.source == .openPrices }, barcode: snapshot.product.barcode)
    }
    var isWiderArea: Bool { localObservations.isEmpty && snapshot?.coverage?.scope != nil && snapshot?.coverage?.scope != .nearby }
    var coverageLabel: String { isWiderArea ? "\(snapshot?.coverage?.label ?? "Wider area") · wider-area records" : "Nearby · within 25 km" }
    var availabilityTitle: String {
        if location == nil { return "Choose an area for price history" }
        if snapshot?.historyStatus == .failed { return "Price history couldn't be loaded" }
        if !analysisObservations.isEmpty && selectedStores.isEmpty { return "Select a reference store" }
        return "Store price history unavailable"
    }
    var availabilityMessage: String {
        if location == nil { return "The barcode identified the product. Choose your area to search nearby, city and country price records." }
        if snapshot?.historyStatus == .failed { return "The price service failed. This doesn't mean the product has no history. Try again." }
        if !analysisObservations.isEmpty && selectedStores.isEmpty { return "Select a store below to compare its recorded prices." }
        return "No matching dated USD store records were returned for \(isWiderArea ? snapshot?.coverage?.label ?? "this country" : "this area"). Available online prices are listed above. You can still select dates or record a price you saw."
    }
    var markets: [Store] {
        guard let location else { return [] }
        return history.nearestStores(in: analysisObservations, to: location.coordinate)
    }
    var rangeStart: Date { Calendar.current.startOfDay(for: timeRange == .custom ? min(customStart, customEnd) : Calendar.current.date(byAdding: .month, value: -timeRange.months, to: Date())!) }
    var rangeEnd: Date { timeRange == .custom ? max(customStart, customEnd) : Date() }
    var chartEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: rangeEnd))! }
    var filteredPoints: [PriceObservation] {
        analysisObservations.filter { selectedStores.contains($0.store.id) && $0.observedAt >= rangeStart && $0.observedAt < chartEnd }
    }
    var referenceStore: Store? { markets.first(where: { selectedStores.contains($0.id) }) }
    var referenceHistory: [PriceObservation] {
        guard let referenceStore else { return [] }
        return analysis.ordered(analysisObservations.filter { $0.store.id == referenceStore.id })
    }
    var latest: PriceObservation? { referenceHistory.first }
    var previous: PriceObservation? {
        guard let latest else { return nil }
        return analysis.previousDifferentPrice(before: latest, in: referenceHistory)
    }
    var latestChange: PriceChange? { analysis.change(from: previous, to: latest) }
    var priceDifference: Decimal? { latestChange?.amount }
    var monthly: [MonthlyObservation] { analysis.months(from: rangeStart, through: rangeEnd, in: referenceHistory) }
    var comparisonBefore: PriceObservation? { analysis.observation(on: comparisonStart, in: referenceHistory, policy: comparisonPolicy) }
    var comparisonAfter: PriceObservation? { analysis.observation(on: comparisonEnd, in: referenceHistory, policy: comparisonPolicy) }
    var comparisonDatesValid: Bool { Calendar.current.startOfDay(for: comparisonStart) <= Calendar.current.startOfDay(for: comparisonEnd) }
    var comparisonChange: PriceChange? {
        guard comparisonDatesValid else { return nil }
        return analysis.change(from: comparisonBefore, to: comparisonAfter)
    }
    func compare(_ month: MonthlyObservation) {
        comparisonStart = month.previous?.observedAt ?? Calendar.current.date(byAdding: .day, value: -1, to: month.month)!
        comparisonEnd = month.observation?.observedAt ?? month.month
        comparisonPolicy = .exactDay
    }
    var onlineOffers: [OnlineOffer] {
        guard let snapshot else { return [] }
        return history.availableOffers(in: snapshot.offers, barcode: snapshot.product.barcode)
    }
    var savedOnlineListings: [OnlineOffer] {
        let useCase = OnlinePriceHistoryUseCase()
        let visible = Set(onlineOffers.map { useCase.seriesID($0) })
        return useCase.latestListings(snapshot?.onlineHistory ?? []).filter { !visible.contains(useCase.seriesID($0)) }
    }
    var onlineOffer: OnlineOffer? {
        guard let snapshot else { return nil }
        return history.preferredOffer(in: snapshot.offers, barcode: snapshot.product.barcode)
    }
    var recordableStores: [Store] {
        var ids = Set<String>()
        let combined = (localObservations.map(\.store) + nearbyStores).filter { ids.insert($0.id).inserted }
        guard let location else { return combined }
        return combined.sorted { location.coordinate.distance(to: $0.coordinate) < location.coordinate.distance(to: $1.coordinate) }
    }
    func points(on date: Date) -> [PriceObservation] { history.observations(on: date, in: analysisObservations.filter { selectedStores.contains($0.store.id) }) }
    func toggle(_ store: Store) {
        if !selectedStores.insert(store.id).inserted { selectedStores.remove(store.id) }
    }
    func load(refresh: Bool = false) async {
        generation += 1
        let revision = generation
        isLoading = true; error = nil
        do {
            let value = try await lookup.execute(barcode: barcode, location: location, refresh: refresh)
            guard !Task.isCancelled, revision == generation else { return }
            snapshot = value
            selectedStores = Set(markets.map(\.id))
            isLoading = false
        } catch {
            guard !Task.isCancelled, revision == generation else { return }
            self.error = error.localizedDescription; isLoading = false
        }
    }
    func save(id: UUID, price: String, storeID: String, date: Date) throws {
        guard let product = snapshot?.product else { throw ProductError.notFound }
        let observation = try savePrice.execute(id: id, product: product, price: price, store: recordableStores.first { $0.id == storeID }, date: date)
        if snapshot?.observations.contains(where: { $0.id == observation.id }) != true { snapshot?.observations.append(observation) }
        selectedStores = Set(markets.map(\.id))
    }
    func distanceLabel(_ store: Store) -> String? {
        location.map { String(format: "%.1f mi", $0.coordinate.distance(to: store.coordinate) / 1609.344) }
    }
}
