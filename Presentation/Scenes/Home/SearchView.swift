import SwiftUI

struct SearchView: View {
    @StateObject var viewModel: SearchViewModel
    @FocusState private var editingQuery: Bool
    let onSelect: (String) -> Void
    private func submit() { editingQuery = false; viewModel.submit() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Find a product.").font(.system(size: 32, weight: .semibold, design: .serif))
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Name or barcode", text: $viewModel.query)
                        .focused($editingQuery).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                        .onSubmit { submit() }.accessibilityIdentifier("productSearchField")
                    if !viewModel.query.isEmpty { Button { viewModel.query = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary).accessibilityLabel("Clear search") }
                }.padding(18).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))
                Button("Search") { submit() }.buttonStyle(PrimaryButtonStyle())
                    .disabled(!viewModel.canSearch || viewModel.isLoading).opacity(viewModel.canSearch ? 1 : 0.5)
                    .accessibilityIdentifier("submitSearchButton")
                if viewModel.isLoading { ProgressView("Searching…").frame(maxWidth: .infinity).padding() }
                if let error = viewModel.error { InfoCard(title: "Search couldn't finish", message: error) }
                if viewModel.results.isEmpty && !viewModel.isLoading && viewModel.error == nil {
                    InfoCard(title: viewModel.hasSearched ? "No matching products" : "A name or the full barcode",
                        message: viewModel.hasSearched ? "Try a different name or scan the barcode on the package." : "Enter at least three characters, then tap Search. Previously viewed products appear as you type.", icon: "magnifyingglass")
                }
                if !viewModel.hasSearched && !viewModel.results.isEmpty { Text("Previously viewed").font(.caption).foregroundStyle(.secondary) }
                ForEach(viewModel.results) { product in
                    Button { onSelect(product.barcode.value) } label: {
                        HStack(spacing: 16) {
                            ProductImage(url: product.imageURL)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(product.name).font(.headline).foregroundStyle(.primary).lineLimit(3)
                                if let brand = product.brand { Text(brand).font(.caption).foregroundStyle(.secondary) }
                                if let quantity = product.quantity { Text(quantity).font(.caption).foregroundStyle(AppTheme.accent) }
                                Text(viewModel.priceHint(for: product) ?? "View recorded prices").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(16).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively).background(AppTheme.background).navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .onChange(of: viewModel.query) { _, _ in viewModel.queryChanged() }
            .onDisappear { viewModel.cancel() }
    }
}
