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
    var homeLayout = HomeLayout.standard
    var homeRevision = 0
    var selectedTab: AppTab = .home
    var experienceSection: ExperienceSection = .farts
    var showingFartRecorder = false
    var quickFartRecording = false
    private(set) var farts: [FartClip] = []
    var fartArchiveVisible = false
    private(set) var loadingFartArchive = false
    var alert: AppAlert?
    var showingChangelog = false
    var showingProfile = false
    var showingPartnerProfile = false
    var showingCountdowns = false
    var activity:[String:PartnerActivity] = [:]
    var showingStatus = false
    var showingHealthUpgrade = false
    var showingEvening = false
    private var eveningPresentedDay=Date.now
    var pendingSweet: SharedRecord?
    var pendingPhotoRequest: SharedRecord?
    private(set) var sendingPhotoRequest=false
    private(set) var recallingPhotoRequest=false
    var outgoingPhotoRequest:SharedRecord? {records.first{$0.kind == .photo_request && $0.ownerID==me?.id && $0.payload.completed != true}}
    var storageByUser: [String:Int] = [:]
    var thoughtHistory: [ThoughtEvent] = []
    var lastOpened: [String:String] = [:]
    var openedRecords: [OpenedRecord] = []
    private var lastHealthRefresh = Date.distantPast
    private var activating = false
    private var archiveKinds:Set<RecordKind> = []

    var myStatus: PresencePayload?
    var statusMessage: String {
        didSet { UserDefaults.standard.set(statusMessage, forKey: "rjlove.status-message") }
    }
    var shareWiFiName: Bool {
        didSet { UserDefaults.standard.set(shareWiFiName, forKey: "rjlove.share-wifi-name") }
    }

    let setupJourney = SetupJourney()
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
        return synchronized + WidgetSharedStore.pendingThoughtsToday()
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
        guard UIApplication.shared.applicationState == .active, !activating else { return }
        activating = true; defer { activating = false }
        acceptQuickCaptureRequest()
        nearby.resumeForeground()
        if phase == .authenticated { try? await api.recordAppOpen() }
        if health.sharingEnabled { await health.refresh(force:true); lastHealthRefresh = .now }

        if profile != nil {
            do { try await api.checkCompatibility() }
            catch { connectionMessage = error.localizedDescription; return }
        }
        guard !isActivated else {
            startPolling()
            await syncNow(showErrors: false)
            offerForegroundMoments()
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
        observeSystemEvents()
        startPolling()
        await scheduleSharedReminders()
        await syncNow(showErrors: false)
        offerForegroundMoments()
    }

    func deactivateForeground() {
        if phase == .authenticated {Task {try? await api.reportActivity(mode:"inactive")}}
        location.enterBackground()
        studio.finishRecording()
        studio.stopPlayback()
        nearby.enterBackground(api: api)
        VoiceNoteService.shared.stop()
        pollTask?.cancel()
        pollTask = nil
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
            offerForegroundMoments()
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
        nearby.stop(api: api)
        await liveActivity.stop()
        await api.logout()
        KeychainStore.delete(Self.tokenKey)
        phase = .setup
        me = nil
        activity=[:]
        partners = []
        homeLayout = .standard; homeRevision = 0
        records = []; archiveKinds=[];thoughtHistory=[];lastOpened=[:];openedRecords=[];storageByUser=[:]
        farts = []
        studio.discard()
        showingFartRecorder = false
        showingEvening=false
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
            if let server=profile?.baseURL{LocalFartStore.shared.configure(server:server,userID:snapshot.me.id)}
            setupJourney.check(profile: profile, userID: snapshot.me.id)
            partners = snapshot.partners
            activity = snapshot.activity ?? [:]
            myStatus = snapshot.myPresence
            if let preferences = snapshot.preferences { applyPreferences(preferences) }
            let snapshotIDs=Set(snapshot.records.map(\.id));let deleted=Set(snapshot.deletedRecordIDs ?? [])
            let history=records.filter{archiveKinds.contains($0.kind) && !snapshotIDs.contains($0.id) && !deleted.contains($0.id)}
            records = snapshot.records + history
            dismissRecalledPhotoRequest()
            if fartArchiveVisible { farts = try await api.loadFartArchive() }
            else { farts = snapshot.farts ?? [] }
            thoughts = snapshot.thoughts
            serverLocalDay = snapshot.localDay
            storageUsedBytes = snapshot.storageUsedBytes
            storageByUser = snapshot.storageByUser ?? [:]
            thoughtHistory = snapshot.thoughtHistory ?? []
            lastOpened = snapshot.lastOpened ?? [:]
            openedRecords = snapshot.openedRecords ?? []
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
            if health.sharingEnabled, Date.now.timeIntervalSince(lastHealthRefresh)>60 { await health.refresh(); lastHealthRefresh = .now }
            queuePresenceUpload(force: true)
            await PlannerService.shared.reconcile(app: self)
            if !setupJourney.presented, !showingFartRecorder, pendingSweet==nil,pendingPhotoRequest==nil,UserDefaults.standard.string(forKey:"rjlove.changelog-seen") != RJVersion.app { showingChangelog = true }
            offerForegroundMoments()
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
        if quick, !studio.hasRecording {
            do { try studio.parkDraftForEmergency() }
            catch { alert=AppAlert(title:"Dein Entwurf bleibt sicher",message:"Es wartet bereits ein Notfall-Entwurf. Sende oder verwerfe ihn zuerst im Recorder."); showingFartRecorder=true; return }
        }
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
        catch { if !Task.isCancelled && !(error is CancellationError) { alert = AppAlert(title: "Archiv konnte nicht geladen werden", message: error.localizedDescription) } }
    }
    private func receiveFart(_ clip: FartClip) {
        farts.removeAll { $0.id == clip.id }; farts.insert(clip, at: 0)
        farts.sort { $0.createdAt > $1.createdAt }
        persistCache()
    }
    func shareFart(title: String, caption: String, category: String, includeLocation: Bool = true, situation: String = "alltag") async -> Bool {
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
            updateWidgetSnapshot()
            if kind == .reminder { await scheduleSharedReminders() }; if [.calendar,.milestone,.reminder].contains(kind) { await PlannerService.shared.reconcile(app: self) }
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
            updateWidgetSnapshot()
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
        let interval:Double = UIApplication.shared.applicationState == .active ? 8:30
        let delay = force ? 0.0 : max(0, interval - Date.now.timeIntervalSince(lastPresenceUpload))
        queuedPresenceTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.uploadPresence()
        }
    }

    func setStatus(text: String, hours: Int, quiet: Bool) async -> Bool {
        do {
            let duration=min(8,max(0,hours))
            let deadline=duration>0 ? Date.now.addingTimeInterval(Double(duration)*3600).rjISO8601 : ""
            let body=["status_message":String(text.prefix(120)), "status_expires_at":deadline, "dnd_until":quiet ? (deadline.isEmpty ? Date.now.addingTimeInterval(28800).rjISO8601:deadline):""]
            _ = try await api.execute(try api.request(path:"/v1/status",method:"POST",body:JSONEncoder().encode(body)),as:EmptyResponse.self)
            statusMessage=text
            _ = await syncNow(showErrors:false)
            return true
        } catch { alert=AppAlert(title:"Status nicht geteilt",message:error.localizedDescription); return false }
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
        payload.motionConfidence=deviceStatus.motionConfidence
        payload.motionUpdatedAt=deviceStatus.motionUpdatedAt?.rjISO8601
        if health.sharingEnabled {
            payload.steps = health.shareActivity ? health.steps : nil
            payload.sleepMinutes = health.shareSleep ? health.sleepMinutes : nil
            payload.sleepScore = health.shareSleep ? health.sleepScore : nil
            payload.healthMetrics = health.sharedMetrics
            payload.healthMetricDates = health.sharedMetricDates
            payload.sleepSummary = health.shareSleep ? health.sleepSummary:nil
            payload.healthUpdatedAt = health.lastUpdated?.rjISO8601
        }
        payload.appState = UIApplication.shared.applicationState == .active ? "foreground":"background"
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

    func didReadChangelog() {
        UserDefaults.standard.set(RJVersion.app,forKey:"rjlove.changelog-seen")
        showingChangelog = false
    }
    func offerForegroundMoments() {
        guard UIApplication.shared.applicationState == .active, !showingChangelog, !showingProfile, !showingPartnerProfile, !showingCountdowns, !showingStatus, !showingHealthUpgrade, !showingEvening, myStatus?.isQuiet != true, !setupJourney.presented, !showingFartRecorder, pendingSweet == nil, pendingPhotoRequest == nil else { return }
        let defaults = UserDefaults.standard
        if defaults.string(forKey:"rjlove.changelog-seen") != RJVersion.app {showingChangelog=true;return}
        if health.needsExpandedAccess {showingHealthUpgrade=true;return}
        if defaults.object(forKey:"rjlove.sweet-autoplay") == nil || defaults.bool(forKey:"rjlove.sweet-autoplay") {
            pendingSweet = records.filter { $0.kind == .chat && $0.ownerID != me?.id && $0.payload.autoplay == true }.sorted { $0.createdAt < $1.createdAt }.first { record in !openedRecords.contains { $0.recordID == record.id && $0.userID == me?.id } && !defaults.bool(forKey:"rjlove.opened."+record.id) }
        }
        if pendingSweet == nil, defaults.object(forKey:"rjlove.instant-enabled") == nil || defaults.bool(forKey:"rjlove.instant-enabled") {
            pendingPhotoRequest = records.first { $0.kind == .photo_request && $0.payload.targetID == me?.id && $0.payload.completed != true && !defaults.bool(forKey:"rjlove.photo-skip."+$0.id) }
        }
        if pendingSweet==nil,pendingPhotoRequest==nil,selectedTab == .home,
           UserDefaults.standard.object(forKey:"rjlove.evening-auto") == nil || UserDefaults.standard.bool(forKey:"rjlove.evening-auto"),
           Calendar.current.component(.hour,from:.now)>=19,
           UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).flatMap(\.windows).first(where:{$0.isKeyWindow})?.rootViewController?.presentedViewController == nil,
           UserDefaults.standard.string(forKey:eveningSeenKey) != JournalDates.key(.now) {
            eveningPresentedDay = .now;showingEvening=true
        }
    }
    private var eveningSeenKey:String {"rjlove.evening-seen."+(profile?.baseURL ?? "")+"."+(me?.id ?? "")}
    func didCloseEvening(){UserDefaults.standard.set(JournalDates.key(eveningPresentedDay),forKey:eveningSeenKey);offerForegroundMoments()}
    func applyPreferences(_ value: UserPreferences) {
        homeLayout = value.dashboard; homeRevision = value.revision
        if let profile, let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: "rjlove.home-layout." + profile.baseURL + "." + profile.username)
        }
    }
    func refreshPhotoRequests() async throws -> PhotoRequestState {
        let state=try await api.photoRequestState()
        records.removeAll{$0.kind == .photo_request && $0.payload.completed != true}
        if let outgoing=state.outgoing {records.removeAll{$0.id==outgoing.id};records.append(outgoing)}
        for request in state.incoming {records.removeAll{$0.id==request.id};records.append(request)}
        dismissRecalledPhotoRequest();persistCache();return state
    }
    private func dismissRecalledPhotoRequest() {
        if let pendingPhotoRequest,!records.contains(where:{$0.id==pendingPhotoRequest.id && $0.kind == .photo_request && $0.payload.completed != true}) {self.pendingPhotoRequest=nil}
    }
    func requestPhoto(title: String, id: String) async -> Bool {
        guard !sendingPhotoRequest else{return false}
        guard outgoingPhotoRequest==nil else{alert=AppAlert(title:"Ein Fotowunsch wartet schon",message:"Lass deinen offenen Wunsch beantworten oder rufe ihn zuerst zurück.");return false}
        sendingPhotoRequest=true;defer{sendingPhotoRequest=false}
        do {
            let photoRequest = try await api.createPhotoRequest(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
            records.removeAll { $0.id == photoRequest.id }; records.insert(photoRequest, at: 0)
            persistCache(); return true
        } catch {
            if case APIClientError.server(status:409,message:_) = error {_ = try? await refreshPhotoRequests()}
            alert = AppAlert(title: "Fotowunsch", message: error.localizedDescription)
            return false
        }
    }
    func recallPhotoRequest(_ request:SharedRecord) async -> Bool {
        guard !recallingPhotoRequest,request.ownerID==me?.id else{return false}
        recallingPhotoRequest=true;defer{recallingPhotoRequest=false}
        do {
            try await api.recallPhotoRequest(id:request.id)
            records.removeAll{$0.id==request.id};dismissRecalledPhotoRequest();persistCache();Haptics.success();return true
        }catch{
            _ = try? await refreshPhotoRequests()
            alert=AppAlert(title:"Fotowunsch zurückrufen",message:error.localizedDescription);return false
        }
    }
    func receiveInstantPhoto(_ photo: SharedRecord, requestID: String) {
        records.removeAll { $0.id == photo.id }; records.insert(photo, at: 0)
        if let index = records.firstIndex(where: { $0.id == requestID }) { records[index].payload.completed = true }
        persistCache()
    }
    func markOpened(_ record: SharedRecord) async {
        UserDefaults.standard.set(true,forKey:"rjlove.opened."+record.id)
        try? await api.markOpened(id:record.id)
    }
    func loadRecordArchive(kind: RecordKind) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview"), !ProcessInfo.processInfo.arguments.contains("--ui-test-server"){return}
        #endif
        do {
            let archive = try await api.recordArchive(kind:kind)
            records.removeAll { $0.kind == kind }; records += archive;archiveKinds.insert(kind)
        } catch { if !Task.isCancelled { alert = AppAlert(title:"Archiv",message:error.localizedDescription) } }
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
        if let data = UserDefaults.standard.data(forKey: "rjlove.home-layout." + profile.baseURL + "." + profile.username),
           let preferences = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            homeLayout = preferences.dashboard; homeRevision = preferences.revision
        }
        if let cached = AppCache.load(matching: profile) {
            apply(cached)
        }
        phase = .authenticated
        connectionMessage = lastSync == nil ? "Gespeicherte Sitzung" : "Offline-Daten geladen · synchronisiere …"
    }

    func acceptQuickCaptureRequest(){
        guard phase == .authenticated else {return}
        if let route=WidgetSharedStore.defaults.string(forKey:"rjlove.route-requested"),let url=URL(string:route) {
            WidgetSharedStore.defaults.removeObject(forKey:"rjlove.route-requested");handleDeepLink(url)
        }
        if let values=WidgetSharedStore.defaults.dictionary(forKey:"rjlove.status-requested"),let text=values["text"] as? String {
            WidgetSharedStore.defaults.removeObject(forKey:"rjlove.status-requested")
            Task { _ = await setStatus(text:text,hours:values["hours"] as? Int ?? 2,quiet:values["quiet"] as? Bool ?? false) }
        }
        if phase == .authenticated,WidgetSharedStore.defaults.bool(forKey:"rjlove.quick-fart-requested") {
            WidgetSharedStore.defaults.set(false,forKey:"rjlove.quick-fart-requested")
            handleDeepLink(URL(string:"rjlove://record-fart")!)
        }
    }
    private func observeSystemEvents() {
        notificationTasks.append(Task{[weak self] in for await _ in NotificationCenter.default.notifications(named:Notification.Name("rjEmergencyFartRequested")){self?.acceptQuickCaptureRequest()}})

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
            if event.kind != "push_test", myStatus?.isQuiet != true { await notifications.scheduleLocal(event: event) }
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
                guard let pending = WidgetSharedStore.nextPendingThought() else{break}
                let response = try await api.sendThought(id:pending.id, occurredAt:pending.occurredAt)
                if response.day == serverLocalDay, let myID = me?.id { thoughts[myID] = max(thoughts[myID] ?? 0,response.count) }
                if let id=response.id,let received=response.receivedAt,!thoughtHistory.contains(where:{$0.id==id}) {thoughtHistory.insert(ThoughtEvent(id:id,userID:me?.id ?? "",occurredAt:response.occurredAt,receivedAt:received),at:0)}
                _ = WidgetSharedStore.consumePendingThought(id:pending.id)
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
        let countdowns=records.compactMap{LoveCountdown(record:$0)}.sorted{($0.nextDate() ?? .distantFuture)<($1.nextDate() ?? .distantFuture)}
        value.countdowns=countdowns
        let featured=countdowns.first{$0.anniversary} ?? countdowns.first
        value.milestoneTitle=featured?.title
        value.milestoneDate=featured?.nextDate()?.rjISO8601
        WidgetSharedStore.saveSnapshot(value)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "rjlove" else { return }
        switch url.host?.lowercased() {
        case "stop-nearby": nearby.stop(api: api)
        case "map": selectedTab = .map
        case "together": selectedTab = .together
        case "moments": selectedTab = .moments; experienceSection = .moments
        case "farts": selectedTab = .moments; experienceSection = .farts
        case "dates": selectedTab = .moments; experienceSection = .love
        case "record-fart":
            selectedTab = .moments; experienceSection = .farts
            openFartRecorder(quick:true)
        case "stop-recording":
            studio.finishRecording()
            selectedTab = .moments; experienceSection = .farts
            quickFartRecording = false; showingFartRecorder = true
        case "radio", "messenger": selectedTab = .together
        case "settings", "health": selectedTab = .home; showingProfile=true
        case "countdowns": selectedTab = .home;showingCountdowns=true
        case "partner": selectedTab = .home;showingPartnerProfile=true
        case "status": selectedTab = .home; showingStatus=true
        case "bereal": selectedTab = .moments; experienceSection = .moments
        default: selectedTab = .home
        }
    }

    func startLiveActivity() async {
        do {
            try await liveActivity.start(partnerName:partner?.displayName ?? "Schatzi",battery:partner?.presence?.batteryLevel,motion:partner?.presence?.motion ?? "Noch kein Status",mine:myThoughtCount,partner:partnerThoughtCount,updatedAt:partner?.presence?.updatedAt?.rjDate,status:partner?.presence?.visibleStatus,quietUntil:partner?.presence?.dndUntil?.rjDate)
        }catch {alert=AppAlert(title:"Live-Aktivität",message:error.localizedDescription)}
    }

    private func updateLiveActivity() async {
        if liveActivity.enabled, liveActivity.automaticallyResume, !liveActivity.isRunning, UIApplication.shared.applicationState == .active {
            await startLiveActivity()
        }
        guard liveActivity.isRunning else { return }
        await liveActivity.update(
            battery: partner?.presence?.batteryLevel,
            motion: partner?.presence?.motion ?? "Unbekannt",
            mine: myThoughtCount,
            partner: partnerThoughtCount,
            updatedAt: partner?.presence?.updatedAt?.rjDate,
            status: partner?.presence?.visibleStatus,
            quietUntil: partner?.presence?.dndUntil?.rjDate
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
        LocalFartStore.shared.configure(server:cached.profile.baseURL,userID:cached.me.id)
        partners = cached.partners
        activity = cached.activity ?? [:]
        lastOpened = cached.lastOpened ?? [:]
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
                activity:activity,
                lastOpened:lastOpened,
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
        homeLayout = .standard; homeRevision = 0
        if ProcessInfo.processInfo.arguments.contains("--preview-empty-recorder") { studio.discard() }
        for kind in ["old","future"] where ProcessInfo.processInfo.arguments.contains("--preview-"+kind+"-server") {
            api.configure(baseURL: URL(string: "http://127.0.0.1:8787/"+kind)!,token:nil)
            Task { try? await api.checkCompatibility() }
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-draft") { studio.preparePreviewDraft() }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-server") { profile=ServerProfile(baseURL:"http://127.0.0.1:8787",username:"robin");api.configure(baseURL: URL(string: "http://127.0.0.1:8787")!, token: "ui-test-token") }
        phase = .authenticated
        me = UserProfile(id: "robin", displayName: "Robin", accent: "cyan", storageLimitMB: 0)
        var presence = PresencePayload()
        presence.batteryLevel = 82; presence.batteryState = "unplugged"
        presence.motion = "Zu Fuß"; presence.statusMessage = "Mit dir ist jeder Tag ein bisschen schöner."
        presence.steps = 6840; presence.sleepMinutes = 462; presence.sleepScore = 96
        presence.updatedAt = Date.now.rjISO8601; presence.healthUpdatedAt = Date.now.rjISO8601
        presence.healthMetrics = ["distance_km": 4.6, "active_kcal": 318, "heart_rate": 72, "resting_heart_rate": 61, "hrv_ms": 48, "exercise_minutes": 24, "flights": 7, "oxygen_percent": 98, "respiratory_rate": 15]
        partners = [PartnerSnapshot(id: "raphaela", displayName: "Raphaela", accent: "pink", storageLimitMB: 0, presence: presence)]
        if ProcessInfo.processInfo.arguments.contains("--ui-test-server") {
            Task { if let value = try? await api.preferences() { applyPreferences(value) } }
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-instant-camera") {
            pendingPhotoRequest = SharedRecord(id: "CA82F1DB-2379-4A43-8AD0-24AB34D089CE", kind: .photo_request, ownerID: "raphaela", payload: RecordPayload(title: "Bitte lächeln · UI", targetID: "robin", completed: false), createdAt: Date.now.rjISO8601, updatedAt: Date.now.rjISO8601)
        }
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
