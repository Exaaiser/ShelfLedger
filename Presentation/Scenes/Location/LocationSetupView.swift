import SwiftUI

struct LocationSetupView: View {
    @ObservedObject var session: SessionManager
    let stores: any StoreRepositoryProtocol
    let locationManager: LocationManager
    let onContinue: () -> Void
    @State private var zipCode = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var work: Task<Void, Never>?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "location.circle").font(.system(size: 48)).foregroundStyle(AppTheme.accent)
                Text("Prices near you.").font(.largeTitle.bold())
                Text("Choose an area to see nearby price observations and stores.").foregroundStyle(.secondary)
                if let location = session.location {
                    Label(location.label, systemImage: "mappin.and.ellipse").font(.headline)
                    Button("Keep this area", action: onContinue).buttonStyle(PrimaryButtonStyle())
                }
                Button { locate() } label: { Label("Use current location", systemImage: "location.fill") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(isLoading)
                Text("OR ENTER A US ZIP CODE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    TextField("ZIP code", text: $zipCode).keyboardType(.numberPad).textContentType(.postalCode)
                        .accessibilityIdentifier("zipCodeField")
                    Button("Use ZIP") { resolveZIP() }.fontWeight(.semibold).disabled(zipCode.count != 5 || isLoading)
                }.padding().background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                if isLoading { ProgressView("Finding your area…") }
                if let error { Text(error).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("locationError") }
                Button("Continue without changing location", action: onContinue)
                    .font(.callout).frame(maxWidth: .infinity).padding(.top, 8)
                    .accessibilityIdentifier("skipLocationButton")
                Text("You can change your area from the home screen at any time.").font(.footnote).foregroundStyle(.secondary)
            }.padding(28)
        }
        .background(AppTheme.background)
        .navigationTitle("Your area").navigationBarTitleDisplayMode(.inline)
        .onDisappear { work?.cancel() }
    }
    private func locate() {
        start { try await locationManager.currentLocation() }
    }
    private func resolveZIP() {
        let code = zipCode
        start { try await stores.resolve(zipCode: code) }
    }
    private func start(_ operation: @escaping @MainActor () async throws -> LocationContext) {
        work?.cancel(); isLoading = true; error = nil
        work = Task {
            do {
                let context = try await operation()
                try Task.checkCancellation()
                session.setLocation(context)
                isLoading = false
                onContinue()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }
}
