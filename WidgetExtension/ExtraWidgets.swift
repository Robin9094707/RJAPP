import SwiftUI
import WidgetKit

struct RJLoveHealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RJLoveHealthWidget", provider: LoveTimelineProvider()) { entry in
            VStack(alignment: .leading, spacing: 12) {
                Label(entry.snapshot.partnerName, systemImage: "heart.text.square.fill").font(.headline).foregroundStyle(.pink)
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Schritte", systemImage: "figure.walk").font(.caption).foregroundStyle(.secondary)
                        Text(entry.snapshot.partnerSteps?.formatted() ?? "–").font(.title2.bold().monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Schlaf · 24 Std.", systemImage: "moon.zzz.fill").font(.caption).foregroundStyle(.secondary)
                        Text(entry.snapshot.partnerSleepMinutes.map { "\($0 / 60) h \($0 % 60)" } ?? "–").font(.title2.bold().monospacedDigit())
                    }
                }
                if let date = entry.snapshot.lastSync?.rjDate { Text("App-Abgleich \(date, style: .relative)").font(.caption2).foregroundStyle(.secondary) }
            }.containerBackground(.fill.tertiary, for: .widget).widgetURL(URL(string: "rjlove://health"))
        }.configurationDisplayName("Euer Wohlgefühl").description("Bewusst geteilte Schritte und Schlafdauer. Zeigt den letzten App-Abgleich.").supportedFamilies([.systemMedium])
    }
}

struct RJLoveCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RJLoveCountdownWidget", provider: LoveTimelineProvider()) { entry in
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "calendar.badge.heart").font(.title2).foregroundStyle(.pink)
                if let date = entry.snapshot.milestoneDate?.rjDate {
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: entry.date), to: Calendar.current.startOfDay(for: date)).day ?? 0
                    Text(abs(days).formatted()).font(.system(size: 44, weight: .light, design: .serif)).minimumScaleFactor(0.6)
                    Text(days < 0 ? "Tage voller Wir" : "Tage Vorfreude").font(.caption2).foregroundStyle(.secondary)
                    Text(entry.snapshot.milestoneTitle ?? "Unsere Zeit").font(.caption.bold()).lineLimit(2)
                } else {
                    Text("Unsere Zeit").font(.headline)
                    Text("Legt euren ersten besonderen Tag in der App an.").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .containerBackground(.fill.tertiary, for: .widget).widgetURL(URL(string: "rjlove://together"))
        }.configurationDisplayName("Unsere Zeit").description("Euer besonderer Tag als Countdown oder gemeinsame Tage.").supportedFamilies([.systemSmall])
    }
}

struct RJLoveLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RJLoveLockWidget", provider: LoveTimelineProvider()) { entry in
            LockLoveView(entry: entry).containerBackground(.fill.tertiary, for: .widget).widgetURL(URL(string: "rjlove://home"))
        }.configurationDisplayName("Ein Stück Wir").description("Herzgedanken auf eurem Sperrbildschirm.").supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
private struct LockLoveView: View {
    let entry: LoveTimelineEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(entry.snapshot.partnerName) · \(entry.snapshot.partnerThoughts) Herzen", systemImage: "heart.fill")
        case .accessoryCircular:
            VStack(spacing: 2) { Image(systemName: "heart.fill"); Text(entry.snapshot.partnerThoughts.formatted()).font(.headline) }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label(entry.snapshot.partnerName, systemImage: "heart.fill").font(.headline)
                Text("\(entry.snapshot.partnerThoughts) Herzgedanken heute").font(.caption)
                Text("Letzter App-Abgleich").font(.caption2)
            }
        }
    }
}
