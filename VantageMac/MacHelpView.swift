import SwiftUI

/// Help → Photo Point Help (⌘?). A plain in-app guide rather than an Apple Help Book:
/// no separate bundle to build or index, and it can't drift out of the app bundle.
/// Keep it in step with the Mac features — each topic describes what the app does now.
struct MacHelpView: View {
    static let windowID = "help"

    @State private var selection: HelpTopic.ID? = HelpTopic.all.first?.id

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.all, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.symbol)
                    .tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            if let topic = HelpTopic.all.first(where: { $0.id == selection }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(topic.title, systemImage: topic.symbol)
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(AppTheme.cobalt)
                        ForEach(topic.sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if let heading = section.heading {
                                    Text(heading).font(.title3.weight(.semibold))
                                }
                                ForEach(section.lines, id: \.self) { line in
                                    Text(LocalizedStringKey(line))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 680, alignment: .leading)
                    .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct HelpTopic: Identifiable {
    struct Section: Identifiable {
        let id = UUID()
        let heading: String?
        let lines: [String]
    }

    let id: String
    let title: String
    let symbol: String
    let sections: [Section]

    static let all: [HelpTopic] = [
        HelpTopic(id: "start", title: "Getting Started", symbol: "sparkles", sections: [
            Section(heading: nil, lines: [
                "Photo Point for Mac is the planning side of Photo Point: review the spots you saved on your iPhone or Apple Watch, add new ones from your desk, and plan the day you'll go shoot them.",
                "The **sidebar** lists your spots, newest first. Select one to see its details; select nothing to see the **map**. Search at the top of the sidebar matches names, notes, tags, and trip names."
            ]),
            Section(heading: "Everything syncs", lines: [
                "Spots, photos, and trips sync through your own iCloud account — there's no Photo Point account to create. Anything you add here shows up on your iPhone, and vice versa. See **Sync & iCloud** if something doesn't appear."
            ])
        ]),
        HelpTopic(id: "add", title: "Adding Spots", symbol: "mappin.and.ellipse", sections: [
            Section(heading: "From a Google Maps link", lines: [
                "Copy a link from Google Maps in your browser, click in the sidebar, and press **⌘V** — the spot is created with the place's name and exact location.",
                "You can also **drag a link** from your browser straight onto the sidebar or the map."
            ]),
            Section(heading: "From the map", lines: [
                "**Right-click** anywhere on the map and choose **Add Spot Here**.",
                "**Drag a photo** (a Street View screenshot, a picture from Photos or Finder) onto the map to create a new spot at that point with the photo attached."
            ]),
            Section(heading: "By address or coordinates", lines: [
                "Choose **File → New Spot…** (⌘N). Paste a Maps link (if one is on your clipboard it's filled in for you), type an address, or enter latitude and longitude."
            ]),
            Section(heading: nil, lines: [
                "Spots added on the Mac are tagged **planned** and go into your active trip, if one is set in **Trips → Manage Trips…**."
            ])
        ]),
        HelpTopic(id: "ai", title: "Import with AI", symbol: "wand.and.stars", sections: [
            Section(heading: nil, lines: [
                "Somewhere new and don't know where to look? Let any AI chat tool — Claude, ChatGPT, or others — find spots for you.",
                "1. Choose **File → Import via AI Chat…** (⇧⌘I) and click **Copy Prompt**.",
                "2. Paste it into your AI chat and add what you're looking for, e.g. *\"abandoned buildings, old gas stations, and roadside oddities near Route 66 in Arizona.\"*",
                "3. Copy the AI's reply, come back, and click **Paste & Import**.",
                "Every spot is located on the map and filed together in a new trip, named from the AI's reply."
            ]),
            Section(heading: "Find more near a trip", lines: [
                "Already have a trip somewhere? Click **Find More Spots…** in the Trip Planner — or filter the list to the trip and choose **Import → Find More Near…** — and the prompt already describes the trip's area and the spots you have, so the AI suggests new places nearby instead of repeats. What you import is added straight to that trip."
            ]),
            Section(heading: "From a file", lines: [
                "**File → Import from File…** (⌘O) imports a spots file another Photo Point user shared with you (see **Getting There & Sharing**)."
            ])
        ]),
        HelpTopic(id: "photos", title: "Photos", symbol: "photo.on.rectangle", sections: [
            Section(heading: nil, lines: [
                "**Drag a photo onto a spot** in the sidebar — or onto its details — to attach it as a reference photo: what you want the shot to look like.",
                "Photos taken on your iPhone and reference photos both sync to the Mac. Large photos can take a little longer to arrive than the spot itself."
            ]),
            Section(heading: "Look Around", lines: [
                "Where Apple has street-level imagery, a spot's details show a **Look Around** preview. Click it to explore — check the view, the access road, and where to park before you drive out. Where there's no coverage, use **Street View** under Location instead."
            ])
        ]),
        HelpTopic(id: "organize", title: "Organizing & Trips", symbol: "signpost.right.and.left", sections: [
            Section(heading: "Working with several spots", lines: [
                "**⌘-click** to select individual spots, **⇧-click** to select a range. **Right-click** a spot (or a selection) for everything you can do with it: Show on Map, Directions, Copy Coordinates, Open Route, Move to Trip, Share, Export KML, and Delete.",
                "With several spots selected, the right side shows the same actions as buttons. Press **Delete** to delete the selected spots."
            ]),
            Section(heading: "Trips", lines: [
                "**Trips → Manage Trips…** (⇧⌘T) creates, renames, and deletes trips and sets the **active trip** new spots go into.",
                "**Move to Trip** (right-click menu) moves one spot or a whole selection into a different trip.",
                "The **Filter** button in the toolbar narrows the list to one tag or one trip."
            ])
        ]),
        HelpTopic(id: "map", title: "The Map", symbol: "map", sections: [
            Section(heading: nil, lines: [
                "Every spot is a pin. **Zoom in** to about neighborhood level and pins become thumbnails of the spot's photo — a reference photo if it has one, otherwise the newest photo.",
                "**Hover** over a pin to see a larger preview; **click** it to open the spot.",
                "To find a spot from the list on the map, right-click it and choose **Show on Map**. With several spots selected, Show on Map fits them all on screen."
            ]),
            Section(heading: "Where the sun will be", lines: [
                "Click **Sun** in the map's toolbar, pick a date, and drag the time slider. At each spot in view, a **gold line** points toward the sun and a **dashed line** shows which way shadows fall — longer when the sun is low. Thin orange and red lines mark where the sun rises and sets that day.",
                "The slider's track shows night, **golden hour** (gold), and daylight at a glance; the buttons jump straight to sunrise, golden hour, noon, and sunset. Times are in the time zone of the area on the map. Zoom in if the lines don't appear."
            ])
        ]),
        HelpTopic(id: "planner", title: "Trip Planner", symbol: "calendar.badge.clock", sections: [
            Section(heading: nil, lines: [
                "**Trips → Plan Trip Day…** (⇧⌘P) plans a trip one day at a time; your plan syncs to your iPhone. Pick a trip at the top, or click **+** to start a new one."
            ]),
            Section(heading: "Days", lines: [
                "Each day is a tab — click **+ Add Day** for the next one, and give each its date. **Right-click** a stop to move it to another day. Spots added to the trip later appear under **Not Scheduled** until you place them. Click them to select (they're the gold pins on the map), then **Add Selected**; click **ⓘ** or right-click one for its photos, note, and source before you decide."
            ]),
            Section(heading: "Your schedule", lines: [
                "**Right-click the map** to **Add Stop Here** (it's named after the nearest town and gets a picture) or **Start the Day Here**.",
                "Set where the day starts (a hotel, an address, a Google Maps link, or the location button for where you are now), what time you leave, and how long you spend at each stop. Every stop then shows when you'll **arrive**, using real driving times, and whether that works for the light:",
                "🟢 **On time for the light** · ⚪ **Early**, with how long until best light · 🟠 **Late** for best light · 🔴 **After sunset**",
                "**Leave in Time for First Light** sets your departure so you reach the first stop 15 minutes before its best light. Drag stops to reorder them, or click **Order by Best Light**."
            ]),
            Section(heading: "Timing the light", lines: [
                "**Best light** is the moment the sun is low and lined up with the direction you were facing when you saved the spot. Spots added without a compass heading (from a link or the map) show the day's golden-hour windows instead.",
                "Times are shown in the **trip's own time zone**, so planning a trip across the country needs no mental math."
            ]),
            Section(heading: "On your iPhone", lines: [
                "Your plan syncs. On iPhone, open **Trips → Plan & Pack** and pick the trip to see each day's stops with arrival times and the light, open the day in Google Maps, and get directions to any stop."
            ]),
            Section(heading: "Cloud forecast", lines: [
                "Within about two weeks of the date, each stop shows the forecast cloud cover at its best light, with a quick read: clear, high cloud that could light up, low cloud likely to block the sun, overcast, or rain. Hover it for the low, mid, and high cloud layers.",
                "Forecasts come from Open-Meteo.com; only an approximate location (to about 1 km) is sent to get them."
            ]),
            Section(heading: "Taking it with you", lines: [
                "**Open Route** sends the day's stops, in order and from your start point, to Google Maps for turn-by-turn directions.",
                "**Shot Sheet** prints or saves a PDF of one day or the whole trip: arrival times, best light, forecast, notes, parking, and a shot-list checklist for each stop."
            ])
        ]),
        HelpTopic(id: "route", title: "Find Along the Route", symbol: "road.lanes", sections: [
            Section(heading: nil, lines: [
                "Planning a long drive — say, Route 66 — and want the odd, specific stops that take hours of digging through forums and blogs to find? Open **Trips → Plan Trip Day…** and choose **Along the Route**. It's also on iPhone: **Trips → Plan & Pack**."
            ]),
            Section(heading: "1. Set the route", lines: [
                "Enter where you start and end. Following a specific road (historic Route 66, a scenic byway)? Without towns to route through, directions take the fastest highway. Three ways to set them:",
                "• **From Google Maps (easiest):** get directions in Google Maps, drag the route onto the road you want, then **Share → Copy Link** and click **Paste Google Maps Route**. Google allows about 10 stops per route, so for a long trip paste a few links and choose **Add to the End of the Route** for each.",
                "• **With AI:** describe the road under *How to get there*, click **Copy Waypoint Prompt**, paste it into an AI chat, copy its reply, and click **Paste Waypoints**.",
                "• **By hand:** type towns into *Add a town to route through*."
            ]),
            Section(heading: "2. Say what you're after", lines: [
                "Tap the kinds of places you want — roadside oddities, ghost towns, neon signs, classic diners… — or type your own. Choose how far off the route you'll go, and how long each segment is."
            ]),
            Section(heading: "3. Work through it a segment at a time", lines: [
                "A long route is split into segments (e.g. *Tulsa, OK → Amarillo, TX*), each small enough for one AI reply to cover well. For each: **Copy Prompt** → paste into Claude, ChatGPT, or another AI chat — **turn on web search** if it has it — → copy the whole reply → **Paste Results**.",
                "Finds are added to the trip and listed in driving order with the **mile** where each falls and how far off the route it is. Anything farther than you asked for shows in orange.",
                "If the AI bunches its finds together, the stretches it skipped appear under the segment — **Copy Gap Prompt** asks about just that stretch.",
                "AI tools sometimes get places wrong. Each find's address is checked against its coordinates, and any that disagree are tagged **unverified** — check those before you detour. The AI's source is kept in each spot's note, with a link you can open from the spot's details."
            ]),
            Section(heading: "Pictures", lines: [
                "Every find gets a picture automatically: the photo the AI linked to (when that link really is a photo), otherwise Apple's **Look Around** street view, otherwise a **satellite** view of the exact spot with the pin circled. The satellite view doubles as a check — if the circle is on an empty field, the AI may have the location wrong."
            ])
        ]),
        HelpTopic(id: "packing", title: "Packing & Gear", symbol: "suitcase", sections: [
            Section(heading: "Your gear library", lines: [
                "**Trips → Gear Library…** (⇧⌘G) holds your equipment and personal items, entered once and reused on every trip. **Start with a Common Set** fills in a typical set to edit.",
                "Group items into **kits** — *Landscape kit*, *Drone kit*, *Road trip basics*. In the **Kits** section, click **New Kit** (or an existing kit) and tick everything that belongs in it. An item can be in any number of kits, and adding two kits that share an item lists it once.",
                "Already built a good packing list? **Save as Kit…** on the Packing tab turns it — or just the items you tick — into a kit for next time, adding anything new to your library."
            ]),
            Section(heading: "Gear for each stop", lines: [
                "In a spot's details, **Gear Needed** lists what that spot calls for — the drone, a 10-stop ND, a headlamp for a night shoot. Pick from your library or type anything."
            ]),
            Section(heading: "The trip's packing list", lines: [
                "In the Trip Planner, choose **Packing**. Add whole kits, items from your library, or one-offs. Gear your stops need that isn't on the list yet shows under **Your Stops Need**, with which stops need it.",
                "The list syncs, so build it here and check things off on your iPhone as you pack. **Uncheck All** starts over — handy for packing up to go home."
            ]),
            Section(heading: "Leaving a stop", lines: [
                "On iPhone, **Leaving? Check Your Gear** in a spot's details (or swipe a stop in the itinerary) runs through the equipment you'd have had out — so the tripod doesn't stay behind at a pull-off."
            ])
        ]),
        HelpTopic(id: "share", title: "Getting There & Sharing", symbol: "car", sections: [
            Section(heading: nil, lines: [
                "**Directions** opens a spot in Apple Maps. **Open Route** (with two or more spots selected) builds a multi-stop Google Maps route.",
                "**Export KML** saves spots in a format Google My Maps and Google Earth open.",
                "**Share with Photo Point User** creates a spots file another Photo Point user can import with **File → Import from File…**."
            ])
        ]),
        HelpTopic(id: "sync", title: "Sync & iCloud", symbol: "icloud", sections: [
            Section(heading: nil, lines: [
                "Photo Point syncs through iCloud on every device signed in to the **same Apple Account** with iCloud Drive turned on. Changes usually appear on your other devices within seconds while Photo Point is open there.",
                "If something doesn't show up: make sure Photo Point is open on the other device, then **quit and reopen** Photo Point on both. Photos are larger and may arrive a little after the spot itself.",
                "Your spots live in your own private iCloud storage — Photo Point has no server of its own and never sees your data."
            ])
        ]),
        HelpTopic(id: "keys", title: "Keyboard Shortcuts", symbol: "keyboard", sections: [
            Section(heading: nil, lines: [
                "**⌘N** — New Spot",
                "**⌘O** — Import from File",
                "**⇧⌘I** — Import via AI Chat",
                "**⌘V** (in the sidebar) — Paste a Google Maps link as a new spot",
                "**⇧⌘T** — Manage Trips",
                "**⇧⌘P** — Plan Trip Day",
                "**⇧⌘G** — Gear Library",
                "**Delete** — Delete the selected spots",
                "**⌘-click / ⇧-click** — Select several spots",
                "**⌘?** — This help"
            ])
        ])
    ]
}
