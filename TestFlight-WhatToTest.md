# Vantage — TestFlight Build 1.0 (2)

## What is Vantage?
Vantage is a location-scouting companion app for photographers/videographers (built as a companion to LumenMeter). It's built to be used one-handed, often while driving: tap once to save your current GPS spot with heading, weather, and time — then come back later to add photos, notes, and tags.

## What to test

**Capture flow**
- Tap "Save This Spot" in the app, from the Lock Screen widget, or say "Hey Siri, save this spot" / "Hey Siri, save this location" — confirm it saves your current location, heading, and timestamp.
- Check that Siri gives you a spoken confirmation when saving hands-free.

**Location details**
- Open a saved spot and check: coordinates, heading, "Best Light Today" (golden hour suggestion based on your heading and sun position), captured time.
- Weather at capture — **known issue**: this is currently failing for everyone due to a WeatherKit account-side activation delay, not a bug in your build. If it starts working, that's useful to know!
- Try adding a title, note, parking notes, and tags (both built-in and your own custom tags — once you type a new one, it should show up as a suggestion next time).
- Add a photo (camera) and a reference photo (from your library).
- Try the Shot List — add a few checklist items, check them off.

**Trips**
- Create a trip, mark it active, save a few spots while it's active, and confirm they get grouped under it.
- Rename a trip, check the entry counts.

**Map & list**
- Switch to the map view — confirm pins show up in the right places.
- Try the tag filter and trip filter on the main list.
- Try "Near Me" sorting.
- Multi-select a few entries and try deleting.

**Navigation integrations**
- From a spot, try "Open in Waze" and the Google Maps link — confirm they launch and route correctly.
- Select 2+ spots and try "Open Route" (multi-stop Google Maps route).
- Try "Copy Coordinates" and "Copy Address."

**Export & sharing**
- Export a spot (or a whole trip) as KML and try opening it in Google My Maps.
- Try "Share with Vantage User" — this exports a JSON file. Share it to another device/person running Vantage and import it there (via the paste-import or file-import flow) to confirm round-tripping works.

**AI-assisted import**
- From the main list, tap "Import Spots" → "How to Import" for instructions.
- Copy the provided prompt, paste it into any AI chat tool (ChatGPT, Claude, etc.) along with what you're looking for (e.g., "abandoned barns near Route 9 in NJ"), then paste the AI's JSON response back into Vantage using the paste-import option. Confirm it correctly geocodes and imports the spots.

**Cross-device sync**
- Save a spot on your iPhone, confirm it shows up on iPad and Mac (via iCloud/CloudKit) within a few seconds to a minute.
- Same test for photos, tags, trips, and shot list edits — confirm they sync in both directions.

**iPad & Mac**
- Confirm the app is usable in both portrait and landscape on iPad.
- On Mac, confirm the sidebar/detail split view works, and that "Show Map" gets you back to the map after selecting a list entry.

## Known issues
- **Weather at capture is currently broken** (shows no weather summary). This is a WeatherKit server-side entitlement propagation delay on Apple's end, not something in this build — expected to resolve on its own; no action needed from testers.

## Feedback
Anything that feels confusing, slow, or broken — especially around the one-handed/driving use case — is exactly the kind of feedback that's most useful right now.
