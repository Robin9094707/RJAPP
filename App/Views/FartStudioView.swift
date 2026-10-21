import SwiftUI

enum ExperienceSection: String, CaseIterable, Identifiable {
    case farts = "Duftpost", love = "Liebe", moments = "Momente"
    var id: String { rawValue }
}
struct ExperienceView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            Picker("Euer Spielplatz", selection: $state.experienceSection) {
                ForEach(ExperienceSection.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 10)
            switch state.experienceSection {
            case .farts: FartStudioView()
            case .love: LovePlayView()
            case .moments: MomentsView()
            }
        }.background(LoveBackground()).animation(reduceMotion ? nil : .snappy(duration: 0.25), value: state.experienceSection)
    }
}
private enum FartFilter: String, CaseIterable { case all = "Alle", mine = "Meine", partner = "Deine", favorites = "Lieblinge", best = "Best of" }

struct FartStudioView: View {
    @Environment(AppState.self) private var appState
    @State private var filter: FartFilter = .all
    private var clips: [FartClip] {
        let filtered = appState.farts.filter { clip in
            switch filter {
            case .all, .best: return true
            case .mine: return clip.ownerID == appState.me?.id
            case .partner: return clip.ownerID != appState.me?.id
            case .favorites: return clip.reactions.contains { $0.userID == appState.me?.id && $0.emoji == "❤️" }
            }
        }
        return filter == .best ? filtered.sorted { ($0.stars ?? 0, $0.createdAt) > ($1.stars ?? 0, $1.createdAt) } : filtered
    }
    private var winner: FartClip? { appState.farts.filter { $0.stars != nil }.max { ($0.stars ?? 0) < ($1.stars ?? 0) } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                hero
                HStack(spacing: 12) {
                    LoveMetric(title: "Kleine Meisterwerke", value: appState.farts.count.formatted(), symbol: "waveform", tint: LovePalette.violet)
                    LoveMetric(title: "Von dir", value: appState.farts.filter { $0.ownerID == appState.me?.id }.count.formatted(), symbol: "mic.fill", tint: LovePalette.pink)
                }
                if let winner {
                    HStack(spacing: 14) {
                        Text("🏆").font(.largeTitle)
                        VStack(alignment: .leading, spacing: 5) {
                            LoveEyebrow(text: "Euer bisheriges Meisterwerk")
                            Text(winner.title).font(.headline)
                            Text("\(winner.stars ?? 0) von 5 Jury-Sternen").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.loveCard()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FartFilter.allCases, id: \.self) { value in
                            Button { filter = value } label: {
                                Text(value.rawValue).font(.caption.bold()).padding(.horizontal, 15).padding(.vertical, 10)
                                    .foregroundStyle(filter == value ? Color.white : Color.primary)
                                    .background(filter == value ? LovePalette.violet : Color.primary.opacity(0.05), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if clips.isEmpty {
                    ContentUnavailableView("Noch ganz frische Luft.", systemImage: "wind", description: Text("Nehmt euer erstes Meisterwerk auf. Eure kleine Sammlung bleibt nur für euch beide."))
                }
                if let error = appState.studio.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.orange).loveCard()
                }
                ForEach(clips) { clip in FartClipCard(clip: clip) }
                Text("Die Wellenform zeigt den aufgenommenen Pegel. Duftnoten und Sterne kommen ausschließlich von euch. 😄")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 20)
            }.padding(20)
        }.navigationTitle("Euer Spielplatz").navigationBarTitleDisplayMode(.large)
        .refreshable { await appState.syncNow(showErrors: false) }
        .onDisappear { appState.studio.stopPlayback() }
    }
    private var hero: some View {
        VStack(spacing: 14) {
            LoveEyebrow(text: "Liebe liegt in der Luft. Manchmal auch mehr.")
            PuffMascot(active: false).frame(height: 105)
            Text("Für immer. Fürzeinander.").font(.system(size: 28, weight: .medium, design: .serif)).multilineTextAlignment(.center)
            Text("Eure private Sammlung großer Gefühle\nund kleiner Druckwellen.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                appState.openFartRecorder()
            } label: {
                Label(appState.studio.draft == nil ? "Meisterwerk aufnehmen" : "Lokalen Entwurf öffnen", systemImage: "mic.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(LovePalette.violet).controlSize(.large)
        }.frame(maxWidth: .infinity).loveCard()
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

private struct FartClipCard: View {
    let clip: FartClip
    @Environment(AppState.self) private var appState
    @State private var rating = false
    @State private var deleting = false
    @State private var editing = false
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
                    Menu { Button("Schneiden & umbenennen", systemImage: "scissors") { editing = true }; Button("Aufnahme löschen", systemImage: "trash", role: .destructive) { deleting = true } } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Aufnahme verwalten")
                }
            }
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
            if let date = clip.createdAt.rjDate { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary) }
        }.loveCard()
        .sheet(isPresented: $rating) { FartRatingView(clip: clip) }
        .sheet(isPresented: $editing) { FartEditorView(clip: clip) }
        .alert("Dieses Meisterwerk löschen?", isPresented: $deleting) {
            Button("Löschen", role: .destructive) { Task { await appState.deleteFart(clip) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Die Aufnahme und ihre Bewertungen werden für euch beide entfernt.") }
    }
    private var speedControls: some View {
        @Bindable var studio = appState.studio
        return Picker("Tempo", selection: $studio.playbackRate) {
            Text("Zeitlupe").tag(Float(0.65)); Text("Original").tag(Float(1)); Text("Turbo").tag(Float(1.5))
        }.pickerStyle(.segmented)
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
    @State private var saving = false
    @State private var discard = false
    @State private var starting = false
    @State private var failedUpload = false
    private var studio: AudioStudioService { appState.studio }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 8) {
                        stage("1", "Aufnehmen", selected: studio.mode != .review)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        stage("2", "Schneiden", selected: studio.mode == .review)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        stage("3", "Senden", selected: saving)
                    }.frame(maxWidth: .infinity)
                    LoveEyebrow(text: studio.hasRecording ? "Das Mikrofon ist für euch offen" : studio.mode == .review ? "Ein kleines Meisterwerk ist geboren" : "Wenn die Natur ruft: Aufnahme.")
                    PuffMascot(active: studio.isRecording).frame(height: studio.mode == .review ? 66 : 130)
                    Text(studio.mode == .review ? "Bereit für die Duftpost?" : studio.mode == .paused ? "Kurze Atempause." : studio.isRecording ? "Lass es raus." : "Bühne frei.")
                        .font(.system(size: 31, weight: .medium, design: .serif)).multilineTextAlignment(.center)
                    Text(String(format: "%02d:%02d", Int(studio.elapsed) / 60, Int(studio.elapsed) % 60)).font(.system(size: studio.mode == .review ? 32 : 48, weight: .light, design: .rounded)).monospacedDigit()
                    AudioWaveform(values: studio.mode == .review ? studio.draft?.waveform ?? [] : studio.liveLevels).frame(height: 75).padding(.horizontal, 12)
                    recordingControls.disabled(saving)
                    if studio.mode == .review { reviewForm }
                    if let error = studio.errorMessage { Text(error).font(.footnote).foregroundStyle(.orange) }
                    if failedUpload { Text("Noch nicht geteilt. Dein Entwurf bleibt auf diesem iPhone. Versuche es erneut, sobald der Server erreichbar ist.").font(.footnote).foregroundStyle(.orange) }
                    Text("Bis zu 60 Sekunden · Mikrofon nur während der sichtbaren Aufnahme. Beim Verlassen der App wird gestoppt und ein lokaler Entwurf behalten. Geteilt wird erst mit deinem Tipp auf „Duftpost senden“.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(24)
            }.background(LoveBackground()).navigationTitle("Duftstudio").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if studio.mode == .review {
                    VStack(spacing: 7) {
                        sendButton
                        Text(String(format: "Dein Ausschnitt: %.1f s · Name optional", max(0.2, trimEnd - trimStart)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 20).padding(.vertical, 12).background(.ultraThinMaterial)
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() }.disabled(saving) } }
            .confirmationDialog("Aufnahme wirklich verwerfen?", isPresented: $discard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) { studio.discard(); failedUpload = false }
                Button("Behalten", role: .cancel) {}
            }
        }.interactiveDismissDisabled(saving)
        .animation(reduceMotion ? nil : .snappy, value: studio.mode)
        .task {
            guard let ownerID = appState.me?.id else { return }
            studio.prepare(ownerID: ownerID)
            trimEnd = studio.draft?.duration ?? 0.2
            if autoStart && studio.draft == nil && !studio.hasRecording {
                starting = true; await studio.start(ownerID: ownerID); starting = false
            }
        }
        .onChange(of: studio.mode) { _, mode in if mode == .review { trimStart = 0; trimEnd = studio.draft?.duration ?? 0.2 } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { studio.finishRecording() } }
        .onDisappear { studio.finishRecording(); studio.stopPlayback() }
    }
    private func stage(_ number: String, _ title: String, selected: Bool) -> some View {
        HStack(spacing: 5) { Text(number).font(.caption.bold()); Text(title).font(.caption2) }
            .foregroundStyle(selected ? LovePalette.violet : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 8)
            .glassEffect(.regular.tint(selected ? LovePalette.violet.opacity(0.14) : .clear), in: Capsule())
    }
    private var recordingControls: some View {
        HStack(spacing: 25) {
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
                    let success = await appState.shareFart(title: title.trimmingCharacters(in: .whitespacesAndNewlines), caption: caption, category: category.rawValue)
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
            TextField("Name (optional)", text: $title).font(.headline)
            TextField("Eine Duftnote dazu?", text: $caption, axis: .vertical).lineLimit(2...4)
            Text("Ohne Namen heißt deine Aufnahme automatisch „Ein kleines Meisterwerk“.").font(.caption).foregroundStyle(.secondary)
            if let draft = studio.draft {
                AudioTrimControls(url: draft.url, duration: draft.duration, waveform: draft.waveform, start: $trimStart, end: $trimEnd)
            }
            if let trimError { Text(trimError).font(.footnote).foregroundStyle(.orange) }
            if title.count > 100 || caption.count > 500 { Text("Name: maximal 100 Zeichen. Duftnote: maximal 500 Zeichen.").font(.caption).foregroundStyle(.orange) }
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
