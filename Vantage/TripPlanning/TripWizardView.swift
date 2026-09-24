import CoreLocation
import SwiftData
import SwiftUI

/// "New Trip": a few quick questions, one screen at a time, then a ready trip. Every
/// answer has a default, so a spontaneous trip ("leaving now, going there") takes a
/// few taps on the phone, while a planned one can set its dates, style, pace, light,
/// interests, and kits. The same flow on iPhone, iPad, and Mac.
///
/// Travel choices are asked per trip (TripSettings) because they change trip to trip:
/// some drives go straight there, some stop when tired, some are planned stop by stop.
struct TripWizardView: View {
    /// Called with the new trip (and, for trips drafted straight away, the summary).
    var onCreated: (TripModel, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GearItem.name) private var gear: [GearItem]
    @Query private var allTrips: [TripModel]

    private enum Step: Int, CaseIterable {
        case where_, when, style, find, pack, finish
    }

    @State private var step: Step = .where_

    // Where
    @State private var start: TripPlanStart?
    @State private var destination: TripPlanStart?
    @State private var waypoints: [TripPlanStart] = []
    @State private var startText = ""
    @State private var destinationText = ""
    @State private var roundTrip = false
    @State private var isLocating = false
    @State private var isResolving = false

    // When
    @State private var leaveNow = true
    @State private var leaveDate = Date()
    @State private var asLongAsItTakes = true
    @State private var dayCount = 3

    // Style
    @State private var settings = TripSettings()

    // Find
    @State private var interests: [String] = []
    @State private var newInterest = ""
    @State private var maxDetourMiles = 15.0

    // Pack
    @State private var kits: Set<String> = []

    // Finish
    @State private var name = ""
    @State private var isCreating = false
    @State private var message: String?

    private var steps: [Step] {
        Step.allCases.filter { $0 != .find || settings.style == .planStops }
    }

    private var kitNames: [String] {
        Set(gear.flatMap(\.kits)).sorted()
    }

    private var myInterests: [String] {
        var seen = Set(TripRoute.suggestedInterests.map { $0.lowercased() })
        return allTrips.flatMap { $0.route.savedInterests ?? [] }.filter { seen.insert($0.lowercased()).inserted }
    }

    private var suggestedName: String {
        func short(_ place: TripPlanStart?) -> String? {
            place?.name.replacingOccurrences(of: "Current location (", with: "").replacingOccurrences(of: ")", with: "")
        }
        guard let to = short(destination) else { return "New Trip" }
        if roundTrip { return "Round trip to \(to)" }
        return short(start).map { "\($0) → \(to)" } ?? "Trip to \(to)"
    }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .where_: whereStep
                case .when: whenStep
                case .style: styleStep
                case .find: findStep
                case .pack: packStep
                case .finish: finishStep
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == .finish {
                        Button("Create Trip") { Task { await create() } }
                            .disabled(isCreating || destination == nil)
                    } else {
                        Button("Next") { move(by: 1) }
                            .disabled(step == .where_ && destination == nil)
                    }
                }
                ToolbarItem(placement: .navigation) {
                    if step != .where_ {
                        Button("Back") { move(by: -1) }
                    }
                }
            }
            .alert("New Trip", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
            .task {
                if start == nil { await useCurrentLocation() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private var title: String {
        let index = (steps.firstIndex(of: step) ?? 0) + 1
        return "New Trip · \(index) of \(steps.count)"
    }

    private func move(by offset: Int) {
        guard let index = steps.firstIndex(of: step) else { return }
        let next = min(max(index + offset, 0), steps.count - 1)
        if steps[next] == .finish, name.isEmpty { name = suggestedName }
        withAnimation { step = steps[next] }
    }

    // MARK: - Steps

    @ViewBuilder
    private var whereStep: some View {
        Section {
            placeRow("From", place: start, text: $startText) { start = $0 }
            if start == nil {
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    Label(isLocating ? "Finding you…" : "Use My Current Location", systemImage: "location")
                }
                .disabled(isLocating)
            }
            placeRow("To", place: destination, text: $destinationText) { destination = $0 }
            Toggle("Round trip — come back to the start", isOn: $roundTrip)
            if !waypoints.isEmpty {
                Label("Following your Google Maps route through \(waypoints.count) point\(waypoints.count == 1 ? "" : "s")", systemImage: "point.topleft.down.curvedto.point.filled.bottomright.up")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Where to?")
        } footer: {
            Text("Type a city, an address, or a Google Maps link.")
        }
        Section {
            Button {
                Task { await pasteGoogleRoute() }
            } label: {
                Label("Paste a Google Maps Route", systemImage: "map")
            }
            .disabled(isResolving)
        } footer: {
            Text("Already built the route in Google Maps (dragged onto the roads you want)? Share → Copy Link, then paste it here.")
        }
    }

    private var whenStep: some View {
        Section {
            Toggle("Leaving now", isOn: $leaveNow)
            if !leaveNow {
                DatePicker("Leaving", selection: $leaveDate, displayedComponents: [.date, .hourAndMinute])
            }
            Toggle("As many days as it takes", isOn: $asLongAsItTakes)
            if !asLongAsItTakes {
                Stepper(dayCount == 1 ? "Just today" : "\(dayCount) days", value: $dayCount, in: 1...30)
            }
        } header: {
            Text("When?")
        } footer: {
            Text("With a set number of days, stops that don't fit are left for you to place.")
        }
    }

    @ViewBuilder
    private var styleStep: some View {
        Section("How are you traveling this time?") {
            ForEach(TripSettings.Style.allCases) { style in
                Button {
                    settings.style = style
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: style.symbol)
                            .font(.title3)
                            .frame(width: 28)
                            .foregroundStyle(settings.style == style ? AppTheme.cobalt : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.title).font(.headline).foregroundStyle(.primary)
                            Text(style.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: settings.style == style ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(settings.style == style ? AppTheme.cobalt : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        Section("Pace") {
            Stepper("Up to \(Int(settings.maxDriveHours)) hours of driving a day", value: $settings.maxDriveHours, in: 1...14)
            if settings.style == .planStops {
                Stepper("About \(Int(settings.minutesPerStop)) min at each stop", value: $settings.minutesPerStop, in: 10...180, step: 10)
            }
            Picker("Golden hour", selection: $settings.light) {
                ForEach(TripSettings.Light.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    @ViewBuilder
    private var findStep: some View {
        Section {
            FlowLayout {
                ForEach(TripRoute.suggestedInterests + myInterests, id: \.self) { interest in
                    ChipToggle(title: interest, isOn: Binding(
                        get: { interests.contains(interest) },
                        set: { isOn in
                            if isOn { interests.append(interest) } else { interests.removeAll { $0 == interest } }
                        }
                    ))
                }
            }
            .padding(.vertical, 4)
            HStack {
                TextField("Add your own", text: $newInterest)
                    .onSubmit(addInterest)
                Button("Add", action: addInterest)
                    .disabled(newInterest.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Stepper("Within \(Int(maxDetourMiles)) miles of the route", value: $maxDetourMiles, in: 1...100, step: 5)
        } header: {
            Text("What should we look for?")
        } footer: {
            Text("After the trip is created, you'll copy a ready-made prompt for each stretch of the route into an AI chat and paste the replies back — then Build Itinerary fits the finds into days. Skip this if you already have spots in mind.")
        }
    }

    private var packStep: some View {
        Section {
            if kitNames.isEmpty {
                Text("No kits yet — you can build a packing list for this trip later, or make kits in the Gear Library.")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout {
                    ForEach(kitNames, id: \.self) { kit in
                        ChipToggle(title: kit, isOn: Binding(
                            get: { kits.contains(kit) },
                            set: { if $0 { kits.insert(kit) } else { kits.remove(kit) } }
                        ))
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("What are you bringing?")
        } footer: {
            Text("Kits you pick start the trip's packing list. Optional.")
        }
    }

    @ViewBuilder
    private var finishStep: some View {
        Section("Trip name") {
            TextField("Trip name", text: $name)
        }
        Section {
            summaryRow("Route", "\(start?.name ?? "Current location") → \(destination?.name ?? "—")\(roundTrip ? " and back" : "")")
            summaryRow("Leaving", leaveNow ? "Now" : leaveDate.formatted(date: .abbreviated, time: .shortened))
            summaryRow("Length", asLongAsItTakes ? "As many days as it takes" : (dayCount == 1 ? "Just today" : "\(dayCount) days"))
            summaryRow("Style", "\(settings.style.title), up to \(Int(settings.maxDriveHours)) h a day")
            if settings.light != .none { summaryRow("Golden hour", settings.light.title) }
            if settings.style == .planStops, !interests.isEmpty { summaryRow("Looking for", interests.joined(separator: ", ")) }
            if !kits.isEmpty { summaryRow("Packing", kits.sorted().joined(separator: ", ")) }
        } footer: {
            if isCreating {
                Label("Working out your days…", systemImage: "hourglass")
            } else if settings.style == .planStops {
                Text("Next: find stops along the route, then Build Itinerary.")
            } else {
                Text("Your days are worked out as soon as you tap Create Trip.")
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }

    private func placeRow(_ label: String, place: TripPlanStart?, text: Binding<String>, set: @escaping (TripPlanStart?) -> Void) -> some View {
        HStack {
            Text(label).frame(width: 44, alignment: .leading)
            if let place {
                Label(place.name, systemImage: "mappin.circle.fill")
                    .foregroundStyle(AppTheme.cobaltLight)
                Spacer()
                Button {
                    set(nil)
                    waypoints = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            } else {
                TextField("City, address, or Google Maps link", text: text)
                    .onSubmit {
                        Task {
                            isResolving = true
                            defer { isResolving = false }
                            if let resolved = await RouteFinderService.resolvePlace(text.wrappedValue) {
                                set(resolved)
                                text.wrappedValue = ""
                            } else {
                                message = "Couldn't find “\(text.wrappedValue)” — try a city and state, an address, or a Google Maps link."
                            }
                        }
                    }
                if isResolving { ProgressView().controlSize(.small) }
            }
        }
    }

    // MARK: - Actions

    private func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        if let here = await CurrentLocation.place() {
            start = here
        }
    }

    private func pasteGoogleRoute() async {
        guard let text = pasteFromClipboard(), GoogleMapsLinkParser.looksLikeDirectionsLink(text) else {
            message = "Copy a Google Maps directions link first: get directions in Google Maps, then Share → Copy Link."
            return
        }
        isResolving = true
        defer { isResolving = false }
        guard let stops = await GoogleMapsLinkParser.resolveDirections(from: text), stops.count >= 2 else {
            message = "Couldn't read a route from that link."
            return
        }
        var places: [TripPlanStart] = []
        for stop in stops {
            var name = stop.name
            if name == nil {
                name = await RouteFinderService.placeName(near: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)).map { "Near \($0)" }
            }
            places.append(TripPlanStart(name: name ?? "Via point", latitude: stop.latitude, longitude: stop.longitude))
        }
        start = places.first
        destination = places.last
        waypoints = Array(places.dropFirst().dropLast())
    }

    private func addInterest() {
        for entry in newInterest.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !entry.isEmpty {
            if !interests.contains(entry) { interests.append(entry) }
        }
        newInterest = ""
    }

    private func create() async {
        guard let destination else { return }
        isCreating = true
        defer { isCreating = false }

        let origin = start ?? destination
        let trip = TripModel(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedName : name)
        modelContext.insert(trip)

        var route = TripRoute()
        route.start = origin
        if roundTrip {
            route.waypoints = waypoints + [destination]
            route.end = origin
        } else {
            route.waypoints = waypoints
            route.end = destination
        }
        route.interests = interests
        let known = Set((TripRoute.suggestedInterests + myInterests).map { $0.lowercased() })
        let custom = interests.filter { !known.contains($0.lowercased()) }
        if !custom.isEmpty { route.savedInterests = custom }
        route.maxDetourMiles = maxDetourMiles
        trip.route = route

        let leave = leaveNow ? Date() : leaveDate
        let calendar = Calendar.current
        let leaveParts = calendar.dateComponents([.hour, .minute], from: leave)
        settings.startDate = leave
        settings.firstDayStartMinute = Double((leaveParts.hour ?? 8) * 60 + (leaveParts.minute ?? 0))
        settings.dailyStartMinute = settings.light == .sunrise || settings.light == .both ? 6 * 60 : 8 * 60
        settings.dayLimit = asLongAsItTakes ? nil : dayCount
        trip.plan = TripPlan(
            days: [TripDayPlan(date: leave, start: origin, startMinute: settings.firstDayStartMinute, minutesPerStop: settings.minutesPerStop)],
            settings: settings
        )

        for kit in kits {
            for item in gear where item.kits.contains(kit) && !trip.packingList.contains(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
                trip.packingList.append(PackingItem(name: item.name, category: item.category))
            }
        }

        // Straight-there and stop-when-tired trips need nothing more — draft the days now.
        var summary: String?
        if settings.style != .planStops,
           let result = await ItineraryBuilder.build(trip: trip, entries: [], settings: settings) {
            trip.plan = result.plan
            summary = result.summary
        }
        try? modelContext.save()
        onCreated(trip, summary)
        dismiss()
    }
}
