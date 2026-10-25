# Third-party notices

- gdirect: https://github.com/mizorewww/gdirect — GPL-2.0-or-later. Source baseline d260f5d. `core/src/drive.rs`, `native/bridge.cc` and `vendor/*` derive from this project. Full GPL v2 license is in LICENSE.
- aria2 1.37.0: https://github.com/aria2/aria2 — GPL-2.0-or-later with the upstream OpenSSL linking exception where applicable. iOS script uses AppleTLS, not OpenSSL. Pinned archive hash and local patches are included in scripts/build-ios-core.sh and vendor/.
- GoogleSignIn-iOS: https://github.com/google/GoogleSignIn-iOS — Apache-2.0. Resolved using Swift Package Manager.
- Rust dependency versions are recorded in core/Cargo.lock. Upstream licenses must be included with release distribution; this inventory is not a substitute for generated dependency license texts.

Before distributing a binary, bundle complete third-party license texts and provide the complete corresponding source and build material, including modified aria2 sources/patches and exact dependency versions. No release distribution has been performed by this workspace.
