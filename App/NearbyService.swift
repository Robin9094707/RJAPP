import ActivityKit
import ARKit
import AVFoundation
import Foundation
import NearbyInteraction
import Observation
import simd
import UIKit

@MainActor @Observable
final class NearbyService:NSObject,NISessionDelegate,ARSessionDelegate {
    private(set) var running=false
    private(set) var distance:Float?
    private(set) var elevation:Double?
    private(set) var angle:Double?
    private(set) var message="Findet euch. Auch ganz nah."
    private(set) var coaching=""
    private(set) var arSession:ARSession?
    private(set) var peerDiscovered=false
    private(set) var cameraActive=false
    private(set) var localTokenReady=false
    private(set) var serverReached=false
    private(set) var sessionStarted=false
    private(set) var lastError=""
    private(set) var stage="Noch nicht gestartet"
    private var tokenAttemptAt=Date.now
    private var tokenRestarts=0
    var diagnostics:String {
        ["RJ Love "+RJVersion.app,"iOS "+UIDevice.current.systemVersion,
         "UWB-Distanz: \(supported)","UWB-Richtung: \(NISession.deviceCapabilities.supportsDirectionMeasurement)",
         "Lokaler Token: \(localTokenReady)","Server erreichbar: \(serverReached)","Partner-Token: \(peerDiscovered)",
         "Sitzung gestartet: \(sessionStarted)","Kamera aktiv: \(cameraActive)","Phase: "+stage,
         "Letzter Systemfehler: "+(lastError.isEmpty ? "Keiner gemeldet":lastError)].joined(separator:"\n")
    }
    var supported:Bool {NISession.deviceCapabilities.supportsPreciseDistanceMeasurement}
    var cameraAssistance=false
    var backgroundSearch=false
    var backgroundActive:Bool {searchActivity?.activityState == .active || searchActivity?.activityState == .stale}
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
    private var visible=false
    private var retries=0
    private var permitCamera=false

    func setVisible(_ value:Bool){visible=value;if value{resumeForeground()}else{disableCamera();if !backgroundSearch,let api=sessionAPI{stop(api:api)}}}
    func start(api:APIClient) async {
        guard supported else{message="Dieses iPhone unterstützt keine präzise UWB-Messung.";return}
        guard !running,UIApplication.shared.applicationState == .active else{return}
        generation=UUID();let attempt=generation;running=true;sessionAPI=api;deadline = .now.addingTimeInterval(900);retries=0
        message="Nahsuche wird vorbereitet …";coaching="";lastError="";localTokenReady=false;serverReached=false;sessionStarted=false;stage="UWB-System wird initialisiert";tokenRestarts=0
        permitCamera=false
        if cameraAssistance,NISession.deviceCapabilities.supportsCameraAssistance,ARWorldTrackingConfiguration.isSupported {
            permitCamera=await AVCaptureDevice.requestAccess(for:.video)
        }
        guard running,generation==attempt,!Task.isCancelled else{return}
        createSession(useCamera:false)
        message="Warte auf dein Gegenüber …";startExchange(api:api,attempt:attempt)
    }
    private func createSession(useCamera:Bool) {
        let old=session;session=nil;old?.invalidate();arSession?.pause();arSession=nil
        let next=NISession();next.delegate=self;next.delegateQueue = .main
        cameraActive=useCamera
        if useCamera {
            let ar=ARSession();ar.delegate=self;next.setARSession(ar);arSession=ar
            ar.run(ARWorldTrackingConfiguration(),options:[.resetTracking,.removeExistingAnchors])
            coaching="Ein iPhone ruhig halten. Bewege das suchende iPhone langsam seitlich und etwas auf und ab."
        }
        tokenAttemptAt = .now;localTokenReady=false;sessionStarted=false
        session=next;peerToken=nil;configuration=nil;publishedToken=nil;configurationAt=nil;lastMeasurement=nil;peerDiscovered=false;clearMeasurement()
    }
    private func startExchange(api:APIClient,attempt:UUID) {
        task?.cancel()
        task=Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.running,self.generation==attempt else{return}
                guard let deadline=self.deadline,deadline > .now else{self.stop(api:api);self.message="Suche nach 15 Minuten beendet. Du kannst sie neu starten.";return}
                if let activity=self.searchActivity,activity.activityState == .dismissed || activity.activityState == .ended {self.stop(api:api);return}
                // A missing local token is NOT a permission result. Still fetch a peer:
                // running a received peer configuration is what triggers the NI permission flow.
                do {
                    if let token=self.session?.discoveryToken {
                        do {
                            let data=try NSKeyedArchiver.archivedData(withRootObject:token,requiringSecureCoding:true)
                            self.localTokenReady=true
                            let encoded=data.base64EncodedString()
                            try await api.publishNearbyToken(encoded,lifetime:self.backgroundActive ? max(20,Int(deadline.timeIntervalSinceNow)):20)
                            guard self.running,self.generation==attempt,!Task.isCancelled else{return}
                            self.publishedToken=encoded;self.serverReached=true
                        } catch {
                            self.lastError="Token-Übertragung: "+error.localizedDescription
                            throw error
                        }
                    }
                    let peer=try await api.partnerNearbyToken()
                    guard self.running,self.generation==attempt,!Task.isCancelled else{return}
                    self.serverReached=true
                    if let peer,let bytes=Data(base64Encoded:peer) {
                        let discovery=try NSKeyedUnarchiver.unarchivedObject(ofClass:NIDiscoveryToken.self,from:bytes)
                        guard let discovery else{throw APIClientError.invalidResponse}
                        self.peerDiscovered=true
                        if peer != self.peerToken || self.configuration==nil {
                            self.peerToken=peer
                            if self.permitCamera,self.visible,self.localTokenReady {self.enableCamera()}
                            let config=NINearbyPeerConfiguration(peerToken:discovery);config.isCameraAssistanceEnabled=self.cameraActive
                            self.configuration=config;self.session?.run(config);self.configurationAt = .now
                            self.stage="Partner verbunden · UWB wird gestartet"
                            self.message="Gegenüber gefunden. Beide iPhones aufrecht halten und die Rückkameras zueinander ausrichten."
                            if self.backgroundSearch,self.searchActivity==nil {self.startBackgroundActivity()}
                        }
                        let stale=self.lastMeasurement.map{Date.now.timeIntervalSince($0)>8} ?? true
                        if stale,let since=self.configurationAt,Date.now.timeIntervalSince(since)>15 {
                            self.clearMeasurement()
                            if self.cameraActive {self.disableCamera();self.coaching="Noch kein Kamerafortschritt. Normale UWB-Messung wird versucht; beide iPhones geöffnet lassen."}
                            else if let config=self.configuration {self.session?.run(config)}
                            self.configurationAt = .now;self.stage="UWB sucht ein Messsignal";self.message="Noch kein Messsignal. Geht auf wenige Meter zusammen und richtet die Rückkameras zueinander aus."
                        }
                    }else{
                        if self.peerToken != nil{self.session?.pause()}
                        self.peerToken=nil;self.configuration=nil;self.peerDiscovered=false;self.clearMeasurement()
                        self.stage=self.localTokenReady ? "Eigener Token übertragen · warte auf Partner":"iOS liefert noch keinen lokalen UWB-Token"
                        self.message=self.localTokenReady ? "Bereit. Starte die Nahsuche auch auf dem anderen iPhone.":"iOS initialisiert UWB. Die App hat keine verweigerte Freigabe gemeldet."
                    }
                    if !self.localTokenReady,Date.now.timeIntervalSince(self.tokenAttemptAt)>8 {
                        if self.tokenRestarts<2 {
                            self.tokenRestarts+=1;self.createSession(useCamera:false)
                            self.stage="UWB-System wird neu initialisiert (\(self.tokenRestarts)/2)"
                        }else{
                            self.lastError="Kein lokaler Discovery-Token nach drei Sitzungsstarts. Kein Berechtigungsfehler von iOS empfangen."
                            self.stop(api:api);self.stage="UWB derzeit nicht bereit"
                            self.message="iOS stellt keinen UWB-Token bereit. Bluetooth und Flugmodus prüfen, beide Apps vollständig öffnen und das iPhone gegebenenfalls neu starten. Details unter Diagnose."
                            return
                        }
                    }
                }catch{
                    if !Task.isCancelled,self.generation==attempt {
                        self.clearMeasurement();self.lastError=error.localizedDescription;self.stage="Token-Austausch unterbrochen";self.message="Austausch mit dem Server nicht möglich: "+error.localizedDescription
                    }
                }
                try? await Task.sleep(for:.seconds(2))
            }
        }
    }
    private func enableCamera() {
        guard arSession==nil,let session,UIApplication.shared.applicationState == .active else{return}
        let ar=ARSession();ar.delegate=self;session.setARSession(ar);arSession=ar
        ar.run(ARWorldTrackingConfiguration(),options:[.resetTracking,.removeExistingAnchors]);cameraActive=true
        coaching="Zuerst Rückkameras zueinander ausrichten. Dann ein Gerät ruhig halten und das suchende iPhone langsam bewegen."
    }
    private func startBackgroundActivity() {
        do {
            guard ActivityAuthorizationInfo().areActivitiesEnabled,let deadline else{throw LiveActivityError.disabled}
            searchActivity=try Activity.request(attributes:NearbySearchAttributes(until:deadline),content:ActivityContent(state:NearbySearchAttributes.ContentState(active:true),staleDate:deadline,relevanceScore:150))
        }catch{coaching="Live-Aktivität nicht verfügbar. Beide Apps für die Suche geöffnet lassen."}
    }
    private func clearMeasurement(){distance=nil;angle=nil;elevation=nil}
    private func disableCamera(){arSession?.pause();cameraActive=false;if let config=configuration{config.isCameraAssistanceEnabled=false;session?.run(config)}}
    func resumeForeground() {
        guard running,visible,UIApplication.shared.applicationState == .active else{return}
        if permitCamera,let ar=arSession {ar.run(ARWorldTrackingConfiguration());cameraActive=true}
        if let config=configuration {config.isCameraAssistanceEnabled=cameraActive;session?.run(config);configurationAt = .now}
    }
    func enterBackground(api:APIClient) {
        guard running else{return}
        guard backgroundActive,let deadline,deadline > .now else{stop(api:api);return}
        disableCamera();message="Suche mit Live-Aktivität aktiv. Bei pausiertem Signal beide Apps wieder öffnen."
    }
    func stop(api:APIClient) {
        let oldToken=publishedToken
        generation=UUID();task?.cancel();task=nil;lastMeasurement=nil;deadline=nil;configuration=nil;sessionAPI=nil
        let old=session;session=nil;old?.invalidate();arSession?.pause();arSession=nil
        if let activity=searchActivity{searchActivity=nil;Task{await activity.end(nil,dismissalPolicy:.immediate)}}
        running=false;cameraActive=false;peerDiscovered=false;peerToken=nil;publishedToken=nil;clearMeasurement()
        Task{try? await api.publishNearbyToken("",expectedToken:oldToken ?? "")}
    }
    nonisolated func session(_ session:NISession,didUpdate nearbyObjects:[NINearbyObject]) {
        guard let object=nearbyObjects.first else{return}
        let distance=object.distance,direction=object.direction,horizontal=object.horizontalAngle
        Task{@MainActor [weak self] in
            guard let self,self.running,self.session === session else{return}
            self.distance=distance
            let measured=direction.map{Double(atan2($0.x,-$0.z))*180 / .pi} ?? horizontal.map{Double($0)*180 / .pi}
            if let old=self.angle,let measured {let delta=(measured-old)*Double.pi/180;self.angle=old+atan2(sin(delta),cos(delta))*180/Double.pi}else{self.angle=measured}
            self.elevation=direction.map{Double(asin(max(-1,min(1,$0.y))))*180 / .pi}
            if distance != nil {self.lastMeasurement = .now;self.retries=0;self.stage="UWB-Messsignal empfangen"}
            self.message=distance==nil ? "Kalibrierung läuft …":self.angle==nil ? "Entfernung erkannt. Langsam aufeinander ausrichten.":"Folge dem Pfeil. Da bist du. 💗"
        }
    }
    nonisolated func session(_ session:NISession,didInvalidateWith error:Error) {
        Task{@MainActor [weak self] in
            guard let self,self.session === session,let api=self.sessionAPI else{return}
            let ns=error as NSError;self.lastError="\(ns.domain) (\(ns.code)): \(ns.localizedDescription)"
            DebugLogger.shared.log(self.lastError,category:"Nahsuche")
            let canRetry:Bool
            switch error {case NIError.userDidNotAllow:canRetry=false;default:canRetry=self.retries<2}
            if canRetry {
                self.retries+=1;let token=self.publishedToken
                self.createSession(useCamera:false)
                self.message="Nahsuche wird ohne Kamera neu aufgebaut …"
                if let token{Task{try? await api.publishNearbyToken("",expectedToken:token)}}
            }else{self.stop(api:api);self.message="Nahsuche beendet: "+error.localizedDescription;self.stage="Systemfehler · Details unter Diagnose";self.coaching="Bei verweigerter Freigabe die App-Einstellungen öffnen. Andernfalls Bluetooth, Flugmodus und die Diagnose prüfen."}
        }
    }
    nonisolated func sessionDidStartRunning(_ session:NISession){Task{@MainActor [weak self] in guard let self,self.session === session else{return};self.sessionStarted=true;self.stage="UWB-Sitzung läuft · warte auf Messsignal"}}
    nonisolated func sessionWasSuspended(_ session:NISession){Task{@MainActor [weak self] in guard let self,self.session === session else{return};self.clearMeasurement();self.arSession?.pause();self.message="iOS pausiert die Nahsuche. Beide Apps wieder öffnen."}}
    nonisolated func sessionSuspensionEnded(_ session:NISession){Task{@MainActor [weak self] in guard let self,self.session === session else{return};self.resumeForeground();self.configurationAt = .now}}
    nonisolated func session(_ session:NISession,didRemove nearbyObjects:[NINearbyObject],reason:NINearbyObject.RemovalReason){Task{@MainActor [weak self] in guard let self,self.session === session else{return};self.clearMeasurement();self.peerToken=nil;self.configuration=nil;self.message="Signal verloren. Verbindung wird erneuert …"}}
    nonisolated func session(_ session:NISession,didUpdateAlgorithmConvergence convergence:NIAlgorithmConvergence,for object:NINearbyObject?){
        let converged:Bool
        switch convergence.status{case .converged:converged=true;default:converged=false}
        Task{@MainActor [weak self] in guard let self,self.session === session,self.cameraActive else{return};self.coaching=converged ? "Kamera kalibriert. Ein Gerät weiter ruhig halten.":"Langsam seitlich und auf/ab schwenken. Gute Beleuchtung und sichtbare Raumdetails helfen."}
    }
    nonisolated func session(_ session:ARSession,didFailWithError error:Error){Task{@MainActor [weak self] in guard let self,self.arSession === session else{return};self.disableCamera();self.coaching="Kamera nicht verfügbar. Die Nahsuche läuft ohne Kamera weiter."}}
}
