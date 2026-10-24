# Codex Quota Implementation Plan

> For agentic workers: use superpowers:executing-plans to implement task by task.

**Goal:** Deliver an unsigned iPhone IPA with account OAuth, native Liquid Glass and quota/reset widgets.
**Architecture:** Foundation-only QuotaCore decodes real usage and owns time semantics; a SwiftUI app manages OAuth credentials in Keychain. WidgetKit reads an App Group snapshot and shared access token without rotating refresh tokens.
**Tech Stack:** Swift 5 language mode, iOS 26+, SwiftUI, WidgetKit, URLSession, Security, XcodeGen, GitHub macOS Actions.
**Spec:** ../specs/2026-10-25-codex-quota-design.md (approved by user).

## Global Constraints
- Chinese UI, one ChatGPT account, no server deployment, no inference requests.
- Native glass controls and readable usage cards; small and medium widgets with absolute reset dates and countdowns.
- Unknown quota/reset remains unknown; elapsed reset never means 100% without a fresh response.
- Refresh credentials in main app only; tokens never in ordinary preferences or logs.
- An IPA is only complete after a real iPhoneOS build; signing and account login require device validation.

## Review Focus
- Partial schemas and single windows must retain unknowns.
- Expired reset timestamps must yield pending refresh, not replenished quota.
- Cancellation/logout must prevent in-flight data from resurrecting an old session.
- Widget and app concurrent network fetch must not overwrite session or retry state.
- Missing shared entitlements must display actionable signing guidance.

### Task 1: Quota model and tests
Files: Package.swift, Sources/QuotaCore/Quota.swift, Tests/QuotaCoreTests/QuotaTests.swift.
Produces: UsageResponse.snapshot(at:), QuotaSnapshot.nextReset(after:), QuotaWindow.remainingPercent.
- [ ] Write tests for snake_case decoding, missing fields, negative/over-100 usage clamping, expired reset, multiple windows and earliest future reset.
- [ ] Run swift test on macOS to observe RED before model implementation.
- [ ] Implement Codable values with optional quota data and absolute Unix seconds.
- [ ] Run swift test and commit on GREEN.

### Task 2: OAuth and storage
Files: Shared/HTTPClient.swift, Shared/SecureStore.swift, Shared/SnapshotStore.swift, App/OAuthClient.swift, App/QuotaStore.swift.
Consumes: QuotaCore models. Produces: @MainActor QuotaStore login/refresh/logout state and generation-bound persistent snapshots.
- [ ] Implement official device-code request, bounded polling, code exchange and token refresh with sanitized errors.
- [ ] Store refresh credentials in app-only Keychain and widget access grants in App Group Keychain; keep snapshot in App Group file.
- [ ] Gate all completions by session UUID; serialize app refresh; widget never rotates refresh tokens.
- [ ] Add HTTP Retry-After and 401/error behavior; test polling alias and retry parsing in QuotaCore.

### Task 3: App and WidgetKit
Files: App/CodexQuotaApp.swift, App/DashboardView.swift, App/SettingsView.swift, Widget/CodexQuotaWidget.swift, Shared/QuotaViews.swift.
Consumes: models and stores. Produces: Chinese app screens and two widget sizes.
- [ ] Build glass login/account/refresh controls and quota progress cards with dynamic type and accessibility labels.
- [ ] Render reset time with local dates and live timer, using pending state after elapsed reset.
- [ ] Build small/medium timeline entries, foreground deep link, stale data and permission diagnostics.
- [ ] Request 30-minute/relevant reset reloads and persist throttling; never claim exact system scheduling.

### Task 4: Build and delivery
Files: project.yml, Config/*.plist, Config/*.entitlements, .github/workflows/build-ipa.yml, scripts/build.sh, README.md.
- [ ] Generate application + embedded widget extension with matching App Group and Keychain access.
- [ ] Run core tests and iPhoneOS build on a separate branch of zkjjs/codex-ios-v8-jit; do not change main.
- [ ] Build simulator and capture UI for inspection where runner tools permit it.
- [ ] Review whole branch, repair important issues, package unsigned IPA and verify Payload/PlugIns structure.
- [ ] Download artifact, save IPA and source archive, state remaining device-login/signing validation.
