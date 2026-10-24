import Foundation

enum NearbySearchPolicy {
    static func shouldStart(enabled:Bool,foreground:Bool,partnerAvailable:Bool,running:Bool,permissionBlocked:Bool,retryAfter:Date?,now:Date = .now)->Bool {
        enabled && foreground && partnerAvailable && !running && !permissionBlocked && (retryAfter.map{$0 <= now} ?? true)
    }
    static func sessionAllowed(deadline:Date,foreground:Bool,automatic:Bool,now:Date = .now)->Bool { (foreground && automatic) || deadline > now }
    static func tokenLifetime(backgroundEnabled:Bool,foreground:Bool,deadline:Date,now:Date = .now)->Int {
        guard backgroundEnabled else{return 20}
        return foreground ? 900:max(20,min(900,Int(deadline.timeIntervalSince(now))))
    }
}
