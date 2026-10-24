import SwiftUI

struct FartCommentsView:View {
    let clip:FartClip
    var initialCommentID: String? = nil
    @FocusState private var commentFocused: Bool
    @AppStorage("rjlove.keyboard-dismiss-after-send") private var closeKeyboardAfterSend=false
    @State private var positioned=false
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var comments:[FartComment]=[]
    @State private var text=""
    @State private var pendingID=UUID().uuidString
    @State private var pendingText:String?
    @State private var loading=false
    @State private var sending=false
    @State private var hasMore=false
    @State private var cursor:String?
    @State private var error:String?
    @State private var deleting:FartComment?
    private var draftKey:String {"rjlove.fart-comment."+(app.profile?.baseURL ?? "")+"."+(app.me?.id ?? "")+"."+clip.id}
    var body:some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:16) {
                        Label(clip.title,systemImage:"cloud.fill").font(.title2.bold()).padding(.bottom,8)
                        if comments.isEmpty && !loading {ContentUnavailableView("Eure Duftpost hat Gesprächsstoff",systemImage:"bubble.left.and.bubble.right",description:Text("Schreibt euch einen Kommentar – auch zu alten Meisterwerken."))}
                        ForEach(comments) { item in commentRow(item).id(item.id) }
                        if loading {ProgressView().frame(maxWidth:.infinity)}
                        if hasMore {Button("Weitere Kommentare laden"){Task{await load(reset:false)}}.disabled(loading)}
                    }.padding(20)
                }.refreshable{await load(reset:true)}
                    .task(id:comments.map(\.id)){if !positioned,let id=initialCommentID,comments.contains(where:{$0.id==id}){await Task.yield();scroll.scrollTo(id,anchor:.center);positioned=true}}
                    .onChange(of:comments.last?.id) {_,value in if sending,let value {withAnimation{scroll.scrollTo(value,anchor:.bottom)}}}
            }
            .safeAreaInset(edge:.bottom) {
                VStack(alignment:.leading,spacing:8) {
                    if let error {Text(error).font(.caption).foregroundStyle(.orange);Button("Erneut laden"){Task{await load(reset:true)}}.font(.caption)}
                    HStack(alignment:.bottom,spacing:12) {
                        TextField("Ein paar Worte zur Duftpost …",text:$text,axis:.vertical).focused($commentFocused).lineLimit(1...5).textFieldStyle(.roundedBorder)
                        Button{commentFocused=false}label:{Image(systemName:"keyboard.chevron.compact.down")}.accessibilityLabel("Tastatur schließen").disabled(!commentFocused)
                        Button {Task{await send()}} label: {if sending {ProgressView()}else{Image(systemName:"arrow.up.circle.fill").font(.title)}}.accessibilityLabel("Kommentar senden").disabled(sending || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count>1000)
                    }
                    Text("\(text.count) / 1000 · Nur für euch zwei").font(.caption2).foregroundStyle(.secondary)
                }.padding(16).background(.regularMaterial)
            }
            .navigationTitle("Kommentare").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){dismiss()}}}
            .alert("Deinen Kommentar löschen?",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})) {
                Button("Löschen",role:.destructive){if let item=deleting{Task{await remove(item)}};deleting=nil}
                Button("Behalten",role:.cancel){deleting=nil}
            }
            .task {text=UserDefaults.standard.string(forKey:draftKey) ?? "";await load(reset:true)}
            .onChange(of:text){_,value in UserDefaults.standard.set(value,forKey:draftKey)}
            .onDisappear{Task{_ = await app.syncNow(showErrors:false)}}
        }.background(LoveBackground())
    }
    private func commentRow(_ item:FartComment)->some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text(item.userID==app.me?.id ? "Du":app.partner?.displayName ?? "Schatzi").font(.subheadline.bold()).foregroundStyle(item.userID==app.me?.id ? LovePalette.violet:LovePalette.pink)
                Spacer()
                if let date=item.createdAt.rjDate {Text(date.formatted(.dateTime.day().month().hour().minute())).font(.caption2).foregroundStyle(.secondary)}
                if item.userID==app.me?.id {Button(role:.destructive){deleting=item}label:{Image(systemName:"trash").font(.caption)}.accessibilityLabel("Eigenen Kommentar löschen")}
            }
            Text(item.text).textSelection(.enabled)
        }.frame(maxWidth:.infinity,alignment:.leading).loveCard()
    }
    private func load(reset:Bool) async {
        guard !loading else{return};loading=true;defer{loading=false}
        do {
            let page=try await app.api.fartComments(id:clip.id,after:reset ? nil:cursor,focus:reset ? initialCommentID:nil)
            if reset {comments=page.comments}else{let ids=Set(comments.map(\.id));comments+=page.comments.filter{!ids.contains($0.id)}}
            comments.sort{($0.createdAt,$0.id)<($1.createdAt,$1.id)}
            hasMore=page.hasMore;cursor=page.nextCursor;error=nil
        }catch{self.error=error.localizedDescription}
    }
    private func send() async {
        sending=true;defer{sending=false}
        let submitted=text
        let message=submitted.trimmingCharacters(in:.whitespacesAndNewlines)
        if pendingText != message {pendingID=UUID().uuidString;pendingText=message}
        do {
            let item=try await app.api.addFartComment(clipID:clip.id,id:pendingID,text:message)
            if !comments.contains(where:{$0.id==item.id}) {comments.append(item);comments.sort{($0.createdAt,$0.id)<($1.createdAt,$1.id)}}
            if text==submitted{text=""};if closeKeyboardAfterSend{commentFocused=false};pendingText=nil;error=nil;Haptics.success()
        }catch{self.error=error.localizedDescription}
    }
    private func remove(_ item:FartComment) async {
        do{try await app.api.deleteFartComment(clipID:clip.id,id:item.id);comments.removeAll{$0.id==item.id};error=nil}catch{self.error=error.localizedDescription}
    }
}

