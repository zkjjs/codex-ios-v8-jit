# Codex Quota

User-approved intent: an IPA that reads the Codex account already signed in on this server, shows real remaining quota and reset times, and includes black and white widgets. Use GitHub compilation; the user signs the IPA themselves. The latest instruction replaces the earlier App-side OpenAI login requirement.

## Approach

SwiftUI App + WidgetKit extension + a read-only Python service on the current server. Query the installed Codex app-server via `account/rateLimits/read`, retaining its existing authentication. Rejected alternatives: App-side OpenAI device login no longer matches the request; shipping the server's OpenAI credentials to the phone exposes unnecessary account access.

## Product

- Chinese interface, remaining percentages, progress indicators, actual quota windows, local reset dates, live countdowns, last successful refresh, manual refresh, honest offline and expired states.
- iOS 16 minimum; native Liquid Glass on iOS 26 and standard materials on older systems. App UI has calm blue light behind readable glass controls.
- Two widget kinds: black and white, each small/medium. iOS 26 home-screen clear/tinted appearance is controlled by the system. Widget refresh is scheduled, not a promise of continuous network polling.
- The app stores a read-only server access code in Keychain. Shared App Group configuration enables automatic widget setup when the signing profile supports App Groups. iOS 17+ widgets also allow manual server/code configuration when a signing tool cannot preserve App Groups. iOS 16 widgets require working App Groups.
- Default server URL is `https://cfinal.com/codex-quota`; verify TLS and the actual route before considering deployed. Access codes are generated at deployment, excluded from Git, and never embedded into the IPA.

## Backend and safety

Listen on loopback behind the existing nginx HTTPS listener at a new `/codex-quota/` route. Require bearer authorization for quota reads. No login, execution, reset-redemption or OpenAI proxy endpoints. Normalize only quota windows, plan, and update time; never return account IDs, OAuth tokens or reset-credit IDs. Query-only requests must not consume reset credits or make inference calls.

Serialize refreshes, use a 60-second cache and a bounded subprocess timeout. If upstream is temporarily unavailable, return cached data marked stale, preserving its original timestamp. Never fabricate a full quota after a reset. Without cached data return a clear 503.

## Delivery and verification

Use the authorized `zkjjs/codex-ios-v8-jit` repository, separate `codex-quota-ios` branch and `quota-ios/` directory. Add a new workflow without modifying existing products. GitHub macOS runner builds device and simulator targets, runs model tests and packages an unsigned `Payload/CodexQuota.app` including its `.appex`. User re-signs both targets; exact widget availability depends on signature entitlements.

Verify normalization and HTTP authorization/error handling with Python tests; verify Swift decoding and expired-reset behavior with XCTest on macOS. Verify a real authenticated quota request through local and public HTTPS routes without printing access codes. Report separately if Actions or device testing cannot be completed.
