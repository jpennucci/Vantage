# Vantage — working notes for Claude Code sessions

## This machine builds and ships without opening Xcode's GUI

`xcode-select` on this Mac points at the Command Line Tools, not full Xcode, so
`xcodebuild`/`devicectl` must be invoked with the full path:
`/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild` (same dir for `devicectl`).

Project is XcodeGen-managed — `Vantage.xcodeproj` is gitignored and regenerated with:

```bash
xcodegen generate
```

## Share Extension (VantageShare, added 2026-09-18)

Lets you share an image from Photos (or any share-sheet source, e.g. a Street
View screenshot) straight into Photo Point — either attached to an existing
spot or used to create a new one. Confirmed working end-to-end on-device via
TestFlight build 1.1 (10).

Structure mirrors the widget/watch extensions: a UIKit `ShareViewController`
(the `NSExtensionPrincipalClass`) pulls the image out of the `NSExtensionItem`
the OS hands it, then embeds a SwiftUI view (`ShareExtensionRootView` →
`ShareExtensionView`) via `UIHostingController`. The SwiftUI side reuses
`VantageModelContainer.shared` directly (same App Group + CloudKit config as
every other process), so no custom IPC/file-copying was needed — inserting a
`PhotoAsset`/`LocationEntryModel` from the extension is visible to the main
app the same way a widget capture is.

**Location for "create new spot":** screenshots carry no GPS EXIF, so this
mode primes the pin at the extension's own current-location fix (via
`LocationCaptureService`, reused as-is) and lets you tap the map to correct
it (`MapReader` + `.onTapGesture` → `proxy.convert(point, from: .local)` —
the standard iOS 17 tap-to-place pattern; SwiftUI `Map` has no built-in
draggable-annotation API pre-iOS 18). A real camera photo's actual location
isn't read from EXIF yet — worth doing if this needs to feel smarter later.

**Known gap carried over, not fixed:** `ActiveTripStore.activeTripID` reads
`UserDefaults.standard`, which isn't shared across the App Group — so spots
created from the extension (like the widget/watch) can't see which trip is
active in the main app and always land with no trip assigned. Fix would be
switching `ActiveTripStore` to `UserDefaults(suiteName: "group.com.jamespennucci.Vantage")`.

Needs its own entitlements file (`VantageShare/VantageShare.entitlements`) —
same App Group + iCloud container as the widget — and its own
`NSLocationWhenInUseUsageDescription`, since extensions are separate bundles
with their own permission prompts (the main app's location grant doesn't
carry over automatically).

## App Store Connect upload (CLI only, confirmed working 2026-08-16)

Archive to a project-local path, then export with upload built in — no separate
`altool`/`notarytool`/Transporter step needed, `ExportOptions.plist` already has
`destination: upload`:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Vantage.xcodeproj -scheme Vantage -configuration Release \
  -archivePath build/Vantage.xcarchive -allowProvisioningUpdates archive

/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -exportArchive -archivePath build/Vantage.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates
```

**Before archiving for a real upload, undo the watch-embed `postGenCommand` patch
first** (confirmed 2026-08-26, build 6). That patch exists to make *local*
`xcodebuild`/`devicectl` installs work under Xcode 26 (see the watchOS embedding
bug note further down) by switching "Embed Watch Content" to
`dstSubfolderSpec = 13; dstPath = "";` — but App Store Connect's own server-side
validator rejects exactly that, with `code 90680: Invalid directory... It should
be under Watch.` The two requirements are opposite and both real: local installs
need the PlugIns-style embed, the App Store upload needs the classic one. Since
`xcodegen generate` always re-applies the local-friendly patch, revert just the
"Embed Watch Content" phase (not the two "Embed Foundation Extensions" phases —
leave those alone) in the freshly generated `Vantage.xcodeproj/project.pbxproj`
right before archiving:

```bash
# after `xcodegen generate`, before archiving for App Store Connect:
# find the "Embed Watch Content" PBXCopyFilesBuildPhase block specifically
# (identify it by its `files = ( ... VantageWatch.app ... )` entry, not by
# value — the two widget "Embed Foundation Extensions" phases have the same
# dstSubfolderSpec/dstPath text and must NOT be touched) and change:
#   dstPath = "";                              ->  dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
#   dstSubfolderSpec = 13;                     ->  dstSubfolderSpec = 16;
```

No need to revert this back afterward — it's gitignored, and the next
`xcodegen generate` (e.g. for the next local on-device test) reapplies the
local-friendly patch automatically.

Bundle ID `com.jamespennucci.Vantage` (widget extension:
`com.jamespennucci.Vantage.Widget`), Team ID `PG3PKC873L`, signing style
Automatic. `-allowProvisioningUpdates` is required on the *first* build after
any entitlement/capability change (e.g. adding WeatherKit), otherwise the
build fails with "doesn't include the ... entitlement" even though the code
and `project.yml` are correct — Xcode needs that flag to register the new
capability on the provisioning profile itself.

First real TestFlight upload succeeded 2026-08-16 at 1.0 (1) — `xcodebuild
-exportArchive` printed `Upload succeeded` with no duplicate-build-number
error, and the archive/export step auto-resigns with an Apple Distribution
identity for the App Store even though `archive` itself signs with the Apple
Development identity/profile last used for on-device testing — that's normal,
not a signing problem to chase.

**Bumping `CFBundleVersion`/`CFBundleShortVersionString`:** don't hand-edit
`Info.plist` with `PlistBuddy` — each target's `info:` block in `project.yml`
only lists the *additional* keys to merge in (usage strings, orientations,
etc.), but `xcodegen generate` still regenerates the whole plist from
scratch each run and silently resets any key not listed back to its default
(`1.0` / `1`). Add explicit `CFBundleShortVersionString`/`CFBundleVersion`
entries to the `properties:` block in `project.yml` instead, then
`xcodegen generate`, so the bump survives regeneration.

**WeatherKit removed entirely (2026-09-13).** It never worked in ~34+ real
capture attempts over a week (`WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors
Code=2` / HTTP 401 on Apple's own `signSapSetup` endpoint — see
`WeatherKit-Support-Report.md` for the full investigation, kept for
reference only, not an active issue). Rather than keep chasing a
server-side activation problem on Apple's side, pulled the whole thing out:
`Vantage/Services/WeatherService.swift` deleted, the `WeatherLookup.summary`
call site in `CaptureAndSaveUseCase.swift` removed, the
`com.apple.developer.weatherkit` entitlement/capability removed from
`project.yml` (and regenerated out of `Vantage.entitlements`), and the fake
`weatherSummary` values removed from `ScreenshotSeedData.swift` (App Store
screenshots showing a populated "Weather at Capture" row is what triggered
an Apple App Review Guideline 5.2.5 rejection asking about WeatherKit
attribution — the app never actually surfaced real weather data to any user).
`LocationEntryModel.weatherSummary` and its conditional row in
`EntryDetailView.swift` were left in place (harmless dead field, avoids a
SwiftData/CloudKit schema change) but nothing sets it anymore.
Sun-position/golden-hour (`SunPositionEngine`) is unaffected — that's pure
local math, no WeatherKit dependency, and was never part of this issue.
**Don't re-add WeatherKit without deliberately deciding to re-litigate the
signSapSetup 401** — it was never resolved, just abandoned.

## Testing on a physical device via CLI

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -showdestinations \
  -project Vantage.xcodeproj -scheme Vantage   # find the device's id=...

/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Vantage.xcodeproj -scheme Vantage -configuration Debug \
  -destination "id=<device-id>" -allowProvisioningUpdates build

/Applications/Xcode.app/Contents/Developer/usr/bin/devicectl device install app \
  --device <device-id> \
  ~/Library/Developer/Xcode/DerivedData/Vantage-*/Build/Products/Debug-iphoneos/Vantage.app

/Applications/Xcode.app/Contents/Developer/usr/bin/devicectl device process launch \
  --device <device-id> com.jamespennucci.Vantage
```

Crash logs pulled straight off the device (works regardless of whether the
user has "Share iPhone Analytics" enabled in Settings, unlike the Analytics
Data crash list):

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/devicectl device info files \
  --device <device-id> --domain-type systemCrashLogs
```

## Mac companion app (VantageMac target, added 2026-08-16)

Shares MapView, TripsView, EntryDetailView, and the model/persistence layer with
the iOS app — see `Vantage/Theme/PlatformCompat.swift` for the small shims
(`ToolbarItemPlacement.trailingBar`, `loadPhoto(at:)`) that let those files
compile on both platforms with `#if os(iOS)` guards instead of forked copies.

The target is still named `VantageMac` (scheme, folder, Swift module), but its
`PRODUCT_NAME` is "Photo Point" — macOS shows the product name in the title bar,
menu bar, Dock and Finder, so the built app is `Photo Point.app`.

Mac-only features beyond the shared views: multi-select + bulk actions/right-click
menu (`MacContentView`), drag-and-drop photos onto spots or the map and paste/drop
Google Maps links (`MacSpotDrop`, the Mac's stand-in for the iOS share extension),
right-click map → "Add Spot Here", the Trip Planner window (`TripPlannerView`),
menu-bar commands/shortcuts (`MacCommands`, wired to the main window via a
`focusedSceneValue`), and Help → Photo Point Help (`MacHelpView`, ⌘?) — keep the
help topics in step when Mac features change.
The planner's stop order is saved per trip in this Mac's UserDefaults, deliberately
not synced — syncing it would need a new CloudKit schema field deployed to
production first.

**Mac TestFlight/App Store upload** (first done 2026-09-23, 1.1 (11)): same
archive → export-with-upload flow as iOS, just the `VantageMac` scheme (no
watch-embed patch to revert — that's iOS-only):

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Vantage.xcodeproj -scheme VantageMac -configuration Release \
  -archivePath build/VantageMac.xcarchive -allowProvisioningUpdates archive

/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -exportArchive -archivePath build/VantageMac.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export-mac \
  -allowProvisioningUpdates
```

**CloudKit Production schema must be deployed by hand — found never deployed on
2026-09-24.** Production had *no* record types at all, so every TestFlight/App
Store build (iPhone included) failed every export with "Cannot create new type
CD_… in production schema" and nothing ever synced between devices outside debug
builds. SwiftData never initializes the full schema itself, so after any model
change: run `VANTAGE_INIT_CLOUDKIT_SCHEMA=1 "<debug build>/Photo Point.app/Contents/MacOS/Photo Point"`
(see `VantageMac/CloudKitSchemaInitializer.swift`) to push every type/field to
Development, then CloudKit Console → Deploy Schema Changes… to Production
*before* shipping the build. Production schema is additive-only — fields and
types can't be deleted once deployed.

After the 2026-09-24 deploy, devices that had been failing needed the app
**relaunched** (force-quit on iOS) — after repeated setup failures the mirroring
delegate logs "Never successfully initialized" and stops retrying until the next
launch. Once relaunched, iPhone ↔ Mac sync took seconds. Debug check on the Mac:
`/usr/bin/log show --last 10m --predicate 'process == "Photo Point"' | grep -E 'server message|Received error'`
(plain `log` is a zsh builtin — use the full path).

Debug builds use a separate local store file (`debug.store` vs. release
`default.store`, see `VantageModelContainer`) so running one on a machine that
also has the TestFlight build can't mix Development and Production sync state.

**Debug builds sync to CloudKit's Development database; TestFlight/App Store
builds (including the iPhone's) use Production.** So a locally built Mac app
will *not* see spots from a TestFlight iPhone — test cross-device sync with
TestFlight builds on both ends. The Mac's version/build is independent of iOS
(bump it in the VantageMac `info.properties` block).

**This dev Mac is registered as a Mac Developer device** (done manually via
Xcode's GUI on 2026-08-16 — a *new* Mac device can't be registered purely via
`xcodebuild`/CLI, unlike the iPhone/WeatherKit/iCloud-container cases which
worked fine with `-allowProvisioningUpdates` alone). Build and run it like this:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Vantage.xcodeproj -scheme VantageMac -destination "platform=macOS,arch=arm64" \
  -allowProvisioningUpdates build

open ~/Library/Developer/Xcode/DerivedData/Vantage-*/Build/Products/Debug/"Photo Point.app"
```

Confirmed working end-to-end: launching this shows real `CKFetchRecordZoneChangesOperation`
activity against `iCloud.com.jamespennucci.Vantage` in the system log (`log show
--predicate 'process == "Photo Point"'`), i.e. it's actually pulling synced entries
down from the same container the iPhone writes to.

If this Mac's registration is ever lost (e.g. a new dev Mac, or the device is
removed from the account), fall back to an unsigned local build to at least
verify the code compiles/runs (no working CloudKit sync in this mode):

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Vantage.xcodeproj -scheme VantageMac -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

Photos sync to the Mac too: they live in `PhotoAsset.imageData`, marked
`@Attribute(.externalStorage)`, which CloudKit mirroring stores as a CKAsset
(the old local-file-path `photoReferences` approach that didn't sync is gone).

## Known gotcha (fixed 2026-08-16)

Every WidgetKit view — including Lock Screen `accessoryCircular`/
`accessoryRectangular` widgets — must call `.containerBackground(for: .widget)`
on its root view. Skipping it doesn't crash the extension process (no crash
log, process stays alive) but newer iOS builds silently reject the render and
show the generic "!" / "Please open app" placeholder instead of the widget's
real content. Fixed in `VantageWidget/CaptureWidget.swift`.
