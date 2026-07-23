import CoreLocation
import Foundation

@MainActor
final class MacLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = MacLocationProvider()

    enum LocationError: Error {
        case servicesDisabled
        case authorizationDenied
        case authorizationUnavailable
        case requestAlreadyActive
        case noLocation
    }

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private(set) var lastLocation: CLLocation?
    private(set) var lastAddress: String?

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.servicesDisabled
        }

        if manager.authorizationStatus == .notDetermined {
            try await requestAuthorization()
        }

        guard isAuthorized else {
            throw LocationError.authorizationDenied
        }

        guard locationContinuation == nil else {
            throw LocationError.requestAlreadyActive
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func locationIfAuthorized() async -> CLLocation? {
        guard CLLocationManager.locationServicesEnabled(), isAuthorized else {
            return lastLocation
        }
        if let lastLocation, abs(lastLocation.timestamp.timeIntervalSinceNow) < 3600 {
            return lastLocation
        }
        return try? await requestLocation()
    }

    func requestStartupLocation() async {
        guard CLLocationManager.locationServicesEnabled() else { return }
        _ = try? await requestLocation()
    }

    func address(for location: CLLocation) async -> String? {
        if let lastAddress, lastLocation?.distance(from: location) ?? .greatestFiniteMagnitude < 1000 {
            return lastAddress
        }
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        let parts = [
            placemark.name,
            placemark.subLocality,
            placemark.locality,
            placemark.administrativeArea
        ]
        let address = unique(parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).joined(separator: " ")
        lastAddress = address.isEmpty ? nil : address
        return lastAddress
    }

    private func requestAuthorization() async throws {
        guard authorizationContinuation == nil else {
            throw LocationError.requestAlreadyActive
        }

        try await withCheckedThrowingContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways:
                authorizationContinuation?.resume()
                authorizationContinuation = nil
            case .denied, .restricted:
                authorizationContinuation?.resume(throwing: LocationError.authorizationDenied)
                authorizationContinuation = nil
            case .notDetermined:
                break
            @unknown default:
                authorizationContinuation?.resume(throwing: LocationError.authorizationUnavailable)
                authorizationContinuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                locationContinuation?.resume(throwing: LocationError.noLocation)
                locationContinuation = nil
                return
            }
            lastLocation = location
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
