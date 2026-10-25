# Widget gray-placeholder investigation and 1.0.1

## Device report and scope

The user installed the unsigned 1.0.0 IPA using LCSign. The main App opens. App Groups is unavailable with this signature; the white widget's AppIntent editor contains a manually entered HTTPS server and read-only code. The widget remains gray while the phone is unlocked. The black widget was not tested by the user. Public authenticated backend query returns HTTP200, two windows, and `stale: false`.

The exact physical-device cause is not proven. A server response outside the extension does not establish that WidgetKit launched or completed the provider. Whole-view `privacySensitive()` can redact locked-device content, but by itself does not explain the unlocked report.

## Changes

- Replace two instances of a parameterized Widget type (default `init()` always black) with distinct concrete `BlackQuotaWidget` and `WhiteQuotaWidget` types. Each has a constant kind/color; new V2 kinds invalidate old host configuration. The user must remove/re-add widgets after installation.
- Remove the overbroad whole-view privacy marker. Do not force `.unredacted()` or expose example data as real account quota. System placeholders continue to redact preview percentages.
- Snapshot providers return immediate loading/configuration status without awaiting networking. Timeline queries have a 12-second timeout rather than sharing the main App's 35-second timeout.
- Failed manual requests return actual error entries and retry after 120 seconds. Failed requests with an automatic cached snapshot retain the original 15-minute schedule (minor deferred tuning).
- Add credential-free OSLog lifecycle events for provider begin/success/failure. Do not log server/code/error URLs.
- Share the actual content view with the XCTest host, render black/white images, use on-device Vision OCR to check 31%/60% and error text, and attach images to the test report. Add provider-level manual success/auth-failure/instant-snapshot tests.

## Review and verification

A fresh independent reviewer rejected the initial synthetic test that forced `.placeholder` and then expected content to ignore it. That test was replaced; such a test could verify a rendering workaround but not reproduce the user's WidgetKit lifecycle defect. Current tests preserve system redaction and verify real output/readable error states.

The reviewer's proposed opaque-factory compile blocker was declined with evidence: Swift SE-0360 permits differing opaque types under unconditional availability branches, and Xcode successfully built the new factory in run 40154655473. Simulator and artifact evidence will be recorded after completion. Relevant protocol source: <https://github.com/swiftlang/swift-evolution/blob/main/proposals/0360-opaque-result-types-with-availability.md>.

Backend suite: 8 tests passed. Device App/extension build: passed. Physical LCSign signing and on-device WidgetKit recovery are not yet verified.

## Build branch repair

The prior documentation publication created a tree without a base after per-turn orchestration state was lost. This accidentally omitted product files from the feature branch; the previously downloaded 1.0.0 artifact and deployed backend were unaffected. Regression attempt 40154405700 consequently failed during project generation, before any new tests ran. Restored from verified full tree `e20b3c5b7cd29705f55f43af27aabd4b1280ea95` with explicit base/parent SHAs and checked the remote project spec exists. Restoration also triggered the unrelated existing SideInstaller workflow 40154655454, which failed; no success claim is made for that other product. The separate quota workflow is 40154655473, commit `f1256fa406e1b312576bccf61a3ab7f9a94220d4`.

The original root suite's six missing-upstream-fixture errors remain documented in the previous verification report; the unchanged Rust/V8 product was not rebuilt for this SwiftUI fix.

## Test harness correction

Run 40154655473 built both device targets successfully, but the test target failed to compile: WidgetKit exposes `EnvironmentValues.widgetFamily` as read-only. The content view now receives the actual family explicitly from its widget wrapper; render tests pass `.systemSmall` as an ordinary view input. Tests use SwiftUI's public `.redacted(reason:)` rather than attempting to mutate system environment keys. Corrected run: 40154992454, source `a145813bda38145abef0eb8b0bb63f803ee9a10c`.

## Passed rendering checks and release metadata

Run 40154992454 passed the device build and all 14 Swift XCTest tests, including Vision OCR of actual black/white view renders (31% and 60%), readable error text, manual timeline success/auth failure, and immediate snapshot state. Exported PNG attachments were downloaded and visually inspected; both themes contain legible percentages. These renders use labeled test fixtures, not live account data or a real device WidgetKit host.

The held IPA's bundle plists still contained XcodeGen's default 1.0/build 1 despite updated build settings. It was NOT published as the new release. Added explicit `CFBundleShortVersionString: $(MARKETING_VERSION)` and `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` to both App and extension specs. Release validation run 40155420328, source `f99046088890e86fbbaff314348c84b850aee900`, must yield 1.0.1/build 2 before publication. Runtime code is unchanged from the passing rendering run.

## Delivered unsigned release

The metadata-only rebuild's simulator phase was still running at delivery preparation, so no success claim is made for the complete latest job. To avoid blocking delivery on repeated tests of identical runtime code, reused the verified GitHub artifact 12583319662 from run 40154992454 (14 Swift and 8 backend tests passed). Corrected ONLY the App and extension `Info.plist` version fields in the unsigned archive to 1.0.1/build 2. Kept all ZipInfo modes and every other archived file byte-identical. This is packaging, not a local recompilation; the current project spec also fixes generated version fields for future builds.

Verified both ARM64 executables are byte-identical to the passing GitHub build:

- App executable SHA256: `4b8ed16b5def01fefac7691594f7b7ccd593fb53101154114bceb731b51b93c2`.
- Widget executable SHA256: `0fa4573152536605c3a6274e602d9d348b463c1faec370171eae73d87df9c548`.
- Published IPA SHA256: `bb907a029aa44b35c632bfabb26686fa9b0f68934f2d5dfe5dd121f4c61ff36f`, 269413 bytes.
- Both bundle versions 1.0.1/build 2; compiled BlackV2 and WhiteV2 kind strings verified; executable modes preserved; ZIP CRC check passed; no code-signature directory or deployed access code in package.
- HTTPS download 200 and checksum matched: <https://cfinal.com/codex-quota-download/CodexQuota-1.0.1-unsigned.ipa>.
- Existing API health 200 and unauthorized quota 401 confirmed after nginx reload.

The user must re-sign both targets, install, open the App, remove old widgets and add/configure the new kinds. Actual WidgetKit recovery under the user's LCSign signature remains to be confirmed on their phone; rendering/model tests and executable identity do not substitute for that.
