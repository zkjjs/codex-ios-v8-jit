from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
CODEX_COMMIT = "25af12f7e61572b0bc18ddb1008be543b91519b0"
RUSTY_V8_COMMIT = "5d0e31ea6bf67f4559faa759b91e22bc3f1cd696"


class FetchUpstreamTest(unittest.TestCase):
    def run_fetch(self, create_v8_deps):
        temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(temp_dir.cleanup)
        test_root = Path(temp_dir.name)
        scripts_dir = test_root / "scripts"
        fake_bin = test_root / "fake-bin"
        scripts_dir.mkdir()
        fake_bin.mkdir()

        fetch = scripts_dir / "fetch-upstream.sh"
        shutil.copy2(ROOT / "scripts/fetch-upstream.sh", fetch)
        log = test_root / "git.log"
        fake_git = fake_bin / "git"
        fake_git.write_text(
            textwrap.dedent(
                f"""\
                #!/bin/sh
                set -eu
                printf '%s\\n' "$*" >> "$FAKE_GIT_LOG"

                worktree=
                if [ "$1" = "-C" ]; then
                  worktree="$2"
                  shift 2
                fi

                command="$1"
                shift
                case "$command" in
                  clone)
                    destination=
                    for argument in "$@"; do
                      destination="$argument"
                    done
                    mkdir -p "$destination/.git"
                    ;;
                  rev-parse)
                    case "$worktree" in
                      */codex) printf '%s\\n' "{CODEX_COMMIT}" ;;
                      */rusty_v8) printf '%s\\n' "{RUSTY_V8_COMMIT}" ;;
                      *) exit 2 ;;
                    esac
                    ;;
                  submodule)
                    if [ "${{1:-}}" = "update" ]; then
                      mkdir -p "$worktree/v8"
                      if [ "${{FAKE_CREATE_V8_DEPS:-yes}}" = "yes" ]; then
                        : > "$worktree/v8/DEPS"
                      fi
                    fi
                    ;;
                esac
                """
            )
        )
        fake_git.chmod(0o755)

        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
        env["FAKE_GIT_LOG"] = str(log)
        env["FAKE_CREATE_V8_DEPS"] = "yes" if create_v8_deps else "no"
        result = subprocess.run(
            [str(fetch)],
            cwd=test_root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        calls = log.read_text().splitlines()
        return test_root, result, calls

    def test_fetch_initializes_all_rusty_v8_submodules_recursively(self):
        test_root, result, calls = self.run_fetch(create_v8_deps=True)
        rusty_v8 = test_root / "work/rusty_v8"

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((rusty_v8 / "v8/DEPS").is_file())
        self.assertIn(
            f"-C {rusty_v8} submodule sync --recursive",
            calls,
        )
        update_call = next(
            (
                call
                for call in calls
                if call.startswith(f"-C {rusty_v8} submodule update ")
            ),
            "",
        )
        self.assertIn("--init", update_call)
        self.assertIn("--recursive", update_call)

    def test_fetch_fails_clearly_when_v8_deps_is_missing(self):
        _, result, _ = self.run_fetch(create_v8_deps=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("v8/DEPS", result.stderr)
        self.assertIn("submodule", result.stderr.lower())


if __name__ == "__main__":
    unittest.main()
