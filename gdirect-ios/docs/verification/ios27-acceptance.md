# iOS 27 build and background-download acceptance

## Observed in this session

- Host: Linux x86_64; no xcodebuild, xcrun or iOS SDK.
- XcodeBuildMCP list_sims returned `Failed to list simulators: spawn xcrun ENOENT`.
- `scripts/build-ios-core.sh` failed immediately with `iOS core build requires macOS and Xcode.`
- Linux Rust core: 7 tests passed; Release build succeeded without aria2 feature.
- No IPA was generated. Swift compilation, simulator tests and actual background behavior remain unverified.

## Required on Mac / device

- [ ] Build `scripts/build-unsigned-ipa.sh` with Xcode/iOS SDK 27; retain full build log.
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
