# Execution ledger — 2026-10-25-codex-quota
Spec approved by user on 2026-10-25. Execute inline, no further approval pauses.
Ruling: Use a separate standalone build branch in the user's existing Codex iOS repository, because the connector can create branches but not repositories. Main remains untouched.
Ruling: No local Swift or Xcode; run actual Swift tests and iOS compile in macOS Actions, mark device-only validation honestly.
Pre-flight: All UI and storage consume QuotaCore snapshot types; network code must normalize snake_case wire format at one boundary.
Task 1: RED observed in Actions run 40118917772: QuotaSnapshot/DeviceCode/RetryPolicy absent. Implemented core semantics; GREEN queued next.

Task 1: complete — Actions 40119045123 passes all 10 core tests.
Tasks 2–3: implemented; device/simulator compile pending.
Ruling: Keychain entitlements include a private per-target group before the shared grant group; runtime detects the actual signing prefix for resigned IPAs.

Review: independently reviewed by ios_review. Accepted 3 important fixes: preserve overlapping Retry-After, add widget freshness boundary, respect mapped shared Keychain suffix. Also fixing earliest-reset marker and clock-driven retry button states. No critical findings.

Review regression RED: run 40119653388 fails for missing SharedState reducer, SigningGroups resolver and timelineBoundaries. Implemented all four regressions and wired shared reducer into app/widget flow.

Visual QA: first full build 40119469329 succeeded (device+simulator), login and dashboard screenshots inspected. Found unsupported chart.donut tab symbol; replaced with chart.pie.fill. Future build retains device+simulator compilation but skips repeating the same simulator boot capture; UI capture remains available via CAPTURE_UI=1.
