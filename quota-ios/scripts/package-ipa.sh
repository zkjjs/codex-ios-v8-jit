#!/bin/bash
set -euo pipefail
app_path="${1:?usage: package-ipa.sh path/to/CodexQuota.app output-directory}"
output_path="${2:?output directory required}"
test -d "$app_path/PlugIns/CodexQuotaWidget.appex"
test -f "$app_path/CodexQuota"
mkdir -p "$output_path"
output_path="$(cd "$output_path" && pwd)"
package_work="$(mktemp -d)"
trap 'rm -rf "$package_work"' EXIT
mkdir "$package_work/Payload"
ditto "$app_path" "$package_work/Payload/CodexQuota.app"
find "$package_work" -name _CodeSignature -type d -prune -exec rm -rf '{}' +
find "$package_work" -name embedded.mobileprovision -type f -delete
(
  cd "$package_work"
  /usr/bin/zip -qry "$output_path/CodexQuota-unsigned.ipa" Payload
)
shasum -a 256 "$output_path/CodexQuota-unsigned.ipa" > "$output_path/SHA256SUMS"
unzip -l "$output_path/CodexQuota-unsigned.ipa" | tail -3
