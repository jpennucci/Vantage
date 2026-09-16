# Photo Point — TestFlight Build 1.1 (9)

## What is Photo Point?
Photo Point (formerly Vantage — same app, new name, nothing lost) is a location-scouting companion app for photographers/videographers (built as a companion to LumenMeter). It's built to be used one-handed, often while driving: tap once to save your current GPS spot with heading and time — then come back later to add photos, notes, and tags.

## What's new since the last round (build 6)
- **Renamed from Vantage to Photo Point** — same app, same account, same iCloud data; only the name and icon changed.
- **Weather at capture removed** — it never worked reliably (a persistent activation issue on Apple's side) and was flagged in App Review for showing a field it couldn't actually back with real data, so it's been pulled entirely rather than left half-working. Spots no longer show a "Weather at Capture" row — nothing to test here anymore.
- **Move to Trip** — reassign a spot to a different trip without opening it. Long-press a spot in the main list for "Move to Trip," or select several spots at once (via "Select Multiple" or edit mode) and use the new "Move to Trip" bulk action in the toolbar. Useful if you captured a spot before starting a trip, or want to consolidate spots from two trips into one.
- **Watch complication captures actually save now** — a real bug in the last build: captures made from the watch face complication could report success (haptic buzz) but silently fail to save anywhere. Root-caused and fixed (a background-save race, plus the complication and its container app weren't sharing the same local data store). If you use the complication, this is the main thing worth re-testing.
- **Complication haptic feedback** — tapping the watch face complication now gives a felt confirmation (success/failure buzz) even when the app doesn't visibly open.
- **Complication icon color** — now uses Photo Point's own brand blue instead of the default system tint (on watch faces that support full-color complications).
- **Apple Watch app** — a companion watchOS app with its own one-tap capture button, independent GPS (works even without your iPhone nearby), and a recent-spots list. Requires a paired Apple Watch; skip this section if you don't have one.
- **Watch face complication** — the same one-tap "Save Spot" button, now addable directly to a watch face (long-press the face → Edit → add a complication → Photo Point). Larger, more glanceable target than opening the app or even the widget.
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
- Long-press a spot in the main list and try the new "Move to Trip" — confirm it moves to the chosen trip (or clears to "No Trip").
- Select multiple spots ("Select Multiple" or edit mode) and try the bulk "Move to Trip" toolbar action — confirm all selected spots move together.

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
- Try "Share with Photo Point User" — this exports a JSON file. Share it to another device/person running Photo Point and import it there (via the paste-import or file-import flow) to confirm round-tripping works.

**AI-assisted import**
- From the main list, tap the Import menu → "Import via AI Chat" for instructions.
- Copy the provided prompt, paste it into any AI chat tool (ChatGPT, Claude, etc.) along with what you're looking for (e.g., "abandoned barns near Route 9 in NJ"), then paste the AI's JSON response back into Photo Point using the paste-import option. Confirm it correctly geocodes and imports the spots, and lands them in a new trip.

**Cross-device sync**
- Save a spot on your iPhone, confirm it shows up on iPad, Mac, and Apple Watch (via iCloud/CloudKit) within a few seconds to a minute.
- Same test for photos, tags, trips, and shot list edits — confirm they sync in both directions.

**iPad & Mac**
- Confirm the app is usable in both portrait and landscape on iPad.
- On Mac, confirm the sidebar/detail split view works, and that "Show Map" gets you back to the map after selecting a list entry.

## Known issues
- None currently open. This build is mostly organizational (Move to Trip) plus the rename and the weather-feature removal above.

## Feedback
Anything that feels confusing, slow, or broken — especially around the one-handed/driving use case — is exactly the kind of feedback that's most useful right now.
