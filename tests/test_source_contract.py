from pathlib import Path
import os
import re
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]


def rust_block(source, marker):
    start = source.index(marker)
    opening_brace = source.index("{", start)
    depth = 0
    for index in range(opening_brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[opening_brace + 1 : index]
    raise ValueError(f"unclosed Rust block after {marker!r}")


class SourceContractTest(unittest.TestCase):
    def test_pins(self):
        self.assertEqual(
            (ROOT / "UPSTREAM_CODEX_COMMIT").read_text().strip(),
            "25af12f7e61572b0bc18ddb1008be543b91519b0",
        )
        self.assertEqual((ROOT / "UPSTREAM_CODEX_VERSION").read_text().strip(), "0.145.0")
        self.assertEqual(
            (ROOT / "UPSTREAM_RUSTY_V8_COMMIT").read_text().strip(),
            "5d0e31ea6bf67f4559faa759b91e22bc3f1cd696",
        )
        self.assertEqual((ROOT / "UPSTREAM_RUSTY_V8_VERSION").read_text().strip(), "149.2.0")

    def test_code_mode_is_not_stubbed(self):
        lib = (ROOT / "work/codex/codex-rs/code-mode/src/lib.rs").read_text()
        self.assertIn("mod v8_init;", lib)
        self.assertNotIn("code mode is unavailable in this iOS build", lib)

    def test_ios_compatibility_symbol_exists(self):
        main = (ROOT / "work/codex/codex-rs/cli/src/main.rs").read_text()
        self.assertIn('pub extern "C" fn __chkstk_darwin()', main)

    def test_v8_patch_override_is_exact(self):
        cargo = (ROOT / "work/codex/codex-rs/Cargo.toml").read_text()
        self.assertIn('v8 = { path = "../../rusty_v8" }', cargo)

    def test_rusty_v8_ios_configuration(self):
        build = (ROOT / "work/rusty_v8/build.rs").read_text()
        required = [
            'target_os == "ios"',
            'target_os="ios"',
            'target_platform="iphoneos"',
            'target_environment="device"',
            'ios_deployment_target="16.0"',
            'v8_enable_lite_mode=false',
            'v8_enable_turbofan=true',
            'v8_enable_maglev=true',
            'v8_enable_sandbox=false',
            'v8_enable_pointer_compression=false',
            'v8_enable_webassembly=false',
        ]
        for item in required:
            self.assertIn(item, build)

        bindgen = rust_block(build, '} else if target_os == "ios"')
        self.assertIn('.args(["--sdk", "iphoneos", "--show-sdk-path"])', bindgen)
        self.assertIn("output.status.success()", bindgen)
        self.assertIn("String::from_utf8_lossy(&output.stderr)", bindgen)
        self.assertIn('"-isysroot".to_string()', bindgen)
        self.assertIn('"-target".to_string()', bindgen)
        self.assertIn('"arm64-apple-ios16.0".to_string()', bindgen)

    def test_rusty_v8_ios_gn_keys_are_assigned_once(self):
        build = (ROOT / "work/rusty_v8/build.rs").read_text()
        build_v8 = rust_block(build, "fn build_v8(is_asan: bool)")
        ios_gn = rust_block(
            build_v8, 'if target_triple == "aarch64-apple-ios"'
        )
        ios_specific_keys = re.findall(r'"([a-z][a-z0-9_]*)=', ios_gn)
        shared_keys = [
            "target_cpu",
            "use_custom_libcxx",
            "v8_enable_sandbox",
            "v8_enable_pointer_compression",
            "treat_warnings_as_errors",
        ]

        for key in shared_keys:
            self.assertNotIn(key, ios_specific_keys)

        self.assertIn('target_os != "ios"', build_v8)
        self.assertEqual(
            build_v8.count(
                'gn_args.push(format!("use_custom_libcxx={use_custom_libcxx}"))'
            ),
            1,
        )
        extra_args = rust_block(build_v8, "let extra_args =")
        ios_extra_args = rust_block(extra_args, 'if target_os == "ios"')
        self.assertEqual(ios_extra_args.count('"v8_enable_sandbox=false"'), 1)
        self.assertEqual(
            ios_extra_args.count('"v8_enable_pointer_compression=false"'), 1
        )
        aarch64 = rust_block(build_v8, 'if target_arch == "aarch64"')
        self.assertEqual(aarch64.count('target_cpu="arm64"'), 1)
        warnings_marker = (
            'if target_os == "ios"\n'
            '      || (target_os == "android" && target_arch == "aarch64")'
        )
        self.assertIn(warnings_marker, build_v8)
        ios_warnings = rust_block(build_v8, warnings_marker)
        self.assertEqual(
            ios_warnings.count('"treat_warnings_as_errors=false"'), 1
        )

        effective_keys = ios_specific_keys + shared_keys
        self.assertEqual(len(effective_keys), len(set(effective_keys)))
        self.assertEqual(
            set(effective_keys),
            {
                "target_os",
                "target_platform",
                "target_environment",
                "target_cpu",
                "v8_target_cpu",
                "ios_deployment_target",
                "use_sysroot",
                "use_custom_libcxx",
                "v8_enable_lite_mode",
                "v8_enable_turbofan",
                "v8_enable_maglev",
                "v8_enable_sandbox",
                "v8_enable_pointer_compression",
                "v8_enable_webassembly",
                "treat_warnings_as_errors",
            },
        )

    def test_ios_build_workflow_retries_with_verified_archive(self):
        workflow = yaml.safe_load(
            (ROOT / ".github/workflows/build-ios-v8-jit.yml").read_text()
        )
        steps = workflow["jobs"]["build"]["steps"]
        build_step = next(
            step
            for step in steps
            if step.get("name") == "Build iOS Codex and Code Mode host"
        )
        self.assertEqual(build_step["shell"], "bash")
        run = build_step["run"]
        self.assertIn("set -e -o pipefail", run)
        self.assertLess(
            run.index("scripts/build-ios.sh 2>&1 | tee"),
            run.index("scripts/build-v8-archive.sh 2>&1 | tee"),
        )
        self.assertLess(
            run.index("scripts/build-v8-archive.sh 2>&1 | tee"),
            run.index("scripts/build-ios.sh archive 2>&1 | tee"),
        )

    def test_ios_build_workflow_prepares_sources_before_unit_tests(self):
        workflow = yaml.safe_load(
            (ROOT / ".github/workflows/build-ios-v8-jit.yml").read_text()
        )
        steps = workflow["jobs"]["build"]["steps"]
        prepare_index = next(
            (
                index
                for index, step in enumerate(steps)
                if step.get("name") == "Prepare pinned source fixtures"
            ),
            None,
        )
        self.assertIsNotNone(prepare_index)
        test_index = next(
            index
            for index, step in enumerate(steps)
            if step.get("name") == "Run unit tests"
        )
        prepare_run = steps[prepare_index]["run"]

        self.assertLess(prepare_index, test_index)
        self.assertIn("scripts/fetch-upstream.sh", prepare_run)
        self.assertIn("scripts/apply-patches.sh", prepare_run)
        self.assertLess(
            prepare_run.index("scripts/fetch-upstream.sh"),
            prepare_run.index("scripts/apply-patches.sh"),
        )

    def test_all_shell_scripts_are_executable(self):
        scripts = sorted((ROOT / "scripts").glob("*.sh"))
        self.assertGreaterEqual(
            {script.name for script in scripts},
            {
                "fetch-upstream.sh",
                "apply-patches.sh",
                "build-ios.sh",
                "build-v8-archive.sh",
                "sign-ios.sh",
                "package.sh",
                "verify-artifacts.sh",
            },
        )
        for script in scripts:
            with self.subTest(script=script.name):
                self.assertTrue(os.access(script, os.X_OK))

    def test_ios_build_archive_mode_uses_verified_archive(self):
        build = (ROOT / "scripts/build-ios.sh").read_text()
        self.assertIn('mode="${1:-source}"', build)
        self.assertIn('archive)', build)
        self.assertIn('unset V8_FROM_SOURCE', build)
        self.assertIn('export RUSTY_V8_ARCHIVE="$archive"', build)
        self.assertIn('shasum -a 256 -c "$checksum"', build)

    def test_v8_archive_uses_isolated_target_dir(self):
        build = (ROOT / "scripts/build-v8-archive.sh").read_text()
        self.assertIn('target_dir="$(mktemp -d', build)
        self.assertIn('export CARGO_TARGET_DIR="$target_dir"', build)
        self.assertIn('archive_count="$(find', build)
        self.assertIn('[ "$archive_count" -ne 1 ]', build)
        self.assertNotIn("sort | tail -n 1", build)


if __name__ == "__main__":
    unittest.main()
