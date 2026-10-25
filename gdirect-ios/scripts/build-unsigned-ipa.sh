#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Cannot build an iOS IPA: macOS and Xcode are required (current host is $(uname -s))." >&2
  exit 1
fi
command -v xcodegen >/dev/null
command -v cargo >/dev/null
if [[ "${GDIRECT_USE_CACHED_CORE:-0}" == 1 ]]; then
  [[ -d build/GDirectCore.xcframework ]] || { echo "Native core cache is missing." >&2; exit 1; }
else
  ./scripts/build-ios-core.sh
fi
(cd ios && xcodegen generate)
xcodebuild -project ios/GDirect.xcodeproj -scheme GDirect -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/GDirect-unsigned.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive
app=build/GDirect-unsigned.xcarchive/Products/Applications/GDirect.app
[[ -d "$app" ]] || { echo "Archive contains no GDirect.app" >&2; exit 1; }
staging="$(mktemp -d "$project_root/build/unsigned-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/Payload"
cp -R "$app" "$staging/Payload/GDirect.app"
(cd "$staging" && ditto -c -k --sequesterRsrc --keepParent Payload "$project_root/build/GDirect-unsigned.ipa")
echo "Created build/GDirect-unsigned.ipa — requires signing before installation."
