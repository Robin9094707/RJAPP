import CoreLocation
import Foundation
import Observation
import UIKit
import WidgetKit

enum SessionPhase: Equatable {
    case setup
    case restoring
    case authenticated
}

struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class AppState {
    static let profileKey = "rjlove.server-profile.v1"
    static let tokenKey = "server-token"
    static let deviceIDKey = "rjlove.device-id"

    private(set) var phase: SessionPhase = .restoring
    private(set) var isSyncing = false
    private(set) var me: UserProfile?
    private(set) var partners: [PartnerSnapshot] = []
    private(set) var records: [SharedRecord] = []
    private(set) var thoughts: [String: Int] = [:]
    private(set) var storageUsedBytes = 0
    private(set) var features: ServerFeatures?
    private(set) var lastSync: Date?
    private(set) var connectionMessage = "Verbindung wird geprüft …"
    var selectedTab: AppTab = .home
    var alert: AppAlert?
    var statusMessage: String {
        didSet { UserDefaults.standard.set(statusMessage, forKey: "rjlove.status-message") }
    }
    var shareWiFiName: Bool {
        didSet { UserDefaults.standard.set(shareWiFiName, forKey: "rjlove.share-wifi-name") }
    }
    var shareFocus: Bool {
        didSet { UserDefaults.standard.set(shareFocus, forKey: "rjlove.share-focus") }
    }

    let api = APIClient()
    let location = LocationService.shared
    let deviceStatus = DeviceStatusService.shared
    let health = HealthService.shared
    let notifications = NotificationCoordinator.shared
    let alarms = AlarmService.shared
    let liveActivity = LiveActivityService.shared
    let calendar = CalendarService.shared
    let privacyLock = PrivacyLockService.shared

    private(set) var profile: ServerProfile?
    private var pollTask: Task<Void, Never>?
    private var notificationTasks: [Task<Void, Never>] = []
    private var lastPresenceUpload = Date.distantPast
    private var queuedPresenceTask: Task<Void, Never>?
    private var isActivated = false
    private var serverLocalDay = WidgetSharedStore.localDayStamp()

    init() {
        statusMessage = UserDefaults.standard.string(forKey: "rjlove.status-message") ?? "Bin für dich da 💗"
        shareWiFiName = UserDefaults.standard.bool(forKey: "rjlove.share-wifi-name")
        shareFocus = UserDefaults.standard.bool(forKey: "rjlove.share-focus")
        profile = Self.loadProfile()
        configureCallbacks()
        restoreSession()
    }

    var partner: PartnerSnapshot? { partners.first }
    var notes: [SharedRecord] { records.filter { $0.kind == .note } }
    var reminders: [SharedRecord] { records.filter { $0.kind == .reminder } }
    var moments: [SharedRecord] { records.filter { $0.kind == .moment } }
    var geofences: [SharedRecord] { records.filter { $0.kind == .geofence } }
    var calendarEvents: [SharedRecord] { records.filter { $0.kind == .calendar } }
    var myThoughtCount: Int {
        let synchronized: Int
        if serverLocalDay == WidgetSharedStore.localDayStamp() {
            synchronized = me.flatMap { thoughts[$0.id] } ?? 0
        } else {
            synchronized = 0
        }
        return synchronized + WidgetSharedStore.pendingThoughts()
    }
    var partnerThoughtCount: Int {
        guard serverLocalDay == WidgetSharedStore.localDayStamp() else { return 0 }
        return partner.flatMap { thoughts[$0.id] } ?? 0
    }
    var isUsingHTTPS: Bool { profile?.baseURL.lowercased().hasPrefix("https://") == true }

    func activate() async {
        if privacyLock.isEnabled, !privacyLock.isUnlocked {
            _ = await privacyLock.unlock()
        }
        guard !isActivated else {
            startPolling()
            await syncNow(showErrors: false)
            return
        }
        isActivated = true
        deviceStatus.start()
        location.start()
        await notifications.refreshStatus()
        if notifications.authorizationStatus == .authorized ||
            notifications.authorizationStatus == .provisional ||
            notifications.authorizationStatus == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
            if let token = UserDefaults.standard.string(forKey: NotificationCoordinator.deviceTokenKey) {
                await registerDeviceToken(token)
            }
        }
        BackgroundRefreshCoordinator.shared.handler = { [weak self] in
            guard let self else { return false }
            await self.syncNow(showErrors: false)
            let timestamp = await self.lastSync
            return timestamp.map { Date.now.timeIntervalSince($0) < 60 } ?? false
        }
        BackgroundRefreshCoordinator.shared.schedule()
        observeSystemEvents()
        startPolling()
        await scheduleSharedReminders()
        await syncNow(showErrors: false)
    }

    func deactivateForeground() {
        pollTask?.cancel()
        pollTask = nil
        privacyLock.lock()
        BackgroundRefreshCoordinator.shared.schedule()
    }

    func login(server: String, username: String, password: String) async {
        guard let url = Self.normalizedServerURL(server) else {
            alert = AppAlert(title: "Serveradresse prüfen", message: APIClientError.invalidServerURL.localizedDescription)
            return
        }
        phase = .restoring
        connectionMessage = "Sichere Anmeldung …"
        let newProfile = ServerProfile(baseURL: url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), username: username.trimmingCharacters(in: .whitespacesAndNewlines))
        api.configure(baseURL: url, token: nil)
        do {
            let response = try await api.login(username: newProfile.username, password: password, deviceID: deviceID)
            try KeychainStore.set(response.token, for: Self.tokenKey)
            if profile != newProfile { AppCache.clear() }
            profile = newProfile
            Self.saveProfile(newProfile)
            me = response.user
            api.configure(baseURL: url, token: response.token)
            phase = .authenticated
            connectionMessage = "Verbunden"
            DebugLogger.shared.log("Anmeldung erfolgreich", category: "Server")
            if notifications.authorizationStatus == .notDetermined {
                _ = await notifications.requestAuthorization()
            }
            await syncNow(showErrors: true)
            startPolling()
        } catch {
            phase = .setup
            connectionMessage = "Nicht verbunden"
            alert = AppAlert(title: "Anmeldung fehlgeschlagen", message: error.localizedDescription)
            DebugLogger.shared.log("Anmeldung fehlgeschlagen: \(error.localizedDescription)", category: "Server")
        }
    }

    func logout() async {
        await api.logout()
        KeychainStore.delete(Self.tokenKey)
        phase = .setup
        me = nil
        partners = []
        records = []
        thoughts = [:]
        storageUsedBytes = 0
        features = nil
        lastSync = nil
        pollTask?.cancel()
        AppCache.clear()
        WidgetSharedStore.clearPendingThoughts()
        WidgetSharedStore.saveSnapshot(WidgetSnapshot())
        WidgetCenter.shared.reloadAllTimelines()
    }

    @discardableResult
    func syncNow(showErrors: Bool = true) async -> Bool {
        guard phase == .authenticated, !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let snapshot = try await api.bootstrap()
            me = snapshot.me
            partners = snapshot.partners
            records = snapshot.records
            thoughts = snapshot.thoughts
            serverLocalDay = snapshot.localDay
            storageUsedBytes = snapshot.storageUsedBytes
            features = snapshot.features
            lastSync = .now
            connectionMessage = "Gerade synchronisiert"
            synchronizeGeofences()
            await process(snapshot.commands, events: snapshot.events)
            await scheduleSharedReminders()
            await drainWidgetThoughts()
            updateWidgetSnapshot()
            await updateLiveActivity()
            persistCache()
            if health.sharingEnabled { await health.refresh() }
            queuePresenceUpload(force: true)
            return true
        } catch let error as APIClientError {
            if case .server(let status, _) = error, status == 401 {
                KeychainStore.delete(Self.tokenKey)
                phase = .setup
            }
            connectionMessage = "Offline · Daten bleiben erhalten"
            if showErrors { alert = AppAlert(title: "Synchronisierung fehlgeschlagen", message: error.localizedDescription) }
            DebugLogger.shared.log("Sync: \(error.localizedDescription)", category: "Server")
            return false
        } catch {
            connectionMessage = "Offline · Daten bleiben erhalten"
            if showErrors { alert = AppAlert(title: "Synchronisierung fehlgeschlagen", message: error.localizedDescription) }
            return false
        }
    }

    func sendThought() async {
        _ = WidgetSharedStore.addPendingThought()
        updateWidgetSnapshot()
        Haptics.success()
        await drainWidgetThoughts()
        if WidgetSharedStore.pendingThoughts() > 0 {
            connectionMessage = "Offline · Herzgedanke vorgemerkt"
        }
        updateWidgetSnapshot()
        persistCache()
    }

    func sendWake(message: String) async -> Bool {
        guard let partner else { return false }
        do {
            _ = try await api.sendWake(targetID: partner.id, message: message)
            Haptics.success()
            return true
        } catch {
            alert = AppAlert(title: "Weckruf nicht gesendet", message: error.localizedDescription)
            return false
        }
    }

    func saveRecord(id: String? = nil, kind: RecordKind, payload: RecordPayload) async -> SharedRecord? {
        do {
            let record = try await api.upsertRecord(id: id ?? UUID().uuidString, kind: kind, payload: payload)
            records.removeAll { $0.id == record.id }
            records.insert(record, at: 0)
            synchronizeGeofences()
            if kind == .reminder { await scheduleSharedReminders() }
            persistCache()
            Haptics.success()
            return record
        } catch {
            alert = AppAlert(title: "Speichern fehlgeschlagen", message: error.localizedDescription)
            return nil
        }
    }

    func deleteRecord(_ record: SharedRecord) async -> Bool {
        do {
            try await api.deleteRecord(id: record.id)
            records.removeAll { $0.id == record.id }
            alarms.cancel(id: record.id)
            synchronizeGeofences()
            persistCache()
            Haptics.success()
            return true
        } catch {
            alert = AppAlert(title: "Löschen fehlgeschlagen", message: error.localizedDescription)
            return false
        }
    }

    func registerDeviceToken(_ token: String) async {
        guard phase == .authenticated else { return }
        do {
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
            try await api.registerDevice(token: token, deviceID: deviceID, environment: environment)
            DebugLogger.shared.log("APNs-Gerät registriert", category: "Push")
        } catch {
            DebugLogger.shared.log("APNs-Gerät: \(error.localizedDescription)", category: "Push")
        }
    }

    func queuePresenceUpload(force: Bool = false) {
        queuedPresenceTask?.cancel()
        let delay = force ? 0.0 : max(0, 8 - Date.now.timeIntervalSince(lastPresenceUpload))
        queuedPresenceTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.uploadPresence()
        }
    }

    func uploadPresence() async {
        guard phase == .authenticated else { return }
        var payload = PresencePayload()
        if location.sharingEnabled, let value = location.lastLocation {
            payload.latitude = value.coordinate.latitude
            payload.longitude = value.coordinate.longitude
            payload.horizontalAccuracy = value.horizontalAccuracy
            payload.altitude = value.altitude
            payload.speed = value.speed >= 0 ? value.speed : nil
            payload.course = value.course >= 0 ? value.course : nil
            payload.locationTimestamp = value.timestamp.rjISO8601
        }
        payload.locationSharing = location.sharingEnabled
        payload.batteryLevel = deviceStatus.batteryLevel
        payload.batteryState = deviceStatus.batteryState
        payload.lowPowerMode = deviceStatus.lowPowerMode
        payload.networkType = deviceStatus.networkType
        payload.wifiName = shareWiFiName ? deviceStatus.wifiName : nil
        payload.focusActive = shareFocus ? deviceStatus.focusActive : nil
        payload.motion = deviceStatus.motion
        if health.sharingEnabled {
            payload.steps = health.steps
            payload.sleepMinutes = health.sleepMinutes
            payload.sleepScore = health.sleepScore
            payload.healthUpdatedAt = health.lastUpdated?.rjISO8601
        }
        payload.statusMessage = statusMessage
        payload.deviceName = UIDevice.current.model
        payload.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        do {
            try await api.postPresence(payload)
            lastPresenceUpload = .now
        } catch {
            DebugLogger.shared.log("Status-Upload: \(error.localizedDescription)", category: "Server")
        }
    }

    private func configureCallbacks() {
        location.onLocation = { [weak self] _ in
            Task { @MainActor in self?.queuePresenceUpload() }
        }
        location.onGeofenceEvent = { [weak self] id, name, event in
            Task { @MainActor in
                guard let self else { return }
                try? await self.api.sendGeofenceEvent(id: id, name: name, event: event)
                await self.syncNow(showErrors: false)
            }
        }
        deviceStatus.onMeaningfulChange = { [weak self] in
            Task { @MainActor in self?.queuePresenceUpload() }
        }
    }

    private func restoreSession() {
        guard let profile, let url = Self.normalizedServerURL(profile.baseURL),
              let token = KeychainStore.get(Self.tokenKey) else {
            phase = .setup
            connectionMessage = "Server einrichten"
            return
        }
        api.configure(baseURL: url, token: token)
        if let cached = AppCache.load(matching: profile) {
            apply(cached)
        }
        phase = .authenticated
        connectionMessage = lastSync == nil ? "Gespeicherte Sitzung" : "Offline-Daten geladen · synchronisiere …"
    }

    private func observeSystemEvents() {
        notificationTasks.append(Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .rjDeviceTokenReceived) {
                guard let token = notification.object as? String else { continue }
                await self?.registerDeviceToken(token)
            }
        })
        notificationTasks.append(Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .rjRemoteSyncRequested) {
                let success = await self?.syncNow(showErrors: false) ?? false
                if let completion = notification.object as? (UIBackgroundFetchResult) -> Void {
                    completion(success ? .newData : .failed)
                }
            }
        })
    }

    private func startPolling() {
        guard phase == .authenticated else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.syncNow(showErrors: false)
            }
        }
    }

    private func process(_ commands: [RemoteCommand], events: [RemoteEvent]) async {
        for event in events {
            await notifications.scheduleLocal(event: event)
            try? await api.acknowledgeEvent(id: event.id)
        }
        for command in commands {
            let sender = partners.first(where: { $0.id == command.ownerID })?.displayName ?? "Schatzi"
            do {
                try await alarms.schedule(command: command, senderName: sender)
            } catch {
                await notifications.scheduleLocal(
                    event: RemoteEvent(
                        id: command.id,
                        kind: "wake_fallback",
                        title: "Weckruf von \(sender) 💗",
                        body: command.payload.message,
                        createdAt: command.createdAt
                    )
                )
                DebugLogger.shared.log("Weckruf-Fallback: \(error.localizedDescription)", category: "Alarm")
            }
            try? await api.acknowledgeCommand(id: command.id)
        }
    }

    private func scheduleSharedReminders() async {
        guard let myID = me?.id else { return }
        await alarms.reconcile(
            reminders: reminders,
            myID: myID,
            senderName: partner?.displayName ?? "Schatzi"
        )
    }

    private func drainWidgetThoughts() async {
        var sent = 0
        while WidgetSharedStore.pendingThoughts() > 0, sent < 20 {
            do {
                let response = try await api.sendThought()
                if let myID = me?.id { thoughts[myID] = response.count }
                _ = WidgetSharedStore.consumeOnePendingThought()
                sent += 1
            } catch {
                break
            }
        }
    }

    private func updateWidgetSnapshot() {
        let value = WidgetSnapshot(
            partnerName: partner?.displayName ?? "Schatzi",
            partnerBattery: partner?.presence?.batteryLevel,
            partnerBatteryState: partner?.presence?.batteryState,
            partnerNetwork: partner?.presence?.networkType,
            partnerMotion: partner?.presence?.motion,
            partnerLastSeen: partner?.presence?.updatedAt ?? partner?.presence?.reportedAt,
            myThoughts: myThoughtCount,
            partnerThoughts: partnerThoughtCount,
            lastSync: Date.now.rjISO8601
        )
        WidgetSharedStore.saveSnapshot(value)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "rjlove" else { return }
        switch url.host?.lowercased() {
        case "map": selectedTab = .map
        case "together": selectedTab = .together
        case "moments": selectedTab = .moments
        case "settings": selectedTab = .settings
        default: selectedTab = .home
        }
    }

    private func updateLiveActivity() async {
        guard liveActivity.isRunning else { return }
        await liveActivity.update(
            battery: partner?.presence?.batteryLevel,
            motion: partner?.presence?.motion ?? "Unbekannt",
            mine: myThoughtCount,
            partner: partnerThoughtCount
        )
    }

    private func synchronizeGeofences() {
        guard let myID = me?.id else { return }
        let places = geofences.compactMap { record -> MonitoredLovePlace? in
            let payload = record.payload
            guard payload.targetID == nil || payload.targetID == myID,
                  let latitude = payload.latitude,
                  let longitude = payload.longitude else { return nil }
            return MonitoredLovePlace(
                id: record.id,
                name: payload.name ?? "Gemeinsamer Ort",
                latitude: latitude,
                longitude: longitude,
                radius: payload.radius ?? 100,
                notifyOnEnter: payload.notifyOnEnter ?? true,
                notifyOnExit: payload.notifyOnExit ?? true
            )
        }
        location.synchronizeGeofences(places)
    }

    private func apply(_ cached: CachedAppSnapshot) {
        me = cached.me
        partners = cached.partners
        records = cached.records
        thoughts = cached.localDay == WidgetSharedStore.localDayStamp() ? cached.thoughts : [:]
        storageUsedBytes = cached.storageUsedBytes
        features = cached.features
        lastSync = cached.lastSync
        serverLocalDay = cached.localDay
        synchronizeGeofences()
        updateWidgetSnapshot()
    }

    private func persistCache() {
        guard let profile, let me, let features, let lastSync else { return }
        AppCache.save(
            CachedAppSnapshot(
                profile: profile,
                localDay: serverLocalDay,
                me: me,
                partners: partners,
                records: records,
                thoughts: thoughts,
                storageUsedBytes: storageUsedBytes,
                features: features,
                lastSync: lastSync
            )
        )
    }

    private var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: Self.deviceIDKey) { return existing }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: Self.deviceIDKey)
        return value
    }

    static func normalizedServerURL(_ input: String) -> URL? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") { value = "http://\(value)" }
        guard let components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil,
              let url = components.url else { return nil }
        return url
    }

    private static func loadProfile() -> ServerProfile? {
        guard let data = UserDefaults.standard.data(forKey: profileKey) else { return nil }
        return try? JSONDecoder().decode(ServerProfile.self, from: data)
    }

    private static func saveProfile(_ profile: ServerProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }
}
