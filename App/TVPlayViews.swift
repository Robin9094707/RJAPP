import SwiftUI

private func tvColor(_ hex: String) -> Color {
    let value = UInt64(hex.dropFirst(),radix: 16) ?? 0xD74C87
    return Color(red: Double((value >> 16) & 255)/255,green: Double((value >> 8) & 255)/255,blue: Double(value & 255)/255)
}
struct TVDrawingSurface: View {
    var interactive = false
    var color = "#D74C87"
    var width = 4.0
    @State private var together = TVTogetherService.shared
    @State private var points: [CGPoint] = []
    @State private var unsent: [CGPoint] = []
    @State private var lastSent = Date.distantPast
    @State private var epoch: String?
    var body: some View {
        GeometryReader { geometry in
            Canvas { context,size in
                for stroke in together.state.strokes {
                    var path = Path()
                    for (index,point) in stroke.points.enumerated() where point.count == 2 {
                        let p = CGPoint(x: point[0]*size.width,y: point[1]*size.height)
                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path,with: .color(tvColor(stroke.color)),style: StrokeStyle(lineWidth: stroke.width*min(size.width,size.height)/400,lineCap: .round,lineJoin: .round))
                }
                if interactive,points.count > 1 {
                    var path = Path(); path.addLines(points.map { CGPoint(x: $0.x*size.width,y: $0.y*size.height) })
                    context.stroke(path,with: .color(tvColor(color)),style: StrokeStyle(lineWidth: width*min(size.width,size.height)/400,lineCap: .round,lineJoin: .round))
                }
            }.background(Color(white: 0.975)).clipShape(RoundedRectangle(cornerRadius: 24))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard interactive,geometry.size.width > 0,geometry.size.height > 0 else { return }
                    if epoch == nil { epoch = together.state.epoch }
                    let point = CGPoint(x: min(1,max(0,value.location.x/geometry.size.width)),y: min(1,max(0,value.location.y/geometry.size.height)))
                    if let previous = points.last,abs(previous.x-point.x)+abs(previous.y-point.y)<0.003 { return }
                    points.append(point); unsent.append(point)
                    if unsent.count >= 32 || (unsent.count >= 3 && Date.now.timeIntervalSince(lastSent)>0.25) { send() }
                }.onEnded { _ in
                    if unsent.count == 1,let point = unsent.first { unsent.append(CGPoint(x: min(1,point.x+0.001),y: point.y)) }
                    send(final: true); points = []; unsent = []; epoch = nil
                })
                .allowsHitTesting(interactive)
        }.onAppear { if interactive { together.editing = true } }.onDisappear { if interactive { together.editing = false } }
            .accessibilityElement(children: .ignore).accessibilityLabel("Gemeinsame Zeichenfläche").accessibilityIdentifier(interactive ? "tv-drawing-touch" : "tv-drawing-screen")
    }
    private func send(final: Bool = false) {
        guard unsent.count >= 2,let epoch else { return }
        let values = unsent.prefix(128).map { [Double($0.x),Double($0.y)] }
        let last = unsent.last
        unsent = final ? [] : last.map { [$0] } ?? []
        lastSent = .now
        Task { await together.action("stroke",values: ["points":values,"color":color,"width":width,"epoch":epoch]) }
    }
}
struct TVDrawingRemote: View {
    @State private var together = TVTogetherService.shared
    @State private var color = "#D74C87"
    @State private var width = 4.0
    private let colors = ["#D74C87","#674BB1","#159A9C","#F3AB3C","#253454","#FFFFFF"]
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text("Ein Bild. Von uns beiden.").font(.title2.bold())
            if together.state.epoch.isEmpty { ProgressView("Gemeinsame Zeichenfläche verbinden …").frame(height: 310) }
            else { TVDrawingSurface(interactive: true,color: color,width: width).aspectRatio(16.0/9.0,contentMode: .fit) }
            HStack {
                ForEach(colors,id: \.self) { value in
                    Button { color = value } label: { Circle().fill(tvColor(value)).frame(width: 28,height: 28).overlay { Circle().stroke(color == value ? Color.primary : .clear,lineWidth: 3) } }.accessibilityLabel("Zeichenfarbe " + value)
                }
            }
            Slider(value: $width,in: 1...14).accessibilityLabel("Strichbreite")
            Button("Zeichenfläche leeren",systemImage: "trash",role: .destructive) { Task { await together.action("clear") } }
            Text("Die Striche werden während des Zeichnens in kleinen Abschnitten übertragen. Beide Apps und euer Server müssen erreichbar sein.").font(.caption).foregroundStyle(.secondary)
            if let error = together.error { Text(error).font(.footnote).foregroundStyle(.orange) }
        }.loveCard().task { await together.refresh() }
    }
}
struct TVGameBoard: View {
    var interactive = false
    @State private var together = TVTogetherService.shared
    private var result: String {
        if together.state.winner == "draw" { return "Unentschieden 💗" }
        if !together.state.winner.isEmpty { return "\(together.state.winner) gewinnt!" }
        if together.state.players.isEmpty { return "Eine Runde für uns?" }
        return "\(together.state.turn) ist am Zug"
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                Text(result).font(.system(size: max(18,min(36,geometry.size.height*0.07)),weight: .medium,design: .rounded))
                let side = min(geometry.size.width,geometry.size.height*0.78)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 8),count: 3),spacing: 8) {
                    ForEach(0..<9,id: \.self) { index in
                        Button { if interactive { Task { await together.action("move",values: ["index":index]) } } } label: {
                            Text(together.state.board.indices.contains(index) ? together.state.board[index] : "")
                                .font(.system(size: side*0.16,weight: .medium,design: .rounded))
                                .frame(maxWidth: .infinity).frame(height: (side-16)/3)
                                .background(.regularMaterial,in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).disabled(!interactive).accessibilityLabel("Spielfeld \(index+1)").accessibilityValue(together.state.board.indices.contains(index) && !together.state.board[index].isEmpty ? together.state.board[index] : "Leer").accessibilityIdentifier("tv-game-cell-\(index)")
                    }
                }.frame(width: side)
            }.frame(maxWidth: .infinity,maxHeight: .infinity)
        }
    }
}
struct TVGameRemote: View {
    @State private var together = TVTogetherService.shared
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text("Tic-Tac-Toe für uns zwei").font(.title2.bold())
            TVGameBoard(interactive: true).frame(height: 380)
            Text(together.state.players["X"] == together.userID ? "Du spielst X · Schatzi spielt O" : together.state.players["O"] == together.userID ? "Du spielst O · Schatzi spielt X" : "Starte eine neue Runde.").font(.caption).foregroundStyle(.secondary)
            Button("Neue Runde",systemImage: "arrow.clockwise") { Task { await together.action("new_game") } }.buttonStyle(.borderedProminent).accessibilityIdentifier("tv-game-new")
            if let error = together.error { Text(error).font(.footnote).foregroundStyle(.orange) }
        }.loveCard().task { await together.refresh() }
    }
}
struct TVSignalRemote: View {
    @State private var together = TVTogetherService.shared
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text("Ein Zeichen für Schatzi").font(.headline)
            HStack(spacing: 20) {
                ForEach(["heart","kiss","hug","star","wave"],id: \.self) { symbol in
                    Button { Task { await together.action("signal",values: ["symbol":symbol]) } } label: { Text(["heart":"💗","kiss":"😘","hug":"🤗","star":"✨","wave":"👋"][symbol] ?? "💗").font(.largeTitle) }.accessibilityLabel("Signal " + symbol)
                }
            }
            TVSignalsCard()
            Text("Erscheint im Signale-Widget des Dashboards und neben eurer gemeinsamen Bühne. Keine Videos werden überdeckt.").font(.caption).foregroundStyle(.secondary)
        }.loveCard()
    }
}
