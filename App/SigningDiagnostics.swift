import Foundation
import UIKit

struct SigningProfile {
    let bundleID: String
    let teamID: String?
    let applicationID: String?
    let environment: String?
    let permitsPushToTalk: Bool?
    let development: Bool?
    let expires: Date?
    let found: Bool
    static let current = inspect()
    static func inspect() -> SigningProfile {
        let id = Bundle.main.bundleIdentifier ?? "eu.rjuhas.rjlove"
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let bytes = try? Data(contentsOf: url),
              let start = bytes.range(of: Data("<plist".utf8)), let end = bytes.range(of: Data("</plist>".utf8)),
              let dictionary = (try? PropertyListSerialization.propertyList(from: bytes.subdata(in: start.lowerBound..<end.upperBound), format: nil)) as? [String: Any] else {
            return SigningProfile(bundleID: id, teamID: nil, applicationID: nil, environment: nil, permitsPushToTalk: nil, development: nil, expires: nil, found: false)
        }
        let entitlements = dictionary["Entitlements"] as? [String: Any] ?? [:]
        return SigningProfile(bundleID: id,
            teamID: (dictionary["TeamIdentifier"] as? [String])?.first,
            applicationID: entitlements["application-identifier"] as? String,
            environment: entitlements["aps-environment"] as? String,
            permitsPushToTalk: entitlements["com.apple.developer.push-to-talk"] as? Bool ?? false,
            development: entitlements["get-task-allow"] as? Bool,
            expires: dictionary["ExpirationDate"] as? Date, found: true)
    }
    var pushEnvironment: String {
        if environment == "development" { return "sandbox" }
        if environment == "production" { return "production" }
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
    var profileDescription: String {
        guard found else { return "Kein auswertbares Profil eingebettet. Auf Simulator und unsigned IPA normal; auf dem iPhone Signatur prüfen." }
        return development == true ? "Developer-/JIT-Profil" : "Distribution-Profil"
    }
    func pushToTalkError(_ error: Error) -> String {
        let value = error as NSError
        let detail = "\(value.domain) (\(value.code)): \(value.localizedDescription)"
        if permitsPushToTalk == false {
            return "Das installierte Profil erlaubt com.apple.developer.push-to-talk nicht. Die App kann diese Apple-Freigabe nicht selbst hinzufügen. In Feather das Distribution-Profil prüfen und bei ArcticSign gezielt Push to Talk für diese App-ID anfragen. System: " + detail
        }
        return "iOS hat den Systemkanal abgelehnt. Profil, aktive Telefonate und einen anderen aktiven Funkkanal prüfen. System: " + detail
    }
}

@MainActor final class PushRegistrationStatus: ObservableObject {
    static let shared = PushRegistrationStatus()
    @Published var error: String? = UserDefaults.standard.string(forKey: "rjlove.push-registration-error") {
        didSet { UserDefaults.standard.set(error, forKey: "rjlove.push-registration-error") }
    }
    func failed(_ error: Error) {
        let value = error as NSError
        self.error = "\(value.domain) (\(value.code)): \(value.localizedDescription)"
        UserDefaults.standard.removeObject(forKey: NotificationCoordinator.deviceTokenKey)
    }
}
