import Foundation
import CoreLocation
import Combine

/// Thin CoreLocation wrapper for Menu Checker. Permission is requested only when
/// location is actually used (`requestWhenInUse`), and the whole feature still
/// works via manual search if the user declines. Publishes the latest coordinate
/// and authorization status for the UI to react to.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var coordinate: GeoPoint?
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var isResolving = false
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var pendingContinuations: [CheckedContinuation<GeoPoint?, Never>] = []

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
    /// to manual search.
    func requestLocation() async -> GeoPoint? {
        if isDenied { return nil }
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        isResolving = true
        lastError = nil
        return await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
            manager.requestLocation()
        }
    }

    private func resolvePending(with point: GeoPoint?) {
        isResolving = false
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        for c in continuations { c.resume(returning: point) }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let point = GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        Task { @MainActor in
            self.coordinate = point
            self.resolvePending(with: point)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.resolvePending(with: self.coordinate)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .denied || status == .restricted {
                self.resolvePending(with: nil)
            }
        }
    }
}
