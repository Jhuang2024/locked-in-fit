import Foundation
import CoreLocation
import Combine

/// Thin CoreLocation wrapper for Menu Checker. Permission is requested when the
/// feature is first used (on entering Menu Checker, or via "Use location"), and
/// the whole feature still works via manual search if the user declines.
/// Publishes the latest coordinate and authorization status for the UI.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var coordinate: GeoPoint?
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var isResolving = false
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var locationContinuations: [CheckedContinuation<GeoPoint?, Never>] = []
    private var authContinuations: [CheckedContinuation<Bool, Never>] = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }
    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    /// Ask for permission (first use only) and resolve one location fix. Returns
    /// nil if permission is denied or a fix can't be obtained — callers fall back
    /// to manual search. Safe to call repeatedly; concurrent calls share the fix.
    func requestLocation() async -> GeoPoint? {
        if isDenied { return nil }
        if authorization == .notDetermined {
            // Wait for the permission dialog result BEFORE requesting a fix, so
            // we never fire requestLocation() against an undetermined status.
            let granted = await requestAuthorization()
            guard granted else { return nil }
        } else if !isAuthorized {
            return nil
        }
        isResolving = true
        lastError = nil
        return await withCheckedContinuation { continuation in
            locationContinuations.append(continuation)
            manager.requestLocation()
        }
    }

    private func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            authContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    private func resolveLocation(with point: GeoPoint?) {
        isResolving = false
        let continuations = locationContinuations
        locationContinuations.removeAll()
        for c in continuations { c.resume(returning: point) }
    }

    private func resolveAuthorization(granted: Bool) {
        let continuations = authContinuations
        authContinuations.removeAll()
        for c in continuations { c.resume(returning: granted) }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let point = GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        Task { @MainActor in
            // Only republish when the fix moves meaningfully (~50 m); a stream of
            // near-identical refinements would otherwise re-render the UI needlessly.
            if let existing = self.coordinate, existing.distance(to: point) < 50 {
                self.resolveLocation(with: existing)
            } else {
                self.coordinate = point
                self.resolveLocation(with: point)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.resolveLocation(with: self.coordinate)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            guard status != .notDetermined else { return }
            let granted = status == .authorizedWhenInUse || status == .authorizedAlways
            self.resolveAuthorization(granted: granted)
            if !granted { self.resolveLocation(with: nil) }
        }
    }
}
