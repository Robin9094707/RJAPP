import CoreLocation
import MapKit
import SwiftUI

struct PartnerMapView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshing=false
    @State private var refreshTurn=0.0
    @State private var geocodeTask:Task<Void,Never>?
    @State private var position: MapCameraPosition = .automatic
    @State private var address = "Standort wird aufgelöst …"
    @State private var showingPlaceEditor = false
    @State private var showingPlaces = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                UserAnnotation()
                if let coordinate = partnerCoordinate {
                    if let accuracy=partnerAccuracy {
                        MapCircle(center:coordinate,radius:accuracy)
                            .foregroundStyle(LovePalette.pink.opacity(0.12))
                            .stroke(LovePalette.pink.opacity(0.6),lineWidth:1.5)
                    }
                    Annotation(appState.partner?.displayName ?? "Schatzi", coordinate: coordinate, anchor: .bottom) {
                        VStack(spacing: 3) {
                            PartnerAvatar(name: appState.partner?.displayName ?? "Schatzi", size: 58)
                            Image(systemName: "triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(LovePalette.pink)
                                .rotationEffect(.degrees(180))
                        }
                    }
                }
                ForEach(appState.geofences) { record in
                    if let latitude = record.payload.latitude, let longitude = record.payload.longitude {
                        MapCircle(
                            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                            radius: record.payload.radius ?? 100
                        )
                        .foregroundStyle(LovePalette.cyan.opacity(0.12))
                        .stroke(LovePalette.cyan.opacity(0.65), lineWidth: 2)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapUserLocationButton()
            }
            .ignoresSafeArea(edges: .bottom)

            partnerSheet
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .navigationTitle("Wo ist Schatzi?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingPlaces = true } label: { Image(systemName: "mappin.and.ellipse") }
                Button { centerOnPartner() } label: { Image(systemName: "scope") }
                    .disabled(partnerCoordinate == nil)
            }
        }
        .sheet(isPresented: $showingPlaceEditor) {
            GeofenceEditorView(initialCoordinate: partnerCoordinate)
        }
        .sheet(isPresented: $showingPlaces) {
            GeofenceListView()
        }
        .onAppear {
            centerOnPartner()
            resolveAddress()
        }
        .onChange(of: appState.partner?.presence?.locationTimestamp) { _, _ in resolveAddress() }
        .onChange(of: appState.partner?.presence?.locationSharing) { _,_ in resolveAddress() }
        .onDisappear {geocodeTask?.cancel()}
    }

    private var partnerSheet: some View {
        VStack(alignment: .leading, spacing: 15) {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 46, height: 5)
                .frame(maxWidth: .infinity)
            HStack(spacing: 13) {
                PartnerAvatar(name: appState.partner?.displayName ?? "Schatzi", size: 54).onTapGesture{appState.showingPartnerProfile=true}
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.partner?.displayName ?? "Schatzi")
                        .font(.title2.bold())
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let date = appState.partner?.presence?.locationTimestamp?.rjDate {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Date.now.timeIntervalSince(date) < 90 ? .green : .orange)
                    }
                }
                Spacer()
                BatteryBadge(level: appState.partner?.presence?.batteryLevel, state: appState.partner?.presence?.batteryState)
            }

            HStack(spacing: 11) {
                mapAction("Route", symbol: "arrow.triangle.turn.up.right.diamond.fill", tint: LovePalette.cyan) {
                    openRoute()
                }
                .disabled(partnerCoordinate == nil)
                mapAction("Ort merken", symbol: "mappin.and.ellipse", tint: LovePalette.pink) {
                    showingPlaceEditor = true
                }
                .disabled(partnerCoordinate == nil)
                mapAction("Neu laden", symbol: "arrow.clockwise", tint: LovePalette.violet) {
                    guard !refreshing else {return}
                    refreshing=true
                    if !reduceMotion {withAnimation(.linear(duration:0.8)) {refreshTurn += 360}}
                    Task {
                        let success=await appState.syncNow(showErrors:true)
                        if success {resolveAddress();if reduceMotion {centerOnPartner()} else {withAnimation(.smooth(duration:0.6)) {centerOnPartner()}};Haptics.success()}
                        refreshing=false
                    }
                }.disabled(refreshing || appState.isSyncing)
            }
            if let accuracy=partnerAccuracy {Label("Genauigkeit ca. \(Int(accuracy.rounded())) m",systemImage:"scope").font(.caption).foregroundStyle(.secondary)}
            if let distance {
                Label(distance.formatted(.measurement(width: .abbreviated, usage: .road)), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .loveGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var partnerCoordinate: CLLocationCoordinate2D? {
        guard appState.partner?.presence?.locationSharing == true,
              let latitude = appState.partner?.presence?.latitude,
              let longitude = appState.partner?.presence?.longitude else { return nil }
        let coordinate=CLLocationCoordinate2D(latitude:latitude,longitude:longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private var partnerAccuracy:Double? {
        guard partnerCoordinate != nil,let accuracy=appState.partner?.presence?.horizontalAccuracy,accuracy.isFinite,accuracy > 0 else {return nil}
        return min(accuracy,20_000_000)
    }
    private var distance: Measurement<UnitLength>? {
        guard let own = appState.location.lastLocation, let partnerCoordinate else { return nil }
        let meters = own.distance(from: CLLocation(latitude: partnerCoordinate.latitude, longitude: partnerCoordinate.longitude))
        return Measurement(value: meters, unit: UnitLength.meters)
    }

    private func centerOnPartner() {
        guard let coordinate = partnerCoordinate else { return }
        position = .camera(
            MapCamera(centerCoordinate: coordinate, distance: max(1_100,min((partnerAccuracy ?? 0)*5,20_000_000)), heading: 0, pitch: 35)
        )
    }

    private func resolveAddress() {
        geocodeTask?.cancel()
        guard let coordinate = partnerCoordinate else {
            address = appState.partner?.presence?.locationSharing == false
                ? "Standortfreigabe ist ausgeschaltet"
                : "Noch kein Standort verfügbar"
            return
        }
        geocodeTask=Task {
            do {
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard let request = MKReverseGeocodingRequest(location: location) else { return }
                let mapItems = try await request.mapItems
                guard !Task.isCancelled,let current=partnerCoordinate,current.latitude == coordinate.latitude,current.longitude == coordinate.longitude else {return}
                address = mapItems.first?.name
                    ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
            } catch {
                guard !Task.isCancelled else {return}
                address = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
            }
        }
    }

    private func openRoute() {
        guard let coordinate = partnerCoordinate else { return }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = appState.partner?.displayName ?? "Schatzi"
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    private func mapAction(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if title == "Neu laden" && refreshing {ProgressView().tint(tint)}
                    else {Image(systemName:symbol).font(.title3).foregroundStyle(tint).rotationEffect(.degrees(title == "Neu laden" ? refreshTurn:0))}
                }
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .loveGlass(in:RoundedRectangle(cornerRadius:18,style:.continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct GeofenceEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Lieblingsort"
    @State private var latitude: Double
    @State private var longitude: Double
    @State private var radius = 100.0
    @State private var onEnter = true
    @State private var onExit = true
    @State private var saving = false

    init(initialCoordinate: CLLocationCoordinate2D?) {
        _latitude = State(initialValue: initialCoordinate?.latitude ?? 51.0)
        _longitude = State(initialValue: initialCoordinate?.longitude ?? 6.75)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gemeinsamer Ort") {
                    TextField("Name", text: $name)
                    LabeledContent("Breitengrad") {
                        TextField("Latitude", value: $latitude, format: .number.precision(.fractionLength(5)))
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Längengrad") {
                        TextField("Longitude", value: $longitude, format: .number.precision(.fractionLength(5)))
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading) {
                        Text("Radius · \(Int(radius)) m")
                        Slider(value: $radius, in: 50...1000, step: 25)
                    }
                }
                Section("Benachrichtigen") {
                    Toggle("Beim Betreten", isOn: $onEnter)
                    Toggle("Beim Verlassen", isOn: $onExit)
                    Text("Der Ort wird auf dem iPhone von \(appState.partner?.displayName ?? "Schatzi") überwacht, sobald dort „Immer“ für Standort erlaubt wurde.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ort merken")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        saving = true
                        Task {
                            let payload = RecordPayload(
                                targetID: appState.partner?.id,
                                name: name,
                                latitude: latitude,
                                longitude: longitude,
                                radius: radius,
                                notifyOnEnter: onEnter,
                                notifyOnExit: onExit
                            )
                            if await appState.saveRecord(kind: .geofence, payload: payload) != nil { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }
}

private struct GeofenceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: SharedRecord?

    var body: some View {
        NavigationStack {
            List {
                if appState.geofences.isEmpty {
                    ContentUnavailableView("Keine Orte", systemImage: "mappin.slash", description: Text("Lege auf der Karte euren ersten gemeinsamen Ort an."))
                }
                ForEach(appState.geofences) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.payload.name ?? "Gemeinsamer Ort").font(.headline)
                        Text("Radius \(Int(record.payload.radius ?? 100)) m · \(record.payload.targetID == appState.me?.id ? "für dich" : "für Schatzi")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Löschen", role: .destructive) { deleting = record }
                    }
                }
            }
            .navigationTitle("Gemeinsame Orte")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .alert("Ort löschen?", isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            )) {
                Button("Löschen", role: .destructive) {
                    guard let record = deleting else { return }
                    Task { _ = await appState.deleteRecord(record); deleting = nil }
                }
                Button("Abbrechen", role: .cancel) { deleting = nil }
            } message: {
                Text("Die Geofence-Überwachung wird auf beiden Geräten entfernt.")
            }
        }
    }
}
