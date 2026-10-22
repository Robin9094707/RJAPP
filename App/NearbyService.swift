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
    private var arSession:ARSession?
    private var session: NISession?
    private var task: Task<Void, Never>?
    private var peerToken: String?
    private var lastMeasurement: Date?

    func start(api: APIClient) async {
        guard supported else { message = "Präzise Nahbereichssuche ist auf diesem Gerät nicht verfügbar."; return }
        guard !running else { return }
        var assisted=false
        if cameraAssistance,NISession.deviceCapabilities.supportsCameraAssistance {assisted=await AVCaptureDevice.requestAccess(for:.video)}
        let session = NISession()
        if assisted {
            let ar=ARSession();session.setARSession(ar);ar.run(ARWorldTrackingConfiguration());arSession=ar
        }
        session.delegate = self
        self.session = session
        running = true
        message = "Beide öffnen diese Ansicht. Haltet eure iPhones aufrecht."
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.running, let token = self.session?.discoveryToken,
                      let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
                do {
                    try await api.publishNearbyToken(data.base64EncodedString())
                    let peer = try await api.partnerNearbyToken()
                    if let peer, peer != self.peerToken,
                       let bytes = Data(base64Encoded: peer),
                       let discovery = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: bytes) {
                        self.peerToken = peer
                        let configuration=NINearbyPeerConfiguration(peerToken:discovery);configuration.isCameraAssistanceEnabled=assisted
                        self.session?.run(configuration)
                        self.message = "Verbunden. Richtet die Rückseiten eurer iPhones zueinander."
                    } else if peer == nil {
                        self.peerToken = nil
                        self.distance = nil
                        self.angle = nil
                        self.message = "Warte auf dein Gegenüber …"
                    }
                    if let last = self.lastMeasurement, Date.now.timeIntervalSince(last) > 8 {
                        self.distance = nil; self.angle = nil
                        self.message = "Kein aktuelles Signal. Geht näher zusammen und richtet die iPhones neu aus."
                    }
                } catch {
                    self.distance = nil; self.angle = nil
                    self.message = "Verbindung unterbrochen: \(error.localizedDescription)"
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop(api: APIClient) {
        task?.cancel(); task = nil
        session?.invalidate(); session = nil
        arSession?.pause();arSession=nil
        running = false; distance = nil; angle = nil; peerToken = nil
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
            self.task?.cancel(); self.running = false
            self.distance = nil; self.angle = nil
            self.message = "Nahbereichssuche beendet: \(error.localizedDescription)"
        }
    }
    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor [weak self] in self?.distance = nil; self?.angle = nil; self?.message = "Suche pausiert. Lasst beide die App geöffnet." }
    }
    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor [weak self] in self?.peerToken = nil }
    }
    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor [weak self] in self?.distance = nil; self?.angle = nil; self?.peerToken = nil; self?.message = "Signal verloren. Geht näher zusammen." }
    }
}
