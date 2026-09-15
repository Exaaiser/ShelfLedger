import Foundation
import Combine

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var location: LocationContext?
    @Published private(set) var nearbyStores: [Store] = []
    @Published private(set) var storeNotice: String?
    @Published private(set) var isFindingStores = false
    private let defaults: UserDefaults
    private let repository: any StoreRepositoryProtocol
    private var discoveryTask: Task<Void, Never>?
    init(repository: any StoreRepositoryProtocol, defaults: UserDefaults = .standard) {
        self.repository = repository; self.defaults = defaults
        if let data = defaults.data(forKey: "locationContext.v2") { location = try? JSONDecoder().decode(LocationContext.self, from: data) }
    }
    func setLocation(_ context: LocationContext) {
        location = context
        defaults.set(try? JSONEncoder().encode(context), forKey: "locationContext.v2")
        refreshStores()
    }
    func refreshStores() {
        discoveryTask?.cancel()
        nearbyStores = []
        storeNotice = nil
        guard let location else { isFindingStores = false; return }
        isFindingStores = true
        discoveryTask = Task {
            do {
                let stores = try await repository.stores(near: location.coordinate)
                try Task.checkCancellation()
                nearbyStores = stores
                if stores.isEmpty { storeNotice = "No nearby stores were found for this area." }
            } catch {
                guard !Task.isCancelled else { return }
                storeNotice = "Nearby stores could not be loaded. You can still browse products and saved prices."
            }
            isFindingStores = false
        }
    }
}
