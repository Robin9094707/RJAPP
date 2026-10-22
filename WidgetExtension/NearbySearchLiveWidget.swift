import ActivityKit
import SwiftUI
import WidgetKit

struct NearbySearchLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NearbySearchAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.title).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 5) {
                    Text("RJ Love · Dich finden").font(.headline)
                    Text("Aktive Nahbereichssuche").font(.caption)
                    Text(timerInterval: Date.now...max(.now, context.attributes.until), countsDown: true).font(.caption.monospacedDigit())
                }
                Spacer()
                Link("Beenden", destination: URL(string: "rjlove://stop-nearby")!).font(.caption.bold())
            }.padding(18).activityBackgroundTint(Color.black.opacity(0.85)).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Label("Nahbereichssuche aktiv", systemImage: "dot.radiowaves.left.and.right") }
                DynamicIslandExpandedRegion(.bottom) { Link("Suche beenden", destination: URL(string: "rjlove://stop-nearby")!) }
            } compactLeading: { Image(systemName: "location.fill") }
                compactTrailing: { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                minimal: { Image(systemName: "location.fill") }
                .widgetURL(URL(string: "rjlove://home"))
        }
    }
}

struct RJLoveLiveWidgets: WidgetBundle {
    var body: some Widget {
        ConnectionLiveActivityWidget()
        NearbySearchLiveWidget()
        RJLoveAlarmLiveActivityWidget()
    }
}
