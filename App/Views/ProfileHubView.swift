import SwiftUI

enum ProfileSettingsSection:String,CaseIterable {
    case sharing="Meine Freigaben",permissions="iOS-Berechtigungen",privacy="Privatsphäre & Verhalten",connection="Verbindung & Diagnose",storage="Gemeinsamer Speicher"
}
struct SettingsView:View {
    @Environment(AppState.self) private var app
    @State private var logout=false
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:24){
            profileHero
            VStack(alignment:.leading,spacing:16){
                LoveSectionTitle("Dein Alltag",subtitle:"Alles Wichtige für euer kleines Wir")
                NavigationLink{CinemaView()}label:{LoveSettingsRow(title:"Unser Kino & AirPlay",subtitle:"YouTube, Plex und euer Fernsehabend",symbol:"play.tv.fill",tint:LovePalette.violet)}
                Divider()
                NavigationLink{StatusEditorView()}label:{LoveSettingsRow(title:"Mein Status",subtitle:app.myStatus?.visibleStatus ?? "Wie geht es dir gerade?",symbol:"person.crop.circle.badge.clock",tint:LovePalette.pink)}.accessibilityIdentifier("settings-status")
                Divider()
                NavigationLink{PartnerProfileView()}label:{LoveSettingsRow(title:app.partner?.displayName ?? "Dein Lieblingsmensch",subtitle:"Profil, Aktivität & Datenstände",symbol:"heart.fill",tint:LovePalette.violet)}
                Divider()
                NavigationLink{DropPoopView()}label:{LoveSettingsRow(title:"Drop-Poop",subtitle:"Euer privates Thronarchiv mit Karte",symbol:"toilet.fill",tint:LovePalette.coral)}
                Divider()
                NavigationLink{HealthDashboardView()}label:{LoveSettingsRow(title:"Health & Schlaf",subtitle:"Wohlgefühl und geteilte Werte",symbol:"heart.text.square.fill",tint:LovePalette.coral)}
                Divider()
                NavigationLink{LiveActivitySettingsView()}label:{LoveSettingsRow(title:"Live-Aktivität",subtitle:"Euer Platz auf dem Sperrbildschirm",symbol:"livephoto",tint:LovePalette.cyan)}
            }.loveCard()
            VStack(alignment:.leading,spacing:16){
                LoveSectionTitle("Deine Entscheidung",subtitle:"Freigaben und Ruhe, so wie du sie brauchst")
                NavigationLink{AISettingsView()}label:{LoveSettingsRow(title:"KI-Rückblick",subtitle:"Optional · Freigaben & Kostenkontrolle",symbol:"sparkles",tint:LovePalette.violet)}
                Divider()
                detail(.sharing,"location.fill",LovePalette.cyan,"Standort, Fotos und Health")
                Divider();detail(.privacy,"hand.raised.fill",LovePalette.violet,"Fotowünsche, Wiedergabe & Tagesrückblick")
                Divider();detail(.permissions,"checkmark.shield.fill",LovePalette.pink,"Die Berechtigungen auf deinem iPhone")
            }.loveCard()
            VStack(alignment:.leading,spacing:16){
                LoveSectionTitle("Euer privater Raum")
                NavigationLink{AppUpdateView()}label:{LoveSettingsRow(title:"App aktualisieren",subtitle:"Version "+RJVersion.app,symbol:"arrow.down.app.fill",tint:LovePalette.violet)}
                Divider();detail(.storage,"externaldrive.fill",LovePalette.coral,"Eure geteilten Erinnerungen")
                Divider();NavigationLink{AccountView()}label:{LoveSettingsRow(title:"Mein Zugang",subtitle:"Benutzername & Passwort",symbol:"person.badge.key.fill",tint:LovePalette.cyan)}
                Divider();detail(.connection,"network",LovePalette.cyan,"Server, Synchronisation & Diagnose")
            }.loveCard()
            DisclosureGroup("Weitere Möglichkeiten") {
                VStack(spacing:16){
                    NavigationLink{DeliveryCenterView()}label:{LoveSettingsRow(title:"Push, Wecker & Hintergrund",symbol:"bell.badge.fill")}
                    NavigationLink{CapabilitiesView()}label:{LoveSettingsRow(title:"Funktionen & Signatur",symbol:"checkmark.seal.fill")}
                    Button{app.showingProfile=false;Task{try? await Task.sleep(for:.milliseconds(350));app.setupJourney.presented=true}}label:{LoveSettingsRow(title:"Einrichtung erneut ansehen",symbol:"checklist")}
                }.padding(.top,16)
            }.font(.subheadline.bold()).loveCard()
            Button("Von diesem iPhone abmelden",role:.destructive){logout=true}.font(.subheadline).frame(maxWidth:.infinity).padding(.vertical,10)
            Text("Ein sicherer kleiner Platz für euch zwei.").font(.caption).foregroundStyle(.tertiary).frame(maxWidth:.infinity)
        }.padding(20)}.background(LoveBackground()).navigationTitle("Dein Profil").navigationBarTitleDisplayMode(.inline).buttonStyle(.plain)
        .confirmationDialog("Wirklich abmelden?",isPresented:$logout,titleVisibility:.visible){Button("Abmelden",role:.destructive){Task{await app.logout()}};Button("Bleiben",role:.cancel){}}message:{Text("Du kannst dich mit deinem bestehenden Zugang jederzeit wieder anmelden.")}
    }
    private var profileHero:some View {
        VStack(alignment:.leading,spacing:18){
            HStack(spacing:16){PartnerAvatar(name:app.me?.displayName ?? "Du",size:74);VStack(alignment:.leading,spacing:6){LoveEyebrow(text:"Dein Platz in unserem Wir");Text(app.me?.displayName ?? "Dein Profil").font(.system(size:30,weight:.medium,design:.serif));if app.myStatus?.isQuiet==true{Label("Gerade in Ruhe",systemImage:"moon.fill").font(.caption).foregroundStyle(LovePalette.violet)}};Spacer(minLength:0)}
            Text(app.myStatus?.visibleStatus ?? "Du darfst hier ganz du selbst sein.").font(.subheadline).foregroundStyle(.secondary)
        }.loveCard()
    }
    private func detail(_ section:ProfileSettingsSection,_ symbol:String,_ tint:Color,_ subtitle:String)->some View {
        NavigationLink{ProfileSettingsDetailView(section:section)}label:{LoveSettingsRow(title:section.rawValue,subtitle:subtitle,symbol:symbol,tint:tint)}
    }
}
