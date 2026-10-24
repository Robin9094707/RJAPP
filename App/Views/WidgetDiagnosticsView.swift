import SwiftUI

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
                Button("Status neu prüfen"){checked = .now}.id(checked)
            }
            Section("Signierung") {
                Text("Haupt-App: "+SigningProfile.current.bundleID).font(.caption)
                Text("Profil: "+(SigningProfile.current.applicationID ?? "Nicht eingebettet / nicht lesbar")).font(.caption)
                ForEach(extensionProfiles,id:\.id){item in
                    VStack(alignment:.leading,spacing:6){Text("Widget: "+item.id).font(.caption.bold());Text(item.profile).font(.caption);Text(item.matches ? "Profil passt zur Widget-ID":"Eigenes passendes Widget-Profil fehlt").font(.caption).foregroundStyle(item.matches ? .green:.orange)}
                }
                Text("Ein erreichbarer Container bestätigt noch nicht, dass die Erweiterung installiert und korrekt signiert ist. Der bestätigte Widget-Zugriff oben prüft den tatsächlichen Datenaustausch.")
            }
            Section("Deine bereitgestellten Profile") {
                Text("Die Profile gelten für app.lake6191.velvet1751 und erlauben diese App Group. Sie enthalten kein separates Profil für die Widget-Erweiterung. Signiere in Feather/ArcticSign beide Targets mit jeweils passenden IDs und Profilen. Eine fremde Haupt-App-ID wird hier nicht automatisch übernommen; so bleiben deine bisherigen App-Daten erreichbar.")
                Text("Standort und Entfernung erscheinen nur mit eurer Freigabe und aktuellen Messungen. Widgets und Live-Aktivitäten zeigen den letzten bestätigten Stand; iOS bestimmt die Aktualisierung im Hintergrund.")
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
