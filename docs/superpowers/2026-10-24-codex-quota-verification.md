# Codex Quota verification

## Scope

New product: `quota-ios/`, new workflow `.github/workflows/build-codex-quota.yml`. Existing Codex/JIT products remain unchanged. Repository branch: `codex-quota-ios`.

## Evidence recorded during implementation

- Installed CLI: Codex 0.162.1, already signed in with ChatGPT. `initialize` → `account/rateLimits/read` returned live primary (300 minute) and secondary (10080 minute) windows. No inference or credit-reset methods were called.
- Backend suite: `python3 -m unittest discover -s quota-ios/backend/tests -v` — 8 tests passed, covering authorization-before-query, private-field filtering, absent/invalid quota, actual protocol shape, cache timestamps, stale fallback and safe 503 responses.
- Service: `codex-quota.service` active, enabled at boot, zero restarts at deployment verification. Loopback port 18427, existing nginx HTTPS server extended with a separate route.
- Live loopback and public HTTPS checks: `/health` 200; `/v1/quota` without bearer code 401; `/v1/quota` with code 200 and real normalized quota/reset times. HTTPS certificate validation enabled. The generated code is stored outside the repository.
- `git diff --check`, Python compilation, shell syntax, and project/workflow YAML parsing passed.
- Xcode first run `40125035374` found Widget zero-argument initializer and WidgetBundleBuilder conditional errors. Both corrected. Second run `40125264583` passed the unsigned device build (including WidgetKit and native Liquid Glass) and all 8 XCTest cases. Its optional screenshot failed because the selected simulator was shut down after testing; IPA packaging had been sequenced after that step. Corrected the workflow to package immediately after tests, explicitly boot for screenshots, disable parallel test cloning, and make screenshots non-blocking.
- Independent review found two P2 issues: stale/reset timeline entries were limited by requested refresh time, and pending responses could repopulate data after disconnect. Fixed both and added XCTest regressions.

## Final product verification
+
+GitHub Actions run `40125688095`, source commit `aeb6ce309adf904fd027f288c8f134b24f348655`:
+
+- Xcode 26.3 device build: passed (App + WidgetKit extension, minimum iOS 16).
+- Backend: 8 tests passed.
+- iPhone simulator: 8 XCTest tests passed, including disconnect races and delayed widget refresh.
+- Unsigned IPA packaging: passed; launch screenshot captured and visually inspected (no clipped controls on the tested iPhone simulator). Run completed successfully.
+- Artifact `12573691571`: downloaded and unpacked. IPA contains ARM64 `com.zkjjs.codexquota` and `com.zkjjs.codexquota.widget`, both minimum iOS 16.0. No code-signature directories and no deployed access code in the IPA.
+- IPA SHA256: `9cb1d63f10a145232ea45696d8b4387d480d262a72ad8ef9d95017af5295113a`.
+- User delivery files: `/mnt/data/CodexQuota-unsigned.ipa`, `/mnt/data/CodexQuota-connection.txt` (private code, outside Git), `/mnt/data/Launch.png`.
+- Physical-device signing and widget rendering remain for the user's signing/install step; simulator launch and model tests are verified separately.
+
+## Original repository suite

Ran `python3 -m unittest discover -s tests -v`: **43 tests, 37 passed, 6 errors**. These existing tests require fetched/patched upstream trees under `work/`, absent in this checkout. No failures were hidden or reclassified as passes. The errors are:

- `test_code_mode_is_not_stubbed`: missing `work/codex/codex-rs/code-mode/src/lib.rs`.
- `test_ios_compatibility_symbol_exists`: missing `work/codex/codex-rs/cli/src/main.rs`.
- `test_release_profile_keeps_symbols_for_v8_verification`: missing `work/codex/codex-rs/Cargo.toml`.
- `test_rusty_v8_ios_configuration`: missing `work/rusty_v8/build.rs`.
- `test_rusty_v8_ios_gn_keys_are_assigned_once`: missing `work/rusty_v8/build.rs`.
- `test_v8_patch_override_is_exact`: missing `work/codex/codex-rs/Cargo.toml`.

The new quota workflow intentionally tests its isolated product rather than downloading/building the unrelated Rust/V8 product.

## Device verification still required

No claim is made that an arbitrary third-party signature has been verified on a physical device. User signs both the App and embedded extension. App Group entitlement support controls automatic shared configuration; iOS 17+ manual widget configuration is the fallback. iOS 16 widgets require working App Groups. Actual home-screen Liquid Glass appearance follows system rendering mode.
