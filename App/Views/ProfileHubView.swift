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
            LoveGroup("Ganz nach dir") {
                NavigationLink { HomeEditorView() } label: { LoveSettingsRow(title:"Startseite & Navigation",subtitle:"Alle Karten, Schnellzugriffe und bis zu fünf Tabs",symbol:"slider.horizontal.3") }
                LoveRowDivider()
                NavigationLink { TVSettingsView() } label: { LoveSettingsRow(title:"AirPlay gestalten",subtitle:"Widgets, Kamera und Vorschau",symbol:"airplay.video",tint:LovePalette.violet) }
                LoveRowDivider()
                NavigationLink { SettingsBackupView() } label: { LoveSettingsRow(title:"Automatische Sicherung",subtitle:"Deine Einstellungen auf eurem Server",symbol:"arrow.triangle.2.circlepath",tint:LovePalette.cyan) }
                LoveRowDivider()
                NavigationLink { HomeKitView() } label: { LoveSettingsRow(title:"Unser Zuhause",subtitle:"Kameras, Szenen und Geräte",symbol:"house.fill",tint:LovePalette.cyan) }
                LoveRowDivider()
                NavigationLink { DocumentsView() } label: { LoveSettingsRow(title:"Gemeinsame Dokumente",subtitle:"Dateien, Ordner und Favoriten",symbol:"folder.fill",tint:LovePalette.blue) }
            }
            LoveGroup("Für euch zwei") {
                NavigationLink{WalkieView()}label:{LoveSettingsRow(title:"Funk",subtitle:"Sprechen, loslassen – wird laut abgespielt",symbol:"antenna.radiowaves.left.and.right",tint:LovePalette.coral)}
                LoveRowDivider()
                NavigationLink{DailyQuestionView()}label:{LoveSettingsRow(title:"Frage des Tages",subtitle:"Eine Frage, zwei Antworten",symbol:"bubble.left.and.text.bubble.right.fill",tint:LovePalette.violet)}
                LoveRowDivider()
                NavigationLink{InstantGalleryView()}label:{LoveSettingsRow(title:"Fotowünsche & BeReal",subtitle:"Ein Lächeln nur für euch",symbol:"camera.fill",tint:LovePalette.blue)}
            }
            LoveGroup("Dein Alltag") {
                NavigationLink{CinemaView()}label:{LoveSettingsRow(title:"Unser Kino & AirPlay",subtitle:"YouTube, Plex und euer Fernsehabend",symbol:"play.tv.fill",tint:LovePalette.violet)}
                LoveRowDivider()
                NavigationLink{StatusEditorView()}label:{LoveSettingsRow(title:"Mein Status",subtitle:app.myStatus?.visibleStatus ?? "Wie geht es dir gerade?",symbol:"person.crop.circle.badge.clock",tint:LovePalette.pink)}.accessibilityIdentifier("settings-status")
                LoveRowDivider()
                NavigationLink{PartnerProfileView()}label:{LoveSettingsRow(title:app.partner?.displayName ?? "Dein Lieblingsmensch",subtitle:"Profil, Aktivität & Datenstände",symbol:"heart.fill",tint:LovePalette.violet)}
                LoveRowDivider()
                NavigationLink{DropPoopView()}label:{LoveSettingsRow(title:"Drop-Poop",subtitle:"Euer privates Thronarchiv mit Karte",symbol:"toilet.fill",tint:LovePalette.coral)}
                LoveRowDivider()
                NavigationLink{HealthDashboardView()}label:{LoveSettingsRow(title:"Health & Schlaf",subtitle:"Wohlgefühl und geteilte Werte",symbol:"heart.text.square.fill",tint:LovePalette.coral)}
                LoveRowDivider()
                NavigationLink{LiveActivitySettingsView()}label:{LoveSettingsRow(title:"Live-Aktivität",subtitle:"Euer Platz auf dem Sperrbildschirm",symbol:"livephoto",tint:LovePalette.cyan)}
            }
            LoveGroup("Deine Entscheidung",footer:"Freigaben und Ruhe, so wie du sie brauchst.") {
                NavigationLink{AISettingsView()}label:{LoveSettingsRow(title:"KI-Rückblick",subtitle:"Optional · Freigaben & Kostenkontrolle",symbol:"sparkles",tint:LovePalette.violet)}
                LoveRowDivider()
                detail(.sharing,"location.fill",LovePalette.cyan,"Standort, Fotos und Health")
                LoveRowDivider();detail(.privacy,"hand.raised.fill",LovePalette.violet,"Fotowünsche, Wiedergabe & Tagesrückblick")
                LoveRowDivider();detail(.permissions,"checkmark.shield.fill",LovePalette.pink,"Die Berechtigungen auf deinem iPhone")
            }
            LoveGroup("Euer privater Raum") {
                NavigationLink{AppUpdateView()}label:{LoveSettingsRow(title:"App aktualisieren",subtitle:"Version "+RJVersion.app,symbol:"arrow.down.app.fill",tint:LovePalette.violet)}
                LoveRowDivider();detail(.storage,"externaldrive.fill",LovePalette.coral,"Eure geteilten Erinnerungen")
                LoveRowDivider();NavigationLink{AccountView()}label:{LoveSettingsRow(title:"Mein Zugang",subtitle:"Benutzername & Passwort",symbol:"person.badge.key.fill",tint:LovePalette.cyan)}
                LoveRowDivider();detail(.connection,"network",LovePalette.cyan,"Server, Synchronisation & Diagnose")
            }
            LoveGroup("Weitere Möglichkeiten") {
                NavigationLink{DeliveryCenterView()}label:{LoveSettingsRow(title:"Push, Wecker & Hintergrund",symbol:"bell.badge.fill",tint:.red)}
                LoveRowDivider()
                NavigationLink{CapabilitiesView()}label:{LoveSettingsRow(title:"Funktionen & Signatur",symbol:"checkmark.seal.fill",tint:.green)}
                LoveRowDivider()
                Button{app.showingProfile=false;Task{try? await Task.sleep(for:.milliseconds(350));app.setupJourney.presented=true}}label:{LoveSettingsRow(title:"Einrichtung erneut ansehen",symbol:"checklist",tint:.gray)}
            }
            Button("Von diesem iPhone abmelden",role:.destructive){logout=true}.font(.subheadline).frame(maxWidth:.infinity).padding(.vertical,10)
            Text("RJ Love \(RJVersion.app) · Ein sicherer kleiner Platz für euch zwei.").font(.caption).foregroundStyle(.tertiary).frame(maxWidth:.infinity)
        }.padding(20)}.background(LoveBackground()).navigationTitle("Dein Profil").navigationBarTitleDisplayMode(.inline).buttonStyle(.lovePress)
        .confirmationDialog("Wirklich abmelden?",isPresented:$logout,titleVisibility:.visible){Button("Abmelden",role:.destructive){Task{await app.logout()}};Button("Bleiben",role:.cancel){}}message:{Text("Du kannst dich mit deinem bestehenden Zugang jederzeit wieder anmelden.")}
    }
    /// Like the Apple Account header in iOS Settings: big avatar, name, one quiet line.
    private var profileHero:some View {
        NavigationLink{StatusEditorView()}label:{
            HStack(spacing:16){
                PartnerAvatar(name:app.me?.displayName ?? "Du",size:64)
                VStack(alignment:.leading,spacing:3){
                    Text(app.me?.displayName ?? "Dein Profil").font(.title2.weight(.semibold)).foregroundStyle(.primary)
                    Text(app.myStatus?.visibleStatus ?? "Status, Ruhe & Freigaben").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    if app.myStatus?.isQuiet==true{Label("Gerade in Ruhe",systemImage:"moon.fill").font(.caption.weight(.semibold)).foregroundStyle(LovePalette.violet)}
                }
                Spacer(minLength:0)
                Image(systemName:"chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }.loveCard()
        }.accessibilityIdentifier("settings-hero")
    }
    private func detail(_ section:ProfileSettingsSection,_ symbol:String,_ tint:Color,_ subtitle:String)->some View {
        NavigationLink{ProfileSettingsDetailView(section:section)}label:{LoveSettingsRow(title:section.rawValue,subtitle:subtitle,symbol:symbol,tint:tint)}
    }
}
