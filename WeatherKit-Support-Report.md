# WeatherKit Authorization Failure — Apple Developer Support Report

## Summary
WeatherKit requests from my app **Vantage** (`com.jamespennucci.Vantage`, Team ID `PG3PKC873L`) have never once succeeded, from first use on 2026-08-18 through today (2026-08-21) — despite the WeatherKit capability being confirmed enabled on the App ID, a correctly signed entitlement in every build, and the account's Paid Apps Agreement showing Active (effective 2026-08-16). Apple's own first-party WeatherKit consumer (the system Weather widget) succeeds on the same device at the same time, so this looks specific to this app/account's WeatherKit API authorization rather than a device, network, or general WeatherKit availability issue.

## What's failing
Every call to `WeatherKit.WeatherService.shared.weather(for:)` fails with:
```
Error Domain=WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors Code=2
```

Device console logging traced this to its root cause: `com.apple.weatherkit.authservice` attempts to sign a WeatherKit JWT by calling Apple's own endpoint `https://fpinit.itunes.apple.com/v1/signSapSetup`, which returns **HTTP 401 Unauthorized**. That 401 is what produces the JWTAuthenticatorServiceListener error the app sees.

Captured request identifiers from a reproduction today (2026-08-21, ~10:27am ET) for tracing server-side:
- Request ID: `8BF8584D-2090-4415-A015-FB7B6C85E6D1` (WeatherDaemon request)
- Task ID: `E609EB84-F69C-4225-B636-8F3C846DC4C4` (the 401 response on `signSapSetup`)

## What's confirmed correct (ruled out as the cause)
- **Entitlement**: `com.apple.developer.weatherkit = true` is present and correctly signed in the actual built app, verified directly via `codesign -d --entitlements`.
- **App ID capability**: WeatherKit is shown enabled on the `com.jamespennucci.Vantage` App ID in Certificates, Identifiers & Profiles.
- **Account standing**: Paid Apps Agreement, tax form, and bank account all show Active in App Store Connect.
- **Not a device/network/WeatherKit-availability issue**: at the same moment as a failed Vantage request today, the system Weather widget (`ClockPosterExtension`) on the identical device successfully completed its own WeatherKit fetch and decoded data.
- **Not a fresh provisioning-profile regression**: reproduced consistently across multiple rebuilds and profile regenerations over several days.
- **Not local network/router interference**: the failing request completes a full TLS/HTTP2 handshake to a legitimate Apple IP and receives a well-formed 401 (not a timeout, DNS failure, or connection refusal — the shape of a request that reached Apple and was deliberately rejected, not one that was blocked in transit). Confirmed by reproducing the identical failure on cellular data, bypassing the home network entirely.

## Timeline
- **2026-08-16**: WeatherKit entitlement added; capability confirmed enabled on the App ID; Paid Apps Agreement became effective the same day. First failures observed — attributed at the time to a possible post-agreement propagation delay (~24–48h is typical).
- **2026-08-18 through 2026-08-21**: Continued testing (34+ real capture attempts across multiple days) — zero successful weather fetches in that entire window, confirmed via the app's own synced data store, not just spot-checking.
- **2026-08-21**: Reproduced again with full console logging, isolating the failure to the HTTP 401 on `signSapSetup` described above.

## Question for Apple
Given the entitlement, App ID capability, and account/agreement standing all show correct and Active, why is this app's WeatherKit JWT signing request being rejected with HTTP 401 by Apple's own `signSapSetup` endpoint? Is there an additional account-level authorization step for WeatherKit that hasn't completed, or an issue specific to this App ID/Team ID that needs to be cleared on Apple's side?

## Environment
- App: Vantage, `com.jamespennucci.Vantage`
- Team ID: `PG3PKC873L`
- Build/signing: Debug and Release, Automatic signing, Apple Development / Apple Distribution
- Device: physical iPhone, current iOS
