import Foundation

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var manualBarcode = ""
    @Published var error: String?
    @Published var cameraNotice: String?
    private var completed = false
    func accept(_ value: String) -> String? {
        guard !completed else { return nil }
        do {
            let barcode = try Barcode(value)
            completed = true
            return barcode.value
        } catch { self.error = error.localizedDescription; return nil }
    }
}
