#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
simulator_id="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); ids=[x["udid"] for r,ds in d["devices"].items() if "iOS-27" in r for x in ds if x.get("isAvailable") and x["name"].startswith("iPhone")]; print(ids[0] if ids else "")')"
[[ -n "$simulator_id" ]] || { echo "No available iOS 27 iPhone simulator." >&2; exit 1; }
xcodebuild -project ios/GDirect.xcodeproj -scheme GDirect -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" -parallel-testing-enabled NO \
  -resultBundlePath build/GDirectTests.xcresult CODE_SIGNING_ALLOWED=NO test
