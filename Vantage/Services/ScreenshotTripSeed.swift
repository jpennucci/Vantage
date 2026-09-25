import CoreLocation
import Foundation
import SwiftData

/// Screenshot-mode demo trip: historic Route 66 from Chicago to St. Louis, with real
/// stops along the old road, a route, a built itinerary, a packing list, and pictures
/// (Look Around / satellite, fetched live) — so the trip-planning screens look like a
/// real trip in App Store screenshots. Only runs with VANTAGE_SCREENSHOT_MODE=1, into
/// the in-memory demo store (see VantageModelContainer).
enum ScreenshotTripSeed {
    static let tripName = "Route 66: Chicago to St. Louis"

    @MainActor
    static func seedIfNeeded(context: ModelContext) async {
        guard ScreenshotSeedData.isScreenshotMode else { return }
        // Only the trip-planning screenshots need it; the list/map/detail ones look
        // best with just the original photogenic demo spots.
        let tripScreens = ["trip-", "finds-", "plan", "sun", "wizard"]
        guard let screen = ScreenshotScreen.current, tripScreens.contains(where: { screen.hasPrefix($0) }) else { return }
        if let trips = try? context.fetch(FetchDescriptor<TripModel>()), trips.contains(where: { $0.name == tripName }) { return }

        let trip = TripModel(name: tripName)
        context.insert(trip)

        let stops: [(String, Double, Double, Double?, String, [String], [String])] = [
            ("Gemini Giant", 41.30435, -88.14656, 250, "A 28-foot fiberglass astronaut guarding the old Launching Pad drive-in. Best with the sun low behind you in the evening.", ["roadside giant", "Muffler Man"], ["Wide-angle lens"]),
            ("Ambler's Texaco, Dwight", 41.09304, -88.42866, 260, "A 1933 cottage-style gas station, the longest-operating on Route 66. Glows at dusk when the pumps are lit.", ["historic gas station"], []),
            ("Route 66 Murals, Pontiac", 40.88073, -88.62980, nil, "Dozens of hand-painted murals around the old courthouse square, plus the Route 66 Hall of Fame museum.", ["murals", "folk art"], []),
            ("Funks Grove Maple Sirup", 40.35932, -89.11949, nil, "A family maple farm on the old road since 1824, with a hand-painted \"sirup\" sign that's a classic stop.", ["roadside stop", "vintage sign"], []),
            ("Cozy Dog Drive In, Springfield", 39.76623, -89.66436, nil, "Birthplace of the corn dog on a stick, packed with Route 66 memorabilia.", ["classic diner"], []),
            ("Soulsby's Shell Station, Mount Olive", 39.07260, -89.72731, 270, "A tiny 1926 Shell station with vintage pumps — one of the oldest on the route.", ["historic gas station"], []),
            ("Old Chain of Rocks Bridge", 38.76040, -90.17618, 225, "A mile-long bridge with a famous 22-degree bend over the Mississippi, now walk-only. Sunset over the river.", ["bridge", "sunset"], ["Tripod", "Drone"])
        ]
        var entries: [LocationEntryModel] = []
        for (title, lat, lng, heading, note, tags, gear) in stops {
            let entry = LocationEntryModel(latitude: lat, longitude: lng, headingDegrees: heading, title: title, note: note, tags: tags + [RouteFinderService.alongRouteTag], tripID: trip.id)
            entry.gearNeeded = gear
            context.insert(entry)
            entries.append(entry)
        }

        var route = TripRoute()
        route.start = TripPlanStart(name: "Chicago, IL", latitude: 41.8781, longitude: -87.6298)
        route.end = TripPlanStart(name: "St. Louis, MO", latitude: 38.6270, longitude: -90.1994)
        route.guidance = "Stay on historic Route 66"
        route.interests = ["Roadside oddities", "Vintage neon signs", "Historic gas stations & motels", "Classic diners"]
        route.segmentMiles = 100
        route.completedSegments = [1, 2, 3]
        trip.route = route

        var settings = TripSettings()
        settings.style = .planStops
        settings.maxDriveHours = 3
        settings.light = .sunset
        settings.startDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        settings.firstDayStartMinute = 8 * 60
        settings.dailyStartMinute = 8 * 60
        settings.minutesPerStop = 40
        trip.plan = TripPlan(days: [TripDayPlan(date: settings.startDate, start: route.start)], settings: settings)
        if let result = await ItineraryBuilder.build(trip: trip, entries: entries, settings: settings) {
            trip.plan = result.plan
        }

        StarterGear.add(to: context)
        trip.packingList = [
            PackingItem(name: "Camera body", category: GearCategory.camera.rawValue, isPacked: true),
            PackingItem(name: "Wide-angle lens", category: GearCategory.lenses.rawValue, isPacked: true),
            PackingItem(name: "Telephoto lens", category: GearCategory.lenses.rawValue),
            PackingItem(name: "Tripod", category: GearCategory.support.rawValue, isPacked: true),
            PackingItem(name: "Drone", category: GearCategory.drone.rawValue),
            PackingItem(name: "Spare batteries", category: GearCategory.power.rawValue, quantity: 4, isPacked: true),
            PackingItem(name: "Memory cards", category: GearCategory.power.rawValue, quantity: 3),
            PackingItem(name: "Water", category: GearCategory.personal.rawValue, isPacked: true),
            PackingItem(name: "Snacks", category: GearCategory.personal.rawValue),
            PackingItem(name: "Rain jacket", category: GearCategory.clothing.rawValue)
        ]
        try? context.save()

        for entry in entries {
            await SpotPictureService.addPicture(to: entry, imageURL: nil, in: context)
        }
    }
}
