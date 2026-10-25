from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class DeviceDocumentationContractTest(unittest.TestCase):
    def test_rollback_requires_exact_immutable_package_and_revision(self):
        device_tests = (ROOT / "DEVICE-TESTS.md").read_text()

        self.assertIn('$NF == "codex-ios-roothide-0.145.0-3.deb"', device_tests)
        self.assertIn('[ "$ROLLBACK_COUNT" -ne 1 ]', device_tests)
        self.assertIn('test -d "$CONFIG_DIR"', device_tests)
        self.assertIn("grep -qx '0.145.0-3'", device_tests)


if __name__ == "__main__":
    unittest.main()
