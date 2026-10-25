#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
codex_commit="$(tr -d '\n' < "$root/UPSTREAM_CODEX_COMMIT")"
rusty_v8_commit="$(tr -d '\n' < "$root/UPSTREAM_RUSTY_V8_COMMIT")"

git -C "$root/work/codex" reset --hard "$codex_commit"
git -C "$root/work/rusty_v8" reset --hard "$rusty_v8_commit"

git -C "$root/work/codex" apply --whitespace=error "$root/patches/codex-ios-roothide.patch"

if [ -f "$root/patches/rusty-v8-ios-jit.patch" ]; then
  git -C "$root/work/rusty_v8" apply --whitespace=error "$root/patches/rusty-v8-ios-jit.patch"
fi
