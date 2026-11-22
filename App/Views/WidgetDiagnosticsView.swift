import SwiftUI
import WidgetKit

struct WidgetDiagnosticsView:View {
    @State private var checked=Date.now
    private var defaults:UserDefaults?{WidgetSharedStore.defaults}
    var body:some View {
        List {
            Section("Gemeinsamer Speicher") {
                Label(WidgetSharedStore.connected ? "Container erreichbar":"Widget nicht verbunden",systemImage:WidgetSharedStore.connected ? "checkmark.circle.fill":"exclamationmark.triangle.fill")
                Text("App Group: "+WidgetSharedStore.suiteName).font(.caption).textSelection(.enabled)
                if let read=defaults?.string(forKey:"rjlove.widget-read-at")?.rjDate {Text("Widget hat den Speicher gelesen: \(read.formatted(date:.abbreviated,time:.shortened))")}
                else{Text("Noch kein bestätigter Zugriff der Widget-Erweiterung. Nach Installation App öffnen und Widget hinzufügen.")}
                if let reader=defaults?.string(forKey:"rjlove.widget-reader"){Text(reader).font(.caption)}
                Button {
                    if WidgetSharedStore.connected {
                        WidgetSharedStore.saveSnapshot(WidgetSharedStore.loadSnapshot())
                    }
                    WidgetCenter.shared.reloadAllTimelines()
                    checked = .now
                } label: {
                    Label("Widget-Daten und Anzeige aktualisieren", systemImage: "arrow.clockwise")
                }.id(checked)
                Text("Die App erkennt automatisch eine App Group, die von der installierten Signatur erlaubt ist. Eine frei eingegebene ID kann keine iOS-Berechtigung hinzufügen.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Signierung") {
                Text("Haupt-App: "+SigningProfile.current.bundleID).font(.caption)
                Text("Profil: "+(SigningProfile.current.applicationID ?? "Nicht eingebettet / nicht lesbar")).font(.caption)
                ForEach(extensionProfiles,id:\.id){item in
                    VStack(alignment:.leading,spacing:6){Text("Widget: "+item.id).font(.caption.bold());Text(item.profile).font(.caption);Text(item.matches ? "Profil passt zur Widget-ID":"Eigenes passendes Widget-Profil fehlt").font(.caption).foregroundStyle(item.matches ? .green:.orange)}
                }
                Text("Ein erreichbarer Container bestätigt noch nicht, dass die Erweiterung installiert und korrekt signiert ist. Der bestätigte Widget-Zugriff oben prüft den tatsächlichen Datenaustausch.")
            }
            Section("Server und Hintergrund") {
                if let date=defaults?.string(forKey:"rjlove.widget-background-synced-at")?.rjDate {
                    Text("Letzter Widget-Hintergrundabruf: \(date.formatted(date:.abbreviated,time:.shortened))")
                } else { Text("Noch kein Widget-Hintergrundabruf bestätigt.") }
                if let date=UserDefaults.standard.string(forKey:"rjlove.last-successful-background-at")?.rjDate {
                    Text("Letzter Server-Hintergrundlauf: \(date.formatted(date:.abbreviated,time:.shortened))")
                }
                if let result=UserDefaults.standard.string(forKey:"rjlove.last-background-result") { Text(result) }
                Text("Die vorhandene Serveradresse und Anmeldung bleiben unverändert. iOS bestimmt, wann Hintergrundläufe stattfinden.")
            }.font(.footnote)
            Section("Beide Zertifikate nutzen") {
                Text("iPhone 17 Pro Max: group.dfbc88d056a46f1b.1")
                Text("iPhone 14 Pro: group.4d9963ba648cf299.1")
                Text("Die App erkennt den tatsächlich verfügbaren Container automatisch. Auf jedem iPhone muss die gleiche unsigned IPA separat mit seinem Zertifikat signiert werden.")
                Text("Die Widget-Erweiterung benötigt eine eigene passende Widget-Bundle-ID und ein Provisioning-Profil mit derselben App Group wie die Haupt-App. Ein App-Eingabefeld kann diese Signierung nicht ersetzen.")
                Text("Standort und Entfernung erscheinen nur mit eurer Freigabe und aktuellen Messungen.")
            }.font(.footnote)
        }.navigationTitle("Widgets verbinden")
    }
    private var extensionProfiles:[(id:String,profile:String,matches:Bool)] {
        guard let folder=Bundle.main.builtInPlugInsURL,let urls=try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) else{return []}
        return urls.filter{$0.pathExtension=="appex"}.compactMap{url in
            guard let bundle=Bundle(url:url),let id=bundle.bundleIdentifier else{return nil}
            let profileURL=url.appendingPathComponent("embedded.mobileprovision")
            guard let data=try? Data(contentsOf:profileURL),let start=data.range(of:Data("<plist".utf8)),let end=data.range(of:Data("</plist>".utf8)),let root=(try? PropertyListSerialization.propertyList(from:data.subdata(in:start.lowerBound..<end.upperBound),format:nil)) as? [String:Any],let e=root["Entitlements"] as? [String:Any],let app=e["application-identifier"] as? String else{return (id,"Kein lesbares Widget-Profil",false)}
            return (id,app,app.hasSuffix("."+id) && (e["com.apple.security.application-groups"] as? [String] ?? []).contains(WidgetSharedStore.suiteName))
        }
    }
}
