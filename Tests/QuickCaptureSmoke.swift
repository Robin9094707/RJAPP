import Foundation

// Isolate the intent handoff from WidgetKit and entitlement availability.
enum WidgetSharedStore { static var defaults:UserDefaults? }
@main struct QuickCaptureSmoke {
    static func main() {
        let keys=["rjlove.quick-capture.v2","rjlove.quick-capture.acknowledged"]
        defer {for key in keys {UserDefaults.standard.removeObject(forKey:key)}}
        for key in keys {UserDefaults.standard.removeObject(forKey:key)}
        let first=QuickCaptureRequests.enqueue()
        precondition(QuickCaptureRequests.pending()==first,"Intent lost when App Group is unavailable")
        // Reading never consumes a request before the UI is ready.
        precondition(QuickCaptureRequests.pending()==first)
        QuickCaptureRequests.acknowledge(first.id)
        precondition(QuickCaptureRequests.pending()==nil,"An acknowledged request must not replay")
        let second=QuickCaptureRequests.enqueue()
        precondition(first.id != second.id)
        precondition(QuickCaptureRequests.pending()==second)
        QuickCaptureRequests.acknowledge(first.id)
        precondition(QuickCaptureRequests.pending()==second,"An old acknowledgement removed a newer tap")
        QuickCaptureRequests.acknowledge(second.id)
        let suite="rj-quick-capture-test-"+UUID().uuidString
        WidgetSharedStore.defaults=UserDefaults(suiteName:suite)
        defer {WidgetSharedStore.defaults?.removePersistentDomain(forName:suite)}
        let third=QuickCaptureRequests.enqueue()
        UserDefaults.standard.removeObject(forKey:keys[0])
        precondition(QuickCaptureRequests.pending()==third,"Shared handoff could not be restored")
        QuickCaptureRequests.acknowledge(third.id)
        precondition(QuickCaptureRequests.pending()==nil)
        print("Quick capture handoff passed: missing App Group, delayed mounting, repeated taps, acknowledgement and shared recovery.")
    }
}
