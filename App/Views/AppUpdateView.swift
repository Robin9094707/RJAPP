import SwiftUI
import UniformTypeIdentifiers
import UIKit
struct AppUpdateView:View {
    @Environment(AppState.self) private var app
    @State private var release:AppRelease?
    @State private var importing=false
    @State private var uploading=false
    @State private var feedURL:URL?
    @State private var error:String?
    @State private var sharedFile:URL?
    @State private var share=false
    var body:some View {ScrollView{VStack(alignment:.leading,spacing:22){
        Image(systemName:"arrow.down.app.fill").font(.system(size:50)).foregroundStyle(LovePalette.violet)
        Text("Immer unser neuestes Wir.").font(.system(size:32,weight:.medium,design:.serif))
        Text("Installiert: \(RJVersion.app)").font(.headline)
        if let release{Text("Auf eurem Server: \(release.version) (\(release.build))").font(.title3.bold());Text(RJVersion.older(RJVersion.app,than:release.version) ? "Ein neues Update wartet auf euch.":"Du hast diese Version oder eine neuere.").foregroundStyle(.secondary)}else{Text("Noch keine IPA auf eurem Server freigegeben.").foregroundStyle(.secondary)}
        Button("Neue RJ-Love-IPA hochladen",systemImage:"square.and.arrow.up"){importing=true}.buttonStyle(.borderedProminent).disabled(uploading)
        if uploading{ProgressView(value:MediaTransfer.shared.progress);Text("Upload \(Int(MediaTransfer.shared.progress*100)) %").font(.caption)}
        if release != nil {Button("IPA laden & in Feather öffnen",systemImage:"square.and.arrow.down"){Task{do{sharedFile=try await app.api.latestIPA();share=true}catch{self.error=error.localizedDescription}}}.buttonStyle(.bordered)}
        Button("Private Feather-Quelle erstellen",systemImage:"link"){Task{do{let token=try await app.api.updateFeedToken(baseURL:app.profile?.baseURL ?? "");if let base=app.profile?.baseURL{feedURL=URL(string:base+"/updates/"+token+"/source.json")}}catch{self.error=error.localizedDescription}}}.buttonStyle(.bordered)
        if let feedURL{Text(feedURL.absoluteString).font(.caption.monospaced()).textSelection(.enabled);Button("Quelladresse kopieren"){UIPasteboard.general.url=feedURL};ShareLink(item:feedURL){Label("Quelle teilen",systemImage:"square.and.arrow.up")}}
        Text("In Feather unter Quellen die kopierte Adresse hinzufügen. Neue hochgeladene IPAs erscheinen in dieser privaten Quelle und werden dort mit eurem Zertifikat signiert und installiert. Eine neue Quelladresse widerruft die vorherige Adresse dieses Kontos.").font(.subheadline)
        Text("Die Quelle gibt nur die zuletzt veröffentlichte RJ-Love-IPA frei, keine persönlichen Inhalte. Ihre geheime Adresse vertraulich behandeln. Bei einem Reverse-Proxy wird die Quelladresse aus der gespeicherten HTTPS-Serveradresse erzeugt.").font(.footnote).foregroundStyle(.secondary)
        Text("Eine App kann ihr eigenes signiertes Programm nicht selbst ersetzen. Feather übernimmt den Installationsschritt; Haupt-App und Widget gemeinsam signieren.").font(.footnote).foregroundStyle(.secondary)
        if let error{Text(error).foregroundStyle(.orange)}
    }.padding(24)}.background(LoveBackground()).navigationTitle("App & Feather").task{do{release=try await app.api.latestRelease()}catch{self.error=error.localizedDescription}}
        .sheet(isPresented:$share,onDismiss:{if let sharedFile{try? FileManager.default.removeItem(at:sharedFile)};sharedFile=nil}){if let sharedFile{FileShareView(urls:[sharedFile])}}
        .fileImporter(isPresented:$importing,allowedContentTypes:[UTType(filenameExtension:"ipa") ?? .data]){result in switch result{case .success(let url):Task{await upload(url)};case .failure(let error):self.error=error.localizedDescription}}
    }
    private func upload(_ url:URL) async {
        uploading=true;defer{uploading=false};let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        do {let copied=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".ipa");try FileManager.default.copyItem(at:url,to:copied);defer{try? FileManager.default.removeItem(at:copied)};let ids=try await MediaTransfer.shared.upload(SelectedMedia(files:[copied],mimeTypes:["application/octet-stream"],kind:"ipa",capturedAt:.now,poster:nil),api:app.api);if let id=ids.first{release=try await app.api.publishIPA(assetID:id);error=nil}}
        catch{self.error=error.localizedDescription}
    }
}
