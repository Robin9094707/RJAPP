import AppIntents
import SwiftUI
import WidgetKit

struct DropPoopControl:ControlWidget {
    var body:some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:"eu.rjuhas.rjlove.drop-poop"){ControlWidgetButton(action:LogPoopIntent()){Label("Drop-Poop",systemImage:"toilet.fill")}}
            .displayName("Drop-Poop").description("Öffnet euren privaten Thronbericht. Du bestätigst den Eintrag und entscheidest über den Standort.")
    }
}
struct DropPoopWidget:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:"RJLoveDropPoopWidget",provider:LoveTimelineProvider()){entry in
            VStack(alignment:.leading,spacing:10){HStack{Text("💩").font(.largeTitle);Spacer();Text("Nur wir zwei").font(.caption2).foregroundStyle(.secondary)};Text("Drop-Poop").font(.headline);Text("Ein kleines Geschäft.\nEine große Geschichte.").font(.caption).foregroundStyle(.secondary);Button(intent:LogPoopIntent()){Label("Drop setzen",systemImage:"plus.circle.fill")}.buttonStyle(.borderedProminent)}.modifier(WidgetConnectionStatus()).containerBackground(.fill.tertiary,for:.widget).widgetURL(URL(string:"rjlove://poop"))
        }.configurationDisplayName("Drop-Poop").description("Euer privates Thronarchiv. Ein Tipp öffnet einen neuen Eintrag, ohne heimlich einen Ort zu speichern.").supportedFamilies([.systemSmall,.systemMedium])
    }
}
struct RelationshipMonthWidget:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:"RJLoveRelationshipMonthWidget",provider:LoveTimelineProvider()){entry in
            let item=(entry.snapshot.countdowns ?? []).first{$0.anniversary}
            VStack(alignment:.leading,spacing:10){Label("Unsere Zeit",systemImage:"heart.fill").font(.caption.bold()).foregroundStyle(.pink)
                if let item,let start=item.origin {let time=RelationshipMilestones(start:start,now:entry.date);Text(time.startsInFuture ? "Bald beginnt unser Wir":"Im \(time.currentMonth). Monat").font(.title2.bold());Text("\(time.completedMonths) volle Monate · \(time.togetherDays) Tage").font(.caption);Text(time.startsInFuture ? "Noch \(time.daysUntilMonthly) Tage bis zum Anfang":"Nächster Monatstag in \(time.daysUntilMonthly) Tagen").font(.caption2).foregroundStyle(.secondary);if let days=item.days(at:entry.date){Text(days==0 ? "Heute ist euer Jahrestag 💗":"Jahrestag in \(days) Tagen").font(.caption2).foregroundStyle(.pink)}}
                else{Text("Euer Anfang zählt.").font(.headline);Text("Beziehungsbeginn in der App eintragen.").font(.caption).foregroundStyle(.secondary)}
            }.modifier(WidgetConnectionStatus()).containerBackground(.fill.tertiary,for:.widget).widgetURL(URL(string:"rjlove://countdowns"))
        }.configurationDisplayName("Unsere Beziehungsmonate").description("Vollendete Monate, der aktuelle Beziehungsmonat und eure nächsten kleinen Jahrestage.").supportedFamilies([.systemSmall,.systemMedium])
    }
}

struct CoupleExtrasWidgets:WidgetBundle {var body:some Widget {RJPartnerLocationWidget();EmergencyFartControl();DropPoopWidget();DropPoopControl();RelationshipMonthWidget()}}

