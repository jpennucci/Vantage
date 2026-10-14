# iPhone Duo plan: Photo Point (and LumenMeter)

Notes from 2026-10-14. Nothing is built yet. **The user approved every idea below on 2026-10-14; all of them are planned work, not maybes.** LumenMeter's half also lives in
`~/Documents/LumenMeter/iPhone-Duo-Plan.md`.

## What Apple requires

- iPhone Duo ships **2026-10-23** (pre-orders 10/16).
- Build with **Xcode 27.1 / the iOS 27.1 SDK**. This Mac has **Xcode 26.6**, so install 27.1 first.
  - Builds from the iOS 26 SDK or earlier sit centered on the inner screen with empty space around them.
  - Builds from the 27.1 SDK run edge to edge on both screens, and tab bars and toolbars move to a **vertical position below the status bar**.
- **Inner screen** (~7.6"): regular width and regular height in both orientations. It **ignores
  `UISupportedInterfaceOrientations`**. **Outer screen** (~5.4"): behaves like a normal iPhone.
- Layout should come from size classes or available space. Don't use `UIScreen.main`, device
  orientation, `userInterfaceIdiom`, or hard-coded screen sizes. Don't assume that
  `horizontalSizeClass == .regular` means iPad.
- Apple's checker: in Xcode 27.1, `xcrun agent skills export` gives the "App Resizability" skill.
  Run it on both apps.
- Testing: the iPhone Duo simulator in Xcode 27.1, the resizable simulator in Device Hub, and
  iPhone Mirroring on macOS 27 (drag the window to extreme sizes).
- **Duo screenshots are required for submissions from April 2027.** Submitting them earlier earns
  an "optimized for iPhone Duo" badge. When nominating the app for featuring, say it's optimized
  for every pose.

Sources: developer.apple.com/news/?id=kkphp5qo, developer.apple.com/iphone-duo/prepare/

## Photo Point: current state

- The flagged patterns don't appear anywhere in Vantage, VantageShare or VantageWidget.
- `ContentView` adds the **Plan tab** (`TripPlannerView`) on `horizontalSizeClass == .regular`.
  `MapView` turns on the **Sun overlay** the same way. So the inner screen gets the iPad layout
  automatically.
- **Bug to fix first:** the Plan tab is added and removed as the size class changes. Folding while
  on Plan (`selection == 2`) leaves the TabView pointing at a tab that no longer exists. On a
  size-class change, fall back to Trips → Plan & Pack for the same `plannerTripID` (or to Map).
- The tab bar turns vertical on the 27.1 SDK, so check that it doesn't crowd the full-screen map.
- iOS orientations are set in `project.yml` (not Info.plist). The inner screen ignores them anyway.

## Photo Point: what the inner screen gains (iPad-like layout)

The inner screen is about 669×951 pt, roughly iPad-mini size, so give it the full iPad experience:

1. **Plan tab and Trip Planner**: already wired up. Verify it on the device.
2. **Sun overlay** on the map: already wired up.
3. **Map and list side by side.** Spots or trips in a sidebar (`NavigationSplitView`) next to the
   map, and selecting a spot opens `EntryDetailView` in a column instead of a sheet. The iPad
   would gain this too.
4. **Planner and map together.** Day plan on one side, the trip's route and stops on the other,
   with selections synced between them. This is the Mac Trip Planner window brought to the phone.
5. **Drag and drop.** `MacSpotDrop` (photos and Google Maps links dropped onto spots or the map)
   is Mac-only right now. Enabling it on iOS regular-width layouts lets you drag from Photos or
   Safari in a second window. iPad gains this too.
6. **Multiple windows** (`UIApplicationSupportsMultipleScenes`): for example, a spot or a trip open
   in its own window. New windows can only open on the inner screen, so handle a refused scene
   request.

## Photo Point: ideas for treating the screens differently

- **Outer screen = in the field.** Keep it capture-first: big Capture button, today's itinerary,
  next stop and the golden-hour countdown. Folded is how you'll hold it while shooting.
- **Inner screen = planning and review.** Planner, sun overlay, side-by-side map and detail,
  bulk tagging. It's where you sit down in the car or the hotel.
- **Continuity across the fold** (the most important point): unfolding should expand exactly what
  you were looking at, never reset it. A spot open on the outer screen opens in the detail column
  inside. The map keeps its region, filters and selection. The current trip stays selected. Keep
  this state in `@SceneStorage`/`@State` above the size-class switch so a layout change doesn't
  discard it.
- **Half-folded ("laptop" pose)**: map on the top half, sun timeline scrubber or day plan on the
  bottom half, split at the fold. It needs the fold-region APIs (`reservedRegions(kind:...)`,
  `ArrangementView`), which are listed as iOS 27.1 beta. Try it once they're confirmed in the SDK.
- **StandBy works on either screen, even when not charging.** A "Today's trip" or "Next golden
  hour" widget would be useful there. Widgets and Live Activities are the only app surfaces in
  StandBy.
- **Live Activity for a trip day** (there's no ActivityKit code yet): next stop, ETA, and a
  countdown to sunset or golden hour. On the outer screen it expands around the camera cutout.
  It also works on every iPhone, so it isn't Duo-only work.

## Order of work

1. Install Xcode 27.1, rebuild, and run Apple's resizability skill.
2. Fix the disappearing Plan tab and keep state stable across the fold.
3. Test in the Duo simulator: vertical tab bar, map, share extension, widgets.
4. Ideas 3–5: split view, planner + map, iOS drag and drop.
5. Later: half-folded layout, the StandBy widget, the Live Activity.
6. Duo screenshots (screenshot mode already exists via `VANTAGE_SCREENSHOT_SCREEN`), then ship
   and earn the badge.
