# Vantage — working notes for Claude Code sessions

## This machine builds and ships without opening Xcode's GUI

`xcode-select` on this Mac points at the Command Line Tools, not full Xcode, so
`xcodebuild`/`devicectl` must be invoked with the full path:
`/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild` (same dir for `devicectl`).

Project is XcodeGen-managed — `Vantage.xcodeproj` is gitignored and regenerated with:

```bash
xcodegen generate
```

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

**Known unresolved issue:** WeatherKit lookups fail on-device with
`Error Domain=WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors Code=2`
even though the entitlement, `project.yml`, and provisioning are all
confirmed correct (re-verified 2026-08-16 with live console logging).
Sun-position/golden-hour (`SunPositionEngine`) is unaffected — that's pure
local math, no WeatherKit dependency. This smells like a server-side
WeatherKit activation delay on the App ID (can take up to ~48h after first
being enabled), not a code bug — don't re-chase this without new evidence.

Re-verified 2026-08-16 (evening): confirmed via developer.apple.com >
Certificates, Identifiers & Profiles that the WeatherKit capability
checkbox IS enabled on the `com.jamespennucci.Vantage` App ID — not a
missing-capability config issue. Also checked App Store Connect > Business:
all agreements (Paid Apps, Free Apps), the tax form, and the bank account
show Active, nothing pending/unsigned. Notably the **Paid Apps Agreement's
effective date is 2026-08-16 — the same day** the business/tax/banking
setup was completed. Working theory: WeatherKit's server-side activation
may key off full paid-agreement account standing, not just the App ID
capability toggle, so the ~24-48h propagation window likely starts from
that agreement date, not from whenever the entitlement was first added.
If still broken after ~2026-08-18, it's worth actually re-chasing.

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

**This dev Mac is registered as a Mac Developer device** (done manually via
Xcode's GUI on 2026-08-16 — a *new* Mac device can't be registered purely via
`xcodebuild`/CLI, unlike the iPhone/WeatherKit/iCloud-container cases which
worked fine with `-allowProvisioningUpdates` alone). Build and run it like this:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Vantage.xcodeproj -scheme VantageMac -destination "platform=macOS,arch=arm64" \
  -allowProvisioningUpdates build

open ~/Library/Developer/Xcode/DerivedData/Vantage-*/Build/Products/Debug/VantageMac.app
```

Confirmed working end-to-end: launching this shows real `CKFetchRecordZoneChangesOperation`
activity against `iCloud.com.jamespennucci.Vantage` in the system log (`log show
--predicate 'process == "VantageMac"'`), i.e. it's actually pulling synced entries
down from the same container the iPhone writes to.

If this Mac's registration is ever lost (e.g. a new dev Mac, or the device is
removed from the account), fall back to an unsigned local build to at least
verify the code compiles/runs (no working CloudKit sync in this mode):

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Vantage.xcodeproj -scheme VantageMac -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

**Known gap**: `photoReferences` stores local file paths, not CloudKit-backed
data (no `@Attribute(.externalStorage)` / CKAsset), so photos do not sync
between iPhone and Mac yet — only text/location metadata does.

## Known gotcha (fixed 2026-08-16)

Every WidgetKit view — including Lock Screen `accessoryCircular`/
`accessoryRectangular` widgets — must call `.containerBackground(for: .widget)`
on its root view. Skipping it doesn't crash the extension process (no crash
log, process stays alive) but newer iOS builds silently reject the render and
show the generic "!" / "Please open app" placeholder instead of the widget's
real content. Fixed in `VantageWidget/CaptureWidget.swift`.
