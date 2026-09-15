import Foundation
import CoreLocation

protocol PriceAreaResolving: Sendable {
    func resolve(_ context: LocationContext) async -> LocationContext
}

actor PriceAreaResolver: PriceAreaResolving {
    private var cache: [GeoPoint: LocationContext] = [:]
    func resolve(_ context: LocationContext) async -> LocationContext {
        if context.countryCode != nil, context.city != nil { return context }
        if let cached = cache[context.coordinate] { return cached }
        var result = context
        // Saved ZIP areas were resolved exclusively through the US ZIP endpoint.
        if result.countryCode == nil, result.postalCode != nil { result.countryCode = "US" }
        let geocoder = CLGeocoder()
        do {
            let places = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: context.coordinate.latitude, longitude: context.coordinate.longitude))
            try Task.checkCancellation()
            if let place = places.first {
                result.city = place.locality
                result.countryCode = place.isoCountryCode?.uppercased() ?? result.countryCode
            }
            cache[context.coordinate] = result
        } catch { /* Country/ZIP context may still support the broader query. */ }
        return result
    }
}
