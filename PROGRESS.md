# Execution ledger — 2026-10-25-codex-quota
Spec approved by user on 2026-10-25. Execute inline, no further approval pauses.
Ruling: Use a separate standalone build branch in the user's existing Codex iOS repository, because the connector can create branches but not repositories. Main remains untouched.
Ruling: No local Swift or Xcode; run actual Swift tests and iOS compile in macOS Actions, mark device-only validation honestly.
Pre-flight: All UI and storage consume QuotaCore snapshot types; network code must normalize snake_case wire format at one boundary.
Task 1: RED observed in Actions run 40118917772: QuotaSnapshot/DeviceCode/RetryPolicy absent. Implemented core semantics; GREEN queued next.
