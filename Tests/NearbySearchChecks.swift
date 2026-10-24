import Foundation
@main enum NearbySearchChecks {
    static func main(){
        let now=Date(timeIntervalSince1970:1000)
        func start(_ enabled:Bool=true,_ foreground:Bool=true,_ partner:Bool=true,_ running:Bool=false,_ blocked:Bool=false,_ retry:Date?=nil)->Bool {NearbySearchPolicy.shouldStart(enabled:enabled,foreground:foreground,partnerAvailable:partner,running:running,permissionBlocked:blocked,retryAfter:retry,now:now)}
        precondition(start())
        precondition(!start(false));precondition(!start(true,false));precondition(!start(true,true,false));precondition(!start(true,true,true,true));precondition(!start(true,true,true,false,true));precondition(!start(true,true,true,false,false,now.addingTimeInterval(10)))
        precondition(start(true,true,true,false,false,now.addingTimeInterval(-1)))
        precondition(NearbySearchPolicy.sessionAllowed(deadline:now.addingTimeInterval(-1),foreground:true,automatic:true,now:now))
        precondition(!NearbySearchPolicy.sessionAllowed(deadline:now.addingTimeInterval(-1),foreground:false,automatic:true,now:now))
        precondition(!NearbySearchPolicy.sessionAllowed(deadline:now.addingTimeInterval(-1),foreground:true,automatic:false,now:now))
        precondition(NearbySearchPolicy.tokenLifetime(backgroundEnabled:true,foreground:true,deadline:now,now:now)==900)
        precondition(NearbySearchPolicy.tokenLifetime(backgroundEnabled:true,foreground:false,deadline:now.addingTimeInterval(500),now:now)==500)
        precondition(NearbySearchPolicy.tokenLifetime(backgroundEnabled:false,foreground:true,deadline:now,now:now)==20)
        print("Automatic nearby lifecycle and token lifetime checks passed.")
    }
}
