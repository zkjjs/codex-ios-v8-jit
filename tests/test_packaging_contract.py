from pathlib import Path
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PackagingContractTest(unittest.TestCase):
    def test_roothide_jit_package_metadata_and_code_mode_host(self):
        control = (ROOT / "packaging/control").read_text()
        self.assertIn("Version: 0.145.0-4-jit", control)
        self.assertIn("Architecture: iphoneos-arm64e", control)
        self.assertIn("nodejs22-ios-roothide (>= 22.12.0)", control)

        launcher = (ROOT / "packaging/codex-launcher").read_text()
        self.assertIn(".jbroot-", launcher)
        self.assertIn(
            "codex-code-mode-host", (ROOT / "scripts/package.sh").read_text()
        )

    def test_package_script_selects_privilege_and_verifies_deb_ownership(self):
        package = (ROOT / "scripts/package.sh").read_text()

        self.assertIn('"$(id -u)" -eq 0', package)
        self.assertIn("sudo -n true", package)
        self.assertIn("sudo -n chown -R 501:501", package)
        self.assertIn("requires root or passwordless sudo", package)
        self.assertIn('dpkg-deb --fsys-tarfile "$deb"', package)
        self.assertIn("member.uid != 501 or member.gid != 501", package)

        for path in (
            "var/jb/usr/local/bin/codex",
            "var/jb/usr/local/lib/node_modules/@openai/codex/vendor/aarch64-apple-ios/codex/codex",
            "var/jb/usr/local/lib/node_modules/@openai/codex/vendor/aarch64-apple-ios/codex/codex-code-mode-host",
            "var/jb/usr/local/lib/node_modules/@openai/codex/bin/codex.js",
            "var/jb/usr/local/lib/node_modules/@openai/codex/package.json",
            "var/jb/usr/local/share/entitlements/codex.plist",
        ):
            self.assertIn(f'"{path}"', package)

    def test_package_script_normalizes_before_handoff_and_cleans_with_privilege(self):
        package = (ROOT / "scripts/package.sh").read_text()

        self.assertIn('normalize_tree "$payload"', package)
        normalization = package.index('normalize_tree "$payload"')
        handoff = package.index("\nchown_payload\n", normalization)
        self.assertLess(normalization, handoff)
        self.assertLess(handoff, package.index('dpkg-deb --build "$payload"'))
        self.assertIn('*/codex-ios-package.*)', package)
        self.assertIn('sudo -n rm -rf -- "$1"', package)
        self.assertIn('rm -rf -- "$1"', package)

    def test_jit_entitlements(self):
        data = plistlib.loads((ROOT / "packaging/entitlements.plist").read_bytes())
        self.assertTrue(data["platform-application"])
        self.assertTrue(data["com.apple.private.security.no-container"])
        self.assertTrue(data["com.apple.private.security.no-sandbox"])
        self.assertTrue(data["com.apple.security.cs.allow-jit"])
        self.assertTrue(data["com.apple.security.cs.allow-unsigned-executable-memory"])
        self.assertTrue(data["dynamic-codesigning"])

    def test_sign_script_signs_both_binaries_with_absolute_entitlements_path(self):
        completed, calls = self.run_sign_script()

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual([arguments[0] for arguments in calls], ["-S", "-e", "-S", "-e"])
        self.assertEqual(
            [Path(arguments[-1]).name for arguments in calls],
            ["codex", "codex", "codex-code-mode-host", "codex-code-mode-host"],
        )
        for arguments in calls:
            if arguments[0] == "-S":
                entitlement_path = Path(arguments[1])
                self.assertTrue(entitlement_path.is_absolute())
                self.assertEqual(entitlement_path.name, "entitlements.plist")

    def test_sign_script_rejects_missing_or_false_effective_entitlement(self):
        approved_keys = (
            "platform-application",
            "com.apple.private.security.no-container",
            "com.apple.private.security.no-sandbox",
            "com.apple.security.cs.allow-jit",
            "com.apple.security.cs.allow-unsigned-executable-memory",
            "dynamic-codesigning",
        )
        for key in approved_keys:
            for value in (None, False):
                with self.subTest(key=key, value=value):
                    entitlements = plistlib.loads(
                        (ROOT / "packaging/entitlements.plist").read_bytes()
                    )
                    if value is None:
                        del entitlements[key]
                    else:
                        entitlements[key] = value

                    completed, _ = self.run_sign_script(
                        effective_entitlements=plistlib.dumps(entitlements)
                    )

                    self.assertNotEqual(completed.returncode, 0)
                    self.assertIn(key, completed.stderr)

    def run_sign_script(self, effective_entitlements=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "packaging").mkdir()
            (root / "out/bin").mkdir(parents=True)
            shutil.copy2(ROOT / "scripts/sign-ios.sh", root / "scripts/sign-ios.sh")
            shutil.copy2(
                ROOT / "packaging/entitlements.plist",
                root / "packaging/entitlements.plist",
            )
            for name in ("codex", "codex-code-mode-host"):
                (root / "out/bin" / name).touch()

            effective = effective_entitlements
            if effective is None:
                effective = (root / "packaging/entitlements.plist").read_bytes()
            effective_path = root / "effective-entitlements.plist"
            effective_path.write_bytes(effective)
            fake_bin = root / "fake-bin"
            fake_bin.mkdir()
            fake_ldid = fake_bin / "ldid"
            fake_ldid.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, pathlib, sys\n"
                "arguments = sys.argv[1:]\n"
                "log = pathlib.Path(os.environ['LDID_LOG'])\n"
                "records = json.loads(log.read_text()) if log.exists() else []\n"
                "if arguments[0].startswith('-S'):\n"
                "    records.append(['-S', arguments[0][2:], arguments[1]])\n"
                "elif arguments[0] == '-e':\n"
                "    records.append(['-e', arguments[1]])\n"
                "    sys.stdout.buffer.write(b'ldid effective entitlements\\n')\n"
                "    sys.stdout.buffer.write(pathlib.Path(os.environ['EFFECTIVE_ENTITLEMENTS']).read_bytes())\n"
                "else:\n"
                "    raise SystemExit('unexpected ldid arguments')\n"
                "log.write_text(json.dumps(records))\n"
            )
            fake_ldid.chmod(0o755)
            log = root / "ldid-calls.json"
            environment = os.environ | {
                "EFFECTIVE_ENTITLEMENTS": str(effective_path),
                "LDID_LOG": str(log),
                "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            }
            completed = subprocess.run(
                ["sh", "scripts/sign-ios.sh"],
                cwd=root,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            calls = json.loads(log.read_text()) if log.exists() else []
            return completed, calls


if __name__ == "__main__":
    unittest.main()
