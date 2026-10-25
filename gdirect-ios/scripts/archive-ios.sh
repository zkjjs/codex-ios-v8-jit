#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "IPA export requires macOS, Xcode and signing configuration." >&2
  exit 1
fi
: "${GDIRECT_TEAM_ID:?Set GDIRECT_TEAM_ID to your Apple development team}"
: "${GDIRECT_EXPORT_OPTIONS:?Set GDIRECT_EXPORT_OPTIONS to an exportOptions plist}"
command -v xcodegen >/dev/null
./scripts/build-ios-core.sh
(cd ios && xcodegen generate)
xcodebuild -project ios/GDirect.xcodeproj -scheme GDirect -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/GDirect.xcarchive \
  DEVELOPMENT_TEAM="$GDIRECT_TEAM_ID" archive
xcodebuild -exportArchive -archivePath build/GDirect.xcarchive \
  -exportPath build/ipa -exportOptionsPlist "$GDIRECT_EXPORT_OPTIONS"
