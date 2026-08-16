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

**This dev Mac is not yet registered as a Mac Developer device**, so
`-allowProvisioningUpdates` can't issue it a real "Mac App Development"
provisioning profile (unlike the iPhone/WeatherKit/iCloud-container cases,
which worked fine via CLI). Registering a *new* Mac device needs to happen once
through Xcode's GUI (open the project, select "My Mac" as the run destination,
let automatic signing register it) — not achievable purely via `xcodebuild`/CLI.
Until that's done, build unsigned for local testing/verification only (this
will not have working CloudKit sync, since entitlements aren't applied):

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Vantage.xcodeproj -scheme VantageMac -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build

open ~/Library/Developer/Xcode/DerivedData/Vantage-*/Build/Products/Debug/VantageMac.app
```

Once this Mac is registered, drop the `CODE_SIGN_IDENTITY`/`CODE_SIGNING_*`
overrides and use `-allowProvisioningUpdates` as normal for a properly signed,
CloudKit-capable build.

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
