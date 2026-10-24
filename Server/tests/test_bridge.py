import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bridge', pathlib.Path(__file__).parents[1] / 'bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)

class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.now = 1000.0
        self.calls = []
        self.responses = []
        def upstream(method, url, body=None, headers=None):
            self.calls.append((method, url, body, headers))
            result = self.responses.pop(0)
            if isinstance(result, Exception): raise result
            return result
        self.service = bridge.Bridge(pathlib.Path(self.tmp.name), 'k' * 48, upstream=upstream, clock=lambda: self.now)
    def tearDown(self): self.tmp.cleanup()
    def dispatch(self, method, path, body=None, key='k' * 48):
        return self.service.dispatch(method, path, body or {}, 'Bearer ' + key)
    def test_rejects_missing_or_wrong_gateway_key(self):
        self.assertEqual(self.dispatch('GET', '/v1/usage', key='wrong')[0], 401)
        self.assertEqual(len(self.calls), 0)
    def test_no_login_is_not_a_zero_balance(self):
        status, payload = self.dispatch('GET', '/v1/usage')
        self.assertEqual(status, 409)
        self.assertEqual(payload['code'], 'login_required')
    def start(self):
        self.responses.append({'device_auth_id':'upstream-private-id', 'usercode':'AB-CD', 'interval':'5'})
        return self.dispatch('POST', '/v1/login/start')[1]
    def test_device_auth_id_is_not_exposed(self):
        payload = self.start()
        self.assertEqual(payload['user_code'], 'AB-CD')
        self.assertNotEqual(payload['device_auth_id'], 'upstream-private-id')
    def test_polling_respects_interval(self):
        payload = self.start()
        status, _ = self.dispatch('POST','/v1/login/poll',{'flow_id':payload['device_auth_id']})
        self.assertEqual(status, 202)
        self.assertEqual(len(self.calls),1)
    def test_pending_poll_is_not_a_login_failure(self):
        payload = self.start(); self.now += 6
        self.responses.append(bridge.UpstreamError(403))
        status, data = self.dispatch('POST','/v1/login/poll',{'flow_id':payload['device_auth_id']})
        self.assertEqual(status,202)
        self.assertEqual(data['status'],'pending')
    def test_login_completion_never_returns_tokens(self):
        payload = self.start(); self.now += 6
        self.responses += [{'authorization_code':'code','code_verifier':'verifier'}, {'access_token':'private-access','refresh_token':'private-refresh','expires_in':3600}]
        status, data = self.dispatch('POST','/v1/login/poll',{'flow_id':payload['device_auth_id']})
        self.assertEqual(status,200)
        self.assertNotIn('token', str(data))
        self.assertEqual(self.service.account['access_token'],'private-access')
        self.assertEqual((pathlib.Path(self.tmp.name)/'account.json').stat().st_mode & 0o777, 0o600)
    def test_expired_flow(self):
        payload = self.start(); self.now += 901
        self.assertEqual(self.dispatch('POST','/v1/login/poll',{'flow_id':payload['device_auth_id']})[0],410)
    def test_usage_is_cached_and_logout_invalidates(self):
        self.service.account={'access_token':'a','refresh_token':'r','expires_at':9000}
        self.responses.append({'plan_type':'plus','rate_limit':None})
        self.assertEqual(self.dispatch('GET','/v1/usage')[0],200)
        self.assertEqual(self.dispatch('GET','/v1/usage')[0],200)
        self.assertEqual(len(self.calls),1)
        self.dispatch('POST','/v1/logout')
        self.assertEqual(self.dispatch('GET','/v1/usage')[0],409)
    def test_throttle_is_preserved(self):
        self.service.account={'access_token':'a','refresh_token':'r','expires_at':9000}
        self.responses.append(bridge.UpstreamError(429, retry=120))
        self.assertEqual(self.dispatch('GET','/v1/usage')[0],429)
        self.assertEqual(self.dispatch('GET','/v1/usage')[0],429)
        self.assertEqual(len(self.calls),1)
    def test_logout_remains_available_during_throttle(self):
        self.service.account={'access_token':'a','refresh_token':'r'}
        self.service.retry_at=self.now+120
        self.assertEqual(self.dispatch('POST','/v1/logout')[0],200)
        self.assertFalse(self.service.account)
    def test_listener_does_not_depend_on_reverse_dns(self):
        with patch('socket.getfqdn',side_effect=AssertionError('Listener must not resolve reverse DNS')):
            server = bridge.SecureServer(('127.0.0.1',0),None)
            server.server_close()
    def test_unknown_routes_and_invalid_flow(self):
        self.assertEqual(self.dispatch('GET','/account.json')[0],404)
        self.assertEqual(self.dispatch('POST','/v1/login/poll',{'flow_id':'unknown'})[0],410)

if __name__ == '__main__': unittest.main()
