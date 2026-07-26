#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(tr -d '\n' < "$root/UPSTREAM_CODEX_VERSION")"
revision="${version}-4-jit"
package_name="codex-ios-roothide-${revision}"
out_dir="$root/out"
deb="$out_dir/${package_name}.deb"
zip_file="$out_dir/${package_name}.zip"
checksums="$out_dir/SHA256SUMS"

require_file() {
    if [ ! -f "$1" ]; then
        printf '%s\n' "missing required file: $1" >&2
        exit 1
    fi
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1"
    else
        shasum -a 256 "$1"
    fi
}

for tool in dpkg-deb python3 zip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf '%s\n' "required tool is unavailable: $tool" >&2
        exit 1
    fi
done

for source in \
    "$root/packaging/control" \
    "$root/packaging/postinst" \
    "$root/packaging/codex-launcher" \
    "$root/packaging/entitlements.plist" \
    "$root/out/bin/codex" \
    "$root/out/bin/codex-code-mode-host" \
    "$root/work/codex/codex-cli/bin/codex.js" \
    "$root/work/codex/codex-cli/scripts/build_npm_package.py" \
    "$root/patches/codex-ios-roothide.patch" \
    "$root/patches/rusty-v8-ios-jit.patch" \
    "$root/UPSTREAM_CODEX_COMMIT" \
    "$root/UPSTREAM_CODEX_VERSION" \
    "$root/UPSTREAM_RUSTY_V8_COMMIT" \
    "$root/UPSTREAM_RUSTY_V8_VERSION"
do
    require_file "$source"
done

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    SOURCE_DATE_EPOCH="$(git -C "$root" log -1 --format=%ct)"
fi
export SOURCE_DATE_EPOCH

umask 022
if [ "$(id -u)" -eq 0 ]; then
    chown_payload() {
        chown -R 501:501 "$payload/var"
    }
    cleanup_stage() {
        rm -rf -- "$1"
    }
elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    chown_payload() {
        sudo -n chown -R 501:501 "$payload/var"
    }
    cleanup_stage() {
        sudo -n rm -rf -- "$1"
    }
else
    printf '%s\n' "packaging requires root or passwordless sudo to stage 501:501 payload ownership" >&2
    exit 1
fi

normalize_tree() {
    python3 - "$1" "$SOURCE_DATE_EPOCH" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
timestamp = int(sys.argv[2])
for path in sorted(root.rglob("*"), reverse=True):
    os.utime(path, (timestamp, timestamp), follow_symlinks=False)
os.utime(root, (timestamp, timestamp), follow_symlinks=False)
PY
}

stage="$(mktemp -d "${TMPDIR:-/tmp}/codex-ios-package.XXXXXX")"
cleanup() {
    case "$stage" in
        */codex-ios-package.*)
            cleanup_stage "$stage"
            ;;
        *)
            printf '%s\n' "refusing to clean unexpected staging path: $stage" >&2
            return 1
            ;;
    esac
}
trap cleanup 0 HUP INT TERM

payload="$stage/root"
module="$payload/var/jb/usr/local/lib/node_modules/@openai/codex"
vendor="$module/vendor/aarch64-apple-ios/codex"
npm_stage="$stage/npm"
release="$stage/release"

verify_deb_ownership() {
    data_tar="$stage/data.tar"
    dpkg-deb --fsys-tarfile "$deb" > "$data_tar"
    python3 - "$data_tar" \
        "var/jb/usr/local/bin/codex" \
        "var/jb/usr/local/lib/node_modules/@openai/codex/vendor/aarch64-apple-ios/codex/codex" \
        "var/jb/usr/local/lib/node_modules/@openai/codex/vendor/aarch64-apple-ios/codex/codex-code-mode-host" \
        "var/jb/usr/local/lib/node_modules/@openai/codex/bin/codex.js" \
        "var/jb/usr/local/lib/node_modules/@openai/codex/package.json" \
        "var/jb/usr/local/share/entitlements/codex.plist" <<'PY'
import sys
import tarfile

archive_path = sys.argv[1]
required = set(sys.argv[2:])
found = set()

with tarfile.open(archive_path, "r:*") as archive:
    for member in archive:
        name = member.name.lstrip("./")
        if name not in required:
            continue
        if member.uid != 501 or member.gid != 501:
            raise SystemExit(
                f"{name}: expected owner/group 501:501, got {member.uid}:{member.gid}"
            )
        found.add(name)

missing = sorted(required - found)
if missing:
    raise SystemExit("DEB payload is missing required ownership entries: " + ", ".join(missing))
PY
}

mkdir -p \
    "$payload/DEBIAN" \
    "$payload/var/jb/usr/local/bin" \
    "$vendor" \
    "$module/bin" \
    "$payload/var/jb/usr/local/share/entitlements" \
    "$release/patches"

install -m 644 "$root/packaging/control" "$payload/DEBIAN/control"
install -m 755 "$root/packaging/postinst" "$payload/DEBIAN/postinst"
install -m 755 "$root/packaging/codex-launcher" "$payload/var/jb/usr/local/bin/codex"
install -m 755 "$root/out/bin/codex" "$vendor/codex"
install -m 755 "$root/out/bin/codex-code-mode-host" "$vendor/codex-code-mode-host"
install -m 644 "$root/packaging/entitlements.plist" \
    "$payload/var/jb/usr/local/share/entitlements/codex.plist"

python3 "$root/work/codex/codex-cli/scripts/build_npm_package.py" \
    --package codex --version "$version" --staging-dir "$npm_stage" >/dev/null
install -m 755 "$npm_stage/bin/codex.js" "$module/bin/codex.js"
install -m 644 "$npm_stage/package.json" "$module/package.json"

# Normalize all archive input timestamps so repeated builds from the same
# inputs generate identical payload archives before mobile ownership is handed
# off. This keeps unprivileged macOS runners from mutating 501-owned files.
normalize_tree "$payload"

# Package payload files are owned by mobile; control data remains root-owned.
chown_payload

mkdir -p "$out_dir"
dpkg-deb --build "$payload" "$deb"
verify_deb_ownership

install -m 644 "$deb" "$release/$package_name.deb"
for source in \
    "$root/patches/codex-ios-roothide.patch" \
    "$root/patches/rusty-v8-ios-jit.patch"
do
    install -m 644 "$source" "$release/patches/$(basename "$source")"
done
for source in \
    "$root/UPSTREAM_CODEX_COMMIT" \
    "$root/UPSTREAM_CODEX_VERSION" \
    "$root/UPSTREAM_RUSTY_V8_COMMIT" \
    "$root/UPSTREAM_RUSTY_V8_VERSION"
do
    install -m 644 "$source" "$release/$(basename "$source")"
done

(
    cd "$release"
    sha256 "$package_name.deb" > SHA256SUMS
)
install -m 644 "$release/SHA256SUMS" "$checksums"

normalize_tree "$release"

(
    cd "$release"
    zip -X -q "$zip_file" \
        "$package_name.deb" \
        SHA256SUMS \
        UPSTREAM_CODEX_COMMIT \
        UPSTREAM_CODEX_VERSION \
        UPSTREAM_RUSTY_V8_COMMIT \
        UPSTREAM_RUSTY_V8_VERSION \
        patches/codex-ios-roothide.patch \
        patches/rusty-v8-ios-jit.patch
)

printf '%s\n' "built $deb"
printf '%s\n' "built $zip_file"
