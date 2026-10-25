# Execution ledger — 2026-10-25-ios-background-download

- Scope: implementation authorized by user; execute in current fresh workspace.
- Ruling: workspace contained only the approved plan and no Git repository. Initialized feature/ios-background-download in place; no existing branch to protect.
- Ruling: real-device acceptance, signing, SDK type-checking and IPA export remain external prerequisites on Linux. Build scripts and acceptance instructions will be delivered; no simulated success claims.
- Pre-flight: tasks 1–4 share DownloadRequest, engine identity, persisted state, token provider and task progress. Define these once in Transfers and keep native engine cancellation independent of the main actor.
- Ruling: continuous background tasks provide system progress UI. Use this first rather than duplicating it with an ActivityKit widget.
- Task 1: in progress; Rust contract tests written before mobile core implementation.
- Core contract RED: cargo test failed with missing resolve/allowed_url/execute/valid_endpoint; implemented core and observed 7 tests pass.
- Linux Release core build: succeeded, default features (aria2 not linked).
- iOS build attempt: scripts/build-ios-core.sh exited 1: macOS and Xcode required. XcodeBuildMCP independently failed with xcrun ENOENT.
- Ruling: added unsigned IPA packaging and a manual macOS Actions workflow so compilation does not require provisioning credentials; neither was run successfully on an Apple host.
- Review: fresh reviewer found four important issues (pause/resume overlap, ineffective background redirect delegate, finalization recovery gap, stale finalization errors). Added cancellation acknowledgment, per-attempt event identity, durable response metadata/staging recovery and generation-gated finalization. Removed ineffective redirect delegate; documented system redirect ownership.
- Swift lifecycle/store tests are written but NOT executed; no Apple SDK available.
- Tasks 1–5 remain partial: native iOS linking, OAuth integration, Swift tests, Release IPA and real-device background acceptance cannot be marked complete from this host.
- GitHub compilation authorized: user allowed any accessible repository.
- Uploaded 40 project files under gdirect-ios/ on isolated branch codex/ios-build/gdirect-20261025 in zkjjs/codex-ios-v8-jit. Original default branch untouched.
- Initial commit 4be0ad35714b587d2b67d057d1718ae8306bc43b.
- Actions run started: https://github.com/zkjjs/codex-ios-v8-jit/actions/runs/40175789609 . Result pending.

- Cloud build succeeded: run 40176502030, commit 44037927fe7bd08b91067fadb6f1d14cda77da57, Xcode 27.1 / iOS 27.1 SDK.
- ARCHIVE SUCCEEDED, unsigned IPA uploaded as artifact 12593185739. Core cloud tests passed. Signing, configured OAuth and background device acceptance remain pending.
