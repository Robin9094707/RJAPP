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
    var experienceSection: ExperienceSection = .farts
    var showingFartRecorder = false
    var showingRadio = false
    var quickFartRecording = false
    private(set) var farts: [FartClip] = []
    var fartArchiveVisible = false
    private(set) var loadingFartArchive = false
    var alert: AppAlert?
    var statusMessage: String {
        didSet { UserDefaults.standard.set(statusMessage, forKey: "rjlove.status-message") }
    }
    var shareWiFiName: Bool {
        didSet { UserDefaults.standard.set(shareWiFiName, forKey: "rjlove.share-wifi-name") }
    }

    let setupJourney = SetupJourney()
    let radio = WalkieTalkieService.shared
    let studio = AudioStudioService.shared
    let api = APIClient()
    let nearby = NearbyService()
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
        profile = Self.loadProfile()
        configureCallbacks()
        restoreSession()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { loadPreview() }
        #endif
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { return }
        #endif
        guard UIApplication.shared.applicationState == .active else { return }
        if profile != nil {
            do { try await api.checkCompatibility() }
            catch { connectionMessage = error.localizedDescription; return }
        }
        if privacyLock.isEnabled, !privacyLock.isUnlocked {
            _ = await privacyLock.unlock()
        }
        guard !isActivated else {
            await radio.restoreIfEnabled(api: api)
            startPolling()
            await syncNow(showErrors: false)
            return
        }
        isActivated = true
        liveActivity.restorePushObservers()
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
        BackgroundRefreshCoordinator.shared.schedule()
        await radio.restoreIfEnabled(api: api)
        observeSystemEvents()
        startPolling()
        await scheduleSharedReminders()
        await syncNow(showErrors: false)
    }

    func deactivateForeground() {
        studio.finishRecording()
        studio.stopPlayback()
        radio.enterBackground()
        nearby.stop(api: api)
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
            try await api.checkCompatibility()
            let response = try await api.login(username: newProfile.username, password: password, deviceID: deviceID)
            try KeychainStore.set(response.token, for: Self.tokenKey)
            if profile != newProfile {
                AppCache.clear()
                health.sharingEnabled = false
                health.shareActivity = false; health.shareSleep = false; health.shareVitals = false
                location.sharingEnabled = false
                WidgetSharedStore.clearPendingThoughts()
                WidgetSharedStore.saveSnapshot(WidgetSnapshot())
                UserDefaults.standard.removeObject(forKey: "rjlove.chat-draft")
            }
            profile = newProfile
            Self.saveProfile(newProfile)
            me = response.user
            api.configure(baseURL: url, token: response.token)
            phase = .authenticated
            connectionMessage = "Verbunden"
            DebugLogger.shared.log("Anmeldung erfolgreich", category: "Server")
            await syncNow(showErrors: true)
            if let token = UserDefaults.standard.string(forKey: NotificationCoordinator.deviceTokenKey) { await registerDeviceToken(token) }
            startPolling()
        } catch {
            phase = .setup
            connectionMessage = "Nicht verbunden"
            alert = AppAlert(title: "Anmeldung fehlgeschlagen", message: error.localizedDescription)
            DebugLogger.shared.log("Anmeldung fehlgeschlagen: \(error.localizedDescription)", category: "Server")
        }
    }

    func logout() async {
        radio.disable()
        nearby.stop(api: api)
        await liveActivity.stop()
        await api.logout()
        KeychainStore.delete(Self.tokenKey)
        phase = .setup
        me = nil
        partners = []
        records = []
        farts = []
        studio.discard()
        showingFartRecorder = false
        thoughts = [:]
        UserDefaults.standard.removeObject(forKey: "rjlove.chat-draft")
        queuedPresenceTask?.cancel()
        location.stop()
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
            try await api.checkCompatibility()
            let snapshot = try await api.bootstrap()
            me = snapshot.me
            setupJourney.check(profile: profile, userID: snapshot.me.id)
            partners = snapshot.partners
            records = snapshot.records
            if fartArchiveVisible { farts = try await api.loadFartArchive() }
            else { farts = snapshot.farts ?? [] }
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
        } catch let issue as UpdateRequirement {
            connectionMessage = issue.localizedDescription
            return false
        } catch let error as APIClientError {
            if case .server(let status, _) = error, status == 401 {
                await logout()
                connectionMessage = "Auf einem anderen Gerät angemeldet oder Zugang geändert."
                return false
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

    func openFartRecorder(quick: Bool = false) {
        radio.pauseForStudio()
        quickFartRecording = quick
        showingFartRecorder = true
    }
    func loadFartArchive() async {
        guard !loadingFartArchive else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview") { return }
        #endif
        loadingFartArchive = true; defer { loadingFartArchive = false }
        do { farts = try await api.loadFartArchive() }
        catch { if !(error is CancellationError) { alert = AppAlert(title: "Archiv konnte nicht geladen werden", message: error.localizedDescription) } }
    }
    private func receiveFart(_ clip: FartClip) {
        farts.removeAll { $0.id == clip.id }; farts.insert(clip, at: 0)
        farts.sort { $0.createdAt > $1.createdAt }
        persistCache()
    }
    func shareFart(title: String, caption: String, category: String, includeLocation: Bool = false, situation: String = "alltag") async -> Bool {
        do {
            guard let draft = studio.draft else { return false }
            guard draft.ownerID == me?.id else { studio.discard(); return false }
            let data = try Data(contentsOf: draft.url)
            let body = FartUpload(id: draft.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ein kleines Meisterwerk" : title, caption: caption, category: category, duration: draft.duration, waveform: draft.waveform, recordedAt: draft.recordedAt, location: includeLocation ? draft.location : nil, situation: situation, audioBase64: data.base64EncodedString())
            receiveFart(try await api.uploadFart(body))
            studio.discard(); Haptics.success()
            return true
        } catch { alert = AppAlert(title: "Duftpost wartet noch", message: error.localizedDescription + " Deine lokale Aufnahme bleibt erhalten."); return false }
    }
    func removeFartLocation(_ clip: FartClip) async {
        do { receiveFart(try await api.removeFartLocation(id: clip.id)) }
        catch { alert = AppAlert(title: "Aufnahmeort entfernen",message: error.localizedDescription) }
    }
    func editFart(_ body: FartUpload) async throws {
        receiveFart(try await api.editFart(body)); studio.stopPlayback(); Haptics.success()
    }
    func rateFart(_ clip: FartClip, overall: Int, power: Int, style: Int, comment: String) async -> Bool {
        do { receiveFart(try await api.rateFart(id: clip.id, overall: overall, power: power, style: style, comment: comment)); Haptics.success(); return true }
        catch { alert = AppAlert(title: "Bewertung", message: error.localizedDescription); return false }
    }
    func reactToFart(_ clip: FartClip, emoji: String) async {
        do { receiveFart(try await api.reactToFart(id: clip.id, emoji: emoji)) }
        catch { alert = AppAlert(title: "Reaktion", message: error.localizedDescription) }
    }
    func deleteFart(_ clip: FartClip) async {
        do { try await api.deleteFart(id: clip.id); farts.removeAll { $0.id == clip.id }; studio.stopPlayback(); persistCache() }
        catch { alert = AppAlert(title: "Löschen", message: error.localizedDescription) }
    }

    func sendWake(message: String, dueAt: Date = .now.addingTimeInterval(2)) async -> Bool {
        guard let partner else { return false }
        do {
            _ = try await api.sendWake(targetID: partner.id, message: message, dueAt: dueAt)
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
            let environment = SigningProfile.current.pushEnvironment
            try await api.registerDevice(token: token, deviceID: deviceID, environment: environment)
            PushRegistrationStatus.shared.error = nil
            DebugLogger.shared.log("APNs-Gerät registriert", category: "Push")
        } catch {
            PushRegistrationStatus.shared.error = error.localizedDescription
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
        payload.motion = deviceStatus.motion
        if health.sharingEnabled {
            payload.steps = health.shareActivity ? health.steps : nil
            payload.sleepMinutes = health.shareSleep ? health.sleepMinutes : nil
            payload.sleepScore = health.shareSleep ? health.sleepScore : nil
            payload.healthMetrics = health.sharedMetrics
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
        liveActivity.onPushToken = { [weak self] id, token in
            guard let self, self.phase == .authenticated else { return }
            do { try await self.api.registerLiveActivity(id: id, token: token, environment: SigningProfile.current.pushEnvironment) }
            catch { DebugLogger.shared.log("Live-Push: \(error.localizedDescription)", category: "Push") }
        }
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
        radio.configure(api: api)
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
            // A push test must only arrive through APNs. A poll-generated local
            // notification would falsely suggest that signing/server push works.
            if event.kind != "push_test" { await notifications.scheduleLocal(event: event) }
            try? await api.acknowledgeEvent(id: event.id)
        }
        await CommandDeliveryProcessor.shared.process(commands, api: api, senderName: partner?.displayName ?? "Schatzi")
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
        var value = WidgetSnapshot(
            partnerName: partner?.displayName ?? "Schatzi",
            partnerBattery: partner?.presence?.batteryLevel,
            partnerBatteryState: partner?.presence?.batteryState,
            partnerNetwork: partner?.presence?.networkType,
            partnerMotion: partner?.presence?.motion,
            partnerLastSeen: partner?.presence?.updatedAt ?? partner?.presence?.reportedAt,
            myThoughts: myThoughtCount,
            partnerThoughts: partnerThoughtCount,
            lastSync: lastSync?.rjISO8601
        )
        value.partnerSteps = partner?.presence?.steps
        value.partnerSleepMinutes = partner?.presence?.sleepMinutes
        let milestone = records.filter { $0.kind == .milestone }.sorted { ($0.payload.startAt ?? "") < ($1.payload.startAt ?? "") }.first
        value.milestoneTitle = milestone?.payload.title
        value.milestoneDate = milestone?.payload.startAt
        WidgetSharedStore.saveSnapshot(value)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "rjlove" else { return }
        switch url.host?.lowercased() {
        case "map": selectedTab = .map
        case "together": selectedTab = .together
        case "moments": selectedTab = .moments; experienceSection = .moments
        case "farts": selectedTab = .moments; experienceSection = .farts
        case "dates": selectedTab = .moments; experienceSection = .love
        case "record-fart":
            radio.pauseForStudio()
            selectedTab = .moments; experienceSection = .farts
            quickFartRecording = true; showingFartRecorder = true
        case "stop-recording":
            studio.finishRecording()
            selectedTab = .moments; experienceSection = .farts
            quickFartRecording = false; showingFartRecorder = true
        case "radio": showingRadio = true
        case "settings", "health": selectedTab = .settings
        default: selectedTab = .home
        }
    }

    private func updateLiveActivity() async {
        guard liveActivity.isRunning else { return }
        await liveActivity.update(
            battery: partner?.presence?.batteryLevel,
            motion: partner?.presence?.motion ?? "Unbekannt",
            mine: myThoughtCount,
            partner: partnerThoughtCount,
            updatedAt: partner?.presence?.updatedAt?.rjDate
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
        farts = cached.farts ?? []
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
                farts: farts,
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

#if DEBUG
extension AppState {
    func loadPreview() {
        if ProcessInfo.processInfo.arguments.contains("--preview-empty-recorder") { studio.discard() }
        for kind in ["old","future"] where ProcessInfo.processInfo.arguments.contains("--preview-"+kind+"-server") {
            api.configure(baseURL: URL(string: "http://127.0.0.1:8787/"+kind)!,token:nil)
            Task { try? await api.checkCompatibility() }
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-draft") { studio.preparePreviewDraft() }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-server") { api.configure(baseURL: URL(string: "http://127.0.0.1:8787")!, token: "ui-test-token") }
        phase = .authenticated
        me = UserProfile(id: "robin", displayName: "Robin", accent: "cyan", storageLimitMB: 0)
        var presence = PresencePayload()
        presence.batteryLevel = 82; presence.batteryState = "unplugged"
        presence.motion = "Zu Fuß"; presence.statusMessage = "Mit dir ist jeder Tag ein bisschen schöner."
        presence.steps = 6840; presence.sleepMinutes = 462; presence.sleepScore = 96
        presence.updatedAt = Date.now.rjISO8601; presence.healthUpdatedAt = Date.now.rjISO8601
        presence.healthMetrics = ["distance_km": 4.6, "active_kcal": 318, "heart_rate": 72, "resting_heart_rate": 61, "hrv_ms": 48, "exercise_minutes": 24, "flights": 7, "oxygen_percent": 98, "respiratory_rate": 15]
        partners = [PartnerSnapshot(id: "raphaela", displayName: "Raphaela", accent: "pink", storageLimitMB: 0, presence: presence)]
        thoughts = ["robin": 4, "raphaela": 7]; lastSync = .now; connectionMessage = "Vorschau"
        let now = Date.now.rjISO8601
        records = [
            SharedRecord(id: UUID().uuidString, kind: .chat, ownerID: "raphaela", payload: RecordPayload(text: "Ich freue mich schon auf dich. 💗"), createdAt: now, updatedAt: now),
            SharedRecord(id: UUID().uuidString, kind: .chat, ownerID: "robin", payload: RecordPayload(text: "Noch einen Spaziergang zusammen, bevor die Sonne untergeht?"), createdAt: now, updatedAt: now),
            SharedRecord(id: UUID().uuidString, kind: .milestone, ownerID: "robin", payload: RecordPayload(title: "Unser nächstes Wochenende", startAt: Date.now.addingTimeInterval(3 * 86400).rjISO8601), createdAt: now, updatedAt: now)
        ]
        farts = [
            FartClip(id: "3D1E7C40-93D7-4947-9C0A-BB8A00110762", ownerID: "raphaela", title: "Ein Hauch von Wochenende", caption: "Klein, aber mit Persönlichkeit.", category: "Liebeslüftchen", duration: 3.2,
                     waveform: (0..<60).map { i in max(0.03, abs(sin(Double(i) * 0.43)) * exp(-abs(Double(i) - 27) / 18)) }, sizeBytes: 32000, createdAt: now,
                     ratings: [FartRating(userID: "robin", overall: 5, power: 3, style: 5, comment: "Ein zartes Meisterwerk. 😂", updatedAt: now)], reactions: [FartReaction(userID: "robin", emoji: "❤️"), FartReaction(userID: "raphaela", emoji: "😂")])
        ]
        for index in 0..<24 {
            let date = Calendar.current.date(byAdding: .day, value: -index*15, to: .now)!
            let categories = FartCategory.allCases
            let point: FartLocation? = index%3 == 0 ? FartLocation(latitude: 51.43+Double(index)*0.0008,longitude:6.76+Double(index)*0.001,accuracy:25,capturedAt:date.rjISO8601) : nil
            farts.append(FartClip(id: UUID().uuidString,ownerID:index%2 == 0 ? "robin" : "raphaela",title:["Ein Hauch von Sonntag","Ninja im Flur","Kleines Abendkonzert","Donner überm Sofa"][index%4],caption:"Ein kleiner Insider für uns zwei.",category:categories[index%categories.count].rawValue,duration:Double(index%8+1),waveform:(0..<35).map { abs(sin(Double($0)*0.4)) },sizeBytes:24000,createdAt:date.rjISO8601,ratings:[],reactions:[],recordedAt:date.rjISO8601,location:point,situation:FartSituation.allCases[index%8].rawValue))
        }
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--preview-fart-") }) { selectedTab = .moments; experienceSection = .farts }
        records.append(SharedRecord(id: UUID().uuidString, kind: .coupon, ownerID: "raphaela", payload: RecordPayload(title: "Eine Massage nur für dich", text: "Mit ganz viel Liebe und ohne auf die Uhr zu schauen.", targetID: "robin", completed: false), createdAt: now, updatedAt: now))
        records.append(SharedRecord(id: UUID().uuidString, kind: .gratitude, ownerID: "raphaela", payload: RecordPayload(title: "Heute mag ich an dir …", text: "Dass ich mit dir über jeden Quatsch lachen kann."), createdAt: now, updatedAt: now))
        if ProcessInfo.processInfo.arguments.contains("--preview-hub") { selectedTab = .together }
        if ProcessInfo.processInfo.arguments.contains("--preview-farts") { selectedTab = .moments; experienceSection = .farts }
        if ProcessInfo.processInfo.arguments.contains("--preview-love") { selectedTab = .moments; experienceSection = .love }
    }
}
#endif
