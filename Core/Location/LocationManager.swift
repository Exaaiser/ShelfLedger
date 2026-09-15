import Foundation
import CoreLocation

@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationContext, Error>?
    private var timeout: Task<Void, Never>?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func currentLocation() async throws -> LocationContext {
        try Task.checkCancellation()
        guard continuation == nil else { throw LocationError.inProgress }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(25)) } catch { return }
                    self?.finish(.failure(LocationError.unavailable))
                }
                switch manager.authorizationStatus {
                case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
                case .notDetermined: manager.requestWhenInUseAuthorization()
                default: finish(.failure(LocationError.denied))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self, self.continuation != nil else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse: self.manager.requestLocation()
            case .denied, .restricted: self.finish(.failure(LocationError.denied))
            default: break
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let point = GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let isUsable = location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 10_000 && abs(location.timestamp.timeIntervalSinceNow) < 120
        Task { @MainActor [weak self] in
            guard point.isValid, isUsable else { self?.finish(.failure(LocationError.unavailable)); return }
            self?.finish(.success(LocationContext(coordinate: point, label: "Current location", postalCode: nil, updatedAt: Date())))
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.finish(.failure(error)) }
    }
    private func finish(_ result: Result<LocationContext, Error>) {
        timeout?.cancel(); timeout = nil
        let pending = continuation; continuation = nil
        pending?.resume(with: result)
    }
}

enum LocationError: LocalizedError {
    case denied, unavailable, inProgress
    var errorDescription: String? {
        switch self {
        case .denied: return "Location access is off. Enter a ZIP code, or continue browsing without an area."
        case .unavailable: return "Your location couldn't be determined. Try a ZIP code, or continue browsing."
        case .inProgress: return "A location request is already in progress."
        }
    }
}
