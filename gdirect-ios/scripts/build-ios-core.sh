#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "iOS core build requires macOS and Xcode." >&2
  exit 1
fi
command -v cargo >/dev/null
command -v xcodebuild >/dev/null
command -v make >/dev/null
aria_version=1.37.0
aria_sha=60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b
mkdir -p "$project_root/build/vendor"
archive="$project_root/build/vendor/aria2-$aria_version.tar.xz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "https://github.com/aria2/aria2/releases/download/release-$aria_version/aria2-$aria_version.tar.xz" -o "$archive"
fi
printf '%s  %s\n' "$aria_sha" "$archive" | shasum -a 256 -c -
for rust_target in aarch64-apple-ios aarch64-apple-ios-sim; do
  rustup target add "$rust_target"
  if [[ "$rust_target" == aarch64-apple-ios ]]; then
    sdk=iphoneos
    clang_target=arm64-apple-ios27.0
  else
    sdk=iphonesimulator
    clang_target=arm64-apple-ios27.0-simulator
  fi
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  slice_root="$project_root/build/$rust_target"
  mkdir -p "$slice_root/source"
  tar -xf "$archive" -C "$slice_root/source"
  source_dir="$slice_root/source/aria2-$aria_version"
  cd "$source_dir"
  patch -p1 --forward < "$project_root/vendor/aria2-$aria_version.patch"
  cp "$project_root/vendor/gdirect_route.h" src/
  export CC="$(xcrun --sdk "$sdk" --find clang)"
  export CXX="$(xcrun --sdk "$sdk" --find clang++)"
  export AR="$(xcrun --sdk "$sdk" --find ar)"
  export RANLIB="$(xcrun --sdk "$sdk" --find ranlib)"
  export CFLAGS="-target $clang_target -isysroot $sdk_path -O2"
  # SecureTransport does not expose the server-only SSLSetDiffieHellmanParams on iOS.
  # aria2 already guards that optional server configuration with this macro.
  export CXXFLAGS="$CFLAGS -std=c++11 -DCIPHER_NO_DHPARAM"
  export LDFLAGS="-target $clang_target -isysroot $sdk_path"
  export am_cv_func_iconv=no ac_cv_header_iconv_h=no
  ./configure --host=aarch64-apple-darwin --prefix="$slice_root/aria2" \
    --enable-libaria2 --enable-static --disable-shared --with-appletls \
    --without-openssl --without-wintls --without-gnutls --without-libnettle \
    --without-libgmp --without-libgcrypt --without-libcares --without-libssh2 \
    --without-sqlite3 --without-libxml2 --without-libexpat --without-libz \
    --disable-bittorrent --disable-metalink --disable-websocket --disable-nls \
    --disable-dependency-tracking
  make -j "${JOBS:-4}" -C src libaria2.la
  make -C src install-libLTLIBRARIES
  mkdir -p "$slice_root/aria2/include/aria2"
  cp src/includes/aria2/aria2.h "$slice_root/aria2/include/aria2/"
  cd "$project_root"
  GDIRECT_ARIA2_PREFIX="$slice_root/aria2" cargo build --manifest-path core/Cargo.toml --locked --release --features aria2 --target "$rust_target"
  # Rust staticlib already bundles the linked native archives.
  cp "core/target/$rust_target/release/libgdirect_core.a" "$slice_root/libGDirectCore.a"
done
cd "$project_root"
if [[ -d build/GDirectCore.xcframework ]]; then
  mv build/GDirectCore.xcframework "build/GDirectCore.previous.$(date +%s).xcframework"
fi
xcodebuild -create-xcframework \
  -library build/aarch64-apple-ios/libGDirectCore.a -headers native \
  -library build/aarch64-apple-ios-sim/libGDirectCore.a -headers native \
  -output build/GDirectCore.xcframework
