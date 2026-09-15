import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasSearched = false
    private let search: SearchProductsUseCase
    private let repository: any ProductRepositoryProtocol
    private let session: SessionManager
    private var task: Task<Void, Never>?
    private var generation = 0
    init(search: SearchProductsUseCase, repository: any ProductRepositoryProtocol, session: SessionManager) {
        self.search = search; self.repository = repository; self.session = session
    }
    var canSearch: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 }
    func queryChanged() {
        generation += 1; task?.cancel(); isLoading = false; hasSearched = false; error = nil
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let recent = (try? repository.recentProducts()) ?? []
        results = input.count >= 3 ? recent.filter { $0.name.localizedCaseInsensitiveContains(input) || $0.barcode.value.contains(input) } : []
    }
    func submit() {
        guard canSearch else { return }
        task?.cancel(); generation += 1
        let revision = generation, input = query
        isLoading = true; error = nil; hasSearched = true
        task = Task {
            do {
                let found = try await search.execute(input, location: session.location)
                guard !Task.isCancelled, revision == generation else { return }
                results = found; isLoading = false
            } catch {
                guard !Task.isCancelled, revision == generation else { return }
                self.error = error.localizedDescription; isLoading = false
            }
        }
    }
    func priceHint(for product: Product) -> String? {
        guard let observation = try? repository.lastObservation(for: product, near: session.location) else { return nil }
        return "\(observation.money.formatted) · recorded \(observation.observedAt.formatted(date: .abbreviated, time: .omitted))"
    }
    func cancel() { generation += 1; task?.cancel(); isLoading = false }
}
