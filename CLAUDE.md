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

## Known gotcha (fixed 2026-08-16)

Every WidgetKit view — including Lock Screen `accessoryCircular`/
`accessoryRectangular` widgets — must call `.containerBackground(for: .widget)`
on its root view. Skipping it doesn't crash the extension process (no crash
log, process stays alive) but newer iOS builds silently reject the render and
show the generic "!" / "Please open app" placeholder instead of the widget's
real content. Fixed in `VantageWidget/CaptureWidget.swift`.
