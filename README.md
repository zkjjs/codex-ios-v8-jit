# Codex iOS roothide V8 JIT

This repository builds the `codex-ios-roothide` package for an iPhone 13 Pro
Max running iOS 16.0.2 with Dopamine roothide.

| Item | Value |
| --- | --- |
| Codex | `0.145.0` |
| JIT package | `codex-ios-roothide-0.145.0-5-jit.deb` |
| Rollback input | immutable `codex-ios-roothide-0.145.0-3.zip` |
| Device target | iPhone 13 Pro Max, iOS 16.0.2, Dopamine roothide |

The package retains the existing CPA provider and all data under
`<jbroot>/var/mobile/codex/.codex`. It installs the native `codex` and
`codex-code-mode-host` executables under the active roothide prefix.

Run the build-host validation before transferring a package:

```sh
python3 -m unittest discover -s tests -v
sh scripts/verify-artifacts.sh
```

Build-host checks and `ldid` entitlement output are necessary evidence, but
they do not verify JIT execution. JIT is verified only when the target device
passes the Code Mode checks in [DEVICE-TESTS.md](DEVICE-TESTS.md).

## Install and rollback

Use [DEVICE-TESTS.md](DEVICE-TESTS.md) on the device. It uses the active
`.jbroot-*` path rather than assuming `/var/jb`, backs up `.codex` before an
upgrade, records the six device checks, captures both effective entitlement
sets and any matching iOS crash report, and rolls back without removing user
configuration.
