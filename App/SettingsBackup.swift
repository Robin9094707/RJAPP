import CryptoKit
import Observation
import SwiftUI

struct AppSettingsEnvelope:Codable {
    var values:[String:String]
    var revision:Int
    var updatedAt:String?
}
extension APIClient {
    func appSettings() async throws -> AppSettingsEnvelope {
        try await execute(try request(path:"/v1/settings",method:"GET"),as:AppSettingsEnvelope.self)
    }
    func saveAppSettings(_ value:AppSettingsEnvelope) async throws -> AppSettingsEnvelope {
        try await execute(try request(path:"/v1/settings",method:"POST",body:encoder.encode(value)),as:AppSettingsEnvelope.self)
    }
}

/// Only portable preferences. Credentials, APNs tokens, OS grants and runtime caches are device-specific.
@MainActor @Observable final class SettingsBackup {
    static let shared=SettingsBackup()
    var syncing=false
    var lastSaved:String?
    var error:String?
    private var scope=""
    private var generation=UUID()
    private var baseline:[String:String]=[:]
    private var ready=false
    private static let keys=["rjlove.homekit.enabled","rjlove.homekit.home","rjlove.homekit.camera","rjlove.evening-auto","rjlove.instant-enabled","rjlove.sweet-autoplay","rjlove.keyboard-dismiss-after-send","rjlove.fart-locations","rjlove.live-enabled","rjlove.live-auto-resume","rjlove.live-battery","rjlove.live-thoughts","rjlove.live-status","rjlove.live-action","rjlove.nearby-auto","rjlove.nearby-background","rjlove.sleep-goal-hours","rjlove.location-sharing","rjlove.background-location","rjlove.photo-location","rjlove.health-sharing","rjlove.share-activity","rjlove.share-sleep","rjlove.share-vitals","rjlove.share-wifi-name","rjlove.status-message"]
    private func storageKey(_ key:String)->String {
        switch key {
        case "tv.layout":return "rjlove.tv.layout."+CinemaCoordinator.shared.namespace
        case "cinema.autoJoin":return "rjlove.cinema.autoJoin."+CinemaCoordinator.shared.namespace
        default:return key
        }
    }
    private var allKeys:[String] {Self.keys+["tv.layout","cinema.autoJoin"]}
    private func capture()->[String:String] {
        var result:[String:String]=[:]
        for key in allKeys {
            let value:Any?
            if key == "tv.layout" {value=TVPresentation.shared.encodedLayout()}
            else {value=UserDefaults.standard.object(forKey:storageKey(key))}
            if let value,let bytes=try? PropertyListSerialization.data(fromPropertyList:["value":value],format:.binary,options:0) {result[key]=bytes.base64EncodedString()}
        }
        return result
    }
    func reset() {generation=UUID();scope="";baseline=[:];ready=false;syncing=false;lastSaved=nil;error=nil;HomeCameraSessions.shared.stopAll()}
    func sync(app:AppState) async {
        guard !syncing,let profile=app.profile,let user=app.me?.id,app.phase == .authenticated else {return}
        let account=SHA256.hash(data:Data((profile.baseURL+"|"+user).utf8)).map{String(format:"%02x",$0)}.joined()
        if account != scope {
            scope=account;ready=false;baseline=[:];generation=UUID()
            if let owner=UserDefaults.standard.string(forKey:"rjlove.settings.owner"),owner != account {
                let saved=UserDefaults.standard.data(forKey:"rjlove.settings.local."+account).flatMap {try? JSONDecoder().decode(AppSettingsEnvelope.self,from:$0)}
                restore(saved?.values ?? [:],app:app)
            }
            UserDefaults.standard.set(account,forKey:"rjlove.settings.owner")
            if let data=UserDefaults.standard.data(forKey:"rjlove.settings.baseline."+scope),let saved=try? JSONDecoder().decode(AppSettingsEnvelope.self,from:data) {baseline=saved.values;ready=true;lastSaved=saved.updatedAt}
        }
        let operation=generation
        let local=capture()
        if let data=try? JSONEncoder().encode(AppSettingsEnvelope(values:local,revision:0,updatedAt:nil)) {UserDefaults.standard.set(data,forKey:"rjlove.settings.local."+scope)}
        syncing=true;defer {if generation == operation {syncing=false}}
        do {
            let remote=try await app.api.appSettings()
            guard generation == operation,app.me?.id == user,app.phase == .authenticated else {return}
            // On first install use the server. On upgrades import local settings only when no server backup exists.
            var merged=remote.values
            if ready {
                for key in allKeys where local[key] != baseline[key] {merged[key]=local[key]}
            } else if remote.revision == 0 {merged=local}
            // Read again after await so changes made while the request was in flight are retained.
            let current=capture()
            for key in allKeys where current[key] != local[key] {merged[key]=current[key]}
            if current != merged {restore(merged,app:app)}
            let desired=AppSettingsEnvelope(values:merged,revision:remote.revision,updatedAt:remote.updatedAt)
            // Cache the last acknowledged baseline before POST; unsaved local differences survive an offline restart.
            baseline=remote.values;ready=true;cache(remote)
            let saved:AppSettingsEnvelope
            if merged != remote.values || remote.revision == 0 {saved=try await app.api.saveAppSettings(desired)} else {saved=remote}
            guard generation == operation,app.me?.id == user else {return}
            baseline=saved.values;lastSaved=saved.updatedAt;cache(saved);error=nil
        } catch {if generation == operation {self.error=error.localizedDescription}}
    }
    private func cache(_ value:AppSettingsEnvelope) {
        if let data=try? JSONEncoder().encode(value) {UserDefaults.standard.set(data,forKey:"rjlove.settings.baseline."+scope)}
    }
    private func restore(_ values:[String:String],app:AppState) {
        let defaults=UserDefaults.standard
        for key in allKeys {
            if let encoded=values[key],let data=Data(base64Encoded:encoded),let plist=try? PropertyListSerialization.propertyList(from:data,format:nil),let box=plist as? [String:Any],let value=box["value"] {
                defaults.set(value,forKey:storageKey(key))
            } else {defaults.removeObject(forKey:storageKey(key))}
        }
        if let data=defaults.data(forKey:storageKey("tv.layout")) {TVPresentation.shared.restoreLayout(data)}
        CinemaCoordinator.shared.autoJoin=defaults.object(forKey:storageKey("cinema.autoJoin")) as? Bool ?? true
        app.statusMessage=defaults.string(forKey:"rjlove.status-message") ?? "Bin für dich da 💗"
        app.shareWiFiName=defaults.bool(forKey:"rjlove.share-wifi-name")
        app.location.backgroundSharingEnabled=defaults.bool(forKey:"rjlove.background-location")
        app.location.photoLocationEnabled=defaults.object(forKey:"rjlove.photo-location") as? Bool ?? true
        app.location.sharingEnabled=defaults.bool(forKey:"rjlove.location-sharing")
        app.health.sharingEnabled=defaults.bool(forKey:"rjlove.health-sharing")
        app.health.shareActivity=defaults.bool(forKey:"rjlove.share-activity")
        app.health.shareSleep=defaults.bool(forKey:"rjlove.share-sleep")
        app.health.shareVitals=defaults.bool(forKey:"rjlove.share-vitals")
        app.health.sleepGoalHours=defaults.object(forKey:"rjlove.sleep-goal-hours") as? Double ?? 8
        app.nearby.automaticSearch=defaults.object(forKey:"rjlove.nearby-auto") as? Bool ?? true
        app.nearby.backgroundSearch=defaults.object(forKey:"rjlove.nearby-background") as? Bool ?? true
        let live=app.liveActivity
        live.restoreEnabledPreference()
        live.automaticallyResume=defaults.object(forKey:"rjlove.live-auto-resume") as? Bool ?? true
        live.showBattery=defaults.object(forKey:"rjlove.live-battery") as? Bool ?? true
        live.showThoughts=defaults.object(forKey:"rjlove.live-thoughts") as? Bool ?? true
        live.showStatus=defaults.object(forKey:"rjlove.live-status") as? Bool ?? true
        live.showQuickAction=defaults.object(forKey:"rjlove.live-action") as? Bool ?? true
        HomeKitDashboard.shared.restorePreferences()
    }
}

struct SettingsBackupView:View {
    @Environment(AppState.self) private var app
    @State private var backup=SettingsBackup.shared
    var body:some View {
        List {
            Section {
                Label("Automatisch aktiv",systemImage:"checkmark.icloud.fill").foregroundStyle(LovePalette.cyan)
                Text("Deine Einstellungen werden bei der Synchronisierung in deinem Konto gesichert und nach dem Anmelden automatisch wiederhergestellt.").font(.subheadline)
                if let date=backup.lastSaved?.rjDate {LabeledContent("Letzte Sicherung",value:date.formatted(date:.abbreviated,time:.shortened))}
                Button(backup.syncing ? "Wird gesichert …" : "Jetzt abgleichen",systemImage:"arrow.triangle.2.circlepath") {Task {await backup.sync(app:app)}}.disabled(backup.syncing)
                if let error=backup.error {Text(error).font(.caption).foregroundStyle(.orange)}
            }
            Section("In deiner Sicherung") {
                Label("Startseite, Karten & Schnellzugriffe",systemImage:"square.grid.2x2")
                Label("Persönliche Navigation",systemImage:"rectangle.bottomthird.inset.filled")
                Label("AirPlay, TV-Widgets & Kameraauswahl",systemImage:"airplay.video")
                Label("Live-Aktivität, Freigaben & App-Verhalten",systemImage:"gearshape")
                Label("Dokumentordner & Favoriten",systemImage:"folder")
            }
            Section {
                Text("Gemeinsame Inhalte, Nachrichten, Dokumente und Bark-Einstellungen liegen bereits auf eurem Server. Lokale Audioentwürfe und nur auf dem iPhone gespeicherte Dateien sind kein Teil der Einstellungssicherung. iOS-Berechtigungen, Home-Einladungen, Medien-Anmeldungen und die Widget-Platzierung auf dem iOS-Home-Bildschirm werden auf jedem Gerät eingerichtet.").font(.footnote).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(LoveBackground()).navigationTitle("Automatische Sicherung").navigationBarTitleDisplayMode(.inline)
            .task {await backup.sync(app:app)}
    }
}
