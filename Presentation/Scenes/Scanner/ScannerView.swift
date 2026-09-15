import SwiftUI

struct ScannerView: View {
    @StateObject private var viewModel = ScannerViewModel()
    @FocusState private var editingBarcode: Bool
    @Environment(\.dismiss) private var dismiss
    let onBarcode: (String) -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Find the price story.").font(.system(size: 32, weight: .semibold, design: .serif))
                    ZStack {
                        CameraView(onBarcode: accept, onFailure: { viewModel.cameraNotice = $0 })
                        RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.85), lineWidth: 2)
                            .frame(width: 240, height: 130).allowsHitTesting(false)
                    }
                    .frame(height: 280).background(.black).clipShape(RoundedRectangle(cornerRadius: 24))
                    Text(viewModel.cameraNotice ?? "Hold the product barcode inside the frame.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Or enter a barcode").font(.headline)
                    TextField("8, 12, 13 or 14 digits", text: $viewModel.manualBarcode)
                        .keyboardType(.numberPad).focused($editingBarcode).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("manualBarcodeField")
                    if let error = viewModel.error { Text(error).font(.subheadline).foregroundStyle(.red) }
                    Button("Find product") { accept(viewModel.manualBarcode) }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("findBarcodeButton")
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background).navigationTitle("Scan a product").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    private func accept(_ value: String) { editingBarcode = false; if let barcode = viewModel.accept(value) { onBarcode(barcode) } }
}
