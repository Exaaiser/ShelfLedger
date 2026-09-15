import Foundation

@MainActor
final class DependencyInjection {
    let repository: any ProductRepositoryProtocol
    let stores: any StoreRepositoryProtocol
    let session: SessionManager
    let locationManager: LocationManager
    let lookup: ProductLookupUseCase
    let search: SearchProductsUseCase
    let savePrice: SavePriceObservationUseCase
    let localStore: SwiftDataStore

    init(inMemory: Bool = false) throws {
        let client = URLSessionHTTPClient()
        localStore = try SwiftDataStore(inMemory: inMemory)
        let catalog = ProductCatalogService(catalog: OpenFoodFactsProvider(client: client), offers: CombinedOfferProvider(primary: UPCItemDBProvider(client: client), secondary: OpenPricesOnlineProvider(client: client)))
        let repository = ProductRepository(catalog: catalog, pricing: OpenPricesProvider(client: client), store: localStore)
        self.repository = repository
        stores = StoreRepository(resolver: LocationResolverService(client: client), discovery: StoreDiscoveryService(client: client))
        session = SessionManager(repository: stores)
        locationManager = LocationManager()
        lookup = ProductLookupUseCase(repository: repository)
        search = SearchProductsUseCase(repository: repository)
        savePrice = SavePriceObservationUseCase(repository: repository)
    }
}
