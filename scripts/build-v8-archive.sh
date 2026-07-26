#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
out_dir="$root/out/v8"
mkdir -p "$out_dir"
target_dir="$(mktemp -d "$out_dir/rusty-v8-target.XXXXXX")"

cleanup() {
  rm -rf "$target_dir"
}
trap cleanup 0

export CARGO_TARGET_DIR="$target_dir"

V8_FROM_SOURCE=1 PRINT_GN_ARGS=1 \
  cargo build --manifest-path "$root/work/rusty_v8/Cargo.toml" \
  --release --target aarch64-apple-ios -vv

archive_dir="$target_dir/aarch64-apple-ios/release/build"
archive_count="$(find "$archive_dir" -type f -name librusty_v8.a -print | wc -l | tr -d ' ')"
if [ "$archive_count" -ne 1 ]; then
  printf '%s\n' "expected one librusty_v8.a, found $archive_count" >&2
  exit 1
fi
archive="$(find "$archive_dir" -type f -name librusty_v8.a -print)"

cp "$archive" "$out_dir/librusty_v8.a"
checksum="$(shasum -a 256 "$out_dir/librusty_v8.a")"
printf '%s\n' "$checksum" | tee "$out_dir/librusty_v8.a.sha256"
