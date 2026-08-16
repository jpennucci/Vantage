# ScoutNote — Photographer's Location Scouting Notebook (working title)

## Overview
An iOS app for capturing interesting locations the instant you spot them — especially while driving — with near-zero friction. One-tap GPS save, optional quick photo, and voice or text notes, designed so the whole capture can happen without taking your eyes off the road for more than a glance. Built for a road-trip/scouting workflow: come back later, with full context (location, direction, time of day, weather, notes) to plan an actual shoot.

## Hardware / Environment
- Dev machine: Mac mini
- Test device: iPhone 17 Pro Max
- Apple Developer account: active
- Built with: Xcode (project scaffolded manually) + Claude Code (writes/iterates on Swift files)
- Companion project to LumenMeter (light meter app) — separate app, but shares the same film/road-trip photography workflow and offline-first philosophy

## Core Features

1. **One-tap capture (the whole point of the app)**
   - Single button press: instantly logs GPS coordinates, timestamp, compass heading (direction phone/vehicle was facing), and weather conditions at time of capture
   - Must work with minimal interaction — this is the single most important design constraint
   - **Lock screen widget / Control Center button**: capture a location without unlocking or opening the app
   - **Siri Shortcut** ("Hey Siri, save this spot"): fully hands-free, voice-only capture — critical for driving safety
   - Design principle: assume the person using this is driving and glancing, not sitting still composing an entry

2. **Quick photo**
   - Camera button within the capture flow for an immediate reference shot
   - Not meant to be a good photo — just a visual reminder of what caught your eye
   - Photo attaches to the location entry

3. **Voice or text notes**
   - Voice-to-text note attached to any entry — speak a quick thought ("nice old barn, morning light would be great here") without typing
   - Text note as an alternative/addition for when speaking isn't practical
   - Notes can be added at capture time or later when reviewing entries

4. **Heading/compass + sun position**
   - Log compass heading at time of capture (which direction you were facing/looking)
   - Combined with GPS + timestamp, calculate golden hour / sun position for that exact location and heading — tells you what time to come back for the best light
   - Genuinely differentiated feature — most location-note apps don't do this

5. **Weather auto-logging**
   - Pull current weather conditions at time of capture automatically (no user input needed)
   - Useful later for context ("hazy that day — worth a return trip on a clear one")

6. **Status tags per location**
   - Simple tagging system: "to shoot," "shot," "needs permission / private property," "seasonal — revisit in fall," etc.
   - User-customizable tag list
   - Turns the app from a passive list into an active scouting pipeline

7. **Map view**
   - All saved locations as pins on a map
   - Filterable by tag/status
   - Useful for reviewing an entire road trip route's worth of scouted spots at a glance

8. **Proximity search**
   - "Show me scouted spots near where I am right now"
   - Useful when passing back through a region months or years later

9. **Van/trailer-specific field** (personal use case, but keep it generic/optional for broader usability)
   - Optional note field: parking availability for a larger rig, trailer accessibility, road conditions for towing
   - Relevant given Sprinter van + rPod trailer travel style

10. **Export/share to navigation**
    - Send a saved location directly to Apple Maps or Google Maps for turn-by-turn directions back to it
    - **Auto-generated Street View link**: since GPS + compass heading are already captured at the moment of saving, automatically construct a Google Street View deep-link (`google.com/maps/@?api=1&map_action=pano&viewpoint=LAT,LNG&heading=HEADING`) and store it with the entry — tapping it opens Street View oriented roughly the direction you were facing when you saved the spot, recreating close to what was actually seen. No API key or account needed, just a constructed URL — cheap to add, high recall value when reviewing entries later

11. **Cloud sync (iCloud/CloudKit)**
    - All entries sync automatically between iPhone and Mac — no manual export/import step for normal use
    - Bidirectional: entries created in the field on iPhone appear on Mac, and entries/pins created on Mac while planning appear on iPhone before you even leave
    - Offline-first still applies on the iPhone side — sync happens opportunistically when connectivity is available, never blocks capture

12. **Mac companion app**
    - Full macOS version (likely via SwiftUI multiplatform / Catalyst), not just a web view — real native planning tool
    - **Home planning workflow**: research locations ahead of a trip using Google Maps/Street View (or Apple Maps) in a browser, then manually drop a pin/entry into the Mac app with notes, tags, and a target date — syncs to iPhone automatically so it's ready when you're on the road
    - Larger screen is genuinely useful here: reviewing photos, writing longer notes, organizing tags/trip groupings, and looking at the full map of scouted spots at once
    - This is a two-way relationship: field captures flow home, home planning flows to the field

13. **Sharing (two-tier approach — different tools for different needs)**
    - **CKShare (Apple-to-Apple, collaborative)**: share an individual entry or trip's worth of entries with another Apple user, live-updating, both people can add notes/photos if made collaborative — best for close collaboration with someone also using the app
    - **Google My Maps export (universal, anyone/any device)**: export selected entries as a KML file, importable directly into Google My Maps — generates a shareable link anyone can open on any device/browser, no account or app required on the recipient's end. Much lower effort than building custom map-hosting infrastructure, and Google My Maps already handles pins, notes, and photos well
    - Recommendation: build both — CKShare for close collaborative use between Apple users, KML export for "just send anyone a map link"

14. **Trip/collection grouping**
    - Entries can be grouped into "trips" rather than living as one flat list — same organizing pattern as "rolls" in LumenMeter
    - Enables reviewing everything scouted on a specific trip (e.g. the Gulf Coast route) as its own set
    - Pairs naturally with the Mac planning workflow: create a trip ahead of time, plan/import pins into it, take it on the road, add field captures to the same trip

15. **CarPlay integration (stretch goal — Apple approval not guaranteed, see note below)**
    - Dashboard button for one-tap capture directly from CarPlay — larger touch target and more glanceable than a lock screen widget, doesn't require picking up the phone at all
    - Built alongside the Siri Shortcut, not a replacement — the widget and Siri Shortcut alone likely cover most of the "safe capture while driving" need without any special Apple approval
    - **Important constraint**: CarPlay requires Apple to grant a CarPlay entitlement to the developer account, and only for apps that clearly fit one of Apple's predefined categories (Audio, Communication, EV Charging, Navigation, Parking, Quick Food Ordering, or the newer Voice Conversational category). A location-scouting notebook doesn't cleanly fit any of these, so approval is genuinely uncertain — Apple reviews case-by-case with no published timeline, and generally wants to see a substantively built app before approving, not a placeholder
    - Testing note: the CarPlay Simulator (built into Xcode, runs on the Mac, no physical car needed) can render CarPlay templates for early UI testing regardless of entitlement status — but a signed build that runs on the actual Sprinter's CarPlay screen requires Apple's entitlement approval first
    - Treat as a stretch goal to attempt after the core app is built and working well via widget/Siri — not something to plan the MVP around

16. **Apple Watch integration (stretch goal, build after core iPhone app is working)**
    - Real use case: walking without the phone on hand, or phone tucked away — Watch-only capture covers situations the phone app can't
    - **One-tap complication/app button**: single tap on the watch face captures location instantly — same "just tap it" simplicity, no voice needed, similar in spirit to a one-button voice recorder watch app already in daily use
    - **Voice-to-text note capture**: Watch's built-in dictation lets a quick spoken note attach to the entry, same as the iPhone flow
    - **Independent GPS**: modern Apple Watch models have their own built-in GPS chip, so Watch-only capture works even without the iPhone nearby — a real advantage over CarPlay/phone-only capture in this specific "left the phone behind" scenario
    - **Siri ("Hey Siri, save this spot") works the same on Watch as iPhone** — if built via Apple's App Intents framework, the same Shortcut triggers identically regardless of which device Siri is invoked from, no extra work required for parity there
    - **Sync**: requires a dedicated watchOS app target (not just Siri) — needs to either sync directly to the same iCloud/CloudKit container or relay through the paired iPhone via WatchConnectivity; decide once core CloudKit sync architecture is in place
    - Treat as a second-priority stretch goal alongside CarPlay, but likely more reliably buildable since there's no Apple entitlement approval gate blocking it (unlike CarPlay)

16. **Cross-app link to LumenMeter**
    - Once a scouted location is actually shot, allow linking the entry forward to a LumenMeter roll/reading
    - Closes the full lifecycle loop across both apps: spotted it (Waypoint/Vantage) → scheduled the light (sun position) → metered it (LumenMeter) → shot it → developed it (LumenMeter dev tracking) — all traceable rather than living in two disconnected apps
    - Not required for either app to function independently — an optional connection when both are in use

17. **Multiple photos per entry**
    - Support a small photo gallery per entry rather than a single photo — e.g. wide shot, a detail shot, a parking/access reference shot
    - Build this in from the start (`LocationEntryModel` should hold an array of photo references, not a single one) — much easier than retrofitting later

18. **Full-text search across notes**
    - Search across voice-transcribed and typed notes, not just tags/location/trip name
    - Becomes important once entry count grows into the hundreds — cheap to support since notes are already stored as text, just needs indexed search rather than a linear scan

19. **Shot list checklist (borrowed idea, lightweight)**
    - Simple checklist field per trip or per entry — e.g. "wide shot," "detail of barn door," "shoot at sunset"
    - Not a freeform board — just a small checklist, cheap to build, inspired by shot-list features in photo planning tools like Milanote without adopting their full canvas paradigm
    - **Keep the field medium-agnostic (not photo-specific wording/UI)**: a shot list is equally useful for video creators scouting locations for a shoot — B-roll ideas, specific sequences/angles to capture — so this single feature naturally extends the app's usefulness beyond stills photography without any extra design work, as long as the implementation doesn't assume "photo" specifically

20. **Reference/inspiration image field (borrowed idea, lightweight)**
    - Optional image slot per entry, separate from the quick field capture photo — for saving an inspiration image found online to emulate when returning to shoot the spot
    - Just another photo field, not a moodboard system

## Shared Design System (companion note — also applies to LumenMeter)
Waypoint/Vantage and LumenMeter are meant to feel like a matched personal toolkit, not two unrelated apps:
- **Should match across both apps**: color palette/accent colors, typography, icon style/weight, general interaction patterns (button shapes, spacing), dark-mode-first approach, app icon family resemblance
- **Should NOT match — different jobs need different UI logic**: Waypoint/Vantage is a *capture-and-go tool* (minimal-to-zero screen time, optimized for tap-once-and-put-phone-down via widget/Siri, not for displaying rich data). LumenMeter is an *instrument* (glanceable, precise, Sekonic-inspired, meant to be studied for a few seconds while composing a shot)
- Practical build note: worth creating a small shared Swift package (colors, fonts, shared UI components) used by both projects rather than redefining the design system twice — saves real duplicated work

## AllTrails Integration Research (findings — dead end, documented so it's not re-investigated later)
Investigated whether pins/entries could be pushed to or displayed within AllTrails for landscape/trail-planning context.
- AllTrails does not publish a public developer API, and their platform is actively protected against automated/scraping access — there is no legitimate integration path for third-party apps
- Their only public integrations are fitness/wearable partners (Garmin, COROS, Apple Health, Health Connect) — not a developer ecosystem for apps like this one
- **Practical workaround instead**: the app's own MapKit-based map view already shows scouted pins against real terrain/roads (not AllTrails' specific trail data). If AllTrails trail context genuinely matters for a spot, the manual workaround is to look it up in AllTrails separately and paste the relevant trail info/link into that entry's notes field — same pattern as the Google Maps link import already planned for the Mac workflow
- Revisit only if AllTrails ever publishes a public API in the future — no indication of that happening currently

## Future Integration: Claude/MCP Hooks (strong roadmap candidate, no API key/billing required)
- **Concept**: expose the Mac companion app's data (location entries, trips, notes) to Claude via a local MCP (Model Context Protocol) server — the same mechanism Claude Desktop/Claude Code uses to connect to tools like Google Drive or Slack
- **No API key or billing needed on the developer side**: this runs as a local process on the Mac, only active while the app is running — Claude Desktop connects to it as a local connector, no hosted infrastructure or Anthropic API key required
- **What it enables**: conversational read/write access to the app's data — e.g. "Claude, add these five spots to my Glacier trip" (writes entries via a `create_location_entry` tool), or "what did I save near Bay St. Louis?" (reads back via `search_entries`/`list_locations`) — directly extends the same kind of trip-planning conversation already happening in Claude chat, except now it writes straight into the actual app instead of a summary doc
- **Practical shape**: a small MCP server component exposing a handful of tools (create entry, list/search entries, update tags, get trip summary), either built into the Mac app itself or as a lightweight companion process
- Treat as a genuine differentiator worth prioritizing once the core Mac app and sync are stable — very few personal utility apps expose themselves to an AI assistant this cleanly, and it's a natural fit given how much of this app's own planning already happens through Claude conversations


- **Mac App Store**: the Mac companion app distributes through the Mac App Store under the same developer account as the iPhone apps — same review process, same free/paid mechanics, one account covers all platforms. (Direct-download-outside-the-App-Store is technically possible via notarization, but Mac App Store is simpler given the iPhone apps are already going that route.)
- **Base map = MapKit, not Google Maps**: MapKit is native, free, requires no API key or billing, and is already the map engine for the iPhone app — using it on Mac too means one shared map codebase across both platforms. Google Maps has no native macOS SDK; embedding it would require a web-view-based Google Maps JavaScript API integration with a billed Google Cloud API key (free monthly credit, then pay-per-load) — not worth the cost/complexity for the core map surface.
- **Where Google Maps still fits in (no billing required)**: Street View deep-links (already planned) and parsing pasted Google Maps links to extract coordinates for the Mac planning workflow (already planned) — both are just URL-based, no API key needed. So the useful parts of Google Maps are used without paying for a full map embed.

## Milanote Research (considered, mostly out of scope — documented so it's not re-investigated)
Investigated Milanote (popular photo-shoot planning tool) for relevant ideas before building further.
- Milanote is a freeform drag-and-drop visual canvas for moodboards, inspiration collection, shot lists, and client/team collaboration — built mainly for client-facing brand/commercial shoots where a team needs to align on visual direction beforehand
- **Different paradigm, not a competitor**: this app is structured and field-based (GPS + photo + note, fast capture while driving), not a freeform visual collaboration canvas — replicating Milanote's canvas UI would be significant extra engineering for a use case (client moodboards, team alignment) that doesn't serve the actual personal landscape/road-trip scouting workflow
- **Small ideas worth borrowing (cheap additions, not a canvas rebuild)**:
  - Simple shot list checklist field per trip or entry (e.g. "wide shot," "detail of barn door," "shoot at sunset")
  - Optional reference/inspiration image field per entry, separate from the quick field photo — for saving an inspiration image found online to emulate later
- **Explicitly out of scope**: freeform canvas UI, client collaboration/feedback workflow, general moodboard tooling — real scope creep given this app's actual purpose

## Architecture Principles
- **Offline-first on iPhone**: capture, GPS logging, and local storage must all work with zero connectivity — same principle as LumenMeter, given the remote/rural driving this app is meant for. Weather logging and sync are the two features that need connectivity; both should fail gracefully (skip/queue, don't block capture) when offline, then sync opportunistically once back online.
- **Minimal-interaction capture**: every design decision should be evaluated against "can this be done in under 2 seconds while driving, ideally hands-free."
- **Sync as a first-class citizen, not an afterthought**: since the Mac app and iPhone app are meant to be used together (plan at home, capture on the road, review at home again), CloudKit sync should be part of the core data model from the start rather than bolted on — this affects how `LocationEntryModel` is structured from day one.
- **Entitlement gate for future monetization**: same pattern as LumenMeter — build a lightweight feature-gate layer now, even with no purchase logic yet, so a free/premium split is easy to add later without a retrofit. No obligation to ever publish or charge. (Note: iCloud sync usage may factor into future monetization decisions if the app is ever shared beyond personal use, since sync/storage at scale has real cost — not a concern for personal use.)

## Free vs. Paid Split (concrete decision, if monetized)
- **Free tier**: full capture flow (GPS, photo gallery, voice/text notes), local map view, single-device use, lock screen widget + Siri Shortcut hands-free capture, weather auto-logging, sun position/golden hour calculation, status tags, trip grouping (single device) — free tier is a genuinely complete capture-and-review tool on its own, works great for solo single-device use
- **Paid unlock**: cloud sync across devices (CloudKit), Mac companion app, sharing (CKShare + Google My Maps KML export), cross-app link to LumenMeter, Apple Watch app
- Rationale: capture-anywhere is the hook — stays free, no friction, fully usable solo. Sync/Mac/sharing is what turns it into a real cross-device system rather than a personal notes app, which is both genuinely worth paying for and the most expensive part to run at scale (CloudKit), making it a natural place to monetize

## Suggested File Structure
```
LocationCaptureService.swift — core one-tap capture: GPS, timestamp, heading, weather trigger
QuickCameraView.swift        — lightweight camera capture flow for reference photos
VoiceNoteService.swift       — speech-to-text capture and playback/transcription
SunPositionEngine.swift      — golden hour / sun position calculation from GPS + heading + timestamp
WeatherService.swift         — fetch and attach current conditions at capture time (online-only, fails gracefully)
LocationEntryModel.swift     — struct: GPS, timestamp, heading, photo gallery (array of refs), voice/text note, weather, tags, trip ID, van/trailer notes, optional link to LumenMeter roll/reading — designed for CloudKit sync from the start
TagModel.swift                — user-customizable status tag system
TripModel.swift                — trip/collection grouping for entries, supports both field-created and Mac-planned trips
MapView.swift                 — all entries as pins, filterable by tag/trip (shared between iOS/macOS targets)
EntryDetailView.swift         — full entry detail: photo gallery, notes, sun position info, edit tags, link to LumenMeter entry
ProximitySearchView.swift     — "near me" search against saved entries (iOS-primary, less relevant on Mac)
SearchService.swift           — full-text search across voice/text notes, tags, and trip names
ExportService.swift           — hand off a saved location to Apple/Google Maps; also handles KML export for Google My Maps sharing
SiriShortcutsProvider.swift   — App Intents / Siri Shortcut integration for hands-free capture
CarPlayScene.swift            — CarPlay dashboard capture button, separate low-glance capture path alongside Siri
WatchApp/CaptureView.swift    — watchOS app target: one-tap complication/button capture, voice note dictation, independent GPS
WatchApp/WatchSyncService.swift — Watch-side CloudKit sync or WatchConnectivity relay through paired iPhone
LockScreenWidget.swift        — widget extension for one-tap capture from lock screen/Control Center
SyncService.swift             — CloudKit sync engine, handles bidirectional iPhone↔Mac updates and offline queuing
SharingService.swift          — CKShare-based entry sharing with other Apple users
MacPlanningView.swift         — Mac-specific planning UI: add entries manually, organize by trip, review at larger scale
ContentView.swift             — ties everything together (iOS)
ContentView-macOS.swift       — Mac-specific entry point/layout adjustments
```

## Build Order
1. Core one-tap capture (GPS + timestamp + heading) — the essential MVP loop
2. Quick photo capture, supporting multiple photos per entry from the start
3. Voice-to-text and text notes
4. Local data model built with CloudKit sync, trip grouping, and multi-photo support in mind from the start (even before sync/trips are fully wired up)
5. Map view of all entries
6. Lock screen widget + Siri Shortcut hands-free capture (critical safety/usability feature — don't leave these for last; no special Apple approval required)
7. CloudKit sync between iPhone and Mac (basic entries first, then photos/voice notes)
8. Mac companion app UI — planning workflow, larger-screen review
9. Trip/collection grouping
10. Weather auto-logging
11. Sun position / golden hour calculation
12. Status tags + filtering
13. Full-text search across notes
14. Proximity search
15. Export to Maps
16. Sharing (CKShare and KML export)
17. Cross-app link to LumenMeter
18. Van/trailer notes field
19. Polish, entitlement gate scaffolding
20. CarPlay stretch goal — attempt Apple entitlement request once core app is built and stable; not blocking, may be rejected given category fit is uncertain
21. Apple Watch stretch goal — watchOS app target with one-tap complication capture, voice notes, independent GPS, and sync; no Apple approval gate, more reliably buildable than CarPlay

## Open Questions / To Discuss Further
- Final app name — leaning **Waypoint** or **Vantage** (both liked, final pick still open)
- Should quick photos and "real" reference photos (like ones taken for LumenMeter readings) ever be linked/shared between the two apps, or kept fully separate?
- Widget design — how much info shown on lock screen widget vs. just a capture button?
- CKShare collaborative editing: read-only shared pins vs. fully collaborative shared entries?
- Mac planning workflow: paste a Google Maps link and auto-extract coordinates (confirmed desired — worth building) — need to determine best parsing approach (Google Maps share links encode coordinates in the URL, generally parseable without needing the Google Maps API)
- Data export/backup format if the person wants to get entries out beyond KML (CSV also worth considering for raw data)
