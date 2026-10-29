import SwiftUI

struct LovePlayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var setting = "Egal"
    @State private var dateIdea = "Ein kleiner Abend, der nur euch gehört."
    @State private var spinning = false
    @State private var dateSaved = false
    @State private var saving = false
    @State private var gratitude = ""
    @State private var couponTitle = "Eine Massage nur für dich"
    @State private var couponNote = ""
    @State private var showCoupon = false
    private let ideas: [(String, String)] = [
        ("Zuhause", "Kocht euer Lieblingsessen – die andere Person wählt die Musik."),
        ("Zuhause", "Baut eine Kissenecke und schaut euren ersten gemeinsamen Film noch einmal."),
        ("Zuhause", "Blindverkostung: Drei Snacks aussuchen und gegenseitig erraten."),
        ("Zuhause", "Handys weg, Kerzen an: eine Stunde nur reden und zuhören."),
        ("Zuhause", "Schreibt einander einen Brief und lest ihn laut vor."),
        ("Zuhause", "Malt gegenseitig ein Porträt. Schön muss es nicht werden. Lustig schon."),
        ("Zuhause", "Einander drei Lieblingslieder zeigen und erzählen, warum sie wichtig sind."),
        ("Draußen", "Spazieren ohne Ziel. An jeder Kreuzung darf die andere Person entscheiden."),
        ("Draußen", "Sonnenuntergang suchen und eine Thermoskanne mitnehmen."),
        ("Draußen", "Macht eine kleine Foto-Schnitzeljagd: etwas Rotes, etwas Lustiges, etwas für uns."),
        ("Draußen", "Sucht eine Bank, teilt einen Snack und erzählt euch eure schönste Erinnerung."),
        ("Draußen", "Ein Mini-Picknick an einem Ort, an dem ihr noch nie zusammen wart."),
        ("Draußen", "Geht eine Runde und sammelt fünf Ideen für eure gemeinsame Wunschliste.")
    ]
    private var coupons: [SharedRecord] { appState.records.filter { $0.kind == .coupon } }
    private var appreciations: [SharedRecord] { appState.records.filter { $0.kind == .gratitude } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    LoveEyebrow(text: "Kleine Dinge. Große Nähe.")
                    Text("Mehr Zeit für uns.").font(.system(size: 32, weight: .medium, design: .serif))
                    Text("Eine Idee, ein Versprechen, ein paar liebe Worte.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 10)
                dateRoulette
                gratitudeCard
                if !appreciations.isEmpty {
                    LoveSectionTitle("Das mag ich an dir")
                    ForEach(Array(appreciations.prefix(5))) { record in
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "quote.opening").font(.title2).foregroundStyle(LovePalette.pink)
                            Text(record.payload.text ?? "").font(.system(.title3, design: .serif)).textSelection(.enabled)
                            Text(record.ownerID == appState.me?.id ? "Von dir" : "Von \(appState.partner?.displayName ?? "Schatzi")").font(.caption).foregroundStyle(.secondary)
                        }.loveCard().contextMenu {
                            Button("Löschen", systemImage: "trash", role: .destructive) { Task { _ = await appState.deleteRecord(record) } }
                        }
                    }
                }
                HStack {
                    LoveSectionTitle("Ein kleines Versprechen", subtitle: "Gutscheine, die ihr wirklich einlösen könnt.")
                    Button { showCoupon = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }.accessibilityLabel("Liebesgutschein verschenken")
                }
                if coupons.isEmpty {
                    Button { showCoupon = true } label: {
                        Label("Deinen ersten Gutschein verschenken", systemImage: "gift.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.glass).controlSize(.large)
                }
                ForEach(coupons) { coupon in couponCard(coupon) }
                Text("Nähe braucht keinen perfekten Plan. Nur ein bisschen Zeit füreinander.").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical)
            }.padding(22)
        }.navigationTitle("Euer Spielplatz").navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCoupon) { couponComposer }
    }
    private var dateRoulette: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "dice.fill").font(.title2).foregroundStyle(LovePalette.violet).rotationEffect(.degrees(spinning && !reduceMotion ? 180 : 0)); LoveEyebrow(text: "Date-Roulette") }
            Picker("Wo?", selection: $setting) { ForEach(["Egal", "Zuhause", "Draußen"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
            Text(dateIdea).font(.system(size: 24, weight: .medium, design: .serif)).frame(minHeight: 105, alignment: .leading)
            HStack {
                Button("Neue Idee", systemImage: "shuffle") {
                    withAnimation(.spring(response: 0.4)) { spinning.toggle() }
                    let choices = ideas.filter { setting == "Egal" || $0.0 == setting }.map(\.1).filter { $0 != dateIdea }
                    dateIdea = choices.randomElement() ?? ideas[0].1; dateSaved = false; Haptics.impact(.soft)
                }.buttonStyle(.glassProminent).tint(LovePalette.violet)
                Button(dateSaved ? "Gemerkte Idee" : "Merken", systemImage: dateSaved ? "checkmark" : "heart") {
                    saving = true
                    Task {
                        if await appState.saveRecord(kind: .wish, payload: RecordPayload(title: "Unser nächstes kleines Date", text: dateIdea, completed: false)) != nil { dateSaved = true }
                        saving = false
                    }
                }.buttonStyle(.glass).disabled(saving || dateSaved)
            }
        }.loveCard()
    }
    private var gratitudeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            LoveSectionTitle("Heute mag ich an dir …", subtitle: "Sag es, auch wenn es selbstverständlich scheint.")
            TextField("Dein Lachen, deine Geduld, unseren Quatsch …", text: $gratitude, axis: .vertical).lineLimit(3...5)
            Button("Liebe Worte dalassen", systemImage: "heart.text.square") {
                saving = true
                Task {
                    if await appState.saveRecord(kind: .gratitude, payload: RecordPayload(title: "Heute mag ich an dir …", text: gratitude.trimmingCharacters(in: .whitespacesAndNewlines))) != nil { gratitude = "" }
                    saving = false
                }
            }.buttonStyle(.glass).disabled(saving || gratitude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gratitude.count > 4000)
        }.loveCard()
    }
    private func couponCard(_ coupon: SharedRecord) -> some View {
        let mine = coupon.ownerID == appState.me?.id
        let redeemed = coupon.payload.completed == true
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "gift.fill").font(.title2).foregroundStyle(LovePalette.pink)
                LoveEyebrow(text: redeemed ? "Eingelöst mit Liebe" : mine ? "Von dir verschenkt" : "Nur für dich")
                Spacer()
                if mine {
                    Menu { Button("Gutschein löschen", systemImage: "trash", role: .destructive) { Task { _ = await appState.deleteRecord(coupon) } } } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Gutschein verwalten")
                }
            }
            Text(coupon.payload.title ?? "Ein kleiner Liebesgutschein").font(.system(.title2, design: .serif)).strikethrough(redeemed)
            if let text = coupon.payload.text, !text.isEmpty { Text(text).font(.subheadline).foregroundStyle(.secondary) }
            if !mine && !redeemed {
                Button("Jetzt einlösen", systemImage: "checkmark.seal") {
                    var payload = coupon.payload; payload.completed = true
                    Task { _ = await appState.saveRecord(id: coupon.id, kind: .coupon, payload: payload) }
                }.buttonStyle(.glassProminent).tint(LovePalette.pink)
            } else {
                Text(redeemed ? "Dieses kleine Versprechen gehört schon zu eurer Geschichte. 💗" : "Dein Lieblingsmensch kann diesen Gutschein hier einlösen.").font(.caption).foregroundStyle(.secondary)
            }
        }.loveCard()
    }
    private var couponComposer: some View {
        NavigationStack {
            Form {
                Section("Ein Geschenk für deinen Lieblingsmenschen") {
                    Picker("Idee", selection: $couponTitle) {
                        ForEach(["Eine Massage nur für dich", "Frühstück im Bett", "Dein Wunschfilm, mein Popcorn", "Ein Spaziergang nur zu zweit", "Eine Stunde ganz für uns", "Ich übernehme heute das Kochen"], id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Ein paar persönliche Worte", text: $couponNote, axis: .vertical).lineLimit(3...6)
                }
            }.navigationTitle("Ein kleines Versprechen").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showCoupon = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verschenken") {
                        guard let partner = appState.partner else { return }
                        saving = true
                        Task {
                            if await appState.saveRecord(kind: .coupon, payload: RecordPayload(title: couponTitle, text: couponNote, targetID: partner.id, completed: false)) != nil { showCoupon = false; couponNote = "" }
                            saving = false
                        }
                    }.disabled(saving || appState.partner == nil || couponNote.count > 4000)
                }
            }
        }
    }
}
