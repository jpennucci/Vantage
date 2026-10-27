import MapKit
import SwiftUI

/// The routes Apple Maps offers between a pasted link's start and end. A Google
/// Maps link doesn't say which of Google's alternatives was picked, so when it has
/// no stops in between we ask for alternatives and let you choose again.
struct RouteAlternatives: Identifiable {
    let id = UUID()
    let start: TripPlanStart
    let end: TripPlanStart
    let routes: [MKRoute]

    /// nil when Apple Maps only knows one way (or none) — nothing to choose.
    @MainActor
    static func fetch(from start: TripPlanStart, to end: TripPlanStart) async -> RouteAlternatives? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
        request.transportType = .automobile
        request.requestsAlternateRoutes = true
        guard let routes = try? await MKDirections(request: request).calculate().routes, routes.count > 1 else { return nil }
        return RouteAlternatives(start: start, end: end, routes: routes.sorted { $0.expectedTravelTime < $1.expectedTravelTime })
    }

    /// The trip only stores points to route through, and every leg is recalculated as
    /// the fastest way, so a slower alternative is kept by routing through towns on it:
    /// one about every 250 miles, which keeps each leg on the chosen road.
    @MainActor
    func viaPoints(for index: Int) async -> [TripPlanStart] {
        guard index > 0 else { return [] }
        let polyline = routes[index].polyline
        var points = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&points, range: NSRange(location: 0, length: polyline.pointCount))
        guard points.count >= 2 else { return [] }

        var cumulative = [0.0]
        for (a, b) in zip(points, points.dropFirst()) {
            cumulative.append(cumulative.last! + CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)))
        }
        let total = cumulative.last!
        let count = min(6, max(1, Int(total / RouteFinderService.metersPerMile / 250)))

        var via: [TripPlanStart] = []
        for step in 1...count {
            let target = total * Double(step) / Double(count + 1)
            let index = cumulative.firstIndex { $0 >= target } ?? points.count - 1
            let point = points[index]
            let name = await RouteFinderService.placeName(near: point).map { "Near \($0)" }
            via.append(TripPlanStart(name: name ?? "Via point", latitude: point.latitude, longitude: point.longitude))
        }
        return via
    }
}

/// Pick one of the alternatives, like Google Maps' route options.
struct RouteChoiceView: View {
    let alternatives: RouteAlternatives
    let onChoose: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map {
                    ForEach(alternatives.routes.indices.reversed(), id: \.self) { index in
                        if index != selected {
                            MapPolyline(alternatives.routes[index].polyline)
                                .stroke(.gray.opacity(0.7), lineWidth: 4)
                        }
                    }
                    MapPolyline(alternatives.routes[selected].polyline)
                        .stroke(.blue, lineWidth: 6)
                    Marker(alternatives.start.name, coordinate: alternatives.start.coordinate)
                    Marker(alternatives.end.name, coordinate: alternatives.end.coordinate)
                }
                .frame(minHeight: 260)

                List(alternatives.routes.indices, id: \.self) { index in
                    Button {
                        selected = index
                    } label: {
                        row(index)
                    }
                    .foregroundStyle(.primary)
                }
                .frame(minHeight: 200)
            }
            .navigationTitle("Which Way?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Route") {
                        onChoose(selected)
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    private func row(_ index: Int) -> some View {
        let route = alternatives.routes[index]
        let miles = route.distance / RouteFinderService.metersPerMile
        return HStack(alignment: .firstTextBaseline) {
            Image(systemName: index == selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(index == selected ? Color.blue : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.duration(route.expectedTravelTime))
                    .font(.headline)
                Text(route.name.isEmpty ? "\(Int(miles).formatted()) mi" : "\(Int(miles).formatted()) mi · via \(route.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if index == 0 {
                Text("Fastest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(index == selected ? .isSelected : [])
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }
}

/// The ⓘ beside Paste Google Maps Route: how to copy a route out of Google Maps,
/// and how to keep the exact roads you picked there.
struct GoogleRouteHelpButton: View {
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("How to paste a Google Maps route")
        .sheet(isPresented: $isShowing) {
            NavigationStack {
                List {
                    Section("Copy the route") {
                        Label("In Google Maps, get directions to where you're going.", systemImage: "1.circle")
                        Label("Tap Share, then Copy Link.", systemImage: "2.circle")
                        Label("Come back here and tap Paste Google Maps Route.", systemImage: "3.circle")
                    }
                    Section {
                        Text("Google's link only holds the start, the end and any stops you added. It doesn't say which of Google's route options you picked.")
                        Text("If the link has only a start and an end, Photo Point shows the routes Apple Maps knows so you can pick one. Apple's choices can differ from Google's.")
                    } header: {
                        Text("Picking a route")
                    }
                    Section {
                        Text("Before sharing, tap Add stops in Google Maps and add a town that's only on the route you want, say one every few hundred miles. Photo Point routes through every stop in the link, so it follows the same roads.")
                        Text("A Google Maps route holds about 10 stops. For a longer trip, share it in parts and choose Add to the End of the Route for each one.")
                    } header: {
                        Text("To keep Google's exact route")
                    }
                }
                .navigationTitle("Paste a Google Maps Route")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowing = false }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 520)
            #endif
        }
    }
}
