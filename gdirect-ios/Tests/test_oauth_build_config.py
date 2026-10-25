import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('oauth_config', ROOT / 'scripts/configure-google-oauth.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class OAuthBuildConfigTests(unittest.TestCase):
    def test_callback_is_derived_from_client_id(self):
        config = module.build_config('12345-example.apps.googleusercontent.com', 'org.gdirect.ios')
        self.assertEqual(config['GOOGLE_REVERSED_CLIENT_ID'], 'com.googleusercontent.apps.12345-example')
        self.assertEqual(config['GDIRECT_BUNDLE_ID'], 'org.gdirect.ios')

    def test_placeholder_and_xcconfig_injection_are_rejected(self):
        for client in ['configure-ios-oauth.apps.googleusercontent.com', 'bad\n#include "other"', '$(CLIENT)', 'https://example.com']:
            with self.subTest(client=client), self.assertRaises(ValueError):
                module.build_config(client, 'org.gdirect.ios')
        with self.assertRaises(ValueError):
            module.build_config('12345-example.apps.googleusercontent.com', 'org.bad\nOTHER=1')

    def test_unconfigured_build_does_not_fabricate_client_id(self):
        with tempfile.TemporaryDirectory() as directory:
            result = module.configure(Path(directory), client_id='', bundle_id='org.gdirect.ios')
            self.assertFalse(result)
            self.assertFalse((Path(directory) / 'Config.local.xcconfig').exists())

    def test_config_writes_consistent_client_callback_and_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertTrue(module.configure(root, client_id='12345-example.apps.googleusercontent.com', bundle_id='org.gdirect.ios'))
            text = (root/'Config.local.xcconfig').read_text()
            self.assertIn('GOOGLE_CLIENT_ID = 12345-example.apps.googleusercontent.com', text)
            self.assertIn('GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.12345-example', text)
