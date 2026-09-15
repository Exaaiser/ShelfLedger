import SwiftUI

struct HomeView: View {
    @ObservedObject var session: SessionManager
    @ObservedObject var router: AppRouter
    let repository: any ProductRepositoryProtocol
    @State private var recent: [Product] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Label("SHELFLEDGER", systemImage: "leaf.fill").font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(AppTheme.accent)
                    Spacer()
                    Menu {
                        Button("Change area", systemImage: "location") { router.sheet = .location }
                        Button("About & data credits", systemImage: "info.circle") { router.sheet = .about }
                    } label: { Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(.primary) }
                }
                Text("See how\nprices change.").font(.system(size: 42, weight: .semibold, design: .serif))
                Button { router.sheet = .location } label: {
                    HStack {
                        Image(systemName: "location")
                        Text(session.location?.label ?? "Choose your area").lineLimit(2)
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption)
                    }.font(.subheadline).foregroundStyle(Color(uiColor: .secondaryLabel))
                }.accessibilityIdentifier("changeLocationButton")
                VStack(spacing: 12) {
                    actionCard("Scan a barcode", subtitle: "Find the product in your hand", symbol: "barcode.viewfinder") { router.sheet = .scanner }
                    actionCard("Search products", subtitle: "Look up a name or barcode", symbol: "magnifyingglass") { router.path.append(.search) }
                }
                if session.location == nil {
                    InfoCard(title: "Start with a product", message: "You can browse without an area. Add your location or ZIP to see local price observations.", icon: "mappin.and.ellipse")
                }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recently viewed").font(.title3.bold())
                        ForEach(recent.prefix(6)) { product in
                            Button { router.showProduct(product.barcode.value) } label: {
                                HStack(spacing: 16) {
                                    ProductImage(url: product.imageURL, size: 62)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(product.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text(product.quantity ?? product.brand ?? "View recorded prices").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(14).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Text("Recorded prices, with their place and date.").font(.footnote).foregroundStyle(.secondary).padding(.bottom, 20)
            }.padding(24)
        }
        .background(AppTheme.background).toolbar(.hidden, for: .navigationBar)
        .onAppear { recent = (try? repository.recentProducts()) ?? [] }
    }
    private func actionCard(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: symbol).font(.system(size: 28)).frame(width: 42).foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(AppTheme.accent)
            }.padding(22).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.04)))
        }.buttonStyle(.plain).accessibilityIdentifier(symbol == "magnifyingglass" ? "searchProductsButton" : "scanBarcodeButton")
    }
}
