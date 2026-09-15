import SwiftUI

@main
struct ShelfLedgerApp: App {
    private let dependencies: Result<DependencyInjection, Error>
    init() { dependencies = Result { try DependencyInjection() } }
    var body: some Scene {
        WindowGroup {
            switch dependencies {
            case .success(let container): AppCoordinator(dependencies: container)
            case .failure:
                ContentUnavailableView("Saved data couldn't be opened", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Your existing data has been preserved. Close the app and try again."))
            }
        }
    }
}
