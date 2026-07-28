import hashlib
import io
import os
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

import yaml


ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.145.0-5-jit"
PACKAGE_NAME = f"codex-ios-roothide-{VERSION}"
DEB_NAME = f"{PACKAGE_NAME}.deb"
ZIP_NAME = f"{PACKAGE_NAME}.zip"
VENDOR = (
    "var/jb/usr/local/lib/node_modules/@openai/codex/"
    "vendor/aarch64-apple-ios/codex"
)
PAYLOAD_MODES = {
    "var/jb/usr/local/bin/codex": 0o755,
    f"{VENDOR}/codex": 0o755,
    f"{VENDOR}/codex-code-mode-host": 0o755,
    "var/jb/usr/local/lib/node_modules/@openai/codex/bin/codex.js": 0o755,
    "var/jb/usr/local/lib/node_modules/@openai/codex/package.json": 0o644,
    "var/jb/usr/local/share/entitlements/codex.plist": 0o644,
}
REQUIRED_ENTITLEMENTS = (
    "platform-application",
    "com.apple.private.security.no-container",
    "com.apple.private.security.no-sandbox",
    "com.apple.security.cs.allow-jit",
    "com.apple.security.cs.allow-unsigned-executable-memory",
    "dynamic-codesigning",
)
ZIP_INVENTORY = (
    DEB_NAME,
    "SHA256SUMS",
    "UPSTREAM_CODEX_COMMIT",
    "UPSTREAM_CODEX_VERSION",
    "UPSTREAM_RUSTY_V8_COMMIT",
    "UPSTREAM_RUSTY_V8_VERSION",
    "patches/codex-ios-roothide.patch",
    "patches/rusty-v8-ios-jit.patch",
)


class ArtifactFixture:
    def __init__(self, directory: str):
        self.root = Path(directory)
        (self.root / "scripts").mkdir()
        (self.root / "out/bin").mkdir(parents=True)
        (self.root / "fake-bin").mkdir()
        source = ROOT / "scripts/verify-artifacts.sh"
        destination = self.root / "scripts/verify-artifacts.sh"
        if source.exists():
            shutil.copy2(source, destination)
        else:
            destination.write_text("#!/bin/sh\nexit 0\n")

        (self.root / "UPSTREAM_CODEX_VERSION").write_text("0.145.0\n")
        self.binaries = {
            "codex": b"Mach-O fixture: codex\n",
            "codex-code-mode-host": b"Mach-O fixture: V8 host\n",
        }
        self.platforms = {"codex": "2", "codex-code-mode-host": "2"}
        self.default_platforms = {
            "codex": "2",
            "codex-code-mode-host": "2",
        }
        self.architectures = {
            "codex": "Mach-O 64-bit executable arm64",
            "codex-code-mode-host": "Mach-O 64-bit executable arm64",
        }
        self.host_symbols = "_ZN2v87Isolate3NewEv\n"
        self.codex_symbols = ""
        self.entitlements = {
            name: {key: True for key in REQUIRED_ENTITLEMENTS}
            for name in self.binaries
        }
        self.payload_modes = dict(PAYLOAD_MODES)
        self.payload_owner = {
            path: (501, 501) for path in self.payload_modes
        }
        self.payload_missing: set[str] = set()
        self.bad_checksum = False
        self.checksum_target = DEB_NAME
        self.extra_zip_entry: str | None = None
        self.extra_payload_symlink: str | None = None
        self.forbidden_stub_binary: str | None = None
        self._write_fake_tools()

    def _write_fake_tools(self):
        tool = self.root / "fake-bin/tool"
        tool.write_text(
            """#!/usr/bin/env python3
import os
from pathlib import Path
import plistlib
import sys
import tarfile

name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == "file":
    binary = Path(args[-1]).name
    description = os.environ["ARCH_" + binary.replace("-", "_")]
    print(description if "-b" in args else f"{args[-1]}: {description}")
elif name == "otool":
    binary = Path(args[-1]).name
    prefix = "PLATFORM_ARM64_" if args[:2] == ["-arch", "arm64"] else "PLATFORM_DEFAULT_"
    platform = os.environ[prefix + binary.replace("-", "_")]
    print("Load command 10")
    print("      cmd LC_BUILD_VERSION")
    print("  cmdsize 32")
    print(f" platform {platform}")
    print("    minos 16.0")
elif name == "nm":
    binary = Path(args[-1]).name
    key = "SYMBOLS_" + binary.replace("-", "_")
    sys.stdout.write(os.environ.get(key, ""))
elif name == "ldid":
    binary = Path(args[-1]).name
    key = "ENTITLEMENTS_" + binary.replace("-", "_")
    sys.stdout.buffer.write(Path(os.environ[key]).read_bytes())
elif name == "dpkg-deb":
    if args[0] == "-f":
        fields = {
            "Package": "codex-ios-roothide",
            "Version": os.environ.get("DEB_VERSION", "0.145.0-5-jit"),
            "Architecture": "iphoneos-arm64e",
        }
        print(fields[args[2]])
    elif args[0] == "--fsys-tarfile":
        sys.stdout.buffer.write(Path(os.environ["DATA_TAR"]).read_bytes())
    elif args[0] == "-x":
        with tarfile.open(os.environ["DATA_TAR"]) as archive:
            archive.extractall(args[2])
    else:
        raise SystemExit(f"unexpected dpkg-deb arguments: {args}")
else:
    raise SystemExit(f"unexpected fake tool: {name}")
"""
        )
        tool.chmod(0o755)
        for name in ("file", "otool", "nm", "ldid", "dpkg-deb"):
            (self.root / "fake-bin" / name).symlink_to("tool")

    def _materialize(self):
        forbidden = b"code mode is unavailable in this iOS build"
        materialized_binaries = {}
        for name, content in self.binaries.items():
            if self.forbidden_stub_binary == name:
                content += forbidden
            materialized_binaries[name] = content
            path = self.root / "out/bin" / name
            path.write_bytes(content)
            path.chmod(0o755)

        entitlements_dir = self.root / "effective-entitlements"
        entitlements_dir.mkdir(exist_ok=True)
        for name, values in self.entitlements.items():
            (entitlements_dir / f"{name}.plist").write_bytes(plistlib.dumps(values))

        data_tar = self.root / "data.tar"
        with tarfile.open(data_tar, "w") as archive:
            payload = {
                "var/jb/usr/local/bin/codex": b"#!/bin/sh\n",
                f"{VENDOR}/codex": materialized_binaries["codex"],
                f"{VENDOR}/codex-code-mode-host": materialized_binaries[
                    "codex-code-mode-host"
                ],
                "var/jb/usr/local/lib/node_modules/@openai/codex/bin/codex.js": (
                    b"#!/usr/bin/env node\n"
                ),
                "var/jb/usr/local/lib/node_modules/@openai/codex/package.json": b"{}\n",
                "var/jb/usr/local/share/entitlements/codex.plist": plistlib.dumps(
                    self.entitlements["codex"]
                ),
            }
            directories = {
                str(parent)
                for name in PAYLOAD_MODES
                for parent in PurePosixPath(name).parents
                if str(parent) != "."
            }
            for name in sorted(directories, key=lambda value: (value.count("/"), value)):
                info = tarfile.TarInfo(name)
                info.type = tarfile.DIRTYPE
                info.mode = 0o755
                info.uid = 501
                info.gid = 501
                archive.addfile(info)
            for name, content in payload.items():
                if name in self.payload_missing:
                    continue
                info = tarfile.TarInfo(name)
                info.size = len(content)
                info.mode = self.payload_modes[name]
                info.uid, info.gid = self.payload_owner[name]
                archive.addfile(info, fileobj=io.BytesIO(content))
            if self.extra_payload_symlink:
                info = tarfile.TarInfo(self.extra_payload_symlink)
                info.type = tarfile.SYMTYPE
                info.linkname = f"{VENDOR}/codex"
                info.mode = 0o777
                info.uid = 501
                info.gid = 501
                archive.addfile(info)

        deb = self.root / "out" / DEB_NAME
        deb.write_bytes(b"valid fixture deb\n")
        release_contents = {
            DEB_NAME: deb.read_bytes(),
            "UPSTREAM_CODEX_COMMIT": b"codex-commit\n",
        }
        digest = hashlib.sha256(release_contents[self.checksum_target]).hexdigest()
        if self.bad_checksum:
            digest = "0" * 64
        sums = f"{digest}  {self.checksum_target}\n"
        (self.root / "out/SHA256SUMS").write_text(sums)

        release = {
            DEB_NAME: release_contents[DEB_NAME],
            "SHA256SUMS": sums.encode(),
            "UPSTREAM_CODEX_COMMIT": release_contents["UPSTREAM_CODEX_COMMIT"],
            "UPSTREAM_CODEX_VERSION": b"0.145.0\n",
            "UPSTREAM_RUSTY_V8_COMMIT": b"v8-commit\n",
            "UPSTREAM_RUSTY_V8_VERSION": b"0.99.0\n",
            "patches/codex-ios-roothide.patch": b"codex patch\n",
            "patches/rusty-v8-ios-jit.patch": b"v8 patch\n",
        }
        if self.extra_zip_entry:
            release[self.extra_zip_entry] = b"unexpected\n"
        with zipfile.ZipFile(self.root / "out" / ZIP_NAME, "w") as archive:
            for name, content in release.items():
                archive.writestr(name, content)

    def run(self, *, include_artifacts=True, deb_version=VERSION):
        if include_artifacts:
            self._materialize()
        environment = os.environ | {
            "PATH": f"{self.root / 'fake-bin'}{os.pathsep}{os.environ['PATH']}",
            "DATA_TAR": str(self.root / "data.tar"),
            "DEB_VERSION": deb_version,
            "ARCH_codex": self.architectures["codex"],
            "ARCH_codex_code_mode_host": self.architectures[
                "codex-code-mode-host"
            ],
            "PLATFORM_ARM64_codex": self.platforms["codex"],
            "PLATFORM_ARM64_codex_code_mode_host": self.platforms[
                "codex-code-mode-host"
            ],
            "PLATFORM_DEFAULT_codex": self.default_platforms["codex"],
            "PLATFORM_DEFAULT_codex_code_mode_host": self.default_platforms[
                "codex-code-mode-host"
            ],
            "SYMBOLS_codex": self.codex_symbols,
            "SYMBOLS_codex_code_mode_host": self.host_symbols,
            "ENTITLEMENTS_codex": str(
                self.root / "effective-entitlements/codex.plist"
            ),
            "ENTITLEMENTS_codex_code_mode_host": str(
                self.root
                / "effective-entitlements/codex-code-mode-host.plist"
            ),
        }
        return subprocess.run(
            ["sh", "scripts/verify-artifacts.sh"],
            cwd=self.root,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )


class VerifyArtifactsTest(unittest.TestCase):
    def run_fixture(self, configure=None, **run_options):
        with tempfile.TemporaryDirectory() as directory:
            fixture = ArtifactFixture(directory)
            if configure:
                configure(fixture)
            return fixture.run(**run_options)

    def assert_rejected(self, completed, diagnostic):
        self.assertNotEqual(completed.returncode, 0, completed.stdout)
        self.assertIn(diagnostic, completed.stderr)

    def test_accepts_complete_signed_artifact_set(self):
        completed = self.run_fixture()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("verified iOS V8 JIT artifacts", completed.stdout)

    def test_reports_first_missing_artifact_path(self):
        completed = self.run_fixture(include_artifacts=False)
        self.assert_rejected(completed, "missing artifact:")
        self.assertIn("/out/bin/codex", completed.stderr)

    def test_rejects_non_arm64_macho(self):
        def configure(fixture):
            fixture.architectures["codex-code-mode-host"] = (
                "Mach-O 64-bit executable x86_64"
            )

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "not a Mach-O 64-bit arm64 executable")

    def test_rejects_universal_macho_that_contains_arm64_text(self):
        def configure(fixture):
            fixture.architectures["codex"] = (
                "Mach-O universal binary with 2 architectures: "
                "[arm64:Mach-O 64-bit executable arm64] "
                "[x86_64:Mach-O 64-bit executable x86_64]"
            )

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "thin Mach-O required")

    def test_rejects_non_ios_build_platform(self):
        def configure(fixture):
            fixture.platforms["codex"] = "1"

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "LC_BUILD_VERSION platform 2")

    def test_requires_v8_symbols_in_code_mode_host_itself(self):
        def configure(fixture):
            fixture.host_symbols = ""
            fixture.codex_symbols = "_ZN2v87Isolate3NewEv\n"

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "V8 symbol")

    def test_rejects_each_missing_effective_entitlement_on_each_binary(self):
        for binary in ("codex", "codex-code-mode-host"):
            for key in REQUIRED_ENTITLEMENTS:
                with self.subTest(binary=binary, key=key):
                    def configure(fixture, binary=binary, key=key):
                        del fixture.entitlements[binary][key]

                    completed = self.run_fixture(configure)
                    self.assert_rejected(completed, f"{binary}: missing entitlement: {key}")

    def test_rejects_wrong_deb_version(self):
        completed = self.run_fixture(deb_version="0.145.0-4")
        self.assert_rejected(completed, "unexpected DEB Version")

    def test_rejects_missing_deb_layout_entry(self):
        def configure(fixture):
            fixture.payload_missing.add(f"{VENDOR}/codex-code-mode-host")

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "DEB payload is missing")

    def test_rejects_wrong_deb_binary_mode(self):
        def configure(fixture):
            fixture.payload_modes[f"{VENDOR}/codex-code-mode-host"] = 0o644

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "expected mode 0755")

    def test_rejects_wrong_deb_payload_ownership(self):
        def configure(fixture):
            fixture.payload_owner[f"{VENDOR}/codex"] = (0, 0)

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "expected owner/group 501:501")

    def test_rejects_unexpected_non_regular_deb_member(self):
        def configure(fixture):
            fixture.extra_payload_symlink = "var/jb/usr/local/bin/codex-alias"

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "unexpected DEB payload entry")

    def test_rejects_forbidden_ios_stub(self):
        def configure(fixture):
            fixture.forbidden_stub_binary = "codex-code-mode-host"

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "forbidden iOS Code Mode stub")

    def test_rejects_invalid_zip_checksum(self):
        def configure(fixture):
            fixture.bad_checksum = True

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "ZIP checksum validation failed")

    def test_rejects_checksum_manifest_that_does_not_name_deb(self):
        def configure(fixture):
            fixture.checksum_target = "UPSTREAM_CODEX_COMMIT"

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "SHA256SUMS must name exactly")

    def test_rejects_unexpected_zip_inventory(self):
        def configure(fixture):
            fixture.extra_zip_entry = "unexpected.txt"

        completed = self.run_fixture(configure)
        self.assert_rejected(completed, "unexpected ZIP inventory")


class VerificationWorkflowTest(unittest.TestCase):
    def test_verification_gates_artifacts_while_logs_are_always_retained(self):
        workflow = yaml.safe_load(
            (ROOT / ".github/workflows/build-ios-v8-jit.yml").read_text()
        )
        steps = workflow["jobs"]["build"]["steps"]
        named = {step.get("name"): (index, step) for index, step in enumerate(steps)}
        required_steps = {
            "Sign iOS executables",
            "Package iOS artifacts",
            "Verify iOS artifacts",
            "Upload verified iOS artifacts",
            "Upload iOS build logs",
        }
        self.assertEqual(required_steps - set(named), set())

        sign_index, sign = named["Sign iOS executables"]
        package_index, package = named["Package iOS artifacts"]
        verify_index, verify = named["Verify iOS artifacts"]
        artifact_index, artifacts = named["Upload verified iOS artifacts"]
        logs_index, logs = named["Upload iOS build logs"]

        self.assertLess(sign_index, package_index)
        self.assertLess(package_index, verify_index)
        self.assertLess(verify_index, artifact_index)
        self.assertLess(artifact_index, logs_index)
        self.assertIn("scripts/sign-ios.sh", sign["run"])
        self.assertIn("scripts/package.sh", package["run"])
        self.assertIn("scripts/verify-artifacts.sh", verify["run"])
        self.assertNotEqual(artifacts.get("if"), "always()")
        artifact_paths = artifacts["with"]["path"].splitlines()
        self.assertEqual(
            artifact_paths,
            [
                "out/codex-ios-roothide-0.145.0-5-jit.deb",
                "out/codex-ios-roothide-0.145.0-5-jit.zip",
                "out/SHA256SUMS",
            ],
        )
        self.assertEqual(logs["if"], "always()")
        self.assertEqual(logs["with"]["path"], "logs/")


if __name__ == "__main__":
    unittest.main()
