import SwiftUI

struct CinemaHomeCard: View {
    @Environment(AppState.self) private var app
    @State private var cinema = CinemaCoordinator.shared
    var body: some View {
        Button { app.selectedTab = .cinema } label: {
            VStack(alignment: .leading,spacing: 15) {
                HStack { LoveIcon(symbol: "popcorn.fill",tint: LovePalette.violet,size: 48); VStack(alignment: .leading,spacing: 4) { LoveEyebrow(text: "Ein Platz neben dir"); Text(cinema.active ? "Unser Kino läuft" : "Unser gemeinsames Kino").font(.title3.bold()) }; Spacer(); Image(systemName: "chevron.right").font(.caption) }
                if cinema.active {
                    Text(cinema.title).font(.headline).lineLimit(2)
                    HStack { Label(cinema.playing ? "Wiedergabe" : "Pausiert",systemImage: cinema.playing ? "play.fill" : "pause.fill"); Spacer(); Text(Duration.seconds(cinema.position).formatted(.time(pattern: .hourMinuteSecond))).monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                    if let device = cinema.room?.details?.device { Label(device,systemImage: "tv").font(.caption).foregroundStyle(.secondary) }
                } else { Text("Plex, YouTube und AirPlay. Zusammen schauen, auch wenn ihr gerade nicht nebeneinander sitzt.").font(.subheadline).foregroundStyle(.secondary) }
            }.padding(20).frame(maxWidth: .infinity,alignment: .leading).loveGlass(in: RoundedRectangle(cornerRadius: 28))
        }.buttonStyle(.plain)
    }
}
struct PlexCinemaInformation: View {
    let details: PlexCinemaDetails?
    var body: some View {
        if let details {
            VStack(alignment: .leading,spacing: 9) {
                let badges = [details.year, details.rating, details.resolution.map { $0.isEmpty ? "" : $0+"p" },details.videoCodec?.uppercased(),details.audioCodec?.uppercased()].compactMap { $0 }.filter { !$0.isEmpty }
                if !badges.isEmpty { Text(badges.joined(separator: " · ")).font(.caption.bold()).foregroundStyle(LovePalette.violet) }
                if let device = details.device { Label(device,systemImage: "tv").font(.caption) }
                if let server = details.serverName { Label(server,systemImage: "externaldrive").font(.caption).foregroundStyle(.secondary) }
                if let summary = details.summary, !summary.isEmpty { Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(5) }
            }
        }
    }
}
