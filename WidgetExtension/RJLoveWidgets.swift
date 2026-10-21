import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

struct LoveTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct LoveTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LoveTimelineEntry {
        LoveTimelineEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                partnerName: "Schatzi",
                partnerBattery: 82,
                partnerBatteryState: "unplugged",
                partnerNetwork: "wifi",
                partnerMotion: "Zu Fuß",
                partnerLastSeen: Date.now.rjISO8601,
                myThoughts: 4,
                partnerThoughts: 7,
                lastSync: Date.now.rjISO8601
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LoveTimelineEntry) -> Void) {
        completion(LoveTimelineEntry(date: .now, snapshot: WidgetSharedStore.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LoveTimelineEntry>) -> Void) {
        let entry = LoveTimelineEntry(date: .now, snapshot: WidgetSharedStore.loadSnapshot())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct RJLoveThoughtWidget: Widget {
    let kind = "RJLoveThoughtWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LoveTimelineProvider()) { entry in
            ThoughtWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.11, green: 0.08, blue: 0.22), Color(red: 0.34, green: 0.08, blue: 0.26)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Herzgedanke")
        .description("Ein Tipp merkt vor, dass du an dein Schatzi denkst.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ThoughtWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LoveTimelineEntry

    var body: some View {
        if family == .systemSmall {
            VStack(spacing: 9) {
                Text("Für \(entry.snapshot.partnerName)")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                Button(intent: SendThoughtIntent()) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(.pink.gradient, in: Circle())
                }
                .buttonStyle(.plain)
                Text("Heute \(entry.snapshot.myThoughts)×")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        } else {
            HStack(spacing: 16) {
                Button(intent: SendThoughtIntent()) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(.pink.gradient, in: Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 7) {
                    Text("An \(entry.snapshot.partnerName) denken")
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack {
                        Label("Du \(entry.snapshot.myThoughts)×", systemImage: "heart.fill")
                        Label("Schatzi \(entry.snapshot.partnerThoughts)×", systemImage: "heart.circle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.76))
                    Text("Wird beim nächsten App-Sync gesendet")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.56))
                }
            }
        }
    }
}

struct RJLoveStatusWidget: Widget {
    let kind = "RJLoveStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LoveTimelineProvider()) { entry in
            PartnerStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.02, green: 0.12, blue: 0.23), Color(red: 0.09, green: 0.28, blue: 0.32)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .widgetURL(URL(string: "rjlove://map"))
        }
        .configurationDisplayName("Schatzi-Status")
        .description("Akku, Verbindung, Bewegung und letzter Stand auf einen Blick.")
        .supportedFamilies([.systemMedium])
    }
}

private struct PartnerStatusWidgetView: View {
    let entry: LoveTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: "location.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                Text(entry.snapshot.partnerName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Label(
                    entry.snapshot.partnerBattery.map { "\($0) %" } ?? "– %",
                    systemImage: entry.snapshot.partnerBatteryState == "charging" ? "battery.100percent.bolt" : "battery.75percent"
                )
                .font(.subheadline.bold())
                .foregroundStyle(entry.snapshot.partnerBatteryState == "charging" ? .green : .white)
            }
            HStack(spacing: 12) {
                status(entry.snapshot.partnerNetwork == "wifi" ? "WLAN" : entry.snapshot.partnerNetwork == "cellular" ? "Mobilfunk" : "Offline", symbol: entry.snapshot.partnerNetwork == "wifi" ? "wifi" : "antenna.radiowaves.left.and.right")
                status(entry.snapshot.partnerMotion ?? "Unbekannt", symbol: motionSymbol)
            }
            if let value = entry.snapshot.partnerLastSeen?.rjDate {
                Text("Aktualisiert \(value, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private func status(_ value: String, symbol: String) -> some View {
        Label(value, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.10), in: Capsule())
    }

    private var motionSymbol: String {
        switch entry.snapshot.partnerMotion {
        case "Auto": "car.fill"
        case "Fahrrad": "bicycle"
        case "Laufen": "figure.run"
        case "Zu Fuß": "figure.walk"
        default: "figure.stand"
        }
    }
}

struct ConnectionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConnectionActivityAttributes.self) { context in
            HStack(spacing: 13) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.partnerName).font(.headline)
                    Text(context.isStale ? "Stand veraltet · App öffnen" : context.state.motion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let battery = context.state.battery {
                    Label("\(battery) %", systemImage: "battery.75percent")
                        .font(.subheadline.bold())
                }
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.75))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "rjlove://home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.partnerName, systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.battery.map { "\($0) %" } ?? "– %")
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(context.state.motion, systemImage: "location.fill")
                        Spacer()
                        Text("Du \(context.state.myThoughts)× · Schatzi \(context.state.partnerThoughts)×")
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            } compactTrailing: {
                Text(context.state.battery.map { "\($0)%" } ?? "–")
                    .font(.caption.bold().monospacedDigit())
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            }
            .widgetURL(URL(string: "rjlove://home"))
            .keylineTint(.pink)
        }
    }
}

struct RJLoveAlarmLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<RJLoveAlarmMetadata>.self) { context in
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "alarm.waves.left.and.right.fill")
                        .font(.title2)
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading) {
                        Text(metadata(context).title).font(.headline).lineLimit(2)
                        Text("Von \(metadata(context).senderName)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    alarmTime(context).font(.title3.bold().monospacedDigit())
                }
                Button(intent: StopLoveAlarmIntent(alarmID: context.state.alarmID.uuidString)) {
                    Label("Weckruf stoppen", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }
            .padding(16)
            .activityBackgroundTint(.black.opacity(0.78))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill").foregroundStyle(.pink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    alarmTime(context).font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(metadata(context).title).font(.caption).lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            } compactTrailing: {
                alarmTime(context).font(.caption.bold().monospacedDigit())
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(.pink)
            }
            .keylineTint(.pink)
        }
    }

    @ViewBuilder
    private func alarmTime(_ context: ActivityViewContext<AlarmAttributes<RJLoveAlarmMetadata>>) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...max(countdown.fireDate, Date.now), countsDown: true, showsHours: true)
        case .paused(let paused):
            Text(Duration.seconds(max(0, paused.totalCountdownDuration - paused.previouslyElapsedDuration)), format: .time(pattern: .minuteSecond))
        case .alert:
            Text("Jetzt")
        @unknown default:
            Text("–")
        }
    }

    private func metadata(_ context: ActivityViewContext<AlarmAttributes<RJLoveAlarmMetadata>>) -> RJLoveAlarmMetadata {
        context.attributes.metadata ?? RJLoveAlarmMetadata(
            commandID: context.state.alarmID.uuidString,
            title: "Schatzi möchte dich wecken 💗",
            senderName: "Schatzi"
        )
    }
}

@main
struct RJLoveWidgetBundle: WidgetBundle {
    var body: some Widget {
        RJLoveThoughtWidget()
        RJLoveStatusWidget()
        RJLoveHealthWidget()
        RJLoveCountdownWidget()
        RJLoveLockWidget()
        RJLoveFartQuickWidget()
        RJLoveRadioWidget()
        FartRecordingLiveWidget()
        ConnectionLiveActivityWidget()
        RJLoveAlarmLiveActivityWidget()
    }
}
