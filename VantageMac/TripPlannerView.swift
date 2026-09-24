import AppKit
import CoreLocation
import MapKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Desk-side day planner for one trip: put the trip's spots in visiting order, see when
/// the light is right at each one on a chosen date, how long the drives between them
/// take, and hand the whole day off as a Google Maps route or a printed shot sheet.
///
/// Times are shown in the trip's own time zone (looked up from its first stop), not
/// the Mac's — planning a West Coast trip from New Jersey shouldn't mean mental math.
struct TripPlannerView: View {
    static let windowID = "trip-planner"

    @Binding var tripID: UUID?

    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @Query private var allEntries: [LocationEntryModel]

    @State private var planDate = Date()
    @State private var order: [UUID] = []
    @State private var legs: [String: TripPlanLeg] = [:]
    @State private var timeZone: TimeZone = .current
    @State private var isExportingPDF = false
    @State private var exportDocument: TripShotSheetDocument?
    @State private var cameraPosition: MapCameraPosition = .automatic
    /// Each TripPlanSunDay is ~1,440 sun-position evaluations, and `stops`/the rows read
    /// them on every render, so they're computed once per (date, time zone, spot set).
    @State private var sunDays: [UUID: TripPlanSunDay] = [:]
    @State private var findMoreTrip: TripModel?

    private var trip: TripModel? {
        trips.first { $0.id == tripID }
    }

    /// The trip's spots in planned order: whatever order was saved, then any spots added
    /// to the trip since, appended by best-light time.
    private var stops: [LocationEntryModel] {
        guard let tripID else { return [] }
        let tripEntries = allEntries.filter { $0.tripID == tripID }
        let byID = Dictionary(uniqueKeysWithValues: tripEntries.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        let remaining = tripEntries
            .filter { !order.contains($0.id) }
            .sorted { (sun(for: $0).bestLight ?? .distantFuture) < (sun(for: $1).bestLight ?? .distantFuture) }
        return ordered + remaining
    }

    private func sun(for entry: LocationEntryModel) -> TripPlanSunDay {
        sunDays[entry.id] ?? TripPlanSunDay(latitude: entry.latitude, longitude: entry.longitude, day: planDate, timeZone: timeZone, headingDegrees: entry.headingDegrees)
    }

    private var sunCacheKey: String {
        let tripEntryIDs = allEntries.filter { $0.tripID == tripID }.map(\.id.uuidString).sorted().joined()
        return "\(planDate.formatted(.iso8601.year().month().day()))|\(timeZone.identifier)|\(tripEntryIDs)"
    }

    private func refreshSunDays() {
        var days: [UUID: TripPlanSunDay] = [:]
        for entry in allEntries where entry.tripID == tripID {
            days[entry.id] = TripPlanSunDay(latitude: entry.latitude, longitude: entry.longitude, day: planDate, timeZone: timeZone, headingDegrees: entry.headingDegrees)
        }
        sunDays = days
    }

    private var totalDriveTime: TimeInterval {
        zip(stops, stops.dropFirst()).compactMap { legs[TripPlanLeg.key($0.id, $1.id)]?.travelTime }.reduce(0, +)
    }

    private var routeURL: URL? {
        guard stops.count >= 2 else { return nil }
        return ExternalNavigationService.googleMapsRouteURL(stops: stops.map { (latitude: $0.latitude, longitude: $0.longitude) })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if trip == nil {
                ContentUnavailableView("Choose a Trip", systemImage: "signpost.right.and.left", description: Text("Pick a trip above to plan its day."))
            } else if stops.isEmpty {
                ContentUnavailableView("No Spots in This Trip", systemImage: "mappin.slash", description: Text("Move spots into this trip from the main window first."))
            } else {
                HSplitView {
                    stopList
                        .frame(minWidth: 380, idealWidth: 460)
                    routeMap
                        .frame(minWidth: 320)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .navigationTitle(trip.map { "Plan: \($0.name)" } ?? "Trip Planner")
        .onAppear(perform: loadOrder)
        .onChange(of: tripID) {
            legs = [:]
            loadOrder()
        }
        .task(id: sunCacheKey) {
            refreshSunDays()
        }
        .task(id: stops.first?.id) {
            await lookUpTimeZone()
        }
        .task(id: stops.map(\.id)) {
            await calculateLegs()
        }
        .sheet(item: $findMoreTrip) { trip in
            ImportHelpView(trip: trip)
        }
        .fileExporter(isPresented: $isExportingPDF, document: exportDocument, contentType: .pdf, defaultFilename: pdfFilename) { _ in
            exportDocument = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Picker("Trip", selection: $tripID) {
                Text("Choose…").tag(UUID?.none)
                ForEach(trips) { trip in
                    Text(trip.name).tag(UUID?.some(trip.id))
                }
            }
            .frame(maxWidth: 260)

            DatePicker("Date", selection: $planDate, displayedComponents: .date)
                .frame(maxWidth: 200)

            if let first = stops.first {
                let day = sun(for: first)
                HStack(spacing: 12) {
                    Label(time(day.sunrise), systemImage: "sunrise")
                    Label(time(day.sunset), systemImage: "sunset")
                }
                .foregroundStyle(AppTheme.apertureGold)
                .help(timeZone == .current ? "Sunrise and sunset at the first stop" : "Sunrise and sunset at the first stop, in \(timeZone.identifier)")
            }

            Spacer()

            if totalDriveTime > 0 {
                Label(duration(totalDriveTime), systemImage: "car")
                    .foregroundStyle(.secondary)
                    .help("Total driving time between stops, in this order")
            }

            Button {
                findMoreTrip = trip
            } label: {
                Label("Find More Spots…", systemImage: "sparkles")
            }
            .help("Ask any AI chat tool for more spots near this trip — they're added straight to it")
            .disabled(trip == nil || stops.isEmpty)

            Button {
                sortByBestLight()
            } label: {
                Label("Order by Best Light", systemImage: "sun.max")
            }
            .disabled(stops.count < 2)

            if let routeURL {
                Link(destination: routeURL) {
                    Label("Open Route", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
                }
            }

            Menu {
                Button("Print Shot Sheet…", action: printShotSheet)
                Button("Export Shot Sheet as PDF…") {
                    if let data = shotSheetPDF() {
                        exportDocument = TripShotSheetDocument(data: data)
                        isExportingPDF = true
                    }
                }
            } label: {
                Label("Shot Sheet", systemImage: "printer")
            }
            .fixedSize()
            .disabled(stops.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Stop list

    private var stopList: some View {
        List {
            if timeZone != .current {
                Text("Times shown in \(timeZone.localizedName(for: .standard, locale: .current) ?? timeZone.identifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 6) {
                    if index > 0, let leg = legs[TripPlanLeg.key(stops[index - 1].id, entry.id)] {
                        Label("\(duration(leg.travelTime)) · \(distance(leg.distance))", systemImage: "car")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    stopRow(index: index, entry: entry)
                }
                .padding(.vertical, 4)
            }
            .onMove { source, destination in
                var ids = stops.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                saveOrder(ids)
            }
        }
    }

    private func stopRow(index: Int, entry: LocationEntryModel) -> some View {
        let day = sun(for: entry)
        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.headline.monospacedDigit())
                .frame(width: 26, height: 26)
                .background(AppTheme.cobalt, in: Circle())
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title?.isEmpty == false ? entry.title! : "Untitled Spot")
                    .font(.headline)
                if let bestLight = day.bestLight {
                    Text("Best light \(time(bestLight))")
                        .foregroundStyle(AppTheme.apertureGold)
                } else {
                    Text("Golden hour \(time(day.sunrise))–\(time(day.morningGoldenEnd)) · \(time(day.eveningGoldenStart))–\(time(day.sunset))")
                        .foregroundStyle(AppTheme.apertureGold)
                        .help("No capture heading on this spot, so this is the general golden-hour window rather than a match to the direction you'll face.")
                }
                if !entry.shotList.isEmpty {
                    Text("\(entry.shotList.filter(\.isDone).count)/\(entry.shotList.count) shots done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let parking = entry.parkingNotes, !parking.isEmpty {
                    Label(parking, systemImage: "parkingsign")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Map

    private var routeMap: some View {
        Map(position: $cameraPosition) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, entry in
                Annotation(entry.title ?? "Spot", coordinate: CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude)) {
                    Text("\(index + 1)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 24, height: 24)
                        .background(AppTheme.cobalt, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .foregroundStyle(.white)
                }
            }
            ForEach(Array(zip(stops, stops.dropFirst())), id: \.1.id) { from, to in
                if let leg = legs[TripPlanLeg.key(from.id, to.id)] {
                    MapPolyline(leg.polyline)
                        .stroke(AppTheme.cobalt.opacity(0.85), lineWidth: 4)
                }
            }
        }
    }

    // MARK: - Order persistence

    /// Stored per trip in this Mac's UserDefaults, not synced — a synced order would
    /// need a new CloudKit schema field deployed to production before shipping.
    private static func orderKey(for tripID: UUID) -> String {
        "com.jamespennucci.Vantage.tripPlanOrder.\(tripID.uuidString)"
    }

    private func loadOrder() {
        guard let tripID else { order = []; return }
        order = (UserDefaults.standard.stringArray(forKey: Self.orderKey(for: tripID)) ?? []).compactMap(UUID.init)
    }

    private func saveOrder(_ ids: [UUID]) {
        order = ids
        guard let tripID else { return }
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: Self.orderKey(for: tripID))
    }

    private func sortByBestLight() {
        // Spots without a heading fall back to the evening golden hour, the usual default.
        let sorted = stops.sorted {
            let a = sun(for: $0), b = sun(for: $1)
            return (a.bestLight ?? a.eveningGoldenStart ?? .distantFuture) < (b.bestLight ?? b.eveningGoldenStart ?? .distantFuture)
        }
        saveOrder(sorted.map(\.id))
    }

    // MARK: - Lookups

    private func lookUpTimeZone() async {
        guard let first = stops.first else { return }
        let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
           let zone = placemark.timeZone {
            timeZone = zone
        }
    }

    /// Sequential rather than concurrent — MKDirections throttles apps that fire off
    /// a burst of requests. Legs already calculated for the same pair are reused.
    private func calculateLegs() async {
        for (from, to) in zip(stops, stops.dropFirst()) {
            let key = TripPlanLeg.key(from.id, to.id)
            guard legs[key] == nil else { continue }
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)))
            request.transportType = .automobile
            guard let route = try? await MKDirections(request: request).calculate().routes.first else { continue }
            if Task.isCancelled { return }
            legs[key] = TripPlanLeg(travelTime: route.expectedTravelTime, distance: route.distance, polyline: route.polyline)
        }
    }

    // MARK: - Formatting

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    private func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func distance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }

    // MARK: - Shot sheet

    private var pdfFilename: String {
        "\(trip?.name ?? "Trip") \(planDate.formatted(.iso8601.year().month().day()))"
    }

    /// Paginated US Letter PDF: each stop is rendered as its own block and moved to a
    /// new page rather than split across a page break.
    private func shotSheetPDF() -> Data? {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 36
        let contentWidth = pageSize.width - margin * 2

        var blocks: [AnyView] = [AnyView(shotSheetHeader.frame(width: contentWidth, alignment: .leading))]
        for (index, entry) in stops.enumerated() {
            let leg = index > 0 ? legs[TripPlanLeg.key(stops[index - 1].id, entry.id)] : nil
            blocks.append(AnyView(shotSheetStop(index: index, entry: entry, leg: leg).frame(width: contentWidth, alignment: .leading)))
        }

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        var y = margin
        context.beginPDFPage(nil)
        for block in blocks {
            let renderer = ImageRenderer(content: block.environment(\.colorScheme, .light))
            renderer.render { size, draw in
                if y + size.height > pageSize.height - margin, y > margin {
                    context.endPDFPage()
                    context.beginPDFPage(nil)
                    y = margin
                }
                context.saveGState()
                // PDF origin is bottom-left; blocks flow top-down.
                context.translateBy(x: margin, y: pageSize.height - y - size.height)
                draw(context)
                context.restoreGState()
                y += size.height + 14
            }
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private var shotSheetHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip?.name ?? "Trip")
                .font(.system(size: 22, weight: .bold))
            Text(planDate.formatted(date: .complete, time: .omitted))
                .font(.system(size: 13))
            if let first = stops.first {
                let day = sun(for: first)
                Text("Sunrise \(time(day.sunrise)) · Sunset \(time(day.sunset))\(totalDriveTime > 0 ? " · \(duration(totalDriveTime)) driving" : "")\(timeZone == .current ? "" : " · times in \(timeZone.identifier)")")
                    .font(.system(size: 11))
            }
            Rectangle().frame(height: 1).padding(.top, 6)
        }
        .foregroundStyle(.black)
    }

    private func shotSheetStop(index: Int, entry: LocationEntryModel, leg: TripPlanLeg?) -> some View {
        let day = sun(for: entry)
        return VStack(alignment: .leading, spacing: 4) {
            if let leg {
                Text("↓ \(duration(leg.travelTime)) drive · \(distance(leg.distance))")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
            Text("\(index + 1). \(entry.title?.isEmpty == false ? entry.title! : "Untitled Spot")")
                .font(.system(size: 15, weight: .semibold))
            Text(String(format: "%.5f, %.5f", entry.latitude, entry.longitude))
                .font(.system(size: 10).monospaced())
            if let bestLight = day.bestLight {
                Text("Best light \(time(bestLight))\(entry.headingDegrees.map { String(format: " facing %.0f°", $0) } ?? "")")
                    .font(.system(size: 11, weight: .medium))
            } else {
                Text("Golden hour \(time(day.sunrise))–\(time(day.morningGoldenEnd)) · \(time(day.eveningGoldenStart))–\(time(day.sunset))")
                    .font(.system(size: 11, weight: .medium))
            }
            if let note = entry.note, !note.isEmpty {
                Text(note).font(.system(size: 11))
            }
            if let parking = entry.parkingNotes, !parking.isEmpty {
                Text("Parking: \(parking)").font(.system(size: 11))
            }
            ForEach(entry.shotList) { shot in
                Text("\(shot.isDone ? "☑" : "☐")  \(shot.text)")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(.black)
    }

    private func printShotSheet() {
        guard let data = shotSheetPDF(), let document = PDFDocument(data: data) else { return }
        document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleNone, autoRotate: false)?
            .runModal(for: NSApp.keyWindow ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
    }
}

// MARK: - Supporting types

struct TripPlanLeg {
    let travelTime: TimeInterval
    let distance: CLLocationDistance
    let polyline: MKPolyline

    static func key(_ from: UUID, _ to: UUID) -> String {
        "\(from.uuidString)>\(to.uuidString)"
    }
}

/// Sun events for one spot on one local calendar day. Scans that day minute by minute
/// with `SunPositionEngine.position`, the same NOAA math the rest of the app uses.
/// Unlike `goldenHourSuggestion` (which scans a UTC day), this scans the *local* day,
/// so a West Coast sunset doesn't slip into the next UTC date.
struct TripPlanSunDay {
    var sunrise: Date?
    var sunset: Date?
    /// Morning golden hour runs sunrise → sun at 6°; evening runs 6° → sunset.
    var morningGoldenEnd: Date?
    var eveningGoldenStart: Date?
    /// Moment the sun's azimuth best matches the spot's capture heading at golden-hour
    /// elevation — nil for spots without a heading (e.g. ones added from a link).
    var bestLight: Date?

    init(latitude: Double, longitude: Double, day: Date, timeZone: TimeZone, headingDegrees: Double?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Take the y/m/d the user picked (in the Mac's calendar) and start that same
        // calendar date at midnight in the trip's time zone.
        let picked = Calendar.current.dateComponents([.year, .month, .day], from: day)
        guard let dayStart = calendar.date(from: picked) else { return }

        let horizon = -0.833 // standard refraction-corrected sunrise/sunset altitude
        let golden = 6.0
        var previous: Double?
        var bestDelta = Double.infinity

        for minute in 0...(24 * 60) {
            let sample = dayStart.addingTimeInterval(Double(minute) * 60)
            let position = SunPositionEngine.position(at: sample, latitude: latitude, longitude: longitude)
            let elevation = position.elevationDegrees
            if let previous {
                if previous < horizon, elevation >= horizon, sunrise == nil { sunrise = sample }
                if previous < golden, elevation >= golden, morningGoldenEnd == nil { morningGoldenEnd = sample }
                if previous >= golden, elevation < golden { eveningGoldenStart = sample }
                if previous >= horizon, elevation < horizon { sunset = sample }
            }
            previous = elevation

            if let headingDegrees, elevation >= -1, elevation <= 8 {
                let diff = abs(position.azimuthDegrees - headingDegrees).truncatingRemainder(dividingBy: 360)
                let delta = min(diff, 360 - diff)
                if delta < bestDelta {
                    bestDelta = delta
                    bestLight = sample
                }
            }
        }
    }
}

struct TripShotSheetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
