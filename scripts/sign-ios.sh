#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
entitlements="$root/packaging/entitlements.plist"

if [ ! -f "$entitlements" ]; then
  printf '%s\n' "missing entitlement plist: $entitlements" >&2
  exit 1
fi

for binary in "$root/out/bin/codex" "$root/out/bin/codex-code-mode-host"; do
  if [ ! -f "$binary" ]; then
    printf '%s\n' "missing executable: $binary" >&2
    exit 1
  fi

  ldid "-S$entitlements" "$binary"

  effective_entitlements="$(mktemp "${TMPDIR:-/tmp}/codex-entitlements.XXXXXX")"
  if ! ldid -e "$binary" > "$effective_entitlements"; then
    rm -f "$effective_entitlements"
    printf '%s\n' "could not read effective entitlements: $binary" >&2
    exit 1
  fi

  if ! python3 - "$effective_entitlements" "$binary" <<'PY'
from pathlib import Path
import plistlib
import sys


def load_entitlements(raw):
    try:
        return plistlib.loads(raw)
    except plistlib.InvalidFileException:
        start = raw.find(b"<?xml")
        if start == -1:
            start = raw.find(b"<plist")
        end = raw.rfind(b"</plist>")
        if start == -1 or end == -1 or end < start:
            raise
        return plistlib.loads(raw[start : end + len(b"</plist>")])


path = Path(sys.argv[1])
binary = sys.argv[2]
try:
    entitlements = load_entitlements(path.read_bytes())
except (OSError, plistlib.InvalidFileException, ValueError) as error:
    raise SystemExit(f"{binary}: could not parse effective entitlements: {error}")

for key in (
    "platform-application",
    "com.apple.private.security.no-container",
    "com.apple.private.security.no-sandbox",
    "com.apple.security.cs.allow-jit",
    "com.apple.security.cs.allow-unsigned-executable-memory",
    "dynamic-codesigning",
):
    if entitlements.get(key) is not True:
        raise SystemExit(f"{binary}: missing required JIT entitlement: {key}")
PY
  then
    rm -f "$effective_entitlements"
    exit 1
  fi
  rm -f "$effective_entitlements"
done
