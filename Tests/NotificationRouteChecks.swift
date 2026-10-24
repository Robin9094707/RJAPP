import Foundation

@main struct NotificationRouteChecks {
    static func main() {
        let id="7D530A72-7EBC-48AD-85E7-965B6393AC16"
        let comment="70616023-A189-4F41-820E-927A503B403E"
        let good=URL(string:"rjlove://open?target=fart-comments&id=\(id)&comment=\(comment)&account=robin")!
        let route=NotificationRoute(url:good)!
        precondition(route.target=="fart-comments" && route.identifier==id && route.commentID==comment && route.account=="robin")
        for text in ["rjlove://open?target=delete&id=\(id)","rjlove://open?target=record","rjlove://open?target=record&id=../../private","rjlove://open?target=chat&target=alarms","rjlove://open?target=chat&url=https://evil.example","https://love.rjuhas.eu/open?target=chat","rjlove://evil/open?target=chat","rjlove://open/execute?target=chat"] {
            precondition(NotificationRoute(url:URL(string:text)!)==nil,"Unsafe or malformed route accepted: \(text)")
        }
        for target in NotificationRoute.targets.subtracting(["record","fart","fart-comments"]) {
            precondition(NotificationRoute(url:URL(string:"rjlove://open?target=\(target)")!) != nil)
        }
        print("Notification routes verified: content IDs, account scope, read-only targets and invalid links.")
    }
}
