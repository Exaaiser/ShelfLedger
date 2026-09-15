import XCTest
@testable import ShelfLedger

private enum Fixture {
    static let barcode = try! Barcode("070847811169")
    static let product = Product(barcode: barcode, name: "Monster Energy", brand: "Monster", quantity: "16 oz", imageURL: nil, source: "Test fixture")
    static let point = GeoPoint(latitude: 40.4406, longitude: -79.9959)
    static let location = LocationContext(coordinate: point, label: "Pittsburgh", postalCode: "15222", updatedAt: Date())
    static func store(_ id: String = "osm:node:1", latitude: Double = 40.441) -> Store {
        Store(id: id, name: "Same chain", coordinate: GeoPoint(latitude: latitude, longitude: -79.9959), postalCode: "15222", address: nil)
    }
    static func observation(_ id: String = "1", price: Decimal = 3, currency: String = "USD", date: Date = Date(), store: Store = store()) -> PriceObservation {
        PriceObservation(id: id, barcode: barcode, money: Money(amount: price, currency: currency), observedAt: date,
            store: store, source: .personal, proofURL: nil, isDiscounted: false, priceBasis: nil)
    }
    static func offer(_ id: String = "offer", price: Decimal = 2, currency: String = "USD", date: Date? = Date(), availability: String? = nil) -> OnlineOffer {
        OnlineOffer(id: id, barcode: barcode, merchant: "Seller", title: "Pack of 12", money: Money(amount: price, currency: currency),
            url: URL(string: "https://example.com/product")!, updatedAt: date, availability: availability)
    }
    static func snapshot(observations: [PriceObservation] = [], offers: [OnlineOffer] = [], date: Date = Date()) -> ProductSnapshot {
        ProductSnapshot(product: product, observations: observations, offers: offers, fetchedAt: date, notices: [])
    }
}

final class PriceDomainTests: XCTestCase {
    func testBarcodeCanonicalIdentityAndChecksum() throws {
        XCTAssertEqual(Fixture.barcode.identity, try Barcode("0070847811169").identity)
        XCTAssertEqual(Fixture.barcode.identity, try Barcode("00070847811169").identity)
        XCTAssertEqual(Fixture.barcode.catalogCode, "0070847811169")
        for input in ["070847811168", "123", "０７０８４７８１１１６９", "07084781116A"] { XCTAssertThrowsError(try Barcode(input)) }
    }
    func testCorruptSerializedBarcodeIsRejected() {
        XCTAssertThrowsError(try JSONDecoder().decode(Barcode.self, from: Data(#"{"value":"12345678901234567890"}"#.utf8)))
    }
    func testMissingLocationNeverCreatesLocalPrices() {
        XCTAssertTrue(PriceHistoryUseCase().localObservations([Fixture.observation()], barcode: Fixture.barcode, near: nil).isEmpty)
    }
    func testLocalHistoryFiltersCurrencyDistanceDuplicatesAndFutureDays() {
        let today = Date()
        let values = [Fixture.observation("valid"), Fixture.observation("valid"), Fixture.observation("eur", currency: "EUR"),
            Fixture.observation("far", store: Fixture.store("far", latitude: 48)), Fixture.observation("zero", price: 0),
            Fixture.observation("future", date: Calendar.current.date(byAdding: .day, value: 1, to: today)!)]
        XCTAssertEqual(PriceHistoryUseCase().localObservations(values, barcode: Fixture.barcode, near: Fixture.point).map(\.id), ["valid"])
    }
    func testNearestBranchesKeepDistinctIdentityAndRequireObservations() {
        let values = [Fixture.observation("far", store: Fixture.store("a", latitude: 40.50)),
                      Fixture.observation("near", store: Fixture.store("z", latitude: 40.441)),
                      Fixture.observation("middle", store: Fixture.store("b", latitude: 40.45))]
        XCTAssertEqual(PriceHistoryUseCase().nearestStores(in: values, to: Fixture.point, limit: 2).map(\.id), ["z", "b"])
        XCTAssertTrue(PriceHistoryUseCase().nearestStores(in: [], to: Fixture.point).isEmpty)
    }
    func testExactDateDoesNotSubstituteAnotherDayInMonth() {
        let day = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        let values = [Fixture.observation(date: yesterday)]
        XCTAssertTrue(PriceHistoryUseCase().observations(on: day, in: values).isEmpty)
        XCTAssertEqual(PriceHistoryUseCase().observations(on: yesterday, in: values).count, 1)
    }
    func testOnlineSelectionPreservesAgePackAndChannel() {
        let old = Fixture.offer("old", price: 1, date: Date(timeIntervalSince1970: 1_500_000_000))
        let fresh = Fixture.offer("fresh", price: 12)
        let offers = [old, Fixture.offer("eur", currency: "EUR"), Fixture.offer("sold", availability: "Out of Stock"), fresh]
        let selected = PriceHistoryUseCase().preferredOffer(in: offers, barcode: Fixture.barcode)
        XCTAssertEqual(selected?.id, "fresh")
        XCTAssertEqual(selected?.title, "Pack of 12")
        XCTAssertTrue(old.isStale(at: Date()))
        XCTAssertTrue(Fixture.offer(date: nil).isStale(at: Date()))
    }
    func testManualPriceValidation() throws {
        let validate = ValidatePriceUseCase()
        XCTAssertEqual(try validate.execute(price: " 3.49 ", store: Fixture.store(), observedAt: Date()).amount, Decimal(string: "3.49"))
        for price in ["0", "-1", "1.001", "NaN", "$3", "10000", "3,49", "1e2"] {
            XCTAssertThrowsError(try validate.execute(price: price, store: Fixture.store(), observedAt: Date()), price)
        }
        XCTAssertThrowsError(try validate.execute(price: "1", store: nil, observedAt: Date()))
        XCTAssertThrowsError(try validate.execute(price: "1", store: Fixture.store(), observedAt: Date().addingTimeInterval(3 * 86400)))
    }
}

private actor MockHTTP: HTTPClient {
    var requests: [URLRequest] = []
    var responses: [Result<Data, Error>]
    init(_ responses: [Result<Data, Error>]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> Data {
        requests.append(request)
        guard !responses.isEmpty else { throw NetworkError.invalidResponse }
        return try responses.removeFirst().get()
    }
}

final class ProviderTests: XCTestCase {
    private let item = #"{"id":11,"product_code":"0070847811169","price":3.49,"currency":"USD","date":"2026-08-20","price_is_discounted":true,"discount_type":"LOYALTY_PROGRAM","proof_id":7,"price_per":"UNIT","location":{"id":5,"type":"OSM","osm_id":123,"osm_type":"WAY","osm_name":"Market","osm_lat":40.44,"osm_lon":-79.99,"osm_address_postcode":"15222"}}"#
    func testOpenPricesPreservesObservationProvenance() throws {
        let values = try JSONDecoder().decode([OpenPricesItem].self, from: Data("[\(item)]".utf8))
        let result = OpenPricesProvider.map(values, barcode: Fixture.barcode)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].money.amount, Decimal(string: "3.49"))
        XCTAssertEqual(result[0].store.id, "osm:way:123")
        XCTAssertEqual(result[0].store.postalCode, "15222")
        XCTAssertEqual(result[0].source, .openPrices)
        XCTAssertTrue(result[0].isDiscounted)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(calendar.component(.day, from: result[0].observedAt), 20)
    }
    func testMissingCurrencyBadDateAndWeightPricesAreNotMadeUp() throws {
        for invalid in [item.replacingOccurrences(of: #""currency":"USD""#, with: #""currency":null"#),
                        item.replacingOccurrences(of: "2026-08-20", with: "2026-02-30"),
                        item.replacingOccurrences(of: #""price_per":"UNIT""#, with: #""price_per":"KILOGRAM""#)] {
            let values = try JSONDecoder().decode([OpenPricesItem].self, from: Data("[\(invalid)]".utf8))
            XCTAssertTrue(OpenPricesProvider.map(values, barcode: Fixture.barcode).isEmpty)
        }
    }
    func testPaginationUsesActualAPISizeAndKeepsPartialResultOnFailure() async throws {
        let first = Data("{\"items\":[\(item)],\"page\":1,\"pages\":2,\"total\":101}".utf8)
        let client = MockHTTP([.success(first), .failure(NetworkError.status(503))])
        let value = try await OpenPricesProvider(client: client).history(Fixture.barcode, near: Fixture.point)
        XCTAssertTrue(value.isTruncated); XCTAssertEqual(value.observations.count, 1)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
        let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "size" }?.value, "100")
        XCTAssertEqual(query.first { $0.name == "currency" }?.value, "USD")
        XCTAssertEqual(query.first { $0.name == "radius_km" }?.value, "25")
        XCTAssertNil(query.first { $0.name == "page_size" })
        XCTAssertNil(query.first { $0.name == "date__gte" }, "Historical lookup must not silently discard older years")
    }
    func testPriceProviderDoesNotFetchWithoutLocation() async throws {
        let client = MockHTTP([])
        let result = try await OpenPricesProvider(client: client).history(Fixture.barcode, near: nil)
        XCTAssertTrue(result.observations.isEmpty)
        let requests = await client.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testOFF36StringStatusAndExactPackMetadata() async throws {
        // Shape verified against the live v3.6 response on 2026-09-09.
        let body = Data(#"{"status":"success","product":{"code":"0070847811169","product_name_en":"Monster Energy","brands":"Monster","quantity":"16 oz"}}"#.utf8)
        let provider = OpenFoodFactsProvider(client: MockHTTP([.success(body)]))
        let product = try await provider.lookup(Fixture.barcode)
        XCTAssertEqual(product?.name, "Monster Energy"); XCTAssertEqual(product?.quantity, "16 oz")
    }
    func testOFFNotFoundIsEmptyRatherThanServiceFailure() async throws {
        let provider = OpenFoodFactsProvider(client: MockHTTP([.failure(NetworkError.status(404))]))
        let product = try await provider.lookup(Fixture.barcode); XCTAssertNil(product)
    }
    func testUPCIgnoresHistoricalLowAndPreservesOfferDateAndPack() throws {
        let body = Data(#"{"items":[{"ean":"0070847811169","title":"Monster","lowest_recorded_price":0.01,"offers":[{"merchant":"Store","title":"Case of 24 cans","price":48,"currency":"","link":"https://example.com/24","updated_t":1535258412},{"merchant":"Other","price":0,"link":"https://example.com/zero"}]}]}"#.utf8)
        let value = try UPCItemDBProvider.decode(body, barcode: Fixture.barcode)
        XCTAssertEqual(value.offers.count, 1)
        XCTAssertEqual(value.offers[0].money, Money(amount: 48, currency: "USD"))
        XCTAssertEqual(value.offers[0].title, "Case of 24 cans")
        XCTAssertEqual(value.offers[0].updatedAt, Date(timeIntervalSince1970: 1535258412))
    }
    func testMismatchedCatalogBarcodeCannotBecomeRequestedProduct() throws {
        let body = Data(#"{"items":[{"ean":"012993441012","title":"Wrong product","offers":[]}]}"#.utf8)
        XCTAssertNil(try UPCItemDBProvider.decode(body, barcode: Fixture.barcode).product)
    }
}

private struct MockCatalog: CatalogProvider {
    var fails = false
    func lookup(_ barcode: Barcode) async throws -> Product? { if fails { throw NetworkError.status(503) }; return Fixture.product }
    func search(_ query: String) async throws -> [Product] { [Fixture.product] }
}
private struct MockOffers: OfferProvider {
    var fails = false
    func lookup(_ barcode: Barcode) async throws -> CatalogLookup { if fails { throw NetworkError.status(503) }; return CatalogLookup(product: nil, offers: []) }
}
private struct MockPrices: PriceProvider {
    var fails = false
    func history(_ barcode: Barcode, near location: GeoPoint?) async throws -> PricePage { if fails { throw NetworkError.status(503) }; return PricePage(observations: [], isTruncated: false) }
}
private struct MockStores: StoreRepositoryProtocol {
    func resolve(zipCode: String) async throws -> LocationContext { Fixture.location }
    func stores(near location: GeoPoint) async throws -> [Store] { [Fixture.store()] }
}

@MainActor
final class PersistenceAndFlowTests: XCTestCase {
    func testPersonalObservationSurvivesStoreReopenAndRetriesAreIdempotent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("verified.store")
        let observation = Fixture.observation("personal:stable")
        do {
            let store = try SwiftDataStore(url: url)
            try store.saveObservation(observation); try store.saveObservation(observation)
        }
        let reopened = try SwiftDataStore(url: url)
        XCTAssertEqual(try reopened.personalObservations(barcode: Fixture.barcode), [observation])
    }
    func testFailureFallsBackToDatedCacheAndKeepsPersonalRecords() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let date = Date().addingTimeInterval(-86400)
        try store.saveSnapshot(Fixture.snapshot(observations: [Fixture.observation("remote")], date: date), key: ProductRepository.cacheKey(Fixture.barcode, Fixture.location))
        try store.saveObservation(Fixture.observation("personal"))
        let repository = ProductRepository(catalog: ProductCatalogService(catalog: MockCatalog(fails: true), offers: MockOffers(fails: true)), pricing: MockPrices(fails: true), store: store)
        let value = try await repository.lookup(Fixture.barcode, near: Fixture.location, refresh: true)
        XCTAssertTrue(value.isCached); XCTAssertEqual(value.fetchedAt, date)
        XCTAssertEqual(Set(value.observations.map(\.id)), ["personal", "remote"])
        XCTAssertFalse(value.notices.isEmpty)
    }
    func testSuccessfulEmptyOffersDoNotResurrectOldOfferWhenCatalogFails() async throws {
        let store = try SwiftDataStore(inMemory: true)
        try store.saveSnapshot(Fixture.snapshot(offers: [Fixture.offer()]), key: ProductRepository.cacheKey(Fixture.barcode, nil))
        let repository = ProductRepository(catalog: ProductCatalogService(catalog: MockCatalog(fails: true), offers: MockOffers()), pricing: MockPrices(), store: store)
        let value = try await repository.lookup(Fixture.barcode, near: nil, refresh: true)
        XCTAssertTrue(value.offers.isEmpty)
    }
    func testLegacyHistoryCacheRemainsAvailableOfflineAfterUpgrade() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let oldKey = String(ProductRepository.cacheKey(Fixture.barcode, Fixture.location).dropFirst("history-v4:".count))
        try store.saveSnapshot(Fixture.snapshot(observations: [Fixture.observation("saved-before-upgrade")]), key: oldKey)
        let repository = ProductRepository(catalog: ProductCatalogService(catalog: MockCatalog(fails: true), offers: MockOffers(fails: true)), pricing: MockPrices(fails: true), store: store)
        let result = try await repository.lookup(Fixture.barcode, near: Fixture.location, refresh: false)
        XCTAssertTrue(result.isCached)
        XCTAssertEqual(result.observations.map(\.id), ["saved-before-upgrade"])
        XCTAssertFalse(result.notices.isEmpty)
    }
    func testComparisonUsesCalendarDaysRatherThanHiddenPickerTimes() throws {
        let store = try SwiftDataStore(inMemory: true)
        let repository = ProductRepository(catalog: ProductCatalogService(catalog: MockCatalog(), offers: MockOffers()), pricing: MockPrices(), store: store)
        let session = SessionManager(repository: MockStores(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = PriceTimelineViewModel(barcode: Fixture.barcode.value, lookup: ProductLookupUseCase(repository: repository), savePrice: SavePriceObservationUseCase(repository: repository), session: session)
        let day = Calendar.current.startOfDay(for: Date())
        model.comparisonStart = day.addingTimeInterval(18 * 3600)
        model.comparisonEnd = day.addingTimeInterval(3 * 3600)
        XCTAssertTrue(model.comparisonDatesValid)
        model.comparisonStart = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        XCTAssertFalse(model.comparisonDatesValid)
    }
    func testCacheIsScopedByCanonicalBarcodeAndLocation() throws {
        XCTAssertEqual(ProductRepository.cacheKey(Fixture.barcode, nil), ProductRepository.cacheKey(try Barcode("0070847811169"), nil))
        XCTAssertNotEqual(ProductRepository.cacheKey(Fixture.barcode, nil), ProductRepository.cacheKey(Fixture.barcode, Fixture.location))
    }
    func testManualScannerValidatesAndEmitsOnlyOnce() {
        let model = ScannerViewModel()
        XCTAssertNil(model.accept("123")); XCTAssertNotNil(model.error)
        XCTAssertEqual(model.accept(Fixture.barcode.value), Fixture.barcode.value)
        XCTAssertNil(model.accept(Fixture.barcode.value))
    }
    func testSavedObservationImmediatelyUpdatesSummaryAndMonths() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let repository = ProductRepository(catalog: ProductCatalogService(catalog: MockCatalog(), offers: MockOffers()), pricing: MockPrices(), store: store)
        let session = SessionManager(repository: MockStores(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        session.setLocation(Fixture.location)
        let model = PriceTimelineViewModel(barcode: Fixture.barcode.value, lookup: ProductLookupUseCase(repository: repository), savePrice: SavePriceObservationUseCase(repository: repository), session: session)
        await model.load()
        for _ in 0..<50 { if !session.nearbyStores.isEmpty { break }; await Task.yield() }
        XCTAssertNil(model.latest)
        let id = UUID()
        try model.save(id: id, price: "3.49", storeID: Fixture.store().id, date: Date())
        XCTAssertEqual(model.latest?.money.amount, Decimal(string: "3.49"))
        XCTAssertEqual(model.monthly.first?.observation?.money.amount, Decimal(string: "3.49"))
        XCTAssertNil(model.monthly.last?.observation)
        try model.save(id: id, price: "3.49", storeID: Fixture.store().id, date: Date())
        XCTAssertEqual(try store.personalObservations(barcode: Fixture.barcode).count, 1)
    }
}


@MainActor
private final class ControlledRepository: ProductRepositoryProtocol {
    var pending: [String: CheckedContinuation<[Product], Error>] = [:]
    var started: ((String) -> Void)?
    func lookup(_ barcode: Barcode, near location: LocationContext?, refresh: Bool) async throws -> ProductSnapshot { Fixture.snapshot() }
    func search(_ query: String) async throws -> [Product] {
        try await withCheckedThrowingContinuation { continuation in pending[query] = continuation; started?(query) }
    }
    func recentProducts() throws -> [Product] { [] }
    func lastObservation(for product: Product, near location: LocationContext?) throws -> PriceObservation? { nil }
    func save(_ observation: PriceObservation, product: Product) throws {}
}

@MainActor
final class SearchConcurrencyTests: XCTestCase {
    func testLateSearchResultCannotReplaceNewerQuery() async throws {
        let repo = ControlledRepository()
        let first = expectation(description: "first started"), second = expectation(description: "second started")
        repo.started = { query in (query == "first" ? first : second).fulfill() }
        let session = SessionManager(repository: MockStores(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = SearchViewModel(search: SearchProductsUseCase(repository: repo), repository: repo, session: session)
        model.query = "first"; model.submit()
        await fulfillment(of: [first], timeout: 2)
        model.query = "second"; model.queryChanged(); model.submit()
        await fulfillment(of: [second], timeout: 2)
        repo.pending.removeValue(forKey: "second")?.resume(returning: [Fixture.product])
        for _ in 0..<50 { if !model.isLoading { break }; await Task.yield() }
        XCTAssertEqual(model.results.map(\.id), [Fixture.product.id])
        repo.pending.removeValue(forKey: "first")?.resume(returning: [])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(model.results.map(\.id), [Fixture.product.id])
    }
}

import SwiftUI

@MainActor
final class VisualReviewTests: XCTestCase {
    func testRenderPriceHistoryInBothAppearances() async throws {
        let store = try SwiftDataStore(inMemory: true)
        let calendar = Calendar.current
        let observations = (0..<6).map { index in
            Fixture.observation("fixture:\(index)", price: Decimal(string: ["3.49", "3.29", "3.99", "3.79", "2.99", "3.19"][index])!,
                date: calendar.date(byAdding: .month, value: -index, to: Date())!)
        }
        try store.saveSnapshot(Fixture.snapshot(observations: observations), key: ProductRepository.cacheKey(Fixture.barcode, Fixture.location))
        let repository = ProductRepository(catalog: ProductCatalogService(catalog: MockCatalog(), offers: MockOffers()), pricing: MockPrices(), store: store)
        let session = SessionManager(repository: MockStores(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        session.setLocation(Fixture.location)
        let model = PriceTimelineViewModel(barcode: Fixture.barcode.value, lookup: ProductLookupUseCase(repository: repository), savePrice: SavePriceObservationUseCase(repository: repository), session: session)
        await model.load()
        XCTAssertEqual(model.filteredPoints.count, 6)
        XCTAssertEqual(model.priceDifference, Decimal(string: "0.20"))
        model.comparisonStart = observations[2].observedAt
        model.comparisonEnd = observations[0].observedAt
        for (scheme, comparison) in [(ColorScheme.light, false), (.dark, false), (.light, true), (.dark, true)] {
            let content = VStack(spacing: 0) {
                Text("VISUAL TEST · SYNTHETIC OBSERVATIONS").font(.caption).padding(8)
                if comparison { PriceComparisonView(viewModel: model) }
                else { PriceTimelineView(viewModel: model) }
            }.frame(width: 402, height: comparison ? 1000 : 1800).environment(\.colorScheme, scheme).tint(AppTheme.accent)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: comparison ? 1000 : 1800)
            let controller = UIHostingController(rootView: content)
            window.rootViewController = controller
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            window.windowLevel = .alert + 1
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(500))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(comparison ? "Date comparison" : "Price history") \(scheme) · test fixture"
            attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true
        }
    }
}

private struct FixedAreaResolver: PriceAreaResolving {
    func resolve(_ context: LocationContext) async -> LocationContext { context }
}

final class AreaFallbackTests: XCTestCase {
    private var area: LocationContext {
        LocationContext(coordinate: Fixture.point, label: "Pittsburgh", postalCode: "15222", updatedAt: Date(), city: "Pittsburgh", countryCode: "US")
    }
    private func page(_ items: [String], pages: Int = 1) -> Data {
        Data("{\"items\":[\(items.joined(separator: ","))],\"page\":1,\"pages\":\(pages),\"total\":\(items.count)}".utf8)
    }
    private func item(_ id: Int, city: String, country: String, latitude: Double = 41.5, currency: String = "USD") -> String {
        """
        {"id":\(id),"product_code":"0070847811169","price":3.49,"currency":"\(currency)","date":"2026-08-20","location":{"id":\(id),"type":"OSM","osm_id":\(id),"osm_type":"WAY","osm_name":"Market","osm_lat":\(latitude),"osm_lon":-79.99,"osm_address_city":"\(city)","osm_address_country_code":"\(country)"}}
        """
    }
    func testNearbyRecordsPreventWiderSearch() async throws {
        let http = MockHTTP([.success(page([item(1, city: "Pittsburgh", country: "us", latitude: 40.44)]))])
        let result = try await OpenPricesProvider(client: http, areaResolver: FixedAreaResolver()).history(Fixture.barcode, context: area)
        XCTAssertEqual(result.coverage?.scope, .nearby)
        let requests = await http.requests
        XCTAssertEqual(requests.count, 1)
    }
    func testCityPreferredOverCountryAndRadiusRemovedFromBroaderQuery() async throws {
        let http = MockHTTP([.success(page([])), .success(page([
            item(1, city: "pittsburgh", country: "us"), item(2, city: "Other", country: "US"),
            item(3, city: "Pittsburgh", country: "CA"), item(4, city: "Pittsburgh", country: "US", currency: "EUR")]))])
        let result = try await OpenPricesProvider(client: http, areaResolver: FixedAreaResolver()).history(Fixture.barcode, context: area)
        XCTAssertEqual(result.coverage?.scope, .city)
        XCTAssertEqual(result.observations.map(\.id), ["openprices:1"])
        let requests = await http.requests
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertFalse(query.contains { ["lat", "lon", "radius_km"].contains($0.name) })
        XCTAssertEqual(query.first { $0.name == "currency" }?.value, "USD")
    }
    func testCountryFallbackExcludesOtherCountries() async throws {
        let http = MockHTTP([.success(page([])), .success(page([item(2, city: "Other", country: "US"), item(3, city: "Other", country: "CA")]))])
        let result = try await OpenPricesProvider(client: http, areaResolver: FixedAreaResolver()).history(Fixture.barcode, context: area)
        XCTAssertEqual(result.coverage?.scope, .country)
        XCTAssertEqual(result.coverage?.label, "United States")
        XCTAssertEqual(result.observations.map(\.id), ["openprices:2"])
    }
    func testEmptyCountryResultRetainsCoverageWithoutInventingPrices() async throws {
        let http = MockHTTP([.success(page([])), .success(page([]))])
        let result = try await OpenPricesProvider(client: http, areaResolver: FixedAreaResolver()).history(Fixture.barcode, context: area)
        XCTAssertEqual(result.coverage?.scope, .country)
        XCTAssertTrue(result.observations.isEmpty)
        XCTAssertFalse(result.isTruncated)
    }
    func testBroaderFailureIsPartialNotSuccessfulEmptyCountry() async throws {
        let http = MockHTTP([.success(page([])), .failure(NetworkError.status(503))])
        let result = try await OpenPricesProvider(client: http, areaResolver: FixedAreaResolver()).history(Fixture.barcode, context: area)
        XCTAssertTrue(result.isTruncated)
        XCTAssertFalse(result.notices.isEmpty)
        XCTAssertEqual(result.coverage?.scope, .nearby)
    }
    func testIncompleteNearbySearchDoesNotSilentlyExpand() async throws {
        let http = MockHTTP([.success(page([item(1, city: "Other", country: "US")], pages: 2))])
        let result = try await OpenPricesProvider(client: http, maxPages: 1, areaResolver: FixedAreaResolver()).history(Fixture.barcode, context: area)
        XCTAssertTrue(result.isTruncated)
        let requests = await http.requests
        XCTAssertEqual(requests.count, 1)
    }
}

@MainActor
final class EmptyAndExpandedHistoryTests: XCTestCase {
    private func model(snapshot: ProductSnapshot) async throws -> PriceTimelineViewModel {
        let store = try SwiftDataStore(inMemory: true)
        try store.saveSnapshot(snapshot, key: ProductRepository.cacheKey(Fixture.barcode, Fixture.location))
        let repository = ProductRepository(catalog: ProductCatalogService(catalog: MockCatalog(), offers: MockOffers()), pricing: MockPrices(), store: store)
        let session = SessionManager(repository: MockStores(), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        session.setLocation(Fixture.location)
        let model = PriceTimelineViewModel(barcode: Fixture.barcode.value, lookup: ProductLookupUseCase(repository: repository), savePrice: SavePriceObservationUseCase(repository: repository), session: session)
        await model.load()
        return model
    }
    func testExpandedRecordsReachChartButDoNotBecomeNearbyRecordingStores() async throws {
        let remote = PriceObservation(id: "remote", barcode: Fixture.barcode, money: Money(amount: 3, currency: "USD"), observedAt: Date(), store: Fixture.store("far", latitude: 42), source: .openPrices, proofURL: nil, isDiscounted: false, priceBasis: nil)
        var snapshot = Fixture.snapshot(observations: [remote])
        snapshot.coverage = PriceCoverage(scope: .country, label: "United States")
        let model = try await model(snapshot: snapshot)
        XCTAssertTrue(model.localObservations.isEmpty)
        XCTAssertTrue(model.isWiderArea)
        XCTAssertEqual(model.filteredPoints.map(\.id), ["remote"])
        XCTAssertEqual(model.latest?.id, "remote")
        XCTAssertFalse(model.recordableStores.contains { $0.id == "far" })
    }
    func testEmptyHistoryKeepsMonthsAndAllOnlineListings() async throws {
        var snapshot = Fixture.snapshot(offers: [Fixture.offer("one"), Fixture.offer("two", price: 4)])
        snapshot.coverage = PriceCoverage(scope: .country, label: "United States")
        snapshot.historyStatus = .loaded
        let model = try await model(snapshot: snapshot)
        XCTAssertNil(model.latest)
        XCTAssertFalse(model.monthly.isEmpty)
        XCTAssertTrue(model.monthly.allSatisfy { $0.observation == nil })
        XCTAssertEqual(model.onlineOffers.count, 2)
        XCTAssertTrue(model.availabilityMessage.contains("United States"))
        let content = PriceTimelineView(viewModel: model).frame(width: 402, height: 1800).tint(AppTheme.accent)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 1800)
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(500))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Empty history with online offers - regression fixture"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}

private actor SequencedOffers: OfferProvider {
    var values: [CatalogLookup]
    init(_ values: [CatalogLookup]) { self.values = values }
    func lookup(_ barcode: Barcode) async throws -> CatalogLookup {
        guard !values.isEmpty else { throw NetworkError.status(503) }
        return values.removeFirst()
    }
}

final class OnlineHistoryTests: XCTestCase {
    func testHistoryKeepsPriceChangesAndDeduplicatesRepeatedLookups() {
        let useCase = OnlinePriceHistoryUseCase()
        let first = Fixture.offer("unstable-index-1", price: 3, date: Date().addingTimeInterval(-86400))
        let next = Fixture.offer("unstable-index-99", price: 4)
        let history = useCase.merge([first], [first, next, next], barcode: Fixture.barcode)
        XCTAssertEqual(history.map(\.money.amount), [3, 4])
        XCTAssertEqual(Set(history.map { useCase.seriesID($0) }).count, 1)
        XCTAssertEqual(useCase.merge(history, [next], barcode: Fixture.barcode), history)
    }
    func testMissingDatesFutureDatesAndWrongCurrenciesDoNotBecomeHistory() {
        let values = [Fixture.offer("undated", date: nil), Fixture.offer("future", date: Date().addingTimeInterval(3 * 86400)),
            Fixture.offer("eur", currency: "EUR"), Fixture.offer("sold", availability: "Out of Stock")]
        XCTAssertTrue(OnlinePriceHistoryUseCase().merge([], values, barcode: Fixture.barcode).isEmpty)
    }
    func testPackageSellerSourceAndDiscountChangesKeepSeparateSeries() {
        let useCase = OnlinePriceHistoryUseCase()
        let first = Fixture.offer()
        let differentPack = OnlineOffer(id: "pack", barcode: Fixture.barcode, merchant: first.merchant, title: "Single unit", money: first.money, url: first.url, updatedAt: first.updatedAt, availability: nil)
        var differentSource = first; differentSource.provider = "Open Prices"
        var discounted = first; discounted.priceQualifier = "loyalty program"
        let differentSeller = OnlineOffer(id: "seller", barcode: Fixture.barcode, merchant: "Another seller", title: first.title, money: first.money, url: first.url, updatedAt: first.updatedAt, availability: nil)
        XCTAssertEqual(Set([first, differentPack, differentSource, discounted, differentSeller].map { useCase.seriesID($0) }).count, 5)
    }
    func testExactAndOnOrBeforeDatesUseActualSourceTime() {
        let useCase = OnlinePriceHistoryUseCase()
        let now = Date(), old = Fixture.offer(date: Date().addingTimeInterval(-3 * 86400))
        XCTAssertNil(useCase.observation(on: now, in: [old], policy: .exactDay))
        XCTAssertEqual(useCase.observation(on: now, in: [old], policy: .lastRecorded)?.updatedAt, old.updatedAt)
    }
    func testActualOpenPricesOnlineResponseMapsWithoutStoreCoordinates() throws {
        // Public API record 175370, retrieved during source evaluation; no synthetic price/date.
        let json = #"{"items":[{"id":175370,"product_code":"0049000058499","price":20.49,"currency":"USD","date":"2025-12-26","duplicate_of":null,"price_per":null,"price_is_discounted":false,"discount_type":null,"location":{"id":4802,"type":"ONLINE","website_url":"https://www.bjs.com"}}],"page":1,"pages":1,"total":1}"#
        let response = try JSONDecoder().decode(OpenPricesResponse.self, from: Data(json.utf8))
        let values = OpenPricesOnlineProvider.map(response.items, barcode: try Barcode("0049000058499"))
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.money.amount, Decimal(string: "20.49"))
        XCTAssertEqual(values.first?.merchant, "bjs.com")
        XCTAssertEqual(values.first?.sourceName, "Open Prices")
        XCTAssertNotNil(values.first?.updatedAt)
        XCTAssertTrue(OpenPricesProvider.map(response.items, barcode: try Barcode("0049000058499")).isEmpty)
        XCTAssertTrue(OpenPricesOnlineProvider.map(response.items, barcode: Fixture.barcode).isEmpty)
        let variant = OpenPricesOnlineProvider.map(response.items, barcode: try Barcode("049000058499"))
        XCTAssertEqual(OnlinePriceHistoryUseCase().seriesID(values[0]), OnlinePriceHistoryUseCase().seriesID(variant[0]))
    }
    func testOnlineProviderRequiresNoLocationAndRequestsOnlineRecords() async throws {
        let http = MockHTTP([.success(Data(#"{"items":[],"page":1,"pages":1,"total":0}"#.utf8))])
        let result = try await OpenPricesOnlineProvider(client: http).lookup(Fixture.barcode)
        XCTAssertTrue(result.offers.isEmpty)
        let requests = await http.requests
        let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "location__type" }?.value, "ONLINE")
        XCTAssertFalse(query.contains { ["lat", "lon", "radius_km"].contains($0.name) })
    }
    func testOneFailedProviderDoesNotHideOtherProvidersPrices() async throws {
        let provider = CombinedOfferProvider(primary: MockOffers(fails: true), secondary: SequencedOffers([CatalogLookup(product: nil, offers: [Fixture.offer()])]))
        let result = try await provider.lookup(Fixture.barcode)
        XCTAssertEqual(result.offers.count, 1)
        XCTAssertFalse(result.notices.isEmpty)
    }
}

@MainActor
final class OnlineHistoryPersistenceTests: XCTestCase {
    func testHistorySurvivesEmptyRefreshAndAppRestartAndIsNotARecentProduct() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let old = Fixture.offer("first", price: 3, date: Date().addingTimeInterval(-86400))
        let latest = Fixture.offer("new", price: 4)
        do {
            let store = try SwiftDataStore(url: url)
            let offers = SequencedOffers([CatalogLookup(product: Fixture.product, offers: [old]), CatalogLookup(product: Fixture.product, offers: [latest]), CatalogLookup(product: Fixture.product, offers: [])])
            let repository = ProductRepository(catalog: ProductCatalogService(catalog: MockCatalog(), offers: offers), pricing: MockPrices(), store: store)
            _ = try await repository.lookup(Fixture.barcode, near: nil, refresh: true)
            let result = try await repository.lookup(Fixture.barcode, near: nil, refresh: true)
            XCTAssertEqual(result.onlineHistory?.count, 2)
            let empty = try await repository.lookup(Fixture.barcode, near: nil, refresh: true)
            XCTAssertTrue(empty.offers.isEmpty)
            XCTAssertEqual(empty.onlineHistory?.count, 2)
            XCTAssertEqual(try store.recentProducts().count, 1)
        }
        let reopened = try SwiftDataStore(url: url)
        XCTAssertEqual(try reopened.onlinePriceHistory(barcode: Fixture.barcode).map(\.money.amount), [3, 4])
    }
    func testWarmLegacySnapshotSeedsDatedOnlineHistory() async throws {
        let store = try SwiftDataStore(inMemory: true)
        try store.saveSnapshot(Fixture.snapshot(offers: [Fixture.offer()]), key: ProductRepository.cacheKey(Fixture.barcode, nil))
        let repository = ProductRepository(catalog: ProductCatalogService(catalog: MockCatalog(), offers: MockOffers()), pricing: MockPrices(), store: store)
        let result = try await repository.lookup(Fixture.barcode, near: nil, refresh: false)
        XCTAssertEqual(result.onlineHistory?.count, 1)
    }
    func testRenderOnlinePriceComparison() async throws {
        let records = OnlinePriceHistoryUseCase().merge([], [Fixture.offer("before", price: 3, date: Date().addingTimeInterval(-60 * 86400)), Fixture.offer("after", price: 4)], barcode: Fixture.barcode)
        let content = OnlinePriceHistoryView(records: records, listing: records.last!).frame(width: 402, height: 1400).tint(AppTheme.accent)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 1400)
        let controller = UIHostingController(rootView: content)
        window.rootViewController = controller
        window.windowLevel = .alert + 1
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(500))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Online history comparison - synthetic regression fixture"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}
