import ActivityKit
import Foundation
import ARKit
import AVFoundation
import NearbyInteraction
import Observation
import simd

@MainActor @Observable
final class NearbyService: NSObject, NISessionDelegate {
    private(set) var running = false
    private(set) var distance: Float?
    private(set) var elevation: Double?
    private(set) var angle: Double?
    private(set) var message = "Findet euch. Auch ganz nah."
    var supported: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }
    var cameraAssistance=false
    var backgroundSearch = true
    private var searchActivity: Activity<NearbySearchAttributes>?
    private var deadline: Date?
    private var configuration: NINearbyPeerConfiguration?
    private var arSession:ARSession?
    private var generation=UUID()
    private var session: NISession?
    private var task: Task<Void, Never>?
    private var peerToken: String?
    private var lastMeasurement: Date?

    func start(api: APIClient) async {
        guard supported else { message = "Präzise Nahbereichssuche ist auf diesem Gerät nicht verfügbar."; return }
        guard !running else { return }
        let attempt=UUID();generation=attempt;running=true
        var assisted=false
        if cameraAssistance,NISession.deviceCapabilities.supportsCameraAssistance {assisted=await AVCaptureDevice.requestAccess(for:.video)}
        guard running,generation==attempt,!Task.isCancelled else{return}
        let session = NISession()
        if assisted {
            let ar=ARSession();session.setARSession(ar);ar.run(ARWorldTrackingConfiguration());arSession=ar
        }
        session.delegate = self
        self.session = session
        deadline = .now.addingTimeInterval(900)
        if backgroundSearch {
            do {
                guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw LiveActivityError.disabled }
                let attributes = NearbySearchAttributes(until: deadline!)
                searchActivity = try Activity.request(attributes: attributes, content: ActivityContent(state: NearbySearchAttributes.ContentState(active: true), staleDate: deadline))
            } catch {
                self.session?.invalidate(); self.session = nil; arSession?.pause(); arSession = nil; running = false
                message = "Hintergrundsuche braucht eine erlaubte Live-Aktivität. Schalte die Option aus, um mit beiden geöffneten Apps zu suchen."
                return
            }
        }
        running = true
        message = "Beide öffnen diese Ansicht. Haltet eure iPhones aufrecht."
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.running, let token = self.session?.discoveryToken,
                      let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
                do {
                    guard let deadline = self.deadline, deadline > .now else {
                        self.stop(api: api); self.message = "Suche nach 15 Minuten beendet. Bei Bedarf neu starten."; return
                    }
                    if let activity = self.searchActivity, activity.activityState == .dismissed || activity.activityState == .ended {
                        self.stop(api: api); return
                    }
                    try await api.publishNearbyToken(data.base64EncodedString(), lifetime: self.backgroundSearch ? max(20, Int(deadline.timeIntervalSinceNow)) : 20)
                    let peer = try await api.partnerNearbyToken()
                    if let peer, peer != self.peerToken,
                       let bytes = Data(base64Encoded: peer),
                       let discovery = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: bytes) {
                        self.peerToken = peer
                        let configuration=NINearbyPeerConfiguration(peerToken:discovery);configuration.isCameraAssistanceEnabled=assisted
                        self.configuration = configuration
                        self.session?.run(configuration)
                        self.message = "Verbunden. Richtet die Rückseiten eurer iPhones zueinander."
                    } else if peer == nil && (self.lastMeasurement == nil || Date.now.timeIntervalSince(self.lastMeasurement!) > 8) {
                        self.peerToken = nil
                        self.distance = nil
                        self.angle = nil;self.elevation=nil
                        self.message = "Warte auf dein Gegenüber …"
                    }
                    if let last = self.lastMeasurement, Date.now.timeIntervalSince(last) > 8 {
                        self.distance = nil; self.angle = nil;self.elevation=nil
                        self.message = "Kein aktuelles Signal. Geht näher zusammen und richtet die iPhones neu aus."
                    }
                } catch {
                    self.distance = nil; self.angle = nil;self.elevation=nil
                    self.message = "Verbindung unterbrochen: \(error.localizedDescription)"
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func enterBackground(api: APIClient) {
        guard running else { return }
        guard backgroundSearch, let activity = searchActivity, activity.activityState == .active, let deadline, deadline > .now else {
            stop(api: api); return
        }
        arSession?.pause()
        if let configuration { configuration.isCameraAssistanceEnabled = false; session?.run(configuration) }
        message = "Suche mit Live-Aktivität aktiv. Beide Geräte müssen die Suche bereits gestartet haben."
    }

    func stop(api: APIClient) {
        generation=UUID();lastMeasurement=nil; deadline=nil; configuration=nil
        if let activity = searchActivity { searchActivity = nil; Task { await activity.end(nil, dismissalPolicy: .immediate) } }
        task?.cancel(); task = nil
        session?.invalidate(); session = nil
        arSession?.pause();arSession=nil
        running = false; distance = nil; angle = nil;elevation=nil; peerToken = nil
        Task { try? await api.publishNearbyToken("") }
    }

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        let distance = object.distance
        let direction = object.direction
        let horizontal = object.horizontalAngle
        Task { @MainActor [weak self] in
            guard let self, self.running, self.session === session else { return }
            self.distance = distance
            let measured=direction.map {Double(atan2($0.x,-$0.z))*180 / .pi} ?? horizontal.map{Double($0)*180 / .pi}
            if let previous=self.angle,let measured {
                let delta=(measured-previous)*Double.pi/180
                self.angle=previous+atan2(sin(delta),cos(delta))*180/Double.pi
            }else{self.angle=measured}
            self.elevation = direction.map {Double(asin(max(-1,min(1,$0.y))))*180 / .pi}
            self.lastMeasurement = .now
            self.message = distance == nil ? "Suche nach einem präzisen Signal …" : (self.angle == nil ? "Entfernung empfangen. Für den Pfeil beide iPhones langsam aufeinander ausrichten.":"Folge dem Pfeil. Da bist du. 💗")
        }
    }
    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.session === session else { return }
            self.task?.cancel(); self.running = false;self.arSession?.pause();self.arSession=nil;self.session=nil
            self.distance = nil; self.angle = nil;self.elevation=nil
            if let activity = self.searchActivity { self.searchActivity = nil; await activity.end(nil, dismissalPolicy: .immediate) }
            self.message = "Nahbereichssuche beendet: \(error.localizedDescription)"
        }
    }
    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor [weak self] in guard let self,self.session === session else{return};self.distance=nil;self.angle=nil;self.elevation=nil;self.arSession?.pause();self.message="Suche pausiert. Lasst beide die App geöffnet." }
    }
    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor [weak self] in guard let self,self.session === session,self.running else{return};self.peerToken=nil;self.arSession?.run(ARWorldTrackingConfiguration()) }
    }
    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor [weak self] in guard let self,self.session === session else{return};self.distance=nil;self.angle=nil;self.elevation=nil;self.peerToken=nil;self.message="Signal verloren. Geht näher zusammen." }
    }
}
