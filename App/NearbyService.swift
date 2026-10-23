import ActivityKit
import AVFoundation
import Foundation
import NearbyInteraction
import Observation
import simd
import UIKit

@MainActor @Observable
final class NearbyService:NSObject,NISessionDelegate {
    private(set) var running=false
    private(set) var distance:Float?
    private(set) var elevation:Double?
    private(set) var angle:Double?
    private(set) var heightHint=""
    private(set) var directionSource="Kein Winkel empfangen"
    private(set) var message="Findet euch. Auch ganz nah."
    private(set) var coaching=""
    private(set) var peerDiscovered=false
    private(set) var cameraActive=false
    private(set) var localTokenReady=false
    private(set) var serverReached=false
    private(set) var sessionStarted=false
    private(set) var lastError=""
    private(set) var stage="Noch nicht gestartet"
    var supported:Bool {NISession.deviceCapabilities.supportsPreciseDistanceMeasurement}
    var supportsDirectDirection:Bool {NISession.deviceCapabilities.supportsDirectionMeasurement}
    var supportsCamera:Bool {NISession.deviceCapabilities.supportsCameraAssistance}
    // Newer UWB devices may need camera-assisted horizontalAngle instead of a 3D vector.
    var cameraAssistance=NISession.deviceCapabilities.supportsCameraAssistance
    var backgroundSearch=false
    var backgroundActive:Bool {searchActivity?.activityState == .active || searchActivity?.activityState == .stale}
    var cameraRequested:Bool {configuration?.isCameraAssistanceEnabled == true}
    var diagnostics:String {
        ["RJ Love "+RJVersion.app,"iOS "+UIDevice.current.systemVersion,
         "Suche aktiv: \(running)","UWB-Distanz: \(supported)","Direkte UWB-Richtung: \(supportsDirectDirection)",
         "Kamera-Unterstützung verfügbar: \(supportsCamera)","Kamera freigegeben: \(AVCaptureDevice.authorizationStatus(for:.video) == .authorized)",
         "Kamera-Modus: iOS-verwaltete AR-Sitzung", "Kamera für diese Suche gesperrt: \(cameraFailedForSearch)",
         "Lokaler Token: \(localTokenReady)","Server erreichbar: \(serverReached)","Partner-Token: \(peerDiscovered)",
         "Sitzung läuft: \(sessionStarted)","Kamera angefordert: \(cameraRequested)","Kamera-Sitzung gestartet: \(cameraActive)",
         "Winkelquelle: "+directionSource,"Phase: "+stage,
         "Letzter Systemfehler: "+(lastError.isEmpty ? "Keiner gemeldet":lastError)].joined(separator:"\n")
    }
    private var searchActivity:Activity<NearbySearchAttributes>?
    private var deadline:Date?
    private var sessionAPI:APIClient?
    private var configuration:NINearbyPeerConfiguration?
    private var generation=UUID()
    private var session:NISession?
    private var task:Task<Void,Never>?
    private var peerToken:String?
    private var publishedToken:String?
    private var lastMeasurement:Date?
    private var configurationAt:Date?
    private var tokenAttemptAt=Date.now
    private var tokenRestarts=0
    private var visible=false
    private var retries=0
    private var permitCamera=false
    private var cameraFailedForSearch=false
    private var shouldUseCamera:Bool {permitCamera && !cameraFailedForSearch && visible && UIApplication.shared.applicationState == .active}

    func setVisible(_ value:Bool) {
        visible=value
        if value {resumeForeground()}
        else if !backgroundSearch,let api=sessionAPI {stop(api:api)}
        else if cameraRequested {rebuildSession()}
    }
    func start(api:APIClient) async {
        guard supported else{message="Dieses iPhone unterstützt keine präzise UWB-Messung.";return}
        guard !running,UIApplication.shared.applicationState == .active else{return}
        generation=UUID();let attempt=generation;running=true;sessionAPI=api;deadline = .now.addingTimeInterval(900);retries=0
        message="Nahsuche wird vorbereitet …";coaching="";lastError="";localTokenReady=false;serverReached=false;stage="UWB-System wird initialisiert";tokenRestarts=0
        cameraFailedForSearch=false;permitCamera=false
        if cameraAssistance,supportsCamera {
            permitCamera=await AVCaptureDevice.requestAccess(for:.video)
        }
        guard running,generation==attempt,!Task.isCancelled else{return}
        if !supportsDirectDirection,!permitCamera {
            coaching=supportsCamera ? "Für einen Richtungspfeil auf diesem iPhone die Kamera-Unterstützung und Kamerafreigabe einschalten. Ohne sie ist nur die Entfernung verfügbar.":"Dieses Gerät meldet nur Entfernungsmessung, keine Richtung und keine Kamera-Unterstützung."
        }
        createSession();startExchange(api:api,attempt:attempt)
    }
    private func createSession() {
        let old=session;session=nil;old?.invalidate()
        let next=NISession();next.delegate=self;next.delegateQueue = .main
        session=next;tokenAttemptAt = .now;localTokenReady=false;sessionStarted=false;cameraActive=false
        peerToken=nil;configuration=nil;configurationAt=nil;lastMeasurement=nil;peerDiscovered=false;clearMeasurement()
        // Do not attach a custom ARSession. NI creates and configures exactly one
        // internal AR session when run() receives isCameraAssistanceEnabled=true.
    }
    private func rebuildSession() {
        guard running else{return}
        let oldToken=publishedToken
        createSession();publishedToken=nil
        if let oldToken,let api=sessionAPI {Task{try? await api.publishNearbyToken("",expectedToken:oldToken)}}
    }
    private func startExchange(api:APIClient,attempt:UUID) {
        task?.cancel()
        task=Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.running,self.generation==attempt else{return}
                guard let deadline=self.deadline,deadline > .now else{self.stop(api:api);self.stage="Suche beendet";self.message="Suche nach 15 Minuten beendet. Du kannst sie neu starten.";return}
                if let activity=self.searchActivity,activity.activityState == .dismissed || activity.activityState == .ended {self.stop(api:api);return}
                guard UIApplication.shared.applicationState == .active || self.backgroundActive else{try? await Task.sleep(for:.seconds(1));continue}
                guard let current=self.session else{return}
                do {
                    if let token=current.discoveryToken {
                        let data=try NSKeyedArchiver.archivedData(withRootObject:token,requiringSecureCoding:true)
                        let encoded=data.base64EncodedString();self.localTokenReady=true
                        try await api.publishNearbyToken(encoded,lifetime:self.backgroundActive ? max(20,Int(deadline.timeIntervalSinceNow)):20)
                        guard self.running,self.generation==attempt,!Task.isCancelled else{return}
                        guard self.session === current else{continue}
                        self.publishedToken=encoded;self.serverReached=true
                    }
                    // Still receive a peer if the local token is temporarily unavailable.
                    let peer=try await api.partnerNearbyToken()
                    guard self.running,self.generation==attempt,!Task.isCancelled else{return}
                    guard self.session === current else{continue}
                    self.serverReached=true
                    if let peer,let bytes=Data(base64Encoded:peer) {
                        guard let discovery=try NSKeyedUnarchiver.unarchivedObject(ofClass:NIDiscoveryToken.self,from:bytes) else{throw APIClientError.invalidResponse}
                        self.peerDiscovered=true
                        if peer != self.peerToken || self.configuration==nil {
                            if self.configuration != nil{current.pause()}
                            self.peerToken=peer;self.sessionStarted=false;self.cameraActive=false
                            let config=NINearbyPeerConfiguration(peerToken:discovery)
                            config.isCameraAssistanceEnabled=self.shouldUseCamera
                            self.configuration=config;self.configurationAt = .now
                            current.run(config)
                            self.stage="Partner verbunden · UWB wird gestartet"
                            self.message="Gegenüber gefunden. Rückkameras zueinander ausrichten."
                            if self.shouldUseCamera {self.coaching="Ein iPhone ruhig halten. Das suchende iPhone langsam seitlich und auf/ab bewegen. iOS kalibriert den Pfeil."}
                            if self.backgroundSearch,self.searchActivity==nil {self.startBackgroundActivity()}
                        }
                        let stale=self.lastMeasurement.map{Date.now.timeIntervalSince($0)>8} ?? true
                        if stale,let since=self.configurationAt {
                            if self.cameraRequested,Date.now.timeIntervalSince(since)>45 {
                                self.cameraFailedForSearch=true;self.rebuildSession()
                                self.stage="Entfernung ohne Kamera wird neu aufgebaut"
                                self.coaching="Kein Messsignal nach 45 Sekunden. Kamera für diese Suche beendet; ohne direkte Richtung ist jetzt nur Entfernung möglich."
                            }else if !self.cameraRequested,Date.now.timeIntervalSince(since)>15,let config=self.configuration {
                                self.clearMeasurement();current.run(config);self.configurationAt = .now
                                self.message="Noch kein Messsignal. Auf wenige Meter zusammengehen und Rückkameras zueinander ausrichten."
                            }
                        }
                    }else{
                        if self.peerToken != nil {current.pause();self.sessionStarted=false;self.cameraActive=false}
                        self.peerToken=nil;self.configuration=nil;self.peerDiscovered=false;self.clearMeasurement()
                        self.stage=self.localTokenReady ? "Eigener Token übertragen · warte auf Partner":"iOS liefert noch keinen lokalen UWB-Token"
                        self.message=self.localTokenReady ? "Bereit. Starte die Nahsuche auch auf dem anderen iPhone.":"iOS initialisiert UWB. Kein Freigabefehler gemeldet."
                    }
                    if !self.localTokenReady,Date.now.timeIntervalSince(self.tokenAttemptAt)>8 {
                        if self.tokenRestarts<2 {
                            self.tokenRestarts+=1;self.rebuildSession();self.stage="UWB wird neu initialisiert (\(self.tokenRestarts)/2)"
                        }else{
                            self.lastError="Kein lokaler Discovery-Token nach drei Sitzungsstarts."
                            self.stop(api:api);self.stage="UWB derzeit nicht bereit";self.message="iOS stellt keinen UWB-Token bereit. Bluetooth und Flugmodus prüfen; Details unter Diagnose.";return
                        }
                    }
                }catch{
                    if !Task.isCancelled,self.generation==attempt,self.session === current {
                        self.clearMeasurement();let ns=error as NSError
                        self.lastError="\(ns.domain) (\(ns.code)): \(ns.localizedDescription)"
                        self.stage="Token-Austausch unterbrochen";self.message="Austausch nicht möglich: "+error.localizedDescription
                    }
                }
                try? await Task.sleep(for:.seconds(2))
            }
        }
    }
    private func startBackgroundActivity() {
        do {
            guard ActivityAuthorizationInfo().areActivitiesEnabled,let deadline else{throw LiveActivityError.disabled}
            searchActivity=try Activity.request(attributes:NearbySearchAttributes(until:deadline),content:ActivityContent(state:NearbySearchAttributes.ContentState(active:true),staleDate:deadline,relevanceScore:150))
        }catch{coaching="Live-Aktivität nicht verfügbar. Beide Apps für die Suche geöffnet lassen."}
    }
    private func clearMeasurement(){distance=nil;angle=nil;elevation=nil;heightHint="";directionSource="Kein Winkel empfangen"}
    func resumeForeground() {
        guard running,visible,UIApplication.shared.applicationState == .active else{return}
        if let config=configuration {
            if config.isCameraAssistanceEnabled != shouldUseCamera {rebuildSession()}
            else {session?.run(config);configurationAt = .now}
        }
    }
    func enterBackground(api:APIClient) {
        guard running else{return}
        guard backgroundActive,let deadline,deadline > .now else{stop(api:api);return}
        // Invalidation releases NI's internal camera before continuing distance-only.
        if cameraRequested {rebuildSession()}
        message="Suche mit Live-Aktivität aktiv. Für Kamera und Pfeil die Suchansicht wieder öffnen."
    }
    func stop(api:APIClient) {
        let oldToken=publishedToken
        generation=UUID();task?.cancel();task=nil;lastMeasurement=nil;deadline=nil;configuration=nil;sessionAPI=nil
        let old=session;session=nil;old?.invalidate()
        if let activity=searchActivity{searchActivity=nil;Task{await activity.end(nil,dismissalPolicy:.immediate)}}
        running=false;cameraActive=false;sessionStarted=false;peerDiscovered=false;peerToken=nil;publishedToken=nil;clearMeasurement();stage="Suche beendet"
        Task{try? await api.publishNearbyToken("",expectedToken:oldToken ?? "")}
    }
    nonisolated func session(_ session:NISession,didUpdate nearbyObjects:[NINearbyObject]) {
        guard let object=nearbyObjects.first else{return}
        let token=object.discoveryToken,distance=object.distance,direction=object.direction,horizontal=object.horizontalAngle,vertical=object.verticalDirectionEstimate
        Task{@MainActor [weak self] in
            guard let self,self.running,self.session === session,self.configuration?.peerDiscoveryToken==token else{return}
            self.distance=distance.flatMap{$0.isFinite && $0>=0 ? $0:nil}
            let direct=direction.flatMap{d->Double? in guard d.x.isFinite,d.z.isFinite else{return nil};return Double(atan2(d.x,-d.z))*180 / .pi}
            let camera=horizontal.flatMap{$0.isFinite ? Double($0)*180 / .pi:nil}
            let measured=camera ?? direct
            if let old=self.angle,let measured {let delta=(measured-old)*Double.pi/180;self.angle=old+atan2(sin(delta),cos(delta))*180/Double.pi}else{self.angle=measured}
            self.directionSource=camera != nil ? "Kameragestützter horizontaler Winkel":direct != nil ? "Direkte UWB-Richtung":"Kein Winkel empfangen"
            self.elevation=direction.flatMap{$0.y.isFinite ? Double(asin(max(-1,min(1,$0.y))))*180 / .pi:nil}
            switch vertical {case .above:self.heightHint="Dein Gegenüber ist höher";case .below:self.heightHint="Dein Gegenüber ist tiefer";case .aboveOrBelow:self.heightHint="Dein Gegenüber ist auf einer anderen Höhe";default:self.heightHint=""}
            if self.distance != nil {self.lastMeasurement = .now;self.retries=0;self.stage=measured==nil ? "Entfernung empfangen · Richtung wird gesucht":"Entfernung und Richtung empfangen"}
            self.message=self.distance==nil ? "Kalibrierung läuft …":measured != nil ? "Folge dem Pfeil. Da bist du. 💗":self.cameraRequested ? "Entfernung erkannt. Ein Gerät ruhig halten und das suchende Gerät langsam bewegen.":"Entfernung erkannt. Auf diesem Gerät braucht der Pfeil die Kamera-Unterstützung."
        }
    }
    nonisolated func session(_ session:NISession,didInvalidateWith error:Error) {
        Task{@MainActor [weak self] in
            guard let self,self.running,self.session === session,let api=self.sessionAPI else{return}
            let ns=error as NSError;self.lastError="\(ns.domain) (\(ns.code)): \(ns.localizedDescription)"
            DebugLogger.shared.log(self.lastError,category:"Nahsuche")
            let arError:Bool
            switch error {case NIError.invalidARConfiguration:arError=true;default:arError=ns.domain=="com.apple.NearbyInteraction" && ns.code == -5883}
            if arError,self.cameraRequested,!self.cameraFailedForSearch {
                self.cameraFailedForSearch=true;self.rebuildSession()
                self.stage="Kamerafehler · Entfernung wird neu aufgebaut"
                self.message="iOS konnte die Kamerakalibrierung nicht starten. Die Suche wird ohne Kamera fortgesetzt."
                self.coaching="Die Kamera bleibt für diese Suche aus. Für einen erneuten Kamera-Versuch die Suche bewusst neu starten."
                return
            }
            let canRetry:Bool
            switch error {case NIError.userDidNotAllow:canRetry=false;default:canRetry=self.retries<2}
            if canRetry {
                self.retries+=1;self.rebuildSession();self.stage="Nahsuche wird neu aufgebaut"
                self.message="Die Verbindung wird erneut hergestellt …"
            }else{
                self.stop(api:api);self.message="Nahsuche beendet: "+error.localizedDescription
                self.stage="Systemfehler · Details unter Diagnose";self.coaching="Prüft die Diagnose auf beiden iPhones. Bei einer verweigerten Freigabe die App-Einstellungen öffnen."
            }
        }
    }
    nonisolated func sessionDidStartRunning(_ session:NISession){Task{@MainActor [weak self] in guard let self,self.running,self.session === session else{return};self.sessionStarted=true;self.cameraActive=self.cameraRequested;self.stage=self.cameraRequested ? "iOS-Kamerakalibrierung läuft":"UWB-Sitzung läuft · warte auf Messsignal"}}
    nonisolated func sessionWasSuspended(_ session:NISession){Task{@MainActor [weak self] in guard let self,self.session === session else{return};self.sessionStarted=false;self.cameraActive=false;self.clearMeasurement();self.stage="Von iOS pausiert";self.message="iOS pausiert die Nahsuche. Beide Apps wieder öffnen."}}
    nonisolated func sessionSuspensionEnded(_ session:NISession){Task{@MainActor [weak self] in guard let self,self.session === session else{return};self.resumeForeground()}}
    nonisolated func session(_ session:NISession,didRemove nearbyObjects:[NINearbyObject],reason:NINearbyObject.RemovalReason){Task{@MainActor [weak self] in guard let self,self.session === session else{return};self.clearMeasurement();self.peerToken=nil;self.configuration=nil;self.sessionStarted=false;self.cameraActive=false;session.pause();self.message="Signal verloren. Verbindung wird erneuert …"}}
    nonisolated func session(_ session:NISession,didUpdateAlgorithmConvergence convergence:NIAlgorithmConvergence,for object:NINearbyObject?){
        let hint:String
        switch convergence.status {
        case .converged:hint="Kamera kalibriert. Das Zielgerät weiter ruhig halten."
        case .notConverged(let reasons):hint=reasons.compactMap{$0.localizedDescription}.joined(separator:" ")
        default:hint="Langsam seitlich und auf/ab bewegen. Ein Gerät bleibt ruhig stehen."
        }
        Task{@MainActor [weak self] in guard let self,self.running,self.session === session,self.cameraRequested else{return};self.coaching=hint.isEmpty ? "Bewege das suchende iPhone langsam seitlich und auf/ab.":hint}
    }
}
