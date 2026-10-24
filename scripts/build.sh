#!/bin/bash
set -euo pipefail
mkdir -p dist
export HOMEBREW_NO_AUTO_UPDATE=1
# Prefer a stable installed Xcode capable of compiling native Liquid Glass.
if [ -d /Applications/Xcode_26.0.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode_26.0.app/Contents/Developer
fi
xcodebuild -version
xcodebuild -showsdks
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
xcodegen generate
xcodebuild -project CodexQuota.xcodeproj -scheme CodexQuota -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > dist/device-build.log 2>&1 || {
    tail -n 120 dist/device-build.log
    exit 1
  }
app=build/device/Build/Products/Release-iphoneos/CodexQuota.app
widget="$app/PlugIns/CodexQuotaWidget.appex"
test -f "$app/CodexQuota"
test -f "$widget/CodexQuotaWidget"
mkdir -p dist/Payload
cp -R "$app" dist/Payload/
(cd dist && zip -qry CodexQuota-unsigned.ipa Payload)
rm -rf dist/Payload
python3 scripts/verify_ipa.py dist/CodexQuota-unsigned.ipa
shasum -a 256 dist/CodexQuota-unsigned.ipa > dist/SHA256.txt
# Simulator build confirms UI linkage independently of device packaging.
xcodebuild -project CodexQuota.xcodeproj -scheme CodexQuota -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/simulator \
  CODE_SIGNING_ALLOWED=NO build > dist/simulator-build.log 2>&1 || {
    tail -n 100 dist/simulator-build.log
    exit 1
  }
if [ "${CAPTURE_UI:-1}" = "1" ]; then python3 scripts/capture_ui.py; fi
