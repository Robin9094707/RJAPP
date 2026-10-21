import CoreLocation
import Foundation

struct MonitoredLovePlace: Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let notifyOnEnter: Bool
    let notifyOnExit: Bool
}

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var lastError: String?
    @Published var sharingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(sharingEnabled, forKey: "rjlove.location-sharing")
            sharingEnabled ? start() : stop()
        }
    }

    var onLocation: ((CLLocation) -> Void)?
    var onGeofenceEvent: ((String, String, String) -> Void)?

    private let manager = CLLocationManager()
    private var authorizationWaiter: CheckedContinuation<Void, Never>?
    private var placeNames: [String: String] = [:]

    private override init() {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        sharingEnabled = UserDefaults.standard.object(forKey: "rjlove.location-sharing") as? Bool ?? false
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 15
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = true
    }

    func requestSetupAccess() async {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationWaiter = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestAlwaysAuthorization()
        }
    }

    func requestTemporaryPrecision() {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PartnerMapPrecision")
    }

    func start() {
        guard sharingEnabled else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = manager.authorizationStatus == .authorizedAlways
            manager.startUpdatingLocation()
            manager.startMonitoringSignificantLocationChanges()
        case .notDetermined:
            requestWhenInUse()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        for region in manager.monitoredRegions where region.identifier.hasPrefix("rjlove.") { manager.stopMonitoring(for: region) }
    }

    func updateActivity(_ motion: String) {
        switch motion {
        case "Auto": manager.activityType = .automotiveNavigation
        case "Fahrrad": manager.activityType = .fitness
        case "Zu Fuß", "Laufen": manager.activityType = .fitness
        default: manager.activityType = .otherNavigation
        }
    }

    func synchronizeGeofences(_ places: [MonitoredLovePlace]) {
        let permitted = sharingEnabled ? places : []
        let desired = Dictionary(uniqueKeysWithValues: permitted.prefix(20).map { ("rjlove.\($0.id)", $0) })
        placeNames = Dictionary(uniqueKeysWithValues: desired.map { ($0.key, $0.value.name) })

        for region in manager.monitoredRegions where region.identifier.hasPrefix("rjlove.") && desired[region.identifier] == nil {
            manager.stopMonitoring(for: region)
        }
        guard manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        let existing = Set(manager.monitoredRegions.map(\.identifier))
        for (identifier, place) in desired where !existing.contains(identifier) {
            let center = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            let radius = min(max(place.radius, 50), manager.maximumRegionMonitoringDistance)
            let region = CLCircularRegion(center: center, radius: radius, identifier: identifier)
            region.notifyOnEntry = place.notifyOnEnter
            region.notifyOnExit = place.notifyOnExit
            manager.startMonitoring(for: region)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        if authorizationStatus != .notDetermined { authorizationWaiter?.resume(); authorizationWaiter = nil }
        if sharingEnabled, manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            start()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        lastLocation = location
        lastError = nil
        onLocation?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .locationUnknown { return }
        lastError = error.localizedDescription
        DebugLogger.shared.log("Standortfehler: \(error.localizedDescription)", category: "Standort")
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard sharingEnabled, region.identifier.hasPrefix("rjlove.") else { return }
        onGeofenceEvent?(String(region.identifier.dropFirst("rjlove.".count)), placeNames[region.identifier] ?? "Ort", "enter")
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard sharingEnabled, region.identifier.hasPrefix("rjlove.") else { return }
        onGeofenceEvent?(String(region.identifier.dropFirst("rjlove.".count)), placeNames[region.identifier] ?? "Ort", "exit")
    }
}
