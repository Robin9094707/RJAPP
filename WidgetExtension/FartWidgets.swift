import ActivityKit
import SwiftUI
import WidgetKit

struct RJLoveFartQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RJLoveFartQuickWidget", provider: LoveTimelineProvider()) { entry in
            FartQuickWidgetView().modifier(WidgetConnectionStatus()).containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.20, green: 0.12, blue: 0.32), Color(red: 0.43, green: 0.24, blue: 0.53)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }.widgetURL(URL(string: "rjlove://record-fart"))
        }.configurationDisplayName("Duftpost · Sofortaufnahme")
            .description("Öffnet direkt das Duftstudio und startet nach Mikrofonfreigabe die sichtbare Aufnahme. Ein vorhandener Entwurf wird zuerst geöffnet.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
private struct FartQuickWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if family == .accessoryCircular {
            Image(systemName: "mic.circle.fill").font(.largeTitle).widgetAccentable()
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 4) { Label("Duftpost", systemImage: "wind").font(.headline); Text("Aufnehmen").font(.caption) }
        } else if family == .systemSmall {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: "wind").foregroundStyle(.white.opacity(0.7)); Spacer(); Text("RJ").font(.caption.bold()).foregroundStyle(.white.opacity(0.5)) }
                Spacer(minLength: 0)
                Image(systemName: "mic.fill").font(.system(size: 30)).foregroundStyle(.white)
                Text("Lass es raus.").font(.headline).foregroundStyle(.white)
                Text("Duftstudio öffnen").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        } else {
            HStack(spacing: 18) {
                Image(systemName: "mic.fill").font(.system(size: 32)).foregroundStyle(.white).frame(width: 70, height: 70).background(.white.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 7) {
                    Text("Fürzeinander da.").font(.title3.bold()).foregroundStyle(.white)
                    Text("Ein Tipp öffnet die Sofortaufnahme.").font(.caption).foregroundStyle(.white.opacity(0.8))
                    Label("Duftpost aufnehmen", systemImage: "arrow.up.right").font(.caption.bold()).foregroundStyle(.white)
                }
            }
        }
    }
}
struct FartRecordingLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FartRecordingAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "mic.fill").font(.title2).foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duftstudio").font(.headline)
                    Text(context.state.paused ? "Atempause · Aufnahme pausiert" : "Aufnahme läuft · bis zu 60 Sekunden").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                recordingTimer(context).font(.headline.monospacedDigit())
            }.padding(16).activityBackgroundTint(.black.opacity(0.8)).activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "rjlove://stop-recording"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Duftstudio", systemImage: "mic.fill").foregroundStyle(.pink) }
                DynamicIslandExpandedRegion(.trailing) { recordingTimer(context).font(.headline.monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) {
                    Link(destination: URL(string: "rjlove://stop-recording")!) {
                        Label(context.state.paused ? "Zur Aufnahme" : "Öffnen & stoppen", systemImage: "stop.circle.fill")
                    }.font(.caption.bold())
                }
            } compactLeading: { Image(systemName: "mic.fill").foregroundStyle(.pink) }
            compactTrailing: { recordingTimer(context).font(.caption.monospacedDigit()) }
            minimal: { Image(systemName: "mic.fill").foregroundStyle(.pink) }
                .widgetURL(URL(string: "rjlove://stop-recording")).keylineTint(.pink)
        }
    }
    @ViewBuilder private func recordingTimer(_ context: ActivityViewContext<FartRecordingAttributes>) -> some View {
        if context.state.paused { Text("\(context.state.elapsed)s") }
        else { Text(timerInterval: context.state.startedAt...context.state.startedAt.addingTimeInterval(60), countsDown: false, showsHours: false) }
    }
}
