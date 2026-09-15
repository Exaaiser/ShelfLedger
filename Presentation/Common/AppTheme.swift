import SwiftUI

enum AppTheme {
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.48, green: 0.84, blue: 0.63, alpha: 1) : UIColor(red: 0.10, green: 0.37, blue: 0.25, alpha: 1) })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ProductImage: View {
    let url: URL?
    var size: CGFloat = 72
    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image { image.resizable().scaledToFit() }
            else { Image(systemName: "shippingbox").font(.title2).foregroundStyle(Color.gray).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .padding(10).frame(width: size, height: size)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel("Product image")
    }
}

struct InfoCard: View {
    let title: String
    let message: String
    var icon = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("About these prices") {
                    Text("Price observations record what was seen at a store on a particular day. They do not confirm today's price or current stock.")
                    Text("Online listings may describe a different pack size. Check the seller's title, date and package before comparing.")
                    Text("Your own records stay on this device and are not published to a community database.")
                }
                Section("App version") { Text("1.0 (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))") }
                Section("Data credits") {
                    Link("Product information · Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org")!)
                    Text("Open Database License (ODbL). Product images: CC BY-SA.").font(.caption)
                    Link("Store & online price records · Open Prices", destination: URL(string: "https://prices.openfoodfacts.org")!)
                    Link("Online listings · UPCitemdb", destination: URL(string: "https://www.upcitemdb.com")!)
                    Link("Map data © OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("ZIP areas · Zippopotam.us", destination: URL(string: "https://www.zippopotam.us")!)
                }
            }.navigationTitle("About").toolbar { Button("Done") { dismiss() } }
        }
    }
}
