import CoreLocation
import Foundation
import UIKit

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
    var onSharingChanged:(()->Void)?
    @Published var sharingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(sharingEnabled, forKey: "rjlove.location-sharing")
            sharingEnabled ? start() : stop()
            onSharingChanged?()
        }
    }

    @Published var backgroundSharingEnabled: Bool = UserDefaults.standard.bool(forKey:"rjlove.background-location") {
        didSet {UserDefaults.standard.set(backgroundSharingEnabled,forKey:"rjlove.background-location"); if sharingEnabled {start()}}
    }
    @Published var photoLocationEnabled: Bool = UserDefaults.standard.object(forKey:"rjlove.photo-location") as? Bool ?? true {
        didSet {UserDefaults.standard.set(photoLocationEnabled,forKey:"rjlove.photo-location")}
    }
    var freshPhotoCoordinate: CLLocationCoordinate2D? {
        guard photoLocationEnabled,authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse,let value=lastLocation,abs(value.timestamp.timeIntervalSinceNow)<60,value.horizontalAccuracy>=0,value.horizontalAccuracy<=500 else {return nil}
        return value.coordinate
    }
    func requestPhotoLocation() {
        guard photoLocationEnabled else {return}
        if manager.authorizationStatus == .notDetermined {manager.requestWhenInUseAuthorization()}
        else if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {manager.requestLocation()}
    }
    var onLocation: ((CLLocation) -> Void)?
    var onGeofenceEvent: ((String, String, String) -> Void)?

    private let manager = CLLocationManager()
    /// Keeps "When in Use" sessions alive in the background (blue pill) and tells iOS we deliberately track.
    private var backgroundSession: CLBackgroundActivitySession?
    private var authorizationWaiter: CheckedContinuation<Void, Never>?
    private var placeNames: [String: String] = [:]
    private var fixWaiters: [UUID: CheckedContinuation<CLLocation?, Never>] = [:]

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
        manager.showsBackgroundLocationIndicator = false
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

    func requestRecordingLocation() {
        guard UserDefaults.standard.object(forKey:"rjlove.fart-locations") == nil || UserDefaults.standard.bool(forKey:"rjlove.fart-locations") else{return}
        if manager.authorizationStatus == .notDetermined{manager.requestWhenInUseAuthorization()}
        else if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse{manager.requestLocation()}
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

    var authorizationStatusName: String {
        switch authorizationStatus {
        case .authorizedAlways: "always"
        case .authorizedWhenInUse: "when_in_use"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not_determined"
        @unknown default: "unknown"
        }
    }

    /// 10.0: one fresh position for a background wake (silent push, geofence). Returns the last
    /// known fix when iOS cannot deliver a new one in time. Never asks for permission.
    func freshFix(timeout: Double) async -> CLLocation? {
        guard sharingEnabled, manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else { return nil }
        if let last = lastLocation, -last.timestamp.timeIntervalSinceNow < 20 { return last }
        let id = UUID()
        return await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            fixWaiters[id] = continuation
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, let waiter = self.fixWaiters.removeValue(forKey: id) else { return }
                waiter.resume(returning: self.lastLocation)
            }
        }
    }

    func requestTemporaryPrecision() {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PartnerMapPrecision")
    }

    /// 7.0: reliable background sharing. Updates no longer pause automatically (iOS would not resume
    /// them while suspended), accuracy is relaxed to save battery, and significant changes plus visits
    /// relaunch the app after it was closed so the partner map stays fresh.
    func enterBackground() {
        if sharingEnabled,backgroundSharingEnabled,
           manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.allowsBackgroundLocationUpdates=true
            manager.showsBackgroundLocationIndicator=true
            manager.pausesLocationUpdatesAutomatically=false
            manager.desiredAccuracy=kCLLocationAccuracyHundredMeters
            manager.distanceFilter=60
            if backgroundSession == nil { backgroundSession = CLBackgroundActivitySession() }
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates=false
            backgroundSession?.invalidate(); backgroundSession = nil
        }
        if sharingEnabled,manager.authorizationStatus == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
            if backgroundSharingEnabled { manager.startMonitoringVisits() }
        }
    }
    /// Called at launch: when iOS relaunched the app in the background for a location event,
    /// tracking resumes without waiting for any screen.
    func resumeAfterLaunch() {
        guard sharingEnabled else { return }
        if UIApplication.shared.applicationState != .active { enterBackground() }
    }
    func start() {
        guard sharingEnabled else { return }
        guard UIApplication.shared.applicationState == .active else {enterBackground();return}
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = backgroundSharingEnabled
            manager.showsBackgroundLocationIndicator = backgroundSharingEnabled
            manager.pausesLocationUpdatesAutomatically = !backgroundSharingEnabled
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 15
            if backgroundSharingEnabled, backgroundSession == nil { backgroundSession = CLBackgroundActivitySession() }
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
        manager.stopMonitoringVisits()
        backgroundSession?.invalidate(); backgroundSession = nil
        manager.allowsBackgroundLocationUpdates = false
        Task { await DepartureFence.shared.disarm() }
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
        let desired = Dictionary(uniqueKeysWithValues: permitted.prefix(19).map { ("rjlove.\($0.id)", $0) })
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
        if !fixWaiters.isEmpty {
            // A wake path (ping, geofence) asked for this fix and uploads it itself.
            let waiters = fixWaiters.values
            fixWaiters.removeAll()
            waiters.forEach { $0.resume(returning: location) }
        } else if sharingEnabled, UIApplication.shared.applicationState != .active {
            Task { await BackgroundLocationUploader.shared.upload(location) }
        }
        if sharingEnabled { Task { await DepartureFence.shared.arm(around: location) } }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard sharingEnabled, CLLocationCoordinate2DIsValid(visit.coordinate) else { return }
        let location = CLLocation(coordinate: visit.coordinate, altitude: 0, horizontalAccuracy: visit.horizontalAccuracy, verticalAccuracy: -1, timestamp: .now)
        lastLocation = location
        onLocation?(location)
        if UIApplication.shared.applicationState != .active {
            Task { await BackgroundLocationUploader.shared.upload(location, force: true, source: "Besuch erkannt") }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if !fixWaiters.isEmpty {
            let waiters = fixWaiters.values
            fixWaiters.removeAll()
            waiters.forEach { $0.resume(returning: lastLocation) }
        }
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

/// Sends a small merged update (position, battery) right away while iOS grants background time.
/// Independent of AppState, so it also works when iOS relaunched the app only for a location event.
@MainActor final class BackgroundLocationUploader {
    static let shared = BackgroundLocationUploader()
    private var lastUpload = Date.distantPast
    private var lastSent: CLLocation?
    private var inFlight = false
    private var pending: CLLocation?

    func upload(_ location: CLLocation, force: Bool = false, source: String = "Standortänderung") async {
        if inFlight { pending = location; return }
        var next: CLLocation? = location
        var forced = force
        var reason = source
        // Drain in a loop: a fix that arrives during an upload is sent right after it, never dropped.
        while let current = next {
            next = nil
            await send(current, force: forced, source: reason)
            forced = false
            // The newest fix that arrived meanwhile is the current position: always send it.
            if let waiting = pending { pending = nil; next = waiting; forced = true; reason = "Standortänderung" }
        }
    }

    /// 10.0: sent through the heartbeat endpoint, so battery, telemetry and the wake source travel
    /// with every background position.
    private func send(_ location: CLLocation, force: Bool, source: String) async {
        let moved = lastSent.map { location.distance(from: $0) } ?? .greatestFiniteMagnitude
        guard force || Date.now.timeIntervalSince(lastUpload) >= 60 || moved >= 150 else { return }
        inFlight = true
        defer { inFlight = false }
        if await PresenceHeartbeat.shared.report(source: source, location: location, force: true) {
            lastUpload = .now; lastSent = location
            UserDefaults.standard.set(Date.now.rjISO8601, forKey: "rjlove.last-background-location-at")
        }
    }
}

