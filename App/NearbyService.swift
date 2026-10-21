import Foundation
import NearbyInteraction
import Observation
import simd

@MainActor @Observable
final class NearbyService: NSObject, NISessionDelegate {
    private(set) var running = false
    private(set) var distance: Float?
    private(set) var angle: Double?
    private(set) var message = "Findet euch. Auch ganz nah."
    var supported: Bool { NISession.deviceCapabilities.supportsPreciseDistanceMeasurement }
    private var session: NISession?
    private var task: Task<Void, Never>?
    private var peerToken: String?
    private var lastMeasurement: Date?

    func start(api: APIClient) {
        guard supported else { message = "Präzise Nahbereichssuche ist auf diesem Gerät nicht verfügbar."; return }
        guard !running else { return }
        let session = NISession()
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
                        self.session?.run(NINearbyPeerConfiguration(peerToken: discovery))
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
        running = false; distance = nil; angle = nil; peerToken = nil
        Task { try? await api.publishNearbyToken("") }
    }

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first else { return }
        let distance = object.distance
        let direction = object.direction
        Task { @MainActor [weak self] in
            guard let self, self.running, self.session === session else { return }
            self.distance = distance
            self.angle = direction.map { Double(atan2($0.x, -$0.z)) * 180 / .pi }
            self.lastMeasurement = .now
            self.message = distance == nil ? "Suche nach einem präzisen Signal …" : "Da bist du. 💗"
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
