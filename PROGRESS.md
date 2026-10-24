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

Server-mode change approved by user: use Japanese Ubuntu server 52.195.185.75. Direct SSH from this environment fails before authentication (Network is unreachable). User independently verified actual deviceauth/usercode endpoint responds HTTP 200 JSON on Japanese server. Implement single-owner HTTPS bridge + installer and native pairing; keep deployment status pending until user executes installer.
Server test RED: missing bridge.py observed before implementation; initial ten tests GREEN, added logout-during-throttle regression. Transport test uses a real local Python HTTPS server and self-signed certificate to verify Swift certificate pin handling.

Independent server review: one P2 logout/widget race identified. Replaced reuse of session UUID with new persisted/shared profile identity after logout or server login_required, so pre-logout widget completions are rejected by existing reducer. Added transport profile rotation test; no other material security finding.

Transport investigation: raw TCP and independent Python HTTPS probe both timed out before any Swift TLS challenge, so failure precedes certificate checks. Found HTTPServer.server_bind performs reverse DNS before listen(); added failing getfqdn regression, removed this unnecessary startup dependency and reran all backend tests. Cloud end-to-end rerun pending.

DNS fix verified by cloud TCP and Python HTTPS probes. Swift reached certificate validation and correctly rejected the legacy fixture cert. Apple trusted-server requirements require explicit serverAuth EKU; previous generic self-signed cert lacked it. Updated installer and fixture to serverAuth EKU, digitalSignature/keyEncipherment and CA:FALSE, retaining pin, hostname and validity verification.

Certificate diagnostics confirmed EKU mismatch, then duplicate extension IDs from platform OpenSSL configuration plus addext. Installer and test fixture now use a complete isolated OpenSSL config with a single server extension section, avoiding inherited config and duplicate extensions.
