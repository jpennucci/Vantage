#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
/// The plan is stored on the trip (`TripModel.plan`), so it syncs to the iPhone.
struct TripPlannerView: View {
    static let windowID = "trip-planner"

    @Binding var tripID: UUID?

    @Query(sort: \TripModel.createdDate, order: .reverse) private var trips: [TripModel]
    @Query private var allEntries: [LocationEntryModel]
    @Environment(\.modelContext) private var modelContext

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
    @State private var mode: Mode = ScreenshotScreen.is("plan-route") || ScreenshotScreen.is("finds-plan") ? .route : ScreenshotScreen.is("plan-packing") ? .packing : .itinerary
    @State private var showingNewTrip = false
    @State private var showingWizard = false
    @State private var confirmingBuild = false
    @State private var isBuilding = false
    @State private var buildMessage: String?
    @State private var newTripName = ""
    @State private var isLocating = false
    /// Last pointer position over the day map — contextMenu doesn't say where the
    /// right-click landed (same approach as the main map's "Add Spot Here").
    @State private var mapHoverPoint: CGPoint?
    /// Unscheduled spots ticked for adding to a day together.
    @State private var selectedUnscheduled: Set<UUID> = []
    @State private var detailEntry: LocationEntryModel?

    enum Mode: String, CaseIterable {
        case itinerary = "Itinerary"
        case route = "Along the Route"
        case packing = "Packing"
    }

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
        TripScheduler.schedule(for: day, stops: stops(for: day), legs: legs, timeZone: timeZone) { entry, offset in
            offset == 0
                ? sun(for: entry, on: day)
                : TripPlanSunDay(latitude: entry.latitude, longitude: entry.longitude, day: TripScheduler.date(day, plus: offset), timeZone: timeZone, headingDegrees: entry.headingDegrees)
        }
    }

    private func driveTime(_ items: [TripScheduleItem]) -> TimeInterval {
        items.compactMap { $0.legFromPrevious?.travelTime }.reduce(0, +)
    }

    private func routeURL(for day: TripDayPlan) -> URL? {
        TripScheduler.routeURL(for: day, stops: stops(for: day))
    }

    /// Everything that should trigger recomputing sun times.
    private var sunCacheKey: String {
        let days = plan.days.map { $0.date.formatted(.iso8601.year().month().day()) }.joined(separator: ",")
        let ids = tripEntries.map(\.id.uuidString).sorted().joined()
        return "\(days)|\(timeZone.identifier)|\(ids)"
    }

    /// Every leg the plan needs, in order — recalculated when stops or starts change.
    private var legPairs: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] {
        plan.days.flatMap { TripScheduler.legPairs(for: $0, stops: stops(for: $0)) }
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
            fitsWidth { header }
            Divider()
            if trip == nil {
                ContentUnavailableView("Choose a Trip", systemImage: "signpost.right.and.left", description: Text("Pick a trip above to plan it."))
            } else if mode == .route, let trip {
                RouteFinderView(trip: trip)
            } else if mode == .packing, let trip {
                PackingListView(trip: trip)
            } else if let dayIndex = selectedDayIndex {
                dayBar
                Divider()
                fitsWidth { daySettings(dayIndex) }
                Divider()
                #if os(macOS)
                HSplitView {
                    stopList(dayIndex)
                        .frame(minWidth: 420, idealWidth: 500)
                    routeMap(dayIndex)
                        .frame(minWidth: 320)
                }
                #else
                // iPad: list and map side by side in landscape, stacked in portrait.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        stopList(dayIndex)
                            .frame(minWidth: 420, maxWidth: 520)
                        Divider()
                        routeMap(dayIndex)
                            .frame(minWidth: 380)
                    }
                    VStack(spacing: 0) {
                        routeMap(dayIndex)
                            .frame(height: 320)
                        Divider()
                        stopList(dayIndex)
                    }
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 560)
        #endif
        .navigationTitle(trip.map { "Plan: \($0.name)" } ?? "Trip Planner")
        .onAppear(perform: loadPlan)
        .onChange(of: tripID) {
            legs = [:]
            loadPlan()
        }
        .onChange(of: plan) {
            // Saved on the trip, so it syncs to the iPhone's itinerary.
            if let trip, trip.plan != plan { trip.plan = plan }
        }
        .onChange(of: trip?.planData) {
            // Edited on another device while this window was open.
            if let synced = trip?.plan, synced != plan, !synced.days.isEmpty {
                plan = synced
                if !plan.days.contains(where: { $0.id == selectedDayID }) { selectedDayID = plan.days.first?.id }
            }
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
        .sheet(item: $detailEntry) { entry in
            EntryDetailView(entry: entry)
                #if os(macOS)
                .frame(minWidth: 520, minHeight: 640)
                #endif
        }
        .sheet(isPresented: $showingWizard) {
            TripWizardView { newTrip, summary in
                tripID = newTrip.id
                loadPlan()
                mode = newTrip.plan?.settings?.style == .planStops && !newTrip.route.interests.isEmpty ? .route : .itinerary
                buildMessage = summary
            }
        }
        .confirmationDialog("Build the itinerary?", isPresented: $confirmingBuild, titleVisibility: .visible) {
            Button("Build Itinerary") { Task { await buildItinerary() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            let settings = plan.settings ?? TripSettings()
            Text("This replaces the current days with a fresh draft: \(settings.style.title.lowercased()), up to \(Int(settings.maxDriveHours)) hours of driving a day, stops in route order. Spots that don't fit go to Not Scheduled.")
        }
        .alert("Build Itinerary", isPresented: Binding(get: { buildMessage != nil }, set: { if !$0 { buildMessage = nil } })) {
            Button("OK") { buildMessage = nil }
        } message: {
            Text(buildMessage ?? "")
        }
        .alert("New Trip", isPresented: $showingNewTrip) {
            TextField("Trip name", text: $newTripName)
            Button("Create") {
                let name = newTripName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let trip = TripModel(name: name)
                modelContext.insert(trip)
                try? modelContext.save()
                tripID = trip.id
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add spots to it from the main window, the map, or Along the Route.")
        }
        .fileExporter(isPresented: $isExportingPDF, document: exportDocument, contentType: .pdf, defaultFilename: exportFilename) { _ in
            exportDocument = nil
        }
    }

    /// Toolbar rows are wider than an iPad in portrait; there they scroll sideways
    /// rather than squeeze. (The Mac window has a minimum width instead.)
    @ViewBuilder
    private func fitsWidth<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(macOS)
        content()
        #else
        ScrollView(.horizontal, showsIndicators: false) {
            content()
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            // A Menu labelled from `trip` — the same value the title and page use —
            // rather than a Picker: the macOS pop-up Picker kept showing a previous
            // trip when tripID changed from outside it (e.g. Plan Trip Day reusing
            // the window), so the dropdown and the page disagreed.
            Text("Trip")
            Menu {
                ForEach(trips) { item in
                    Button {
                        tripID = item.id
                    } label: {
                        if item.id == tripID {
                            Label(item.name, systemImage: "checkmark")
                        } else {
                            Text(item.name)
                        }
                    }
                }
            } label: {
                Text(trip?.name ?? "Choose a Trip…")
                    .lineLimit(1)
            }
            .frame(maxWidth: 260)

            Menu {
                Button("New Trip…") { showingWizard = true }
                Button("Blank Trip…") {
                    newTripName = ""
                    showingNewTrip = true
                }
            } label: {
                Image(systemName: "plus")
            }
            .fixedSize()
            .help("New trip — the wizard asks where, when, and how you're traveling")

            Picker("View", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if timeZone != .current, mode == .itinerary {
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

            if mode == .itinerary, trip != nil {
                Button {
                    if trip?.route.hasEnds == true {
                        confirmingBuild = true
                    } else {
                        buildMessage = "Set where the trip starts and ends first — in Along the Route, or with New Trip…."
                    }
                } label: {
                    Label(isBuilding ? "Building…" : "Build Itinerary", systemImage: "wand.and.stars")
                }
                .disabled(isBuilding)
                .help("Draft the days from the route and this trip's spots, up to your daily driving limit")
            }

            if mode == .itinerary, let day = selectedDay, let url = routeURL(for: day) {
                Link(destination: url) {
                    Label("Open Route", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
                }
                .help("Open this day's stops, in order, as a Google Maps route")
            }

            if mode == .itinerary {
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
        return HStack(alignment: .center, spacing: 16) {
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
                    Button {
                        Task { await useCurrentLocation(dayIndex) }
                    } label: {
                        Image(systemName: "location")
                    }
                    .help("Start from your current location")
                    .disabled(isLocating)
                    if isResolvingStart || isLocating { ProgressView().controlSize(.small) }
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
                if items.isEmpty, plan.settings.map({ $0.style != .planStops }) == true {
                    Text("A driving day — no sightseeing stops planned.")
                        .foregroundStyle(.secondary)
                } else if items.isEmpty {
                    Text(unscheduled.isEmpty
                         ? "No stops yet — right-click the map to add one, move spots into this trip from the main window, or find some with Along the Route."
                         : "No stops yet — right-click the map to add one, or right-click a spot under Not Scheduled.")
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

                if let options = day.overnightOptions, !options.isEmpty {
                    overnightRow(options)
                }

                if items.count >= 2 {
                    Button {
                        sortByBestLight(dayIndex)
                    } label: {
                        Label("Order by Best Light", systemImage: "sun.max")
                    }
                    .linkButtonStyle()
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
                        unscheduledRow(entry)
                            .contextMenu {
                                Button("Show Details…") { detailEntry = entry }
                                Button("Show on Map") { showOnMap(entry) }
                                Divider()
                                dayMenu(for: entry.id, currentDayIndex: nil)
                                Divider()
                                Button("Delete Spot", role: .destructive) {
                                    selectedUnscheduled.remove(entry.id)
                                    modelContext.delete(entry)
                                }
                            }
                    }
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
                                Button("Day \(index + 1) (\(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())))") {
                                    addSelected(toDay: index)
                                }
                            }
                        } label: {
                            Text(selectedUnscheduledCount == 0 ? "Add Selected" : "Add \(selectedUnscheduledCount) Selected")
                        } primaryAction: {
                            addSelected(toDay: dayIndex)
                        }
                        .fixedSize()
                        .disabled(selectedUnscheduledCount == 0)
                        .help("Adds to Day \(dayIndex + 1); click the arrow to pick another day")
                        Button(selectedUnscheduledCount == unscheduled.count ? "Select None" : "Select All") {
                            selectedUnscheduled = selectedUnscheduledCount == unscheduled.count ? [] : Set(unscheduled.map(\.id))
                        }
                        .linkButtonStyle()
                    }
                } header: {
                    Text("Not Scheduled")
                } footer: {
                    Text("Spots in this trip that aren't on any day yet. Click to select, ⓘ or right-click for details. They're the gold pins on the map.")
                }
            }
        }
    }

    private func unscheduledRow(_ entry: LocationEntryModel) -> some View {
        let isSelected = selectedUnscheduled.contains(entry.id)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? AppTheme.cobalt : .secondary)
            if let photo = entry.previewPhoto, let thumbnail = PhotoThumbnailCache.thumbnail(for: photo, maxPixelSize: 160) {
                thumbnail
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title?.isEmpty == false ? entry.title! : "Untitled Spot")
                        .font(.headline)
                    if entry.tags.contains(SpotImportService.unverifiedTag) {
                        Label("Unverified", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                if let summary = noteSummary(entry) {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                let tags = entry.tags.filter { !["imported", "planned", RouteFinderService.alongRouteTag, SpotImportService.unverifiedTag].contains($0) }
                if !tags.isEmpty {
                    Text(tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.cobaltLight)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                detailEntry = entry
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Show details — photos, the full note, source link, Look Around")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { toggleSelection(entry.id) }
    }

    /// The first paragraph of the note — for AI finds, the "why it's worth stopping"
    /// line, without the Source/Photo credit lines added on import.
    private func noteSummary(_ entry: LocationEntryModel) -> String? {
        guard let note = entry.note else { return nil }
        let first = note.components(separatedBy: "\n\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return first.isEmpty || first.hasPrefix("Source:") || first.hasPrefix("Photo:") ? nil : first
    }

    /// Only spots still unscheduled — one scheduled or deleted elsewhere drops out.
    private var selectedUnscheduledCount: Int {
        unscheduled.filter { selectedUnscheduled.contains($0.id) }.count
    }

    private func toggleSelection(_ id: UUID) {
        if selectedUnscheduled.contains(id) { selectedUnscheduled.remove(id) } else { selectedUnscheduled.insert(id) }
    }

    /// Keeps the list's order, not the order they were clicked.
    private func addSelected(toDay dayIndex: Int) {
        let ids = unscheduled.map(\.id).filter { selectedUnscheduled.contains($0) }
        plan.days[dayIndex].stopIDs.append(contentsOf: ids)
        selectedUnscheduled.subtract(ids)
    }

    private func showOnMap(_ entry: LocationEntryModel) {
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: coordinate(entry), latitudinalMeters: 4000, longitudinalMeters: 4000))
        }
    }

    private func overnightRow(_ options: [TripPlanStart]) -> some View {
        Label {
            if options.count == 1 {
                Text("End of day: \(options[0].name)")
            } else {
                Text("Places to stop for the night: \(options.map(\.name).joined(separator: " · "))")
            }
        } icon: {
            Image(systemName: "bed.double")
        }
        .foregroundStyle(AppTheme.cobaltLight)
    }

    private func buildItinerary() async {
        guard let trip else { return }
        isBuilding = true
        defer { isBuilding = false }
        var settings = plan.settings ?? TripSettings()
        if let first = plan.days.first {
            settings.startDate = first.date
            settings.firstDayStartMinute = first.startMinute
            settings.minutesPerStop = first.minutesPerStop
        }
        guard let result = await ItineraryBuilder.build(trip: trip, entries: tripEntries, settings: settings) else {
            buildMessage = "Couldn't work out a driving route between the trip's start and end."
            return
        }
        legs = [:]
        plan = result.plan
        selectedDayID = plan.days.first?.id
        buildMessage = result.summary
    }

    @ViewBuilder
    private func dayMenu(for entryID: UUID, currentDayIndex: Int?) -> some View {
        if currentDayIndex != nil, let entry = tripEntries.first(where: { $0.id == entryID }) {
            Button("Show Details…") { detailEntry = entry }
            Button("Show on Map") { showOnMap(entry) }
            Divider()
        }
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
                Text("Arrive \(arrivalText(item)) · leave \(time(item.departure))")
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
        case .beforeSunrise(let wait):
            Label("Before sunrise — sun's up at \(time(item.sun.sunrise)), \(duration(wait)) after you arrive", systemImage: "sunrise")
                .foregroundStyle(AppTheme.apertureGold)
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

    private func routeMap(_ dayIndex: Int) -> some View {
        let day = plan.days[dayIndex]
        let dayStops = stops(for: day)
        var points = dayStops.map(coordinate)
        if let start = day.start { points.insert(start.coordinate, at: 0) }
        return MapReader { proxy in
        Map(position: $cameraPosition) {
            if let start = day.start {
                Annotation(start.name, coordinate: start.coordinate) {
                    Image(systemName: "house.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, AppTheme.shutterGreen)
                }
            }
            ForEach(unscheduled) { entry in
                let isSelected = selectedUnscheduled.contains(entry.id)
                Annotation(entry.title ?? "Spot", coordinate: coordinate(entry)) {
                    Circle()
                        .fill(isSelected ? AppTheme.cobalt : AppTheme.apertureGold)
                        .frame(width: isSelected ? 18 : 14, height: isSelected ? 18 : 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            }
                        }
                        .onTapGesture { toggleSelection(entry.id) }
                        .help("\(entry.title ?? "Spot") — not scheduled yet. Click to select.")
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
        .onContinuousHover { phase in
            if case .active(let point) = phase { mapHoverPoint = point }
        }
        .contextMenu {
            Button {
                if let point = mapHoverPoint, let coordinate = proxy.convert(point, from: .local) {
                    addStop(at: coordinate, toDay: dayIndex)
                }
            } label: {
                Label("Add Stop Here", systemImage: "mappin.and.ellipse")
            }
            Button {
                if let point = mapHoverPoint, let coordinate = proxy.convert(point, from: .local) {
                    Task { await setStart(at: coordinate, dayIndex: dayIndex) }
                }
            } label: {
                Label("Start the Day Here", systemImage: "house")
            }
        }
        }
    }

    /// A new spot in this trip, added to the end of the day — named after the nearest
    /// town and given a picture (Look Around or satellite) so it isn't a blank pin.
    private func addStop(at coordinate: CLLocationCoordinate2D, toDay dayIndex: Int) {
        // Same defaults as a spot added from the map or Add Location ("planned").
        let entry = LocationEntryModel(latitude: coordinate.latitude, longitude: coordinate.longitude, tripID: tripID)
        entry.tags.append("planned")
        modelContext.insert(entry)
        plan.days[dayIndex].stopIDs.append(entry.id)
        try? modelContext.save()
        Task { @MainActor in
            if let town = await RouteFinderService.placeName(near: coordinate) {
                entry.title = "Stop near \(town)"
            }
            await SpotPictureService.addPicture(to: entry, imageURL: nil, in: modelContext)
        }
    }

    private func setStart(at coordinate: CLLocationCoordinate2D, dayIndex: Int) async {
        let town = await RouteFinderService.placeName(near: coordinate)
        plan.days[dayIndex].start = TripPlanStart(name: town ?? "Start", latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func useCurrentLocation(_ dayIndex: Int) async {
        isLocating = true
        startError = nil
        defer { isLocating = false }
        if let place = await CurrentLocation.place() {
            plan.days[dayIndex].start = place
        } else {
            startError = "Couldn't get your location — check that Location Services is on for Photo Point in System Settings → Privacy & Security."
        }
    }

    // MARK: - Plan editing

    private func loadPlan() {
        guard let trip else { plan = TripPlan(); return }
        if let saved = trip.plan, !saved.days.isEmpty {
            plan = saved
        } else {
            // First time planning this trip: one day, today, with every spot ordered
            // by today's best light.
            plan = TripPlan(days: [TripDayPlan(date: Date(), stopIDs: tripEntries.map(\.id))])
            if tripEntries.count >= 2 { sortByBestLight(0) }
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

    private func calculateLegs() async {
        await TripScheduler.calculateLegs(legPairs, skipping: legs) { legs[$0] = $1 }
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

    /// "6:06 AM", or "Fri 6:06 AM (+1 day)" when a long drive runs past midnight —
    /// without the day, a next-morning arrival looked like it was on the plan day.
    private func arrivalText(_ item: TripScheduleItem) -> String {
        guard item.dayOffset > 0 else { return time(item.arrival) }
        let weekday = item.arrival.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))
        return "\(weekday) \(time(item.arrival)) (+\(item.dayOffset) day\(item.dayOffset == 1 ? "" : "s"))"
    }

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
            Text("Arrive \(arrivalText(item)) · leave \(time(item.departure)) · \(String(format: "%.5f, %.5f", item.entry.latitude, item.entry.longitude))")
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
        #if os(macOS)
        document.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleNone, autoRotate: false)?
            .runModal(for: NSApp.keyWindow ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
        #else
        _ = document
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = trip?.name ?? "Shot Sheet"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = data
        controller.present(animated: true)
        #endif
    }
}

private extension View {
    /// Text-link buttons on the Mac; the nearest equivalent on iPad.
    @ViewBuilder
    func linkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }
}
