#!/bin/sh
# Archive a development IPA on a Mac with Xcode.
# Usage: DEVELOPMENT_TEAM=ABCDE12345 sh scripts/archive-ipa.sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

if ! command -v xcodebuild >/dev/null 2>&1; then
    printf '%s\n' "需要在安装了 Xcode 的 Mac 上运行，才能导出 IPA。" >&2
    exit 1
fi

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
    printf '%s\n' "请设置 DEVELOPMENT_TEAM，例如：DEVELOPMENT_TEAM=ABCDE12345 sh scripts/archive-ipa.sh" >&2
    exit 1
fi

out="$root/build"
rm -rf "$out"
mkdir -p "$out"

xcodebuild \
    -project ScreenshotLedger.xcodeproj \
    -scheme ScreenshotLedger \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$out/ScreenshotLedger.xcarchive" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Automatic \
    archive

cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>debugging</string>
	<key>teamID</key>
	<string>${DEVELOPMENT_TEAM}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>compileBitcode</key>
	<false/>
</dict>
</plist>
EOF

xcodebuild \
    -exportArchive \
    -archivePath "$out/ScreenshotLedger.xcarchive" \
    -exportPath "$out/ipa" \
    -exportOptionsPlist "$out/ExportOptions.plist"

printf '%s\n' "IPA 在 $out/ipa"
