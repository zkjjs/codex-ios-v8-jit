#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mode="${1:-source}"

if [ "$(uname -m)" != "arm64" ]; then
  printf '%s\n' "build-ios.sh requires an ARM64 macOS host" >&2
  exit 1
fi

sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
if [ ! -d "$sdk_path" ]; then
  printf '%s\n' "xcrun did not return an iPhoneOS SDK directory" >&2
  exit 1
fi

rustup target add aarch64-apple-ios
"$root/scripts/fetch-upstream.sh"
"$root/scripts/apply-patches.sh"

export IPHONEOS_DEPLOYMENT_TARGET=16.0
export PYTHON=python3
export CXXSTDLIB=c++

case "$mode" in
  source)
    unset RUSTY_V8_ARCHIVE
    export V8_FROM_SOURCE=1
    ;;
  archive)
    archive="$root/out/v8/librusty_v8.a"
    checksum="$archive.sha256"
    if [ ! -s "$archive" ] || [ ! -f "$checksum" ]; then
      printf '%s\n' "verified rusty_v8 archive is required at $archive" >&2
      exit 1
    fi
    shasum -a 256 -c "$checksum"
    unset V8_FROM_SOURCE
    export RUSTY_V8_ARCHIVE="$archive"
    ;;
  *)
    printf '%s\n' "usage: $0 [source|archive]" >&2
    exit 2
    ;;
esac

cargo build --manifest-path "$root/work/codex/codex-rs/Cargo.toml" \
  --release --target aarch64-apple-ios \
  -p codex-cli -p codex-code-mode-host

mkdir -p "$root/out/bin"
cp "$root/work/codex/codex-rs/target/aarch64-apple-ios/release/codex" \
  "$root/out/bin/codex"
cp "$root/work/codex/codex-rs/target/aarch64-apple-ios/release/codex-code-mode-host" \
  "$root/out/bin/codex-code-mode-host"
