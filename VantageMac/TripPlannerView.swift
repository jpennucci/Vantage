import AppKit
import CoreLocation
import MapKit
import PDFKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Desk-side planner for a trip, one day at a time: split the trip's spots into days,
/// put each day's stops in order, set where and when the day starts, and see when
/// you'll arrive at each stop against when its light is best — then hand the day off
/// as a Google Maps route or a printed shot sheet.
///
/// Times are shown in the trip's own time zone (looked up from its first spot), not
/// the Mac's — planning a West Coast trip from New Jersey shouldn't mean mental math.
/// The plan itself is stored on this Mac only (see `TripPlan`).
struct TripPlannerView: View {
    static let windowID = "trip-planner"

    @Binding var tripID: UUID?

    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @Query private var allEntries: [LocationEntryModel]

    @State private var plan = TripPlan()
    @State private var selectedDayID: UUID?
    @State private var legs: [String: TripPlanLeg] = [:]
    @State private var timeZone: TimeZone = .current
    /// Each TripPlanSunDay is ~1,440 sun-position evaluations and the rows read them on
    /// every render, so they're computed once per (day, time zone, spot) — see refreshSunDays.
    @State private var sunDays: [String: TripPlanSunDay] = [:]
    @State private var startText = ""
    @State private var isResolvingStart = false
    @State private var startError: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var findMoreTrip: TripModel?
    @State private var isExportingPDF = false
    @State private var exportDocument: TripShotSheetDocument?
    @State private var exportFilename = "Trip"
    /// Cloud forecast at each stop's target light time, keyed by forecastKey(_:).
    @State private var forecasts: [String: CloudForecast] = [:]

    // MARK: - Derived data

    private var trip: TripModel? {
        trips.first { $0.id == tripID }
    }

    private var tripEntries: [LocationEntryModel] {
        allEntries.filter { $0.tripID == tripID && tripID != nil }
    }

    private var selectedDayIndex: Int? {
        plan.days.firstIndex { $0.id == selectedDayID } ?? (plan.days.isEmpty ? nil : 0)
    }

    private var selectedDay: TripDayPlan? {
        selectedDayIndex.map { plan.days[$0] }
    }

    private func stops(for day: TripDayPlan) -> [LocationEntryModel] {
        let byID = Dictionary(uniqueKeysWithValues: tripEntries.map { ($0.id, $0) })
        return day.stopIDs.compactMap { byID[$0] }
    }

    /// Trip spots not placed on any day — e.g. added to the trip after it was planned.
    private var unscheduled: [LocationEntryModel] {
        let scheduled = Set(plan.days.flatMap(\.stopIDs))
        return tripEntries.filter { !scheduled.contains($0.id) }
    }

    private func dayStart(_ day: TripDayPlan) -> Date {
        SunOverlaySnapshot.dayStart(day.date, in: timeZone)
    }

    private func sunKey(_ entry: LocationEntryModel, _ day: TripDayPlan) -> String {
        "\(entry.id.uuidString)|\(day.date.formatted(.iso8601.year().month().day()))"
    }

    private func sun(for entry: LocationEntryModel, on day: TripDayPlan) -> TripPlanSunDay {
        sunDays[sunKey(entry, day)]
            ?? TripPlanSunDay(latitude: entry.latitude, longitude: entry.longitude, day: day.date, timeZone: timeZone, headingDegrees: entry.headingDegrees)
    }

    private func coordinate(_ entry: LocationEntryModel) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: entry.latitude, longitude: entry.longitude)
    }

    /// Arrival/departure for each stop: leave the start (or arrive at the first stop
    /// when there's no start) at the day's start time, then drive time + time spent at
    /// each stop. A leg still being calculated counts as zero until it arrives.
    private func schedule(for day: TripDayPlan) -> [TripScheduleItem] {
        var clock = dayStart(day).addingTimeInterval(day.startMinute * 60)
        var previous: CLLocationCoordinate2D? = day.start?.coordinate
        var items: [TripScheduleItem] = []
        for entry in stops(for: day) {
            let here = coordinate(entry)
            let leg = previous.flatMap { legs[TripPlanLeg.key($0, here)] }
            let arrival = clock.addingTimeInterval(leg?.travelTime ?? 0)
            let departure = arrival.addingTimeInterval(day.minutesPerStop * 60)
            items.append(TripScheduleItem(entry: entry, legFromPrevious: leg, arrival: arrival, departure: departure, sun: sun(for: entry, on: day)))
            clock = departure
            previous = here
        }
        return items
    }

    private func driveTime(_ items: [TripScheduleItem]) -> TimeInterval {
        items.compactMap { $0.legFromPrevious?.travelTime }.reduce(0, +)
    }

    private func routeURL(for day: TripDayPlan) -> URL? {
        var points = stops(for: day).map { (latitude: $0.latitude, longitude: $0.longitude) }
        if let start = day.start {
            points.insert((latitude: start.latitude, longitude: start.longitude), at: 0)
        }
        guard points.count >= 2 else { return nil }
        return ExternalNavigationService.googleMapsRouteURL(stops: points)
    }

    /// Everything that should trigger recomputing sun times.
    private var sunCacheKey: String {
        let days = plan.days.map { $0.date.formatted(.iso8601.year().month().day()) }.joined(separator: ",")
        let ids = tripEntries.map(\.id.uuidString).sorted().joined()
        return "\(days)|\(timeZone.identifier)|\(ids)"
    }

    /// Every leg the plan needs, in order — recalculated when stops or starts change.
    private var legPairs: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] {
        plan.days.flatMap { day -> [(CLLocationCoordinate2D, CLLocationCoordinate2D)] in
            var points = stops(for: day).map(coordinate)
            if let start = day.start { points.insert(start.coordinate, at: 0) }
            return Array(zip(points, points.dropFirst()))
        }
    }

    private func forecastKey(_ item: TripScheduleItem) -> String {
        "\(item.entry.id.uuidString)@\((item.target ?? item.arrival).timeIntervalSince1970)"
    }

    /// Refetch when the selected day's stops or their target times change.
    private var forecastTaskKey: String {
        guard let day = selectedDay else { return "" }
        return schedule(for: day).map(forecastKey).joined(separator: ",")
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if trip == nil {
                ContentUnavailableView("Choose a Trip", systemImage: "signpost.right.and.left", description: Text("Pick a trip above to plan it."))
            } else if tripEntries.isEmpty {
                ContentUnavailableView("No Spots in This Trip", systemImage: "mappin.slash", description: Text("Move spots into this trip from the main window first."))
            } else if let dayIndex = selectedDayIndex {
                dayBar
                Divider()
                daySettings(dayIndex)
                Divider()
                HSplitView {
                    stopList(dayIndex)
                        .frame(minWidth: 420, idealWidth: 500)
                    routeMap(plan.days[dayIndex])
                        .frame(minWidth: 320)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .navigationTitle(trip.map { "Plan: \($0.name)" } ?? "Trip Planner")
        .onAppear(perform: loadPlan)
        .onChange(of: tripID) {
            legs = [:]
            loadPlan()
        }
        .onChange(of: plan) {
            if let tripID { plan.save(tripID: tripID) }
        }
        .task(id: sunCacheKey) {
            refreshSunDays()
        }
        .task(id: tripEntries.first?.id) {
            await lookUpTimeZone()
        }
        .task(id: legPairs.map { TripPlanLeg.key($0.0, $0.1) }) {
            await calculateLegs()
        }
        .task(id: forecastTaskKey) {
            await loadForecasts()
        }
        .sheet(item: $findMoreTrip) { trip in
            ImportHelpView(trip: trip)
        }
        .fileExporter(isPresented: $isExportingPDF, document: exportDocument, contentType: .pdf, defaultFilename: exportFilename) { _ in
            exportDocument = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Picker("Trip", selection: $tripID) {
                Text("Choose…").tag(UUID?.none)
                ForEach(trips) { trip in
                    Text(trip.name).tag(UUID?.some(trip.id))
                }
            }
            .frame(maxWidth: 260)

            if timeZone != .current {
                Text("Times in \(timeZone.localizedName(for: .shortStandard, locale: .current) ?? timeZone.identifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                findMoreTrip = trip
            } label: {
                Label("Find More Spots…", systemImage: "sparkles")
            }
            .help("Ask any AI chat tool for more spots near this trip — they're added straight to it")
            .disabled(trip == nil || tripEntries.isEmpty)

            if let day = selectedDay, let url = routeURL(for: day) {
                Link(destination: url) {
                    Label("Open Route", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
                }
                .help("Open this day's stops, in order, as a Google Maps route")
            }

            Menu {
                Button("Print This Day…") { printShotSheet(days: selectedDay.map { [$0] } ?? []) }
                Button("Export This Day as PDF…") { export(days: selectedDay.map { [$0] } ?? []) }
                Divider()
                Button("Export Whole Trip as PDF…") { export(days: plan.days) }
            } label: {
                Label("Shot Sheet", systemImage: "printer")
            }
            .fixedSize()
            .disabled(plan.days.allSatisfy { stops(for: $0).isEmpty })
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var dayBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
                    let isSelected = day.id == selectedDay?.id
                    Button {
                        selectedDayID = day.id
                    } label: {
                        VStack(spacing: 1) {
                            Text("Day \(index + 1)").font(.headline)
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(isSelected ? AppTheme.cobalt : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove Day \(index + 1)", role: .destructive) { removeDay(day.id) }
                            .disabled(plan.days.count == 1)
                    }
                }
                Button(action: addDay) {
                    Label("Add Day", systemImage: "plus")
                }
                .help("Add the next day to this trip")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Day settings

    private func daySettings(_ dayIndex: Int) -> some View {
        let day = plan.days[dayIndex]
        let items = schedule(for: day)
        return HStack(alignment: .firstTextBaseline, spacing: 16) {
            DatePicker("Date", selection: $plan.days[dayIndex].date, displayedComponents: .date)
                .fixedSize()

            HStack(spacing: 6) {
                Text("Start")
                if let start = day.start {
                    Label(start.name, systemImage: "house")
                        .lineLimit(1)
                    Button {
                        plan.days[dayIndex].start = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Start at the first stop instead")
                } else {
                    TextField("Hotel, address, or Maps link (optional)", text: $startText)
                        .frame(width: 240)
                        .onSubmit { Task { await resolveStart(dayIndex) } }
                    if isResolvingStart { ProgressView().controlSize(.small) }
                }
            }
            .help("Where the day's driving begins. Leave empty to start at the first stop.")

            DatePicker(day.start == nil ? "First stop at" : "Leave at", selection: startTimeBinding(dayIndex), displayedComponents: .hourAndMinute)
                .environment(\.timeZone, timeZone)
                .fixedSize()

            Stepper("\(Int(day.minutesPerStop)) min per stop", value: $plan.days[dayIndex].minutesPerStop, in: 10...240, step: 10)
                .fixedSize()

            Button("Leave in Time for First Light") { fitStartToFirstLight(dayIndex) }
                .disabled(items.first?.target == nil)
                .help("Set the start time so you reach the first stop 15 minutes before its best light")

            Spacer()

            if let first = items.first {
                HStack(spacing: 10) {
                    Label(time(first.sun.sunrise), systemImage: "sunrise")
                    Label(time(first.sun.sunset), systemImage: "sunset")
                }
                .foregroundStyle(AppTheme.apertureGold)
            }
            if driveTime(items) > 0 {
                Label(duration(driveTime(items)), systemImage: "car")
                    .foregroundStyle(.secondary)
                    .help("Driving time for this day")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .overlay(alignment: .bottomLeading) {
            if let startError {
                Text(startError)
                    .font(.caption)
                    .foregroundStyle(AppTheme.warningRed)
                    .padding(.leading, 240)
            }
        }
    }

    /// The day's start time as a Date in the trip's time zone, for the time picker.
    private func startTimeBinding(_ dayIndex: Int) -> Binding<Date> {
        Binding {
            dayStart(plan.days[dayIndex]).addingTimeInterval(plan.days[dayIndex].startMinute * 60)
        } set: { newValue in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.hour, .minute], from: newValue)
            plan.days[dayIndex].startMinute = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
    }

    // MARK: - Stop list

    private func stopList(_ dayIndex: Int) -> some View {
        let day = plan.days[dayIndex]
        let items = schedule(for: day)
        return List {
            Section("Day \(dayIndex + 1)") {
                if items.isEmpty {
                    Text("No stops yet — right-click a spot under Not Scheduled to add it here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 6) {
                        if let leg = item.legFromPrevious {
                            Label("\(duration(leg.travelTime)) · \(distance(leg.distance))\(index == 0 ? " from \(day.start?.name ?? "start")" : "")", systemImage: "car")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        stopRow(index: index, item: item)
                    }
                    .padding(.vertical, 4)
                    .contextMenu { dayMenu(for: item.entry.id, currentDayIndex: dayIndex) }
                }
                .onMove { source, destination in
                    plan.days[dayIndex].stopIDs.move(fromOffsets: source, toOffset: destination)
                }

                if items.count >= 2 {
                    Button {
                        sortByBestLight(dayIndex)
                    } label: {
                        Label("Order by Best Light", systemImage: "sun.max")
                    }
                    .buttonStyle(.link)
                }
                if items.contains(where: { forecasts[forecastKey($0)] != nil }) {
                    // Required attribution for Open-Meteo's free tier (CC BY 4.0).
                    Link("Cloud forecasts: weather data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com/")!)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let day = selectedDay, dayStart(day) > Date().addingTimeInterval(Double(CloudForecastService.maximumDaysAhead) * 86_400) {
                    Text("Cloud forecasts appear within \(CloudForecastService.maximumDaysAhead) days of the date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !unscheduled.isEmpty {
                Section {
                    ForEach(unscheduled) { entry in
                        Text(entry.title?.isEmpty == false ? entry.title! : "Untitled Spot")
                            .contextMenu { dayMenu(for: entry.id, currentDayIndex: nil) }
                    }
                    Button("Add All to Day \(dayIndex + 1)") {
                        plan.days[dayIndex].stopIDs.append(contentsOf: unscheduled.map(\.id))
                    }
                    .buttonStyle(.link)
                } header: {
                    Text("Not Scheduled")
                } footer: {
                    Text("Spots in this trip that aren't on any day yet.")
                }
            }
        }
    }

    @ViewBuilder
    private func dayMenu(for entryID: UUID, currentDayIndex: Int?) -> some View {
        ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
            if index != currentDayIndex {
                Button("\(currentDayIndex == nil ? "Add" : "Move") to Day \(index + 1) (\(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())))") {
                    move(entryID, toDay: index)
                }
            }
        }
        if currentDayIndex != nil {
            Divider()
            Button("Remove from This Day") { move(entryID, toDay: nil) }
        }
    }

    private func stopRow(index: Int, item: TripScheduleItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.headline.monospacedDigit())
                .frame(width: 26, height: 26)
                .background(AppTheme.cobalt, in: Circle())
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.entry.title?.isEmpty == false ? item.entry.title! : "Untitled Spot")
                    .font(.headline)
                Text("Arrive \(time(item.arrival)) · leave \(time(item.departure))")
                    .monospacedDigit()
                statusLabel(item)
                if let bestLight = item.sun.bestLight {
                    Text("Best light \(time(bestLight))")
                        .foregroundStyle(AppTheme.apertureGold)
                } else {
                    Text("Golden hour \(time(item.sun.sunrise))–\(time(item.sun.morningGoldenEnd)) · \(time(item.sun.eveningGoldenStart))–\(time(item.sun.sunset))")
                        .foregroundStyle(AppTheme.apertureGold)
                        .help("No capture heading on this spot, so this is the general golden-hour window rather than a match to the direction you'll face.")
                }
                if let forecast = forecasts[forecastKey(item)] {
                    Label("\(forecast.total)% cloud at \(item.sun.bestLight == nil ? "golden hour" : "best light") — \(forecast.summary)", systemImage: cloudSymbol(forecast))
                        .help("Low \(forecast.low)% · mid \(forecast.mid)% · high \(forecast.high)%\(forecast.precipitationChance.map { " · \($0)% chance of rain" } ?? "")")
                }
                if !item.entry.shotList.isEmpty {
                    Text("\(item.entry.shotList.filter(\.isDone).count)/\(item.entry.shotList.count) shots done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let parking = item.entry.parkingNotes, !parking.isEmpty {
                    Label(parking, systemImage: "parkingsign")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ item: TripScheduleItem) -> some View {
        switch item.status {
        case .onTime:
            Label("On time for the light", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.shutterGreen)
        case .early(let interval):
            Label("Early — best light \(duration(interval)) after you arrive", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .late(let interval):
            Label("Arrives \(duration(interval)) after best light", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .afterSunset:
            Label("Arrives after sunset", systemImage: "moon.fill")
                .foregroundStyle(AppTheme.warningRed)
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Map

    private func routeMap(_ day: TripDayPlan) -> some View {
        let dayStops = stops(for: day)
        var points = dayStops.map(coordinate)
        if let start = day.start { points.insert(start.coordinate, at: 0) }
        return Map(position: $cameraPosition) {
            if let start = day.start {
                Annotation(start.name, coordinate: start.coordinate) {
                    Image(systemName: "house.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, AppTheme.shutterGreen)
                }
            }
            ForEach(Array(dayStops.enumerated()), id: \.element.id) { index, entry in
                Annotation(entry.title ?? "Spot", coordinate: coordinate(entry)) {
                    Text("\(index + 1)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 24, height: 24)
                        .background(AppTheme.cobalt, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .foregroundStyle(.white)
                }
            }
            ForEach(Array(zip(points, points.dropFirst()).enumerated()), id: \.offset) { _, pair in
                if let leg = legs[TripPlanLeg.key(pair.0, pair.1)] {
                    MapPolyline(leg.polyline)
                        .stroke(AppTheme.cobalt.opacity(0.85), lineWidth: 4)
                }
            }
        }
        .onChange(of: selectedDayID) { cameraPosition = .automatic }
    }

    // MARK: - Plan editing

    private func loadPlan() {
        guard let tripID else { plan = TripPlan(); return }
        if let saved = TripPlan.load(tripID: tripID), !saved.days.isEmpty {
            plan = saved
        } else {
            // First time planning this trip: one day, today, holding the old single-day
            // order if there was one, otherwise every spot ordered by today's best light.
            let legacy = TripPlan.legacyOrder(tripID: tripID)
            let ids = legacy.isEmpty ? tripEntries.map(\.id) : legacy
            plan = TripPlan(days: [TripDayPlan(date: Date(), stopIDs: ids)])
            if legacy.isEmpty, tripEntries.count >= 2 { sortByBestLight(0) }
        }
        selectedDayID = plan.days.first?.id
    }

    private func addDay() {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: plan.days.last?.date ?? Date()) ?? Date()
        let template = plan.days.last
        let day = TripDayPlan(date: next, start: template?.start, startMinute: template?.startMinute ?? 6 * 60, minutesPerStop: template?.minutesPerStop ?? 30)
        plan.days.append(day)
        selectedDayID = day.id
    }

    /// The day's stops go back to Not Scheduled rather than disappearing.
    private func removeDay(_ id: UUID) {
        guard plan.days.count > 1 else { return }
        plan.days.removeAll { $0.id == id }
        if selectedDayID == id { selectedDayID = plan.days.first?.id }
    }

    private func move(_ entryID: UUID, toDay dayIndex: Int?) {
        for index in plan.days.indices {
            plan.days[index].stopIDs.removeAll { $0 == entryID }
        }
        if let dayIndex {
            plan.days[dayIndex].stopIDs.append(entryID)
        }
    }

    private func sortByBestLight(_ dayIndex: Int) {
        let day = plan.days[dayIndex]
        // Spots without a heading fall back to the evening golden hour, the usual default.
        let sorted = stops(for: day).sorted {
            let a = sun(for: $0, on: day), b = sun(for: $1, on: day)
            return (a.bestLight ?? a.eveningGoldenStart ?? .distantFuture) < (b.bestLight ?? b.eveningGoldenStart ?? .distantFuture)
        }
        plan.days[dayIndex].stopIDs = sorted.map(\.id)
    }

    private func fitStartToFirstLight(_ dayIndex: Int) {
        let day = plan.days[dayIndex]
        guard let first = schedule(for: day).first, let target = first.target else { return }
        let leave = target.addingTimeInterval(-15 * 60 - (first.legFromPrevious?.travelTime ?? 0))
        plan.days[dayIndex].startMinute = max(0, min(leave.timeIntervalSince(dayStart(day)) / 60, 1439))
    }

    /// Accepts a Google Maps link (with its place name) or anything the geocoder can find.
    private func resolveStart(_ dayIndex: Int) async {
        let text = startText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isResolvingStart = true
        startError = nil
        defer { isResolvingStart = false }
        if GoogleMapsLinkParser.looksLikeMapsLink(text), let place = await GoogleMapsLinkParser.resolvePlace(from: text) {
            plan.days[dayIndex].start = TripPlanStart(name: place.name ?? "Start", latitude: place.latitude, longitude: place.longitude)
        } else if let placemark = try? await CLGeocoder().geocodeAddressString(text).first, let location = placemark.location {
            plan.days[dayIndex].start = TripPlanStart(name: placemark.name ?? text, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        } else {
            startError = "Couldn't find that place — try a full address or a Google Maps link."
            return
        }
        startText = ""
    }

    // MARK: - Lookups

    private func refreshSunDays() {
        var result: [String: TripPlanSunDay] = [:]
        for day in plan.days {
            for entry in tripEntries {
                result[sunKey(entry, day)] = TripPlanSunDay(latitude: entry.latitude, longitude: entry.longitude, day: day.date, timeZone: timeZone, headingDegrees: entry.headingDegrees)
            }
        }
        sunDays = result
    }

    private func lookUpTimeZone() async {
        guard let first = tripEntries.first else { return }
        let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
        if let zone = try? await CLGeocoder().reverseGeocodeLocation(location).first?.timeZone {
            timeZone = zone
        }
    }

    /// Sequential rather than concurrent — MKDirections throttles apps that fire off
    /// a burst of requests. Legs already calculated for the same pair are reused.
    private func calculateLegs() async {
        for (from, to) in legPairs {
            let key = TripPlanLeg.key(from, to)
            guard legs[key] == nil else { continue }
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
            request.transportType = .automobile
            guard let route = try? await MKDirections(request: request).calculate().routes.first else { continue }
            if Task.isCancelled { return }
            legs[key] = TripPlanLeg(travelTime: route.expectedTravelTime, distance: route.distance, polyline: route.polyline)
        }
    }

    private func cloudSymbol(_ forecast: CloudForecast) -> String {
        if let rain = forecast.precipitationChance, rain >= 50 { return "cloud.rain" }
        if forecast.total >= 90 { return "cloud.fill" }
        if forecast.total <= 20 { return "sun.max" }
        return "cloud.sun"
    }

    /// Sequential and cached per ~1 km/hour in CloudForecastService, so reordering stops
    /// doesn't refetch.
    private func loadForecasts() async {
        guard let day = selectedDay else { return }
        for item in schedule(for: day) {
            let key = forecastKey(item)
            guard forecasts[key] == nil else { continue }
            if let forecast = await CloudForecastService.forecast(latitude: item.entry.latitude, longitude: item.entry.longitude, at: item.target ?? item.arrival) {
                if Task.isCancelled { return }
                forecasts[key] = forecast
            }
        }
    }

    // MARK: - Formatting

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    private func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(max(interval, 60)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func distance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }

    // MARK: - Shot sheet

    private func export(days: [TripDayPlan]) {
        guard let data = shotSheetPDF(days: days) else { return }
        let dateSuffix = days.count == 1 ? " \(days[0].date.formatted(.iso8601.year().month().day()))" : ""
        exportFilename = "\(trip?.name ?? "Trip")\(dateSuffix)"
        exportDocument = TripShotSheetDocument(data: data)
        isExportingPDF = true
    }

    /// Paginated US Letter PDF. Each day starts on a new page; each stop is rendered as
    /// its own block and moved to the next page rather than split across a break.
    private func shotSheetPDF(days: [TripDayPlan]) -> Data? {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 36
        let contentWidth = pageSize.width - margin * 2

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for day in days {
            let dayNumber = (plan.days.firstIndex { $0.id == day.id } ?? 0) + 1
            let items = schedule(for: day)
            var blocks: [AnyView] = [AnyView(shotSheetHeader(day: day, number: dayNumber, items: items).frame(width: contentWidth, alignment: .leading))]
            for (index, item) in items.enumerated() {
                blocks.append(AnyView(shotSheetStop(index: index, item: item, isFirst: index == 0, start: day.start).frame(width: contentWidth, alignment: .leading)))
            }

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
        }
        context.closePDF()
        return data as Data
    }

    private func shotSheetHeader(day: TripDayPlan, number: Int, items: [TripScheduleItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(trip?.name ?? "Trip") — Day \(number)")
                .font(.system(size: 22, weight: .bold))
            Text(day.date.formatted(date: .complete, time: .omitted))
                .font(.system(size: 13))
            if let first = items.first {
                let leave = dayStart(day).addingTimeInterval(day.startMinute * 60)
                Text([
                    day.start.map { "Leave \($0.name) at \(time(leave))" } ?? "First stop at \(time(leave))",
                    "Sunrise \(time(first.sun.sunrise)) · Sunset \(time(first.sun.sunset))",
                    driveTime(items) > 0 ? "\(duration(driveTime(items))) driving" : nil,
                    timeZone == .current ? nil : "times in \(timeZone.identifier)"
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11))
            }
            Rectangle().frame(height: 1).padding(.top, 6)
        }
        .foregroundStyle(.black)
    }

    private func shotSheetStop(index: Int, item: TripScheduleItem, isFirst: Bool, start: TripPlanStart?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let leg = item.legFromPrevious {
                Text("↓ \(duration(leg.travelTime)) drive · \(distance(leg.distance))\(isFirst ? " from \(start?.name ?? "start")" : "")")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
            Text("\(index + 1). \(item.entry.title?.isEmpty == false ? item.entry.title! : "Untitled Spot")")
                .font(.system(size: 15, weight: .semibold))
            Text("Arrive \(time(item.arrival)) · leave \(time(item.departure)) · \(String(format: "%.5f, %.5f", item.entry.latitude, item.entry.longitude))")
                .font(.system(size: 10).monospaced())
            if let bestLight = item.sun.bestLight {
                Text("Best light \(time(bestLight))\(item.entry.headingDegrees.map { String(format: " facing %.0f°", $0) } ?? "")\(shotSheetWarning(item))")
                    .font(.system(size: 11, weight: .medium))
            } else {
                Text("Golden hour \(time(item.sun.sunrise))–\(time(item.sun.morningGoldenEnd)) · \(time(item.sun.eveningGoldenStart))–\(time(item.sun.sunset))\(shotSheetWarning(item))")
                    .font(.system(size: 11, weight: .medium))
            }
            if let forecast = forecasts[forecastKey(item)] {
                Text("Forecast: \(forecast.total)% cloud (low \(forecast.low)%, high \(forecast.high)%) — \(forecast.summary)")
                    .font(.system(size: 11))
            }
            if let note = item.entry.note, !note.isEmpty {
                Text(note).font(.system(size: 11))
            }
            if let parking = item.entry.parkingNotes, !parking.isEmpty {
                Text("Parking: \(parking)").font(.system(size: 11))
            }
            ForEach(item.entry.shotList) { shot in
                Text("\(shot.isDone ? "☑" : "☐")  \(shot.text)")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(.black)
    }

    private func shotSheetWarning(_ item: TripScheduleItem) -> String {
        switch item.status {
        case .late(let interval): return " — ⚠︎ arrives \(duration(interval)) late"
        case .afterSunset: return " — ⚠︎ arrives after sunset"
        default: return ""
        }
    }

    private func printShotSheet(days: [TripDayPlan]) {
        guard let data = shotSheetPDF(days: days), let document = PDFDocument(data: data) else { return }
        document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleNone, autoRotate: false)?
            .runModal(for: NSApp.keyWindow ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
    }
}
