#!/bin/sh
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$root/work"
test -d "$root/work/codex/.git" ||
  git clone --filter=blob:none https://github.com/openai/codex.git "$root/work/codex"
git -C "$root/work/codex" fetch --depth 1 origin 25af12f7e61572b0bc18ddb1008be543b91519b0
git -C "$root/work/codex" checkout --detach 25af12f7e61572b0bc18ddb1008be543b91519b0
test "$(git -C "$root/work/codex" rev-parse HEAD)" = \
  "25af12f7e61572b0bc18ddb1008be543b91519b0"

test -d "$root/work/rusty_v8/.git" ||
  git clone --filter=blob:none https://github.com/denoland/rusty_v8.git "$root/work/rusty_v8"
git -C "$root/work/rusty_v8" fetch --depth 1 origin 5d0e31ea6bf67f4559faa759b91e22bc3f1cd696
git -C "$root/work/rusty_v8" checkout --detach 5d0e31ea6bf67f4559faa759b91e22bc3f1cd696
test "$(git -C "$root/work/rusty_v8" rev-parse HEAD)" = \
  "5d0e31ea6bf67f4559faa759b91e22bc3f1cd696"
