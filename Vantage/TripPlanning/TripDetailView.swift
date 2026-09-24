import MapKit
import SwiftData
import SwiftUI

/// A trip's planning hub on the iPhone: the day-by-day itinerary (planned in detail on
/// the Mac, synced here for the road), the route finder, and the packing list.
struct TripDetailView: View {
    @Bindable var trip: TripModel
    @State private var tab: Tab = .itinerary

    enum Tab: String, CaseIterable {
        case itinerary = "Itinerary"
        case route = "Along the Route"
        case packing = "Packing"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch tab {
            case .itinerary: TripItineraryView(trip: trip)
            case .route: RouteFinderView(trip: trip)
            case .packing: PackingListView(trip: trip)
            }
        }
        .navigationTitle(trip.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The synced day-by-day plan, for use on the road: each day's stops in order with
/// arrival times against the light, directions, and the leaving-a-stop gear check.
/// Stops can be reordered here; start points, times, and adding days are easiest in
/// the Mac's Trip Planner (and are kept if you plan there later).
struct TripItineraryView: View {
    @Bindable var trip: TripModel

    @Query private var allEntries: [LocationEntryModel]
    @State private var plan = TripPlan()
    @State private var selectedDayID: UUID?
    @State private var legs: [String: TripPlanLeg] = [:]
    @State private var timeZone: TimeZone = .current
    @State private var openEntry: LocationEntryModel?
    @State private var leavingEntry: LocationEntryModel?
    @Environment(\.openURL) private var openURL

    private var tripEntries: [LocationEntryModel] {
        allEntries.filter { $0.tripID == trip.id }
    }

    private var selectedDayIndex: Int? {
        plan.days.firstIndex { $0.id == selectedDayID } ?? (plan.days.isEmpty ? nil : 0)
    }

    private func stops(_ day: TripDayPlan) -> [LocationEntryModel] {
        TripScheduler.stops(for: day, in: tripEntries)
    }

    private func schedule(_ day: TripDayPlan) -> [TripScheduleItem] {
        TripScheduler.schedule(for: day, stops: stops(day), legs: legs, timeZone: timeZone) { entry in
            TripPlanSunDay(latitude: entry.latitude, longitude: entry.longitude, day: day.date, timeZone: timeZone, headingDegrees: entry.headingDegrees)
        }
    }

    private var legPairs: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] {
        plan.days.flatMap { TripScheduler.legPairs(for: $0, stops: stops($0)) }
    }

    var body: some View {
        Group {
            if plan.days.isEmpty {
                ContentUnavailableView {
                    Label("No Itinerary Yet", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Plan days, start points, and times in the Trip Planner on your Mac — it syncs here. Or start a simple one-day plan now.")
                } actions: {
                    Button("Start a One-Day Plan") {
                        plan = TripPlan(days: [TripDayPlan(date: Date(), stopIDs: tripEntries.map(\.id))])
                        selectedDayID = plan.days.first?.id
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tripEntries.isEmpty)
                }
            } else if let dayIndex = selectedDayIndex {
                List {
                    if plan.days.count > 1 {
                        Picker("Day", selection: Binding(get: { plan.days[dayIndex].id }, set: { selectedDayID = $0 })) {
                            ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
                                Text("Day \(index + 1) · \(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))").tag(day.id)
                            }
                        }
                    }
                    dayHeader(plan.days[dayIndex])
                    Section {
                        ForEach(Array(schedule(plan.days[dayIndex]).enumerated()), id: \.element.id) { index, item in
                            row(index: index, item: item)
                        }
                        .onMove { plan.days[dayIndex].stopIDs.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
                #if os(iOS)
                .toolbar { EditButton() }
                #endif
            }
        }
        .onAppear(perform: load)
        .onChange(of: plan) {
            if trip.plan != plan { trip.plan = plan }
        }
        .onChange(of: trip.planData) {
            if let synced = trip.plan, synced != plan { plan = synced }
        }
        .task(id: tripEntries.first?.id) {
            guard let first = tripEntries.first else { return }
            let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
            if let zone = try? await CLGeocoder().reverseGeocodeLocation(location).first?.timeZone {
                timeZone = zone
            }
        }
        .task(id: legPairs.map { TripPlanLeg.key($0.0, $0.1) }) {
            await TripScheduler.calculateLegs(legPairs, skipping: legs) { legs[$0] = $1 }
        }
        .sheet(item: $openEntry) { EntryDetailView(entry: $0) }
        .sheet(item: $leavingEntry) { LeaveStopChecklistView(entry: $0, trip: trip) }
    }

    private func dayHeader(_ day: TripDayPlan) -> some View {
        let items = schedule(day)
        let leave = TripPlanning.dayStart(day.date, in: timeZone).addingTimeInterval(day.startMinute * 60)
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.date.formatted(date: .complete, time: .omitted))
                    .font(.headline)
                Text(day.start.map { "Leave \($0.name) at \(time(leave))" } ?? "First stop at \(time(leave))")
                if let first = items.first {
                    Text("Sunrise \(time(first.sun.sunrise)) · Sunset \(time(first.sun.sunset))")
                        .foregroundStyle(AppTheme.apertureGold)
                }
                if timeZone != .current {
                    Text("Times in \(timeZone.localizedName(for: .shortStandard, locale: .current) ?? timeZone.identifier)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let url = TripScheduler.routeURL(for: day, stops: stops(day)) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open Day in Google Maps", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
                }
            }
        }
    }

    private func row(index: Int, item: TripScheduleItem) -> some View {
        Button {
            openEntry = item.entry
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(AppTheme.cobalt, in: Circle())
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.entry.title?.isEmpty == false ? item.entry.title! : "Untitled Spot")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let leg = item.legFromPrevious {
                        Label(duration(leg.travelTime), systemImage: "car")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Arrive \(time(item.arrival)) · \(item.sun.bestLight.map { "best light \(time($0))" } ?? "golden hour \(time(item.sun.eveningGoldenStart))")")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.primary)
                    status(item)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                leavingEntry = item.entry
            } label: {
                Label("Gear Check", systemImage: "checklist.checked")
            }
            .tint(AppTheme.shutterGreen)
        }
        .swipeActions(edge: .trailing) {
            if let url = ExternalNavigationService.googleMapsRouteURL(stops: [(latitude: item.entry.latitude, longitude: item.entry.longitude)]) {
                Button {
                    openURL(url)
                } label: {
                    Label("Directions", systemImage: "map")
                }
                .tint(AppTheme.cobalt)
            }
        }
    }

    @ViewBuilder
    private func status(_ item: TripScheduleItem) -> some View {
        switch item.status {
        case .onTime: Label("On time for the light", systemImage: "checkmark.circle.fill").foregroundStyle(AppTheme.shutterGreen)
        case .early(let interval): Label("Early — light is \(duration(interval)) later", systemImage: "clock").foregroundStyle(.secondary)
        case .late(let interval): Label("\(duration(interval)) after best light", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .afterSunset: Label("After sunset", systemImage: "moon.fill").foregroundStyle(AppTheme.warningRed)
        case .unknown: EmptyView()
        }
    }

    private func load() {
        plan = trip.plan ?? TripPlan()
        selectedDayID = plan.days.first?.id
    }

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    private func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(max(interval, 60)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
