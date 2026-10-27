import SwiftUI

enum ExperienceSection: String, CaseIterable, Identifiable {
    case farts = "Duftpost", love = "Liebe", moments = "Momente", cinema = "Kino"
    var id: String { rawValue }
}
struct ExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            Picker("Erleben", selection: $state.experienceSection) {
                ForEach(ExperienceSection.allCases.filter { $0 != .cinema }) { section in
                    Text(section.rawValue).tag(section)
                }
            }.pickerStyle(.segmented).padding(.horizontal, 18).padding(.vertical, 10)
            Group {
            switch state.experienceSection {
            case .farts: FartStudioView()
            case .love: LovePlayView()
            case .moments: MomentsView()
            case .cinema: Color.clear.onAppear { appState.experienceSection = .moments; appState.selectedTab = .cinema }
            }
            }.id(state.experienceSection).transition(.opacity)
        }.animation(reduceMotion ? nil : .smooth(duration: 0.25), value: state.experienceSection)
            .background(LoveBackground()).navigationBarTitleDisplayMode(.inline)
            .onChange(of:appState.experienceSection) { _,_ in dismissKeyboard() }
    }
}
struct PuffMascot: View {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !active || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { i in
                    Image(systemName: "cloud.fill").font(.system(size: 24 + Double(i) * 7))
                        .foregroundStyle(LovePalette.violet.opacity(0.12 + Double(i) * 0.04))
                        .offset(x: CGFloat(46 + i * 23), y: active && !reduceMotion ? CGFloat(sin(time * 2 + Double(i)) * 8 - Double(i) * 12) : CGFloat(-i * 9))
                }
                Image(systemName: "cloud.fill").font(.system(size: 100)).foregroundStyle(LinearGradient(colors: [Color(red: 0.84, green: 0.74, blue: 0.98), LovePalette.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: LovePalette.violet.opacity(0.2), radius: 14, y: 8)
                HStack(spacing: 22) {
                    Capsule().fill(.white).frame(width: 7, height: active ? 4 : 10)
                    Capsule().fill(.white).frame(width: 7, height: active ? 4 : 10)
                }.offset(y: 3)
                Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.95)).offset(y: 21)
            }.offset(y: active && !reduceMotion ? CGFloat(sin(time * 3) * 3) : 0)
        }.accessibilityHidden(true)
    }
}
struct AudioWaveform: View {
    let values: [Double]
    var tint: Color = LovePalette.violet
    var progress: Double = 0
    var body: some View {
        GeometryReader { geometry in
            let levels = values.isEmpty ? Array(repeating: 0.02, count: 40) : values
            Canvas { context, size in
                let stride = size.width / Double(max(1, levels.count))
                for (i, value) in levels.enumerated() {
                    let height = max(3, min(1, value) * size.height)
                    let rect = CGRect(x: Double(i) * stride, y: (size.height - height) / 2, width: max(1, stride * 0.6), height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Double(i) / Double(max(1, levels.count)) <= progress ? tint : tint.opacity(0.35)))
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.accessibilityLabel("Audio-Wellenform")
    }
}

struct FartClipCard: View {
    let clip: FartClip
    @Environment(AppState.self) private var appState
    @State private var rating = false
    @State private var comments = false
    @State private var deleting = false
    @State private var editing = false
    @State private var exporting=false
    @State private var exportURL:URL?
    @State private var localSaving=false
    private var playing: Bool { appState.studio.playingID == clip.id }
    private var mine: Bool { clip.ownerID == appState.me?.id }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                Text(FartCategory(rawValue: clip.category)?.emoji ?? "💨").font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.title).font(.headline)
                    Text("\(mine ? "Von dir" : "Von " + (appState.partner?.displayName ?? "Schatzi")) · \(clip.category)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if mine {
                    Menu { Button("Auf diesem iPhone sichern",systemImage:"square.and.arrow.down"){saveLocal(share:false)};Button("Exportieren / iMessage teilen",systemImage:"square.and.arrow.up"){saveLocal(share:true)}; Button("Schneiden & umbenennen", systemImage: "scissors") { editing = true }; if clip.location != nil { Button("Geteilten Ort entfernen",systemImage: "mappin.slash",role: .destructive) { Task { await appState.removeFartLocation(clip) } } }; Button("Aufnahme löschen", systemImage: "trash", role: .destructive) { deleting = true } } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Aufnahme verwalten")
                } else {
                    Menu {Button("Auf diesem iPhone sichern",systemImage:"square.and.arrow.down"){saveLocal(share:false)};Button("Exportieren / iMessage teilen",systemImage:"square.and.arrow.up"){saveLocal(share:true)}}label:{Image(systemName:"square.and.arrow.down")}
                }
            }
            if localSaving{ProgressView("Wird lokal gesichert …")}
            if !clip.caption.isEmpty { Text(clip.caption).font(.subheadline).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                Button { appState.studio.togglePlayback(clip, api: appState.api) } label: {
                    Group {
                        if appState.studio.loadingID == clip.id { ProgressView().tint(.white) }
                        else { Image(systemName: playing ? "stop.fill" : "play.fill") }
                    }.font(.headline).foregroundStyle(.white).frame(width: 46, height: 46).background(LovePalette.violet, in: Circle())
                }.accessibilityLabel(playing ? "Wiedergabe stoppen" : "Aufnahme abspielen")
                AudioWaveform(values: clip.waveform, progress: playing && appState.studio.playbackDuration > 0 ? appState.studio.playbackTime / appState.studio.playbackDuration : 0).frame(height: 40)
                Text(String(format: "%.1f s", clip.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if playing {
                Slider(value: Binding(get: { appState.studio.playbackDuration > 0 ? appState.studio.playbackTime / appState.studio.playbackDuration : 0 }, set: { appState.studio.seek(to: $0) }), in: 0...1).tint(LovePalette.violet).accessibilityLabel("Wiedergabeposition")
                speedControls
            }
            HStack(spacing: 8) {
                ForEach(["😂", "💨", "❤️", "🏆"], id: \.self) { emoji in
                    let selected = clip.reactions.contains { $0.userID == appState.me?.id && $0.emoji == emoji }
                    Button { Task { await appState.reactToFart(clip, emoji: emoji) } } label: {
                        HStack(spacing: 3) { Text(emoji); Text(clip.reactions.filter { $0.emoji == emoji }.count.formatted()).font(.caption2) }
                            .padding(.horizontal, 9).padding(.vertical, 7).background(selected ? LovePalette.violet.opacity(0.2) : Color.primary.opacity(0.04), in: Capsule())
                    }.buttonStyle(.plain).accessibilityLabel("Reaktion \(emoji)").accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            Button { comments=true } label: {
                Label("Kommentare · \(clip.commentCount ?? 0)",systemImage:"bubble.left.and.bubble.right.fill").font(.subheadline.weight(.semibold))
            }.buttonStyle(.bordered)
            Divider().opacity(0.4)
            HStack {
                Label(clip.stars.map { "\($0)/5 Sterne" } ?? "Jury noch sprachlos", systemImage: "star.fill").font(.caption.bold()).foregroundStyle(LovePalette.coral)
                Spacer()
                if !mine { Button(clip.ratings.isEmpty ? "Bewerten" : "Ändern") { rating = true }.font(.caption.bold()) }
            }
            if let score = clip.ratings.first {
                Text("Wumms \(score.power)/5 · Stil \(score.style)/5").font(.caption2).foregroundStyle(.secondary)
                if !score.comment.isEmpty { Text("„\(score.comment)“").font(.subheadline).italic() }
            }
            if let date = clip.date { Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.caption2).foregroundStyle(.secondary) }
            HStack {
                if let situation = FartSituation(rawValue: clip.situation ?? "alltag") { Label(situation.title,systemImage: situation.symbol) }
                if let point = clip.location { Label("Ort · ca. \(Int(point.accuracy)) m",systemImage: "mappin.circle.fill") }
            }.font(.caption2).foregroundStyle(LovePalette.violet).fixedSize(horizontal: false, vertical: true)
        }.loveCard()
        .sheet(isPresented:$exporting){if let exportURL{FileShareView(urls:[exportURL])}}
        .sheet(isPresented:$comments){FartCommentsView(clip:clip)}
        .sheet(isPresented: $rating) { FartRatingView(clip: clip) }
        .sheet(isPresented: $editing) { FartEditorView(clip: clip) }
        .alert("Dieses Meisterwerk löschen?", isPresented: $deleting) {
            Button("Löschen", role: .destructive) { Task { await appState.deleteFart(clip) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Die Aufnahme und ihre Bewertungen werden für euch beide entfernt.") }
    }
    private func saveLocal(share:Bool){localSaving=true;Task{defer{localSaving=false};do{if let server=appState.profile?.baseURL,let user=appState.me?.id{LocalFartStore.shared.configure(server:server,userID:user)};let file=try await LocalFartStore.shared.save(clip,api:appState.api);if share{exportURL=file;exporting=true}else{Haptics.success()}}catch{appState.alert=AppAlert(title:"Lokales Sichern",message:error.localizedDescription)}}}
    private var speedControls:some View {
        @Bindable var studio=appState.studio
        return VStack(alignment:.leading,spacing:10){
            HStack{Text("Tempo");Slider(value:$studio.playbackRate,in:0.25...3);Text(String(format:"%.2f×",studio.playbackRate)).font(.caption.monospacedDigit())}
            Picker("Soundart",selection:$studio.soundEffect){ForEach(FartSoundEffect.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.menu)
        }
    }
}

struct FartRecorderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let autoStart: Bool
    @State private var title = ""
    @State private var trimStart = 0.0
    @State private var trimEnd = 0.2
    @State private var trimError: String?
    @State private var caption = ""
    @State private var category: FartCategory = .natural
    @State private var situation: FartSituation = .alltag
    @State private var quip = ""
    @AppStorage("rjlove.fart-locations") private var includeLocation = true
    @State private var saving = false
    @State private var discard = false
    @State private var starting = false
    @State private var attemptedAutoStart = false
    @State private var failedUpload = false
    private var studio: AudioStudioService { appState.studio }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    ViewThatFits(in: .horizontal) {
                      HStack(spacing: 8) {
                        stage("1", "Aufnehmen", selected: studio.mode != .review)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        stage("2", "Schneiden", selected: studio.mode == .review)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        stage("3", "Senden", selected: saving)
                      }
                      Text(studio.mode == .review ? "2 · Schneiden & senden" : "1 · Aufnehmen").font(.caption.bold()).foregroundStyle(LovePalette.violet)
                    }.frame(maxWidth: .infinity)
                    LoveEyebrow(text: studio.hasRecording ? "Das Mikrofon ist für euch offen" : studio.mode == .review ? "Ein kleines Meisterwerk ist geboren" : "Wenn die Natur ruft: Aufnahme.")
                    PuffMascot(active: studio.isRecording).frame(height: studio.mode == .review ? 50 : 85)
                    spruchCard
                    Text(studio.mode == .review ? "Bereit für die Duftpost?" : studio.mode == .paused ? "Kurze Atempause." : studio.isRecording ? "Lass es raus." : "Bühne frei.")
                        .font(.system(size: 29, weight: .medium, design: .serif)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Text(String(format: "%02d:%02d", Int(studio.elapsed) / 60, Int(studio.elapsed) % 60)).font(.system(size: studio.mode == .review ? 32 : 48, weight: .light, design: .rounded)).monospacedDigit()
                    AudioWaveform(values: studio.mode == .review ? studio.draft?.waveform ?? [] : studio.liveLevels).frame(height: 58).padding(.horizontal, 12)
                    if studio.mode == .review { recordingControls.disabled(saving) }
                    if studio.mode == .review { reviewForm }
                    if let error = studio.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if failedUpload { Text("Noch nicht geteilt. Dein Entwurf bleibt auf diesem iPhone. Versuche es erneut, sobald der Server erreichbar ist.").font(.footnote).foregroundStyle(.orange) }
                    Text("Bis zu 60 Sekunden · Mikrofon nur während der sichtbaren Aufnahme. Beim Verlassen der App wird gestoppt und ein lokaler Entwurf behalten. Geteilt wird erst mit deinem Tipp auf „Duftpost senden“.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(24)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if studio.mode == .review {
                    VStack(spacing: 7) {
                        sendButton
                        Text(String(format: "Dein Ausschnitt: %.1f s · Name optional", max(0.2, trimEnd - trimStart)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 20).padding(.vertical, 12)
                        .frame(maxWidth: .infinity).background(.ultraThinMaterial)
                } else {
                    VStack(spacing: 8) {
                        recordingControls
                        Text(studio.hasRecording ? "Nur ihr hört mit · maximal 60 Sekunden" : "Ein Tipp. Ein Naturtalent. Eure Erinnerung.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal,20).padding(.vertical,12).frame(maxWidth:.infinity).background(.ultraThinMaterial)
                }
            }.background(LoveBackground()).navigationTitle("Duftstudio").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) } }
            .confirmationDialog("Aufnahme wirklich verwerfen?", isPresented: $discard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) { studio.discard(); failedUpload = false }
                Button("Behalten", role: .cancel) {}
            }
        }.interactiveDismissDisabled(saving)
        .animation(reduceMotion ? nil : .snappy, value: studio.mode)
        .task(id:appState.me?.id) {
            guard let ownerID = appState.me?.id else { return }
            studio.prepare(ownerID: ownerID)
            if quip.isEmpty {
                situation = DuftspruchDeck.suggested(hasDraft: studio.draft != nil, motion: appState.deviceStatus.motion)
                quip = DuftspruchDeck.next(for: situation)
            }
            trimEnd = studio.draft?.duration ?? 0.2
            await startQuickCaptureIfReady()
        }
        .task(id:scenePhase) { if scenePhase == .active { await startQuickCaptureIfReady() } }
        .task(id:autoStart) { await startQuickCaptureIfReady() }
        .onChange(of: situation) { _, value in quip = DuftspruchDeck.next(for: value) }
        .onChange(of: studio.mode) { _, mode in if mode == .review { trimStart = 0; trimEnd = studio.draft?.duration ?? 0.2 } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { studio.finishRecording() } }
        .onDisappear { studio.finishRecording(); studio.stopPlayback() }
    }
    @MainActor private func startQuickCaptureIfReady() async {
        guard autoStart, !attemptedAutoStart, !starting, scenePhase == .active,
              let ownerID = appState.me?.id else { return }
        starting=true
        studio.prepare(ownerID:ownerID)
        if studio.draft == nil && !studio.hasRecording { await studio.start(ownerID:ownerID) }
        starting=false
        guard !Task.isCancelled, scenePhase == .active else { return }
        attemptedAutoStart=true
        appState.acknowledgeQuickCapture()
    }
    private var spruchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Spruch des Moments",systemImage: "sparkles").font(.caption.bold()).foregroundStyle(LovePalette.violet)
                Spacer()
                Button { quip = DuftspruchDeck.next(for: situation) } label: { Image(systemName: "shuffle") }.accessibilityLabel("Anderen Spruch zeigen")
            }
            Text(quip).font(.subheadline).fixedSize(horizontal: false,vertical: true).accessibilityIdentifier("duft-quip")
            Picker("Deine Situation",selection: $situation) {
                ForEach(FartSituation.allCases) { Label($0.title,systemImage: $0.symbol).tag($0) }
            }.pickerStyle(.menu).tint(LovePalette.violet).accessibilityIdentifier("duft-situation")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .loveGlass(in: RoundedRectangle(cornerRadius: 24))
    }
    private func stage(_ number: String, _ title: String, selected: Bool) -> some View {
        HStack(spacing: 5) { Text(number).font(.caption.bold()); Text(title).font(.caption2) }
            .foregroundStyle(selected ? LovePalette.violet : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 8)
            .glassEffect(.regular.tint(selected ? LovePalette.violet.opacity(0.14) : .clear), in: Capsule())
    }
    private var recordingControls: some View {
        AdaptiveLoveRow(spacing: 16) {
            if studio.hasRecording {
                Button { studio.togglePause() } label: { Image(systemName: studio.mode == .paused ? "play.fill" : "pause.fill").font(.title2).frame(width: 60, height: 60).loveGlass(in: Circle()) }.accessibilityLabel(studio.mode == .paused ? "Aufnahme fortsetzen" : "Aufnahme pausieren")
                Button { studio.finishRecording() } label: { Image(systemName: "stop.fill").font(.title).foregroundStyle(.white).frame(width: 82, height: 82).background(LovePalette.pink.gradient, in: Circle()) }.accessibilityLabel("Aufnahme stoppen")
            } else if studio.mode == .review {
                Button { studio.playDraft() } label: { Label(studio.playingID == studio.draft?.id ? "Stoppen" : "Anhören", systemImage: studio.playingID == studio.draft?.id ? "stop.fill" : "play.fill") }.buttonStyle(.bordered).controlSize(.large)
                Button("Neu aufnehmen", systemImage: "arrow.counterclockwise") { discard = true }.buttonStyle(.bordered).controlSize(.large)
            } else {
                Button {
                    guard let ownerID = appState.me?.id else { return }
                    starting = true
                    Task { await studio.start(ownerID: ownerID); starting = false }
                } label: {
                    Group { if starting { ProgressView().tint(.white) } else { Image(systemName: "mic.fill").font(.system(size: 32)) } }
                        .foregroundStyle(.white).frame(width: 88, height: 88).background(LovePalette.pink.gradient, in: Circle())
                        .glassEffect(.regular.tint(LovePalette.pink.opacity(0.3)).interactive(), in: Circle())
                        .shadow(color: LovePalette.pink.opacity(0.25), radius: 18, y: 8)
                }.disabled(starting).accessibilityLabel("Aufnahme starten")
            }
        }.frame(maxWidth: .infinity)
    }
    private var sendButton: some View {
            Button {
                saving = true; studio.stopPlayback()
                Task {
                    do {
                        if let draft = studio.draft, trimStart > 0.01 || trimEnd < draft.duration - 0.01 {
                            try await studio.trimDraft(start: trimStart, end: trimEnd)
                            trimStart = 0; trimEnd = studio.draft?.duration ?? 0.2
                        }
                    } catch { trimError = error.localizedDescription; saving = false; return }
                    let success = await appState.shareFart(title: title.trimmingCharacters(in: .whitespacesAndNewlines), caption: caption, category: category.rawValue, includeLocation: includeLocation, situation: situation.rawValue)
                    saving = false; failedUpload = !success
                    if success { dismiss() }
                }
            } label: { HStack { if saving { ProgressView().tint(.white) }; Label("Duftpost senden", systemImage: "paperplane.fill").frame(maxWidth: .infinity) } }
                .buttonStyle(.borderedProminent).tint(LovePalette.violet).controlSize(.large)
                .disabled(saving || studio.draft == nil || title.count > 100 || caption.count > 500)
                .accessibilityIdentifier("duftpost-send")
    }

    private var reviewForm: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("Dein Werk. Deine Duftnote.", systemImage: "waveform.path").font(.headline)
            if let date = studio.draft?.recordedAt?.rjDate { Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }
            TextField("Name (optional)", text: $title).font(.headline)
            TextField("Eine Duftnote dazu?", text: $caption, axis: .vertical).lineLimit(2...4)
            Text("Ohne Namen heißt deine Aufnahme automatisch „Ein kleines Meisterwerk“.").font(.caption).foregroundStyle(.secondary)
            if let draft = studio.draft {
                AudioTrimControls(url: draft.url, duration: draft.duration, waveform: draft.waveform, start: $trimStart, end: $trimEnd)
            }
            if let trimError { Text(trimError).font(.footnote).foregroundStyle(.orange) }
            if title.count > 100 || caption.count > 500 { Text("Name: maximal 100 Zeichen. Duftnote: maximal 500 Zeichen.").font(.caption).foregroundStyle(.orange) }
                Button("Nur auf diesem iPhone sichern",systemImage:"square.and.arrow.down") {
                    guard let draft=appState.studio.draft,let server=appState.profile?.baseURL,let user=appState.me?.id else{return}
                    do {LocalFartStore.shared.configure(server:server,userID:user);let data=try Data(contentsOf:draft.url);let clip=FartClip(id:draft.id,ownerID:user,title:title.isEmpty ? "Ein kleines Meisterwerk":title,caption:caption,category:category.rawValue,duration:draft.duration,waveform:draft.waveform,sizeBytes:data.count,createdAt:Date.now.rjISO8601,ratings:[],reactions:[],recordedAt:draft.recordedAt,location:includeLocation ? draft.location:nil,situation:situation.rawValue);try LocalFartStore.shared.saveImported(clip,data:data,localOnly:true);appState.studio.discard();dismiss()}catch{appState.alert=AppAlert(title:"Lokales Sichern",message:error.localizedDescription)}
                }.disabled(saving || title.count>100 || caption.count>500)
            if let point = studio.draft?.location {
                Toggle("Aufnahmeort auf eurer Furzkarte teilen", isOn: $includeLocation).tint(LovePalette.violet)
                Text("Neue Aufnahmen teilen einen verfügbaren Ort standardmäßig. Ohne iOS-Standortfreigabe bleibt der Ort unbekannt.").font(.caption2).foregroundStyle(.secondary)
                Text("Der Ort stammt aus dem Aufnahmezeitraum. Genauigkeit etwa \(Int(point.accuracy)) m. Ohne diesen Schalter wird kein Ort hochgeladen.").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Ohne Aufnahmeort · kein aktueller freigegebener Standort vorhanden", systemImage: "mappin.slash").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Kategorie", selection: $category) { ForEach(FartCategory.allCases) { Text("\($0.emoji) \($0.rawValue)").tag($0) } }
            Button("Entwurf verwerfen", role: .destructive) { discard = true }.font(.caption).disabled(saving)
        }.loveCard()
    }
}
private struct FartRatingView: View {
    let clip: FartClip
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var overall: Int
    @State private var power: Int
    @State private var style: Int
    @State private var comment: String
    @State private var saving = false
    init(clip: FartClip) {
        self.clip = clip
        _overall = State(initialValue: clip.ratings.first?.overall ?? 3)
        _power = State(initialValue: clip.ratings.first?.power ?? 3)
        _style = State(initialValue: clip.ratings.first?.style ?? 3)
        _comment = State(initialValue: clip.ratings.first?.comment ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(clip.title).font(.system(.title2, design: .serif)); Text("Die Duftjury urteilt. Liebevoll, aber ehrlich. 🏆").font(.subheadline).foregroundStyle(.secondary) }
                Section("Deine Wertung") {
                    stars("Gesamtkunstwerk", value: $overall)
                    stars("Wumms", value: $power)
                    stars("Stil & Originalität", value: $style)
                }
                Section("Das Jury-Urteil") { TextField("Da fehlen mir die Worte …", text: $comment, axis: .vertical).lineLimit(3...5) }
            }.navigationTitle("Die Duftjury").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewerten") {
                        saving = true
                        Task { if await appState.rateFart(clip, overall: overall, power: power, style: style, comment: comment) { dismiss() }; saving = false }
                    }.disabled(saving || comment.count > 500)
                }
            }
        }
    }
    private func stars(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold())
            HStack(spacing: 17) {
                ForEach(1...5, id: \.self) { i in Button { value.wrappedValue = i; Haptics.impact(.soft) } label: { Image(systemName: i <= value.wrappedValue ? "star.fill" : "star").font(.title2).foregroundStyle(LovePalette.coral) }.buttonStyle(.plain).accessibilityLabel("\(i) Sterne für \(title)") }
            }.padding(.vertical, 6)
        }
    }
}

