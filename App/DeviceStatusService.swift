import CoreMotion
import Foundation
import Network
import NetworkExtension
import UIKit

@MainActor
final class DeviceStatusService: ObservableObject {
    static let shared = DeviceStatusService()

    @Published private(set) var batteryLevel: Int?
    @Published private(set) var batteryState = "unknown"
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var networkType = "offline"
    @Published private(set) var wifiName: String?
    @Published private(set) var motion = "Unbekannt"
    @Published private(set) var motionAuthorization = CMMotionActivityManager.authorizationStatus()

    var onMeaningfulChange: (() -> Void)?

    private let pathMonitor = NWPathMonitor()
    private let motionManager = CMMotionActivityManager()
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryChanged),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let type: String
            if path.status != .satisfied { type = "offline" }
            else if path.usesInterfaceType(.wifi) { type = "wifi" }
            else if path.usesInterfaceType(.cellular) { type = "cellular" }
            else if path.usesInterfaceType(.wiredEthernet) { type = "ethernet" }
            else { type = "other" }
            Task { @MainActor in
                guard let self else { return }
                let changed = self.networkType != type
                self.networkType = type
                if type == "wifi" { self.refreshWiFiName() } else { self.wifiName = nil }
                if changed { self.onMeaningfulChange?() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "eu.rjuhas.rjlove.network"))
        if motionAuthorization == .authorized { startMotionUpdates() }
    }

    @objc private func batteryChanged() {
        let previousLevel = batteryLevel
        let previousState = batteryState
        refreshBattery()
        if previousLevel != batteryLevel || previousState != batteryState {
            onMeaningfulChange?()
        }
    }

    @objc private func powerChanged() {
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        onMeaningfulChange?()
    }

    private func refreshBattery() {
        let raw = UIDevice.current.batteryLevel
        batteryLevel = raw < 0 ? nil : Int((raw * 100).rounded())
        switch UIDevice.current.batteryState {
        case .charging: batteryState = "charging"
        case .full: batteryState = "full"
        case .unplugged: batteryState = "unplugged"
        case .unknown: batteryState = "unknown"
        @unknown default: batteryState = "unknown"
        }
    }

    private func refreshWiFiName() {
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            Task { @MainActor in
                self?.wifiName = network?.ssid
            }
        }
    }

    func requestMotionAccess() async {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            motionManager.queryActivityStarting(from: .now.addingTimeInterval(-60), to: .now, to: .main) { _, _ in
                continuation.resume()
            }
        }
        motionAuthorization = CMMotionActivityManager.authorizationStatus()
        startMotionUpdates()
    }

    func startMotionUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            Task { @MainActor in
                guard let self else { return }
                self.motionAuthorization = CMMotionActivityManager.authorizationStatus()
                let next: String
                if activity.automotive { next = "Auto" }
                else if activity.cycling { next = "Fahrrad" }
                else if activity.running { next = "Laufen" }
                else if activity.walking { next = "Zu Fuß" }
                else if activity.stationary { next = "Stationär" }
                else { next = "Unbekannt" }
                if next != self.motion {
                    self.motion = next
                    LocationService.shared.updateActivity(next)
                    self.onMeaningfulChange?()
                }
            }
        }
    }
}
