# Vantage — TestFlight Build 1.0 (5)

## What is Vantage?
Vantage is a location-scouting companion app for photographers/videographers (built as a companion to LumenMeter). It's built to be used one-handed, often while driving: tap once to save your current GPS spot with heading, weather, and time — then come back later to add photos, notes, and tags.

## What's new since the last round
- **Apple Watch app** — a companion watchOS app with its own one-tap capture button, independent GPS (works even without your iPhone nearby), and a recent-spots list. Requires a paired Apple Watch; skip this section if you don't have one.
- **Watch face complication** — the same one-tap "Save Spot" button, now addable directly to a watch face (long-press the face → Edit → add a complication → Vantage). Larger, more glanceable target than opening the app or even the widget.
- **Parking location** — a dedicated field on each spot for van/trailer-relevant notes, plus a "Set to Current Location" button that captures a second GPS point for exactly where you parked, with its own directions link.
- **Map current-location button** and two new one-tap links per spot: **Shadow Map** (sun/shadow simulator for that exact coordinate) and **cloud forecast** — both open in the browser from the entry detail screen.
- **AI-assisted import now auto-creates a trip** — a batch import used to scatter into the general list; it now files into one new trip (named from the AI response's own collection name, or a timestamp), so a dozen+ imported spots stay easy to find together.
- **Heading capture bug fixed** — a previous build could record the reversed compass heading in some cases; this should now consistently reflect the direction you were actually facing.
- **Simplified Siri phrase** — "Hey Siri, save this spot" (or "save this location") should trigger more reliably than before.
- Assorted polish: a data-heavy entry's metadata row (heading/golden-hour/status icons) no longer clips instead of scrolling; deleting a trip now correctly clears the trip tag from its former entries instead of leaving them pointing at nothing; the toolbar's Tag/Trip filters and the two Import actions are each consolidated into one menu instead of separate icons.

## What to test

**Capture flow**
- Tap "Save This Spot" in the app, from the Lock Screen widget, from the Watch app or watch face complication (if you have an Apple Watch), or say "Hey Siri, save this spot" / "Hey Siri, save this location" — confirm it saves your current location, heading, and timestamp.
- Check that Siri gives you a spoken confirmation when saving hands-free.
- If you have an Apple Watch: try a capture with your iPhone left in another room, to confirm it really works independently.

**Location details**
- Open a saved spot and check: coordinates, heading, "Best Light Today" (golden hour suggestion based on your heading and sun position), captured time.
- Weather at capture — this was a known issue in the last round (WeatherKit account-side activation delay); let us know either way whether you're seeing a weather summary now.
- Try adding a title, note, parking notes, and tags (both built-in and your own custom tags — once you type a new one, it should show up as a suggestion next time).
- Try the new **Set to Current Location** button under Parking, and its "Directions to Parking" link.
- Try the new **Shadow Map** and **cloud forecast** links.
- Add a photo (camera) and a reference photo (from your library).
- Try the Shot List — add a few checklist items, check them off.
- If you also have LumenMeter installed: enter a Roll ID under the new LumenMeter section and try "Open in LumenMeter" — it should jump straight to that roll.

**Trips**
- Create a trip, mark it active, save a few spots while it's active, and confirm they get grouped under it.
- Run an AI-assisted import (see below) and confirm the imported spots land together in a new, auto-named trip.
- Rename a trip, then delete it — confirm the spots that were in it aren't lost, just no longer show a trip.

**Map & list**
- Switch to the map view — confirm pins show up in the right places, and try the current-location button.
- Try the Filter menu's tag and trip filters on the main list.
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
- From the main list, tap the Import menu → "Import via AI Chat" for instructions.
- Copy the provided prompt, paste it into any AI chat tool (ChatGPT, Claude, etc.) along with what you're looking for (e.g., "abandoned barns near Route 9 in NJ"), then paste the AI's JSON response back into Vantage using the paste-import option. Confirm it correctly geocodes and imports the spots, and lands them in a new trip.

**Cross-device sync**
- Save a spot on your iPhone, confirm it shows up on iPad, Mac, and Apple Watch (via iCloud/CloudKit) within a few seconds to a minute.
- Same test for photos, tags, trips, and shot list edits — confirm they sync in both directions.

**iPad & Mac**
- Confirm the app is usable in both portrait and landscape on iPad.
- On Mac, confirm the sidebar/detail split view works, and that "Show Map" gets you back to the map after selecting a list entry.

## Known issues
- **Weather at capture may still be broken** (shows no weather summary) — this was a WeatherKit server-side entitlement propagation delay on Apple's end in the last round. Please report whether you're seeing weather data now either way, since this determines whether it's actually resolved.

## Feedback
Anything that feels confusing, slow, or broken — especially around the one-handed/driving use case — is exactly the kind of feedback that's most useful right now.
