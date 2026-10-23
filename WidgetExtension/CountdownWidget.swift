import AppIntents
import SwiftUI
import WidgetKit

struct CountdownEntity:AppEntity {
    static var typeDisplayRepresentation:TypeDisplayRepresentation="Unser Countdown"
    static var defaultQuery=CountdownQuery()
    var id:String
    var title:String
    var displayRepresentation:DisplayRepresentation {DisplayRepresentation(title:"\(title)")}
}
struct CountdownQuery:EntityQuery {
    func entities(for identifiers:[String]) async throws -> [CountdownEntity] {
        (WidgetSharedStore.loadSnapshot().countdowns ?? []).filter{identifiers.contains($0.id)}.map{CountdownEntity(id:$0.id,title:$0.title)}
    }
    func suggestedEntities() async throws -> [CountdownEntity] {
        (WidgetSharedStore.loadSnapshot().countdowns ?? []).map{CountdownEntity(id:$0.id,title:$0.title)}
    }
}
struct ChooseCountdownIntent:WidgetConfigurationIntent {
    static var title:LocalizedStringResource="Mein Countdown"
    static var description=IntentDescription("Wähle euren Jahrestag oder einen eigenen Countdown. Ohne Auswahl erscheint der nächste Termin.")
    @Parameter(title:"Countdown") var countdown:CountdownEntity?
}
struct CountdownEntry:TimelineEntry {
    var date:Date
    var item:LoveCountdown?
}
struct CountdownProvider:AppIntentTimelineProvider {
    func placeholder(in context:Context)->CountdownEntry {
        CountdownEntry(date:.now,item:LoveCountdown(id:"preview",title:"Unser Jahrestag",date:Date.now.addingTimeInterval(86400*24).rjISO8601,yearly:true,anniversary:true))
    }
    func snapshot(for configuration:ChooseCountdownIntent,in context:Context) async -> CountdownEntry {entry(configuration:configuration,date:.now)}
    func timeline(for configuration:ChooseCountdownIntent,in context:Context) async -> Timeline<CountdownEntry> {
        let now=Date.now
        var dates=(0...24).map{now.addingTimeInterval(Double($0)*3600)}
        let midnight=Calendar.current.startOfDay(for:now)
        dates += (1...7).compactMap{Calendar.current.date(byAdding:.day,value:$0,to:midnight)}
        return Timeline(entries:dates.sorted().map{entry(configuration:configuration,date:$0)},policy:.after(now.addingTimeInterval(15*60)))
    }
    private func entry(configuration:ChooseCountdownIntent,date:Date)->CountdownEntry {
        let items=WidgetSharedStore.loadSnapshot().countdowns ?? []
        let item:LoveCountdown?
        if let chosen=configuration.countdown {item=items.first{$0.id==chosen.id}}
        else {item=items.filter{($0.nextDate(at:date) ?? .distantPast)>=Calendar.current.startOfDay(for:date)}.min{($0.nextDate(at:date) ?? .distantFuture)<($1.nextDate(at:date) ?? .distantFuture)} ?? items.first}
        return CountdownEntry(date:date,item:item)
    }
}
struct RJLovePersonalCountdownWidget:Widget {
    var body:some WidgetConfiguration {
        AppIntentConfiguration(kind:"RJLovePersonalCountdownWidget",intent:ChooseCountdownIntent.self,provider:CountdownProvider()) {entry in
            CountdownWidgetFace(item:entry.item,now:entry.date)
                .containerBackground(.fill.tertiary,for:.widget).widgetURL(URL(string:"rjlove://countdowns"))
        }.configurationDisplayName("Mein Countdown").description("Wähle euren Jahrestag oder einen eigenen Countdown. Jedes Widget kann einen anderen zeigen.").supportedFamilies([.systemSmall,.systemMedium,.accessoryRectangular])
    }
}
struct CountdownWidgetFace:View {
    let item:LoveCountdown?
    let now:Date
    @Environment(\.widgetFamily) private var family
    var body:some View {
        if let item {
            if family == .accessoryRectangular {
                VStack(alignment:.leading,spacing:4) {
                    Label(item.title,systemImage:item.anniversary ? "heart.fill":"calendar").font(.headline).lineLimit(1)
                    Text(dayLabel(item)).font(.subheadline)
                }
            }else{
                VStack(alignment:.leading,spacing:8) {
                    Label(item.anniversary ? "Unser Jahrestag":"Vorfreude",systemImage:item.anniversary ? "heart.fill":"sparkles").font(.caption).foregroundStyle(.pink)
                    Text(item.days(at:now)==0 ? "Heute":abs(item.days(at:now) ?? 0).formatted()).font(.system(size:family == .systemMedium ? 48:40,weight:.light,design:.rounded)).minimumScaleFactor(0.6)
                    Text(item.title).font(.headline).lineLimit(2)
                    Text(dayLabel(item)).font(.caption).foregroundStyle(.secondary)
                    if let date=item.nextDate(at:now),date>now,date.timeIntervalSince(now)<86400,!item.anniversary {
                        Text(timerInterval:now...date,countsDown:true).font(.caption.monospacedDigit())
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }else{
            VStack(alignment:.leading,spacing:8){Label("Unsere Zeit",systemImage:"heart.fill").foregroundStyle(.pink);Text("Countdown in RJ Love anlegen und im Widget auswählen.").font(.caption)}
        }
    }
    private func dayLabel(_ item:LoveCountdown)->String {
        let days=item.days(at:now) ?? 0
        return days==0 ? "Heute ist euer Tag":days<0 ? "Seit \(abs(days)) Tagen":"Noch \(days) Tage"
    }
}
