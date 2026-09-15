import SwiftUI

enum AppRoute: Hashable { case search, product(String) }
enum AppSheet: String, Identifiable { case scanner, location, about; var id: String { rawValue } }

@MainActor
final class AppRouter: ObservableObject {
    @Published var path: [AppRoute] = []
    @Published var sheet: AppSheet?
    func showProduct(_ barcode: String) { path.append(.product(barcode)) }
}

struct AppCoordinator: View {
    let dependencies: DependencyInjection
    @StateObject private var router = AppRouter()
    @AppStorage("onboarding.v2") private var onboardingComplete = false
    init(dependencies: DependencyInjection) {
        self.dependencies = dependencies
    }
    var body: some View {
        Group {
            if !onboardingComplete {
                NavigationStack {
                    LocationSetupView(session: dependencies.session, stores: dependencies.stores,
                        locationManager: dependencies.locationManager) { onboardingComplete = true }
                }
            } else {
                NavigationStack(path: $router.path) {
                    HomeView(session: dependencies.session, router: router, repository: dependencies.repository)
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .search:
                                SearchView(viewModel: SearchViewModel(search: dependencies.search, repository: dependencies.repository,
                                    session: dependencies.session), onSelect: router.showProduct)
                            case .product(let barcode):
                                PriceTimelineView(viewModel: PriceTimelineViewModel(barcode: barcode, lookup: dependencies.lookup,
                                    savePrice: dependencies.savePrice, session: dependencies.session), onChangeArea: { router.sheet = .location })
                            }
                        }
                }
                .sheet(item: $router.sheet) { sheet in
                    switch sheet {
                    case .scanner:
                        ScannerView { barcode in
                            router.sheet = nil
                            router.showProduct(barcode)
                        }
                    case .location:
                        NavigationStack {
                            LocationSetupView(session: dependencies.session, stores: dependencies.stores,
                                locationManager: dependencies.locationManager) { router.sheet = nil }
                                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { router.sheet = nil } } }
                        }
                    case .about: AboutView()
                    }
                }
                .task { if dependencies.session.location != nil { dependencies.session.refreshStores() } }
            }
        }
        .tint(AppTheme.accent)
    }
}
