#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
revision="$(awk '$1 == "Version:" { print $2; exit }' "$root/packaging/control")"
package_name="codex-ios-roothide-${revision}"
codex="$root/out/bin/codex"
host="$root/out/bin/codex-code-mode-host"
deb="$root/out/${package_name}.deb"
zip_file="$root/out/${package_name}.zip"
checksums="$root/out/SHA256SUMS"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

for artifact in "$codex" "$host" "$deb" "$zip_file" "$checksums"; do
    if [ ! -f "$artifact" ]; then
        fail "missing artifact: $artifact"
    fi
done

for tool in file otool nm ldid dpkg-deb python3 shasum cmp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "required verification tool is unavailable: $tool"
    fi
done

temporary="$(mktemp -d "${TMPDIR:-/tmp}/codex-ios-verify.XXXXXX")"
cleanup() {
    rm -rf -- "$temporary"
}
trap cleanup 0 HUP INT TERM

for binary in "$codex" "$host"; do
    description="$temporary/$(basename "$binary").file"
    if ! file -b "$binary" > "$description"; then
        fail "could not inspect executable format: $binary"
    fi
    executable_format="$(tr -d '\n' < "$description")"
    if [ "$executable_format" != "Mach-O 64-bit executable arm64" ]; then
        fail "$binary: not a Mach-O 64-bit arm64 executable (thin Mach-O required)"
    fi

    load_commands="$temporary/$(basename "$binary").otool"
    if ! otool -arch arm64 -l "$binary" > "$load_commands"; then
        fail "could not inspect arm64 Mach-O load commands: $binary"
    fi
    if ! awk '
        $1 == "cmd" {
            in_build_version = ($2 == "LC_BUILD_VERSION")
            next
        }
        in_build_version && $1 == "platform" && $2 == "2" {
            found = 1
        }
        END {
            exit(found ? 0 : 1)
        }
    ' "$load_commands"; then
        fail "$binary: missing LC_BUILD_VERSION platform 2"
    fi
done

symbols="$temporary/codex-code-mode-host.nm"
if ! nm "$host" > "$symbols"; then
    fail "could not inspect symbols: $host"
fi
if ! grep -Eq 'v8::|_ZN2v8' "$symbols"; then
    fail "$host: no V8 symbol is present"
fi

for binary in "$codex" "$host"; do
    effective="$temporary/$(basename "$binary").entitlements"
    if ! ldid -e "$binary" > "$effective"; then
        fail "could not read effective entitlements: $binary"
    fi
    if ! python3 - "$effective" "$binary" <<'PY'
from pathlib import Path
import plistlib
import sys


path = Path(sys.argv[1])
binary = sys.argv[2]
raw = path.read_bytes()
try:
    entitlements = plistlib.loads(raw)
except plistlib.InvalidFileException:
    start = raw.find(b"<?xml")
    if start == -1:
        start = raw.find(b"<plist")
    end = raw.rfind(b"</plist>")
    if start == -1 or end == -1 or end < start:
        raise SystemExit(f"{binary}: could not parse effective entitlements")
    entitlements = plistlib.loads(raw[start : end + len(b"</plist>")])

for key in (
    "platform-application",
    "com.apple.private.security.no-container",
    "com.apple.private.security.no-sandbox",
    "com.apple.security.cs.allow-jit",
    "com.apple.security.cs.allow-unsigned-executable-memory",
    "dynamic-codesigning",
):
    if entitlements.get(key) is not True:
        raise SystemExit(f"{binary}: missing entitlement: {key}")
PY
    then
        exit 1
    fi
done

check_field() {
    field="$1"
    expected="$2"
    actual="$(dpkg-deb -f "$deb" "$field")" ||
        fail "could not read DEB field: $field"
    if [ "$actual" != "$expected" ]; then
        fail "unexpected DEB $field: expected $expected, got $actual"
    fi
}

check_field Package codex-ios-roothide
check_field Version "$revision"
check_field Architecture iphoneos-arm64e

data_tar="$temporary/data.tar"
if ! dpkg-deb --fsys-tarfile "$deb" > "$data_tar"; then
    fail "could not read DEB payload archive: $deb"
fi
if ! python3 - "$data_tar" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile


vendor = (
    "var/jb/usr/local/lib/node_modules/@openai/codex/"
    "vendor/aarch64-apple-ios/codex"
)
expected_files = {
    "var/jb/usr/local/bin/codex": 0o755,
    f"{vendor}/codex": 0o755,
    f"{vendor}/codex-code-mode-host": 0o755,
    "var/jb/usr/local/lib/node_modules/@openai/codex/bin/codex.js": 0o755,
    "var/jb/usr/local/lib/node_modules/@openai/codex/package.json": 0o644,
    "var/jb/usr/local/share/entitlements/codex.plist": 0o644,
}
expected_directories = {
    str(parent)
    for name in expected_files
    for parent in PurePosixPath(name).parents
    if str(parent) != "."
}
expected = expected_directories | set(expected_files)

with tarfile.open(sys.argv[1], "r:*") as archive:
    members = {}
    for member in archive:
        name = member.name
        while name.startswith("./"):
            name = name[2:]
        name = str(PurePosixPath(name))
        if name == ".":
            continue
        if name in members:
            raise SystemExit(f"DEB payload contains duplicate path: {name}")
        members[name] = member

missing = sorted(expected - set(members))
if missing:
    raise SystemExit("DEB payload is missing: " + ", ".join(missing))
unexpected = sorted(set(members) - expected)
if unexpected:
    raise SystemExit("unexpected DEB payload entry: " + ", ".join(unexpected))

for name in sorted(expected):
    member = members[name]
    if name in expected_directories:
        if not member.isdir():
            raise SystemExit(f"{name}: expected a directory")
        expected_mode = 0o755
    else:
        if not member.isfile():
            raise SystemExit(f"{name}: expected a regular file")
        expected_mode = expected_files[name]
    if member.uid != 501 or member.gid != 501:
        raise SystemExit(
            f"{name}: expected owner/group 501:501, got {member.uid}:{member.gid}"
        )
    actual_mode = member.mode & 0o7777
    if actual_mode != expected_mode:
        raise SystemExit(
            f"{name}: expected mode {expected_mode:04o}, got {actual_mode:04o}"
        )
PY
then
    exit 1
fi

unpacked="$temporary/deb"
mkdir -p "$unpacked"
if ! dpkg-deb -x "$deb" "$unpacked"; then
    fail "could not unpack DEB: $deb"
fi

vendor="$unpacked/var/jb/usr/local/lib/node_modules/@openai/codex/vendor/aarch64-apple-ios/codex"
if ! cmp -s "$codex" "$vendor/codex"; then
    fail "packaged codex binary differs from signed build output"
fi
if ! cmp -s "$host" "$vendor/codex-code-mode-host"; then
    fail "packaged Code Mode host differs from signed build output"
fi

if ! python3 - "$codex" "$host" "$unpacked" <<'PY'
from pathlib import Path
import sys


forbidden = b"code mode is unavailable in this iOS build"
paths = [Path(sys.argv[1]), Path(sys.argv[2])]
paths.extend(path for path in Path(sys.argv[3]).rglob("*") if path.is_file())
for path in paths:
    if forbidden in path.read_bytes():
        raise SystemExit(f"forbidden iOS Code Mode stub found in {path}")
PY
then
    exit 1
fi

zip_dir="$temporary/zip"
mkdir -p "$zip_dir"
if ! python3 - "$zip_file" "$zip_dir" "$package_name" <<'PY'
from pathlib import Path
import sys
import zipfile


archive_path = Path(sys.argv[1])
destination = Path(sys.argv[2])
package_name = sys.argv[3]
expected = {
    f"{package_name}.deb",
    "SHA256SUMS",
    "UPSTREAM_CODEX_COMMIT",
    "UPSTREAM_CODEX_VERSION",
    "UPSTREAM_RUSTY_V8_COMMIT",
    "UPSTREAM_RUSTY_V8_VERSION",
    "patches/codex-ios-roothide.patch",
    "patches/rusty-v8-ios-jit.patch",
}
with zipfile.ZipFile(archive_path) as archive:
    actual = {name for name in archive.namelist() if not name.endswith("/")}
    if actual != expected or len(archive.namelist()) != len(expected):
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise SystemExit(
            f"unexpected ZIP inventory; missing={missing}, extra={extra}"
        )
    archive.extractall(destination)
PY
then
    exit 1
fi

if ! cmp -s "$checksums" "$zip_dir/SHA256SUMS"; then
    fail "top-level and ZIP SHA256SUMS differ"
fi
if ! python3 - "$zip_dir/SHA256SUMS" "$package_name.deb" <<'PY'
from pathlib import Path
import re
import sys


lines = Path(sys.argv[1]).read_text().splitlines()
expected_name = sys.argv[2]
if len(lines) != 1:
    raise SystemExit(f"SHA256SUMS must name exactly {expected_name}")
match = re.fullmatch(r"[0-9A-Fa-f]{64} [ *](.+)", lines[0])
if match is None or match.group(1) != expected_name:
    raise SystemExit(f"SHA256SUMS must name exactly {expected_name}")
PY
then
    exit 1
fi
if ! cmp -s "$deb" "$zip_dir/$package_name.deb"; then
    fail "top-level and ZIP DEB artifacts differ"
fi
if ! (
    cd "$zip_dir"
    shasum -a 256 -c SHA256SUMS
) > "$temporary/shasum.log" 2>&1; then
    cat "$temporary/shasum.log" >&2
    fail "ZIP checksum validation failed"
fi

printf '%s\n' "verified iOS V8 JIT artifacts: $deb $zip_file"
