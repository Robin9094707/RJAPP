import AVFoundation
import CoreLocation
import Foundation
import HealthKit
import Observation
import UIKit
import os

// MARK: - 10.0 Live-Sync-Engine
//
// iOS never lets an app run freely once it is closed. What a sideloaded app *can* use is every system
// event that wakes it: location changes, significant changes, visits, geofence exits (also after the
// app was swiped away), silent APNs pushes, BGAppRefresh/BGProcessing, HealthKit background delivery
// and notification actions. The engine turns every such wake into one small heartbeat (battery,
// network, telemetry, optionally the position) and logs it, so both partners can see exactly when and
// why data arrived. While background location keeps the app running ("Live-Modus"), battery changes
// are reported within seconds and a heartbeat runs on a fixed interval.

/// One background wake as seen by this iPhone.
struct WakeEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let date: Date
    let source: String
    let success: Bool
    let latencyMs: Int?
    let battery: Int?
    let detail: String?
}

@MainActor @Observable final class WakeJournal {
    static let shared = WakeJournal()
    private static let key = "rjlove.wake-journal"
    private static let launchesKey = "rjlove.process-launches"
    private(set) var entries: [WakeEntry] = []
    private(set) var processLaunches = UserDefaults.standard.integer(forKey: WakeJournal.launchesKey)
    private(set) var launchedInBackground = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([WakeEntry].self, from: data) { entries = stored }
    }

    func record(_ entry: WakeEntry) {
        entries.insert(entry, at: 0)
        if entries.count > 150 { entries.removeLast(entries.count - 150) }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func noteLaunch(background: Bool, reason: String?) {
        processLaunches += 1
        launchedInBackground = background
        UserDefaults.standard.set(processLaunches, forKey: Self.launchesKey)
        if background {
            record(WakeEntry(date: .now, source: "Prozessstart im Hintergrund", success: true, latencyMs: nil,
                             battery: DeviceTelemetry.batteryPercent, detail: reason))
        }
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    var wakesLast24h: Int { entries.filter { $0.date > .now.addingTimeInterval(-86_400) }.count }
}

// MARK: - Telemetry

@MainActor enum DeviceTelemetry {
    static var batteryPercent: Int? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let raw = UIDevice.current.batteryLevel
        return raw < 0 ? nil : Int((raw * 100).rounded())
    }

    static var batteryState: String {
        UIDevice.current.isBatteryMonitoringEnabled = true
        switch UIDevice.current.batteryState {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "unplugged"
        default: return "unknown"
        }
    }

    static var thermalState: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    /// Hardware identifier such as "iPhone18,2".
    static let modelIdentifier: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    static var storageFreeGB: Double? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return (Double(bytes) / 1_000_000_000 * 10).rounded() / 10
    }

    static var backgroundRefresh: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return "available"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }

    static func collect(source: String) -> [String: TelemetryValue] {
        let status = DeviceStatusService.shared
        let location = LocationService.shared
        var values: [String: TelemetryValue] = [
            "thermal_state": .string(thermalState),
            "uptime_s": .number(ProcessInfo.processInfo.systemUptime.rounded()),
            "os_version": .string(UIDevice.current.systemVersion),
            "device_model": .string(modelIdentifier),
            "app_build": .string(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"),
            "network_expensive": .bool(status.networkExpensive),
            "network_constrained": .bool(status.networkConstrained),
            "wake_source": .string(String(source.prefix(60))),
            "background_refresh": .string(backgroundRefresh),
            "location_authorization": .string(location.authorizationStatusName),
            "precise_location": .bool(location.accuracyAuthorization == .fullAccuracy),
            "push_registered": .bool(UIApplication.shared.isRegisteredForRemoteNotifications),
            "live_mode": .bool(LiveBackgroundEngine.shared.running),
            "health_background": .bool(HealthBackgroundDelivery.shared.active),
            "battery_monitoring": .bool(UIDevice.current.isBatteryMonitoringEnabled),
            "geofence_armed": .bool(DepartureFence.shared.armed),
            "significant_changes": .bool(CLLocationManager.significantLocationChangeMonitoringAvailable()),
            "visits": .bool(location.sharingEnabled && location.backgroundSharingEnabled),
            "process_launches": .number(Double(WakeJournal.shared.processLaunches)),
            "wakes_24h": .number(Double(WakeJournal.shared.wakesLast24h)),
            "memory_mb": .number((Double(os_proc_available_memory()) / 1_048_576).rounded()),
            "locale": .string(Locale.current.identifier),
            "timezone": .string(TimeZone.current.identifier),
        ]
        if let free = storageFreeGB { values["storage_free_gb"] = .number(free) }
        if let latency = PresenceHeartbeat.shared.lastLatencyMs { values["last_upload_latency_ms"] = .number(Double(latency)) }
        if let fix = location.lastLocation { values["location_age_s"] = .number(max(0, -fix.timestamp.timeIntervalSinceNow).rounded()) }
        if let output = AVAudioSession.sharedInstance().currentRoute.outputs.first { values["audio_route"] = .string(output.portType.rawValue) }
        if status.motion != "Unbekannt" { values["motion"] = .string(status.motion) }
        return values
    }
}

extension APIClient {
    /// A client built only from Keychain + UserDefaults, so it works after a cold background launch
    /// without RootView, Face ID or AppState.
    static func storedBackgroundClient() -> APIClient? {
        guard let bytes = UserDefaults.standard.data(forKey: AppState.profileKey),
              let profile = try? JSONDecoder().decode(ServerProfile.self, from: bytes),
              let url = AppState.normalizedServerURL(profile.baseURL),
              let token = KeychainStore.get(AppState.tokenKey) else { return nil }
        let api = APIClient(background: true)
        api.configure(baseURL: url, token: token)
        return api
    }

    func presenceTelemetry() async throws -> PresenceTelemetryResponse {
        try await execute(try request(path: "/v1/presence/telemetry", method: "GET"), as: PresenceTelemetryResponse.self)
    }

    func pingPartnerPresence() async throws -> PresencePingResult {
        try await execute(try request(path: "/v1/presence/ping", method: "POST", body: Data("{}".utf8)), as: PresencePingResult.self)
    }

    func postHeartbeat(_ payload: PresencePayload) async throws {
        _ = try await execute(try request(path: "/v1/presence/heartbeat", method: "POST", body: JSONEncoder().encode(payload)), as: EmptyResponse.self)
    }
}

// MARK: - Heartbeat

/// Sends one merged background update. Used by every wake path; never blocks alarms or commands.
@MainActor final class PresenceHeartbeat {
    static let shared = PresenceHeartbeat()
    private(set) var lastLatencyMs: Int?
    private(set) var lastSuccess: Date?
    private var lastAttempt = Date.distantPast
    private var lastBattery: Int?
    private var lastBatteryState: String?
    private var inFlight = false
    private var queued: (source: String, location: CLLocation?, pingID: String?)?

    /// Sends battery, network and telemetry. Throttled to one report per 30 s unless something
    /// changed, a position is attached, a ping must be answered or `force` is set.
    @discardableResult
    func report(source: String, location: CLLocation? = nil, pingID: String? = nil, force: Bool = false) async -> Bool {
        let battery = DeviceTelemetry.batteryPercent
        let state = DeviceTelemetry.batteryState
        let changed = battery != lastBattery || state != lastBatteryState
        guard force || changed || location != nil || pingID != nil || Date.now.timeIntervalSince(lastAttempt) >= 30 else { return false }
        if inFlight {
            // The newest request wins; it is sent right after the running one.
            queued = (source, location ?? queued?.location, pingID ?? queued?.pingID)
            return false
        }
        guard let api = APIClient.storedBackgroundClient() else { return false }
        inFlight = true
        lastAttempt = .now
        let box = HeartbeatTaskBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: "rj-heartbeat") {
            if box.id != .invalid { UIApplication.shared.endBackgroundTask(box.id); box.id = .invalid }
        }
        var payload = PresencePayload()
        payload.batteryLevel = battery
        payload.batteryState = state
        payload.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        payload.networkType = DeviceStatusService.shared.networkType
        payload.appState = UIApplication.shared.applicationState == .active ? "foreground" : "background"
        payload.source = String(source.prefix(60))
        payload.pingID = pingID
        payload.telemetry = DeviceTelemetry.collect(source: source)
        if LocationService.shared.sharingEnabled, let location, location.horizontalAccuracy >= 0 {
            payload.latitude = location.coordinate.latitude
            payload.longitude = location.coordinate.longitude
            payload.horizontalAccuracy = location.horizontalAccuracy
            payload.altitude = location.altitude
            payload.speed = location.speed >= 0 ? location.speed : nil
            payload.course = location.course >= 0 ? location.course : nil
            payload.locationTimestamp = location.timestamp.rjISO8601
        }
        let started = ContinuousClock.now
        var success = false
        var detail: String?
        do {
            try await api.postHeartbeat(payload)
            let elapsed = started.duration(to: .now)
            lastLatencyMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
            lastBattery = battery
            lastBatteryState = state
            lastSuccess = .now
            success = true
            if payload.latitude != nil { detail = "mit Standort ±\(Int(payload.horizontalAccuracy ?? 0)) m" }
            if pingID != nil { detail = (detail.map { $0 + " · " } ?? "") + "Ping beantwortet" }
            UserDefaults.standard.set(Date.now.rjISO8601, forKey: "rjlove.last-heartbeat-at")
        } catch {
            detail = error.localizedDescription
            DebugLogger.shared.log("Herzschlag: " + error.localizedDescription, category: "Hintergrund")
        }
        WakeJournal.shared.record(WakeEntry(date: .now, source: source, success: success, latencyMs: success ? lastLatencyMs : nil,
                                            battery: battery, detail: detail))
        inFlight = false
        if box.id != .invalid { UIApplication.shared.endBackgroundTask(box.id); box.id = .invalid }
        if let next = queued {
            queued = nil
            await report(source: next.source, location: next.location, pingID: next.pingID, force: true)
        }
        return success
    }
}

private final class HeartbeatTaskBox: @unchecked Sendable { var id = UIBackgroundTaskIdentifier.invalid }

// MARK: - Live mode

/// While iOS keeps the app running in the background (continuous background location), battery
/// changes are sent within seconds and a heartbeat runs on a fixed interval. Stops in the foreground,
/// where the regular sync takes over.
@MainActor @Observable final class LiveBackgroundEngine {
    static let shared = LiveBackgroundEngine()
    static let intervals: [Double] = [60, 120, 300, 600, 900]

    var enabled: Bool = UserDefaults.standard.object(forKey: "rjlove.live-mode") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "rjlove.live-mode")
            if !enabled { stop() } else if UIApplication.shared.applicationState != .active { enterBackground() }
        }
    }
    var interval: Double = UserDefaults.standard.object(forKey: "rjlove.live-interval") as? Double ?? 120 {
        didSet { UserDefaults.standard.set(interval, forKey: "rjlove.live-interval"); if running { restartLoop() } }
    }
    private(set) var running = false
    private(set) var startedAt: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var batteryDebounce: Task<Void, Never>?

    private init() {}

    func enterBackground() {
        guard enabled, !running else { return }
        running = true
        startedAt = .now
        UIDevice.current.isBatteryMonitoringEnabled = true
        let center = NotificationCenter.default
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification,
                     Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let reason = note.name == UIDevice.batteryStateDidChangeNotification ? "Ladezustand geändert"
                    : note.name == ProcessInfo.thermalStateDidChangeNotification ? "Temperatur geändert"
                    : note.name == Notification.Name.NSProcessInfoPowerStateDidChange ? "Stromsparmodus geändert" : "Akkuänderung"
                Task { @MainActor in self?.scheduleBatteryReport(reason) }
            })
        }
        restartLoop()
    }

    func enterForeground() { stop() }

    private func stop() {
        loop?.cancel(); loop = nil
        batteryDebounce?.cancel(); batteryDebounce = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        running = false
        startedAt = nil
    }

    private func restartLoop() {
        loop?.cancel()
        let seconds = interval
        loop = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, UIApplication.shared.applicationState != .active else { continue }
                await PresenceHeartbeat.shared.report(source: "Live-Herzschlag", force: true)
            }
        }
    }

    /// A 1 % step often arrives together with a state change; wait briefly and send once.
    private func scheduleBatteryReport(_ reason: String) {
        batteryDebounce?.cancel()
        batteryDebounce = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, UIApplication.shared.applicationState != .active else { return }
            await PresenceHeartbeat.shared.report(source: reason)
        }
    }
}

// MARK: - Departure geofence (CLMonitor)

/// A 150 m circle around the last position. Leaving it relaunches the app in the background, even
/// after it was swiped away, which then reports battery and the new position and re-arms the circle.
@MainActor final class DepartureFence {
    static let shared = DepartureFence()
    static let radius: CLLocationDistance = 150
    private static let identifier = "departure"
    private var monitor: CLMonitor?
    private var events: Task<Void, Never>?
    private var starting = false
    private(set) var center: CLLocationCoordinate2D?
    var armed: Bool { center != nil }

    func start() async {
        guard monitor == nil, !starting else { return }
        starting = true
        let monitor = await CLMonitor("rjlove-live-departure")
        self.monitor = monitor
        starting = false
        if let record = await monitor.record(for: Self.identifier),
           let condition = record.condition as? CLMonitor.CircularGeographicCondition {
            center = condition.center
        }
        events = Task { @MainActor [weak self] in
            do {
                for try await event in await monitor.events {
                    self?.handle(event)
                }
            } catch {
                DebugLogger.shared.log("Geofence: " + error.localizedDescription, category: "Standort")
            }
        }
    }

    func arm(around location: CLLocation) async {
        let service = LocationService.shared
        guard service.sharingEnabled, service.authorizationStatus == .authorizedAlways,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 500 else { return }
        if let center, CLLocation(latitude: center.latitude, longitude: center.longitude).distance(from: location) < 75 { return }
        await start()
        guard let monitor else { return }
        await monitor.remove(Self.identifier)
        await monitor.add(CLMonitor.CircularGeographicCondition(center: location.coordinate, radius: Self.radius),
                          identifier: Self.identifier, assuming: .satisfied)
        center = location.coordinate
    }

    func disarm() async {
        await monitor?.remove(Self.identifier)
        center = nil
    }

    private func handle(_ event: CLMonitor.Event) {
        guard event.identifier == Self.identifier, event.state == .unsatisfied else { return }
        center = nil
        Task { @MainActor in
            let fix = await LocationService.shared.freshFix(timeout: 8)
            await PresenceHeartbeat.shared.report(source: "Geofence verlassen", location: fix, force: true)
            if let fix { await self.arm(around: fix) }
        }
    }
}

// MARK: - HealthKit background delivery

/// New step samples wake the app (at most hourly, decided by iOS) for one heartbeat.
@MainActor final class HealthBackgroundDelivery {
    static let shared = HealthBackgroundDelivery()
    private let store = HKHealthStore()
    private var query: HKObserverQuery?
    private(set) var active = false

    func start() {
        guard query == nil, HKHealthStore.isHealthDataAvailable(),
              UserDefaults.standard.bool(forKey: "rjlove.health-requested"),
              UserDefaults.standard.bool(forKey: "rjlove.health-sharing"),
              let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor in
                if UIApplication.shared.applicationState != .active {
                    await PresenceHeartbeat.shared.report(source: "Health-Hintergrundlieferung")
                }
                completion()
            }
        }
        self.query = query
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { success, error in
            Task { @MainActor in
                HealthBackgroundDelivery.shared.active = success
                if let error { DebugLogger.shared.log("Health-Hintergrund: " + error.localizedDescription, category: "Health") }
            }
        }
    }
}

// MARK: - Server models

struct PresenceReport: Decodable, Hashable, Identifiable {
    var id: String { createdAt + source }
    let source: String
    let appState: String
    let batteryLevel: Int?
    let batteryState: String?
    let lowPowerMode: Bool
    let thermalState: String?
    let networkType: String?
    let hasLocation: Bool
    let horizontalAccuracy: Double?
    let uploadLatencyMs: Int?
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case source
        case appState = "app_state", batteryLevel = "battery_level", batteryState = "battery_state"
        case lowPowerMode = "low_power_mode", thermalState = "thermal_state", networkType = "network_type"
        case hasLocation = "has_location", horizontalAccuracy = "horizontal_accuracy"
        case uploadLatencyMs = "upload_latency_ms", createdAt = "created_at"
    }
}

struct PresenceStats: Decodable, Hashable {
    let reports24h: Int
    let bySource: [String: Int]
    let medianGapS: Double?
    let longestGapS: Double?
    enum CodingKeys: String, CodingKey {
        case reports24h = "reports_24h", bySource = "by_source", medianGapS = "median_gap_s", longestGapS = "longest_gap_s"
    }
}

struct PresenceActivity: Decodable, Hashable {
    let foregroundAt: String?
    let foregroundEndedAt: String?
    let backgroundSyncAt: String?
    let backgroundSource: String?
    enum CodingKeys: String, CodingKey {
        case foregroundAt = "foreground_at", foregroundEndedAt = "foreground_ended_at"
        case backgroundSyncAt = "background_sync_at", backgroundSource = "background_source"
    }
}

struct TelemetryUser: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let me: Bool
    let presence: PresencePayload?
    let reports: [PresenceReport]
    let pushDevices: Int
    let activity: PresenceActivity?
    let stats: PresenceStats
    enum CodingKeys: String, CodingKey {
        case id, me, presence, reports, activity, stats
        case displayName = "display_name", pushDevices = "push_devices"
    }
}

struct PresencePing: Decodable, Identifiable, Hashable {
    let id: String
    let requesterID: String
    let targetID: String
    let status: String
    let reason: String
    let createdAt: String
    let answeredAt: String?
    let answerLatencyMs: Int?
    enum CodingKeys: String, CodingKey {
        case id, status, reason
        case requesterID = "requester_id", targetID = "target_id", createdAt = "created_at"
        case answeredAt = "answered_at", answerLatencyMs = "answer_latency_ms"
    }
}

struct PresenceTelemetryResponse: Decodable {
    let serverTime: String
    let serverVersion: String
    let apnsEnabled: Bool
    let pingCooldownS: Int
    let users: [TelemetryUser]
    let pings: [PresencePing]
    enum CodingKeys: String, CodingKey {
        case users, pings
        case serverTime = "server_time", serverVersion = "server_version", apnsEnabled = "apns_enabled"
        case pingCooldownS = "ping_cooldown_s"
    }
}

struct PresencePingResult: Decodable {
    let id: String
    let status: String
    let reason: String
    let devices: Int
}
