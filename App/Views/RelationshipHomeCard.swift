import SwiftUI

struct RelationshipHomeCard:View {
    @Environment(AppState.self) private var app
    private var anniversary:LoveCountdown? {app.records.filter{$0.kind == .milestone && $0.payload.countdownType=="anniversary"}.sorted{$0.updatedAt>$1.updatedAt}.compactMap(LoveCountdown.init).first}
    var body:some View {
        NavigationLink{CountdownHubView()}label:{TimelineView(.periodic(from:.now,by:60)){context in
            VStack(alignment:.leading,spacing:16){
                HStack{LoveEyebrow(text:"Unsere Zeit");Spacer();Image(systemName:"heart.fill").foregroundStyle(LovePalette.pink)}
                if let item=anniversary,let origin=item.origin {
                    let time=RelationshipMilestones(start:origin,now:context.date)
                    Text(time.startsInFuture ? "Ein Anfang voller Vorfreude.":"Im \(time.currentMonth). Monat miteinander.").font(.system(size:29,weight:.medium,design:.serif))
                    Text("Seit "+origin.formatted(date:.long,time:.omitted)).font(.caption).foregroundStyle(.secondary)
                    HStack(alignment:.top,spacing:14){metric("\(time.completedMonths)","volle Monate","heart.circle.fill");metric("\(time.togetherDays)","gemeinsame Tage","sun.max.fill")}
                    Divider()
                    Label(time.startsInFuture ? "Noch \(time.daysUntilMonthly) Tage bis zu eurem Anfang":"Noch \(time.daysUntilMonthly) Tage bis zum \(time.nextMonthlyNumber). Monatstag",systemImage:"calendar.badge.heart").font(.subheadline.bold())
                    if let days=item.days(at:context.date){Text(days==0 ? "Heute ist euer Jahrestag 💗":"Euer nächster Jahrestag in \(days) Tagen").font(.caption).foregroundStyle(LovePalette.pink)}
                }else{Text("Jeder Monat ein bisschen mehr wir.").font(.system(size:28,weight:.medium,design:.serif));Text("Tragt euren Beziehungsbeginn ein. Wir zählen eure Monate, Monatstage und den nächsten Jahrestag.").font(.subheadline).foregroundStyle(.secondary)}
            }.loveCard()
        }}.buttonStyle(.lovePress).accessibilityIdentifier("relationship-home-card")
    }
    private func metric(_ value:String,_ title:String,_ icon:String)->some View {VStack(alignment:.leading,spacing:7){Image(systemName:icon).foregroundStyle(LovePalette.pink);Text(value).font(.system(.title,design:.rounded,weight:.semibold));Text(title).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading)}
}
