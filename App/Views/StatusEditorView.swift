import SwiftUI

/// A navigation destination. Presentation and detents belong only to its sheet host.
struct StatusEditorView:View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text=""
    @State private var hours=2
    @State private var quiet=false
    @State private var saving=false
    @State private var loaded=false
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:24){
            VStack(alignment:.leading,spacing:16){LoveEyebrow(text:"Ein kleines Zeichen von dir");Text("So bin ich\ngerade da.").font(.system(size:34,weight:.medium,design:.serif));HStack(spacing:14){PartnerAvatar(name:app.me?.displayName ?? "Du",size:48);VStack(alignment:.leading,spacing:5){Text(app.me?.displayName ?? "Du").font(.headline);Text(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "Dein Status erscheint hier":text).font(.subheadline).foregroundStyle(.secondary);if quiet{Label("Bitte nicht stören",systemImage:"moon.fill").font(.caption.bold()).foregroundStyle(LovePalette.violet)}};Spacer(minLength:0)}}.loveCard()
            VStack(alignment:.leading,spacing:16){LoveSectionTitle("In deinen Worten");TextField("Wie geht es dir gerade?",text:$text,axis:.vertical).lineLimit(2...4).padding(14).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:16)).accessibilityIdentifier("status-text");Text("\(text.count) / 120 Zeichen").font(.caption).foregroundStyle(text.count>120 ? .red:.secondary).frame(maxWidth:.infinity,alignment:.trailing);LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){preset("😴","Schlafe gerade");preset("💗","Denke an dich");preset("🤗","Brauche Nähe");preset("🎮","Bin am Spielen")}}.loveCard()
            VStack(alignment:.leading,spacing:18){LoveSectionTitle("Für eine kleine Weile");Picker("Dauer",selection:$hours){Text("Bis ich es ändere").tag(0);ForEach([1,2,4,8],id:\.self){Text("\($0) Stunden").tag($0)}}.tint(LovePalette.pink);Divider();Toggle(isOn:$quiet){Label("Bitte nicht stören",systemImage:"moon.fill")}.onChange(of:quiet){_,value in if value,hours==0{hours=8}};Text("Bis zu acht Stunden Ruhe vor normalen RJ-Love-Mitteilungen. Bewusste Weckrufe bleiben möglich. Dein iOS-Fokus wird nicht verändert.").font(.caption).foregroundStyle(.secondary)}.loveCard()
            Button("Meinen Status entfernen",role:.destructive){save(clear:true)}.font(.subheadline).disabled(saving).frame(maxWidth:.infinity).padding(.vertical,8)
        }.padding(20)}.background(LoveBackground()).navigationTitle("Mein Status").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge:.bottom){Button(saving ? "Wird geteilt …":"Status teilen",systemImage:"checkmark"){save()}.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth:.infinity).disabled(saving || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count>120).padding(.horizontal,20).padding(.vertical,12).background(.bar)}
        .interactiveDismissDisabled(saving)
        .onAppear{guard !loaded else{return};loaded=true;text=app.myStatus==nil ? app.statusMessage:app.myStatus?.visibleStatus ?? "";quiet=app.myStatus?.isQuiet ?? false}
    }
    private func preset(_ emoji:String,_ value:String)->some View {
        Button{text=emoji+" "+value;Haptics.impact(.soft)}label:{VStack(alignment:.leading,spacing:9){Text(emoji).font(.title2);Text(value).font(.caption.weight(.medium)).foregroundStyle(.primary)}.frame(maxWidth:.infinity,alignment:.leading).padding(13).background(LovePalette.pink.opacity(text==emoji+" "+value ? 0.14:0.055),in:RoundedRectangle(cornerRadius:18))}.buttonStyle(.lovePress)
    }
    private func save(clear:Bool=false){saving=true;Task{if await app.setStatus(text:clear ? "":text,hours:clear ? 0:hours,quiet:clear ? false:quiet){dismiss()};saving=false}}
}
struct StatusEditorSheet:View {
    @Environment(\.dismiss) private var dismiss
    var body:some View {NavigationStack{StatusEditorView().toolbar{ToolbarItem(placement:.cancellationAction){Button("Schließen"){dismiss()}}}}.presentationDetents([.large]).presentationDragIndicator(.visible)}
}
