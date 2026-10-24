import SwiftUI
import WidgetKit

struct WidgetConnectionStatus:ViewModifier {
    func body(content:Content)->some View {
        if !WidgetSharedStore.connected {
            VStack(alignment:.leading,spacing:8){Label("RJ Love",systemImage:"heart.fill").foregroundStyle(.pink);Text("Widget nicht verbunden").font(.headline);Text("In der App unter Funktionen & Signatur prüfen.").font(.caption)}.widgetURL(URL(string:"rjlove://settings"))
        }else{content}
    }
}
struct RJPartnerLocationWidget:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:"RJPartnerLocation",provider:LoveTimelineProvider()){entry in
            VStack(alignment:.leading,spacing:10){
                Label("Schatzi finden",systemImage:"location.circle.fill").font(.caption.bold()).foregroundStyle(.pink)
                Text(entry.snapshot.partnerName).font(.headline).lineLimit(1)
                if entry.snapshot.locationSharing != true {Text("Standortfreigabe pausiert").font(.caption)}
                else if let distance=entry.snapshot.distanceMeters,let until=entry.snapshot.distanceValidUntil?.rjDate,entry.date<until {
                    Text(distance<1000 ? "\(distance) m":String(format:"%.1f km",Double(distance)/1000)).font(.title.bold().monospacedDigit())
                }else{Text("Keine aktuelle Entfernung").font(.caption)}
                if let updated=entry.snapshot.locationUpdatedAt?.rjDate {Text("Stand \(updated,style:.relative)").font(.caption2).foregroundStyle(.secondary)}
            }.modifier(WidgetConnectionStatus()).containerBackground(.fill.tertiary,for:.widget).widgetURL(URL(string:"rjlove://map"))
        }.configurationDisplayName("Schatzi finden").description("Freigegebene Entfernung mit Zeitstempel. Antippen öffnet die Partnerkarte.").supportedFamilies([.systemSmall,.systemMedium])
    }
}
