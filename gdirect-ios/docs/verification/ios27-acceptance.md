# iOS 27 build and background-download acceptance

## Observed in this session

- Host: Linux x86_64; no xcodebuild, xcrun or iOS SDK.
- XcodeBuildMCP list_sims returned `Failed to list simulators: spawn xcrun ENOENT`.
- `scripts/build-ios-core.sh` failed immediately with `iOS core build requires macOS and Xcode.`
- Linux Rust core: 7 tests passed; Release build succeeded without aria2 feature.
- Subsequently built in GitHub Actions using Xcode 27.1 / iOS 27.1 SDK: Release archive succeeded.
- Source commit: 44037927fe7bd08b91067fadb6f1d14cda77da57 on zkjjs/codex-ios-v8-jit, branch codex/ios-build/gdirect-20261025.
- Run: https://github.com/zkjjs/codex-ios-v8-jit/actions/runs/40176502030
- IPA artifact: GDirect-unsigned-ipa, ID 12593185739, artifact ZIP 2,947,125 bytes, SHA-256 af06ab688ebc8dd68bbd49f9b47a4d5224a2058a9851496cd4016640fc8fa4d1.
- Compiler log confirms ARCHIVE SUCCEEDED and creation of build/GDirect-unsigned.ipa.
- Fixed AppleTLS server-only DH configuration, a Swift variable redeclaration, and migrated to iOS 27 asynchronous task submission based on compiler output.
- Simulator tests, actual background behavior, OAuth configuration and installation signing remain unverified/unconfigured.

## Required on Mac / device

- [x] Build `scripts/build-unsigned-ipa.sh` with Xcode/iOS SDK 27; full build log preserved as Actions artifact ios-build-log.
- [ ] Run GDirectTests on an available arm64 iOS 27 simulator; record Xcode test result bundle.
- [ ] Configure OAuth and signing; install a Release IPA on iOS 27.
- [ ] Start a large ordinary download, background and lock for 30 minutes or until complete; verify size/hash and notification.
- [ ] Repeat with fixed IP on a network where ordinary Google access fails; record selected IP, actual target and task progress.
- [ ] Test task queueing, task rejection, cancellation in system progress UI, low-power mode and system expiration.
- [ ] Test pause/resume, process termination, force quit and relaunch. Do not claim continuous execution after user force quit.
- [ ] Test Wi-Fi/cellular switching, IPv6-only networks and active VPN/TUN routing.
- [ ] Test expired/revoked OAuth tokens, account sign-out and files requiring resourceKey.
- [ ] Test HTML confirmation, quota/permission error, HTTP error, disk full, MD5 mismatch and same-name files.
- [ ] Deny notification permission; verify downloads still work.
- [ ] Confirm lock-screen file protection allows previously authorized tasks to continue.

The checkboxes are acceptance requirements, not completed results.

## Downloaded artifact inspection

- Downloaded Actions artifact ZIP and verified its SHA-256 against GitHub's artifact digest.
- Extracted build/GDirect-unsigned.ipa: 2,977,942 bytes.
- IPA SHA-256: 966e51b171cc216ebd0d64570fe31de0c73aef4bdfb386ffe8352dea706808d9.
- Contains Payload/GDirect.app, 109 ZIP entries, arm64 Mach-O executable, bundle org.gdirect.ios, MinimumOSVersion 27.0.
- This verifies packaging and architecture, not installation or runtime background execution.
