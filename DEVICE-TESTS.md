# Device verification and rollback

Run this on the target iPhone 13 Pro Max (iOS 16.0.2, Dopamine roothide) from
a root-capable roothide terminal. Do not substitute build logs for these
device checks. A successful package build or `ldid` inspection alone does not
verify that V8 JIT executed on the phone.

## Prepare and install

Transfer the verified `codex-ios-roothide-0.145.0-4-jit.deb` and the immutable
`codex-ios-roothide-0.145.0-3.zip` to the device. Set their actual, explicit
paths below; do not overwrite either source artifact.

```sh
set -eu

JBROOT="${JB_ROOT:-$(ls -d /var/containers/Bundle/Application/.jbroot-* 2>/dev/null | head -n 1)}"
test -n "$JBROOT" && test -d "$JBROOT"

JIT_DEB="/absolute/path/codex-ios-roothide-0.145.0-4-jit.deb"
ROLLBACK_ZIP="/absolute/path/codex-ios-roothide-0.145.0-3.zip"
test -f "$JIT_DEB"
test -f "$ROLLBACK_ZIP"

CONFIG_DIR="$JBROOT/var/mobile/codex/.codex"
BACKUP_DIR="$JBROOT/var/mobile/codex/backups"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_FILE="$BACKUP_DIR/codex-config-$RUN_ID.tgz"
test -d "$CONFIG_DIR"
umask 077
mkdir -p "$BACKUP_DIR"
tar -C "$CONFIG_DIR" -czf "$BACKUP_FILE" .
tar -tzf "$BACKUP_FILE" >/dev/null
printf 'configuration backup: %s\n' "$BACKUP_FILE"
```

Install with the roothide bootstrap package manager. The command changes the
package only; it does not remove `$CONFIG_DIR`.

```sh
sudo "$JBROOT/usr/bin/apt" install "$JIT_DEB"
codex --version
"$JBROOT/usr/bin/dpkg-query" -W -f '${Version}\n' codex-ios-roothide
```

Record both outputs. `codex --version` must report `0.145.0`; `dpkg-query`
must report the installed package revision `0.145.0-4-jit`. If the terminal
has no `sudo`, run the same `apt` command from its root shell; do not use a
remove/purge command.

## Record device evidence

Create one capture directory for this run, then collect the effective signing
data for both V8-hosting executables. This confirms what is installed, but is
not a JIT-runtime result.

```sh
CAPTURE_DIR="$JBROOT/var/mobile/codex/device-captures/$RUN_ID"
MODULE="$JBROOT/usr/local/lib/node_modules/@openai/codex"
CODEX_BIN="$MODULE/vendor/aarch64-apple-ios/codex/codex"
HOST_BIN="$MODULE/vendor/aarch64-apple-ios/codex/codex-code-mode-host"
LDID="$JBROOT/usr/bin/ldid"
mkdir -p "$CAPTURE_DIR"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$CAPTURE_DIR/device-test-start-utc.txt"
"$LDID" -e "$CODEX_BIN" > "$CAPTURE_DIR/codex.entitlements.plist"
"$LDID" -e "$HOST_BIN" > "$CAPTURE_DIR/codex-code-mode-host.entitlements.plist"
grep -E 'allow-jit|allow-unsigned-executable-memory|dynamic-codesigning' \
  "$CAPTURE_DIR"/*.entitlements.plist
```

Save the following six results in `$CAPTURE_DIR/results.txt`, including the
UTC time, prompt/cell text, response, and pass/fail. Do not mark JIT verified
unless all Code Mode checks complete on this device.

1. **Existing CPA chat.** Start ordinary chat with the existing configured CPA
   provider and model. Send a harmless prompt such as `Reply with CPA chat OK`.
   Pass only if the response arrives through that existing provider.
2. **Simple Code Mode.** Create a Code Mode cell containing `1 + 1` and run it.
   Pass only if the returned value is `2`.
3. **Nested read-only tool.** In a fresh Code Mode cell, ask: `Invoke exactly
   one nested read-only tool to list the current working directory. Do not
   create, modify, or delete anything; report the tool result.` Pass only if
   one nested read-only invocation completes and its result is shown.
4. **Ten lifecycle cycles.** Ten times, create a new Code Mode cell, execute
   `1 + 1`, confirm `2`, then close that cell. Record cycles `1` through `10`;
   all ten must close cleanly.
5. **Restart and persistence.** Fully close the terminal, open a new terminal,
   run `codex`, and confirm the same CPA provider and selected model are still
   available. Do not reconfigure them for this check.
6. **Survival and memory.** Keep a Code Mode cell active and take a process
   sample before execution, during execution, and after closing it:

   ```sh
   ps -ax -o pid,rss,etime,command | grep '[c]odex' | tee -a "$CAPTURE_DIR/process-rss.txt"
   ```

   Pass only if the process remains alive, there is no termination or restart,
   and the RSS samples show no continuing growth across the completed cycle.

## Failure capture

On a V8 initialization, executable-memory, jetsam, or unexpected process
failure, stop testing and preserve the evidence before retrying. iOS crash
reports are outside the roothide prefix; inspect the system paths below and
copy the report whose timestamp matches `device-test-start-utc.txt` and the
failure time.

```sh
CRASH_DIR="/var/mobile/Library/Logs/CrashReporter"
ROOT_CRASH_DIR="/var/root/Library/Logs/CrashReporter"
DIAGNOSTIC_DIR="/var/log/DiagnosticMessages"

for directory in "$CRASH_DIR" "$ROOT_CRASH_DIR" "$DIAGNOSTIC_DIR"; do
  test -d "$directory" || continue
  printf '\n%s\n' "$directory" | tee -a "$CAPTURE_DIR/crash-report-index.txt"
  ls -lt "$directory" | head -n 40 | tee -a "$CAPTURE_DIR/crash-report-index.txt"
done

# After selecting the report with the matching time, replace this explicit path.
CRASH_REPORT="/var/mobile/Library/Logs/CrashReporter/REPLACE-WITH-MATCHING.ips"
test -f "$CRASH_REPORT"
cp -p "$CRASH_REPORT" "$CAPTURE_DIR/"
```

Export the whole `$CAPTURE_DIR` (the two `ldid -e` files, process samples,
results, crash index, matching `.ips`/`.panic`, and UTC marker) with the exact
package version. Attach it to the next entitlement or V8-memory investigation.

## Roll back safely

Rollback reinstalls the stored `0.145.0-3` package and deliberately leaves
`$CONFIG_DIR` untouched. Confirm the backup still exists, extract only the DEB
to a new temporary directory, then install it with `apt`; do not purge Codex
or delete `.codex`.

```sh
test -f "$BACKUP_FILE"
ROLLBACK_TMP="$(mktemp -d /var/tmp/codex-rollback.XXXXXX)"
ROLLBACK_ENTRIES="$(unzip -Z1 "$ROLLBACK_ZIP" | \
  awk -F/ '$NF == "codex-ios-roothide-0.145.0-3.deb" { print }')"
ROLLBACK_COUNT="$(printf '%s\\n' "$ROLLBACK_ENTRIES" | \
  awk 'NF { count++ } END { print count + 0 }')"
if [ "$ROLLBACK_COUNT" -ne 1 ]; then
  printf '%s\\n' "rollback ZIP must contain exactly one codex-ios-roothide-0.145.0-3.deb" >&2
  exit 1
fi
ROLLBACK_ENTRY="$ROLLBACK_ENTRIES"
ROLLBACK_DEB="$ROLLBACK_TMP/codex-ios-roothide-0.145.0-3.deb"
unzip -p "$ROLLBACK_ZIP" "$ROLLBACK_ENTRY" > "$ROLLBACK_DEB"
test -s "$ROLLBACK_DEB"
sudo "$JBROOT/usr/bin/apt" install "$ROLLBACK_DEB"
test -d "$CONFIG_DIR"
test -f "$BACKUP_FILE"
codex --version
"$JBROOT/usr/bin/dpkg-query" -W -f '${Version}\n' codex-ios-roothide | grep -qx '0.145.0-3'
```

Keep the extracted rollback DEB and capture directory until the restored
version, CPA provider, and model configuration have been checked. Remove only
the explicitly created `$ROLLBACK_TMP` after that review if desired.
