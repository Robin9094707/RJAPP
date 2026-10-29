import SwiftUI

struct PartnerProfileView:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    private var partner:PartnerSnapshot? {app.partner}
    private var activity:PartnerActivity? {partner.flatMap{app.activity[$0.id]}}
    var body:some View {
        ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    VStack(spacing:12) {
                        PartnerAvatar(name:partner?.displayName ?? "Schatzi",size:100)
                        Text(partner?.displayName ?? "Dein Lieblingsmensch").font(.largeTitle.bold())
                        if let status=partner?.presence?.visibleStatus {Text(status).font(.title3).multilineTextAlignment(.center)}
                        if partner?.presence?.isQuiet == true {Label("Bitte nicht stören",systemImage:"moon.fill").font(.subheadline).foregroundStyle(.secondary)}
                    }.frame(maxWidth:.infinity).padding(.vertical,18)
                    TimelineView(.periodic(from:.now,by:15)) {context in
                        VStack(alignment:.leading,spacing:16) {
                            Label(activity?.recentlyActive(at:context.date)==true ? "Vor kurzem in der App aktiv":"Unser letzter Kontakt",systemImage:"person.crop.circle.badge.checkmark").font(.headline).foregroundStyle(LovePalette.pink)
                            ActivityDateRow(title:"App zuletzt geöffnet",date:partner.flatMap{app.lastOpened[$0.id]},symbol:"app.badge",detail:"Ein bestätigtes Öffnen im Vordergrund.")
                            ActivityDateRow(title:"Zuletzt in der App aktiv",date:activity?.foregroundAt,symbol:"hand.tap",detail:"Letzter empfangener Kontakt aus der geöffneten App.")
                            ActivityDateRow(title:"Gerätedaten aktualisiert",date:partner?.presence?.updatedAt,symbol:"arrow.triangle.2.circlepath",detail:"Akku, Bewegung und freigegebene Gerätedaten am Server angekommen.")
                            ActivityDateRow(title:"Hintergrund erfolgreich",date:activity?.backgroundSyncAt,symbol:"arrow.clockwise.icloud",detail:activity?.backgroundSource ?? "Noch kein erfolgreicher Hintergrundabgleich bestätigt.")
                        }.loveCard()
                    }
                    VStack(alignment:.leading,spacing:16) {
                        Text("Die einzelnen Datenstände").font(.headline)
                        ActivityDateRow(title:"Standort aufgenommen",date:partner?.presence?.locationTimestamp,symbol:"location.fill",detail:partner?.presence?.locationSharing==true ? "Zeitpunkt der Standortmessung auf dem anderen iPhone.":"Standort ist momentan nicht freigegeben.")
                        ActivityDateRow(title:"Health ausgewertet",date:partner?.presence?.healthUpdatedAt,symbol:"heart.text.square",detail:"Zeitpunkt der zuletzt geteilten Health-Zusammenfassung.")
                        ActivityDateRow(title:"Auf deinem iPhone abgeglichen",date:app.lastSync?.rjISO8601,symbol:"iphone",detail:"Wann diese App den Server zuletzt erfolgreich abgerufen hat.")
                    }.loveCard()
                    Text("Eine Hintergrundaktualisierung bedeutet nicht, dass die App geöffnet wurde. Ohne Netz, nach erzwungenem Beenden oder wenn iOS pausiert, bleiben die letzten bestätigten Zeiten stehen. Frühere Zeitpunkte werden nicht nachträglich erfunden.").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink{CountdownHubView()}label:{Label("Jahrestag & Countdowns",systemImage:"calendar.badge.heart")}.buttonStyle(.glass)
                }.padding(20)
            }.background(LoveBackground()).navigationTitle("Dein Lieblingsmensch").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){dismiss()}}}
                .refreshable{_ = await app.syncNow(showErrors:false)}
    }
}
private struct ActivityDateRow:View {
    let title:String
    let date:String?
    let symbol:String
    let detail:String
    var body:some View {
        HStack(alignment:.top,spacing:12) {
            Image(systemName:symbol).font(.title3).foregroundStyle(LovePalette.violet).frame(width:26)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.subheadline.bold())
                if let value=date?.rjDate {
                    Text(value,style:.relative).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Text(value.formatted(.dateTime.day().month(.wide).year().hour().minute().second())).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }else{Text("Noch nicht bestätigt").font(.subheadline).foregroundStyle(.secondary)}
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength:0)
        }.accessibilityElement(children:.combine)
    }
}
