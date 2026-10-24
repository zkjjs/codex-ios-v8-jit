import importlib.util
import json
from pathlib import Path
import threading
import unittest
import urllib.error
import urllib.request

MODULE = Path(__file__).parents[1] / 'quota_service.py'


class QuotaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('quota_service', MODULE)
        cls.q = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.q)

    def test_real_protocol_shape_and_private_fields(self):
        result = self.q.normalize({'rateLimits': {
            'planType': 'plus', 'primary': {'usedPercent': 69, 'windowDurationMins': 300, 'resetsAt': 1792882117},
            'secondary': {'usedPercent': 40, 'windowDurationMins': 10080, 'resetsAt': None}},
            'accountId': 'PRIVATE', 'rateLimitResetCredits': {'credits': [{'id': 'SECRET'}]}}, now=100)
        self.assertEqual(result['windows'][0]['remainingPercent'], 31)
        self.assertEqual(result['windows'][1]['remainingPercent'], 60)
        self.assertIsNone(result['windows'][1]['resetsAt'])
        self.assertEqual(result['updatedAt'], 100)
        self.assertEqual(result['plan'], 'plus')
        self.assertNotIn('PRIVATE', json.dumps(result))
        self.assertNotIn('SECRET', json.dumps(result))

    def test_missing_quota_is_not_a_full_allowance(self):
        self.assertEqual(self.q.normalize({'rateLimits': None}, now=1)['windows'], [])
        self.assertEqual(self.q.normalize({'rateLimits': {'primary': None}}, now=1)['windows'], [])

    def test_invalid_and_nonfinite_usage_is_unavailable(self):
        for value in [None, '69', float('nan'), float('inf'), True, -1, 101]:
            with self.subTest(value=value):
                result = self.q.normalize({'rateLimits': {'primary': {'usedPercent': value}}}, now=1)
                self.assertEqual(result['windows'], [])

    def test_multibucket_fallback_selects_codex(self):
        result = self.q.normalize({'rateLimitsByLimitId': {'other': {'primary': {'usedPercent': 90}},
            'codex': {'primary': {'usedPercent': 20, 'windowDurationMins': 300}}}}, now=1)
        self.assertEqual(result['windows'][0]['remainingPercent'], 80)

    def test_failed_refresh_preserves_timestamp_and_marks_stale(self):
        calls = []
        def fetch():
            calls.append(1)
            if len(calls) > 1:
                raise RuntimeError('SECRET upstream details')
            return {'rateLimits': {'primary': {'usedPercent': 69, 'windowDurationMins': 300}}}
        clock = [100]
        cache = self.q.QuotaCache(fetch, ttl=60, clock=lambda: clock[0])
        self.assertFalse(cache.get()['stale'])
        clock[0] = 110
        self.assertEqual(cache.get()['updatedAt'], 100)
        self.assertEqual(len(calls), 1)
        clock[0] = 170
        self.assertTrue(cache.get()['stale'])
        self.assertEqual(cache.get()['updatedAt'], 100)

    def test_first_failure_does_not_fabricate_quota(self):
        def fetch():
            raise RuntimeError('unavailable')
        with self.assertRaises(self.q.QuotaUnavailable):
            self.q.QuotaCache(fetch).get()

    def test_http_access_control_and_unknown_routes(self):
        calls = []
        def fetch():
            calls.append(1)
            return {'rateLimits': {'primary': {'usedPercent': 69}}}
        server = self.q.make_server(('127.0.0.1', 0), 'test-read-only-code', self.q.QuotaCache(fetch))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            with urllib.request.urlopen(base + '/health') as response:
                self.assertEqual(json.load(response), {'status': 'ok'})
            for suffix, code, expected in [('/v1/quota', '', 401), ('/v1/quota', 'wrong', 401),
                                           ('/run', 'test-read-only-code', 404)]:
                request = urllib.request.Request(base + suffix, headers={'Authorization': 'Bearer ' + code})
                with self.assertRaises(urllib.error.HTTPError) as caught:
                    urllib.request.urlopen(request)
                self.assertEqual(caught.exception.code, expected)
                caught.exception.close()
            self.assertEqual(calls, [])
            request = urllib.request.Request(base + '/v1/quota', headers={'Authorization': 'Bearer test-read-only-code'})
            with urllib.request.urlopen(request) as response:
                self.assertEqual(json.load(response)['windows'][0]['remainingPercent'], 31)
                self.assertEqual(response.headers['Cache-Control'], 'no-store')
            self.assertEqual(len(calls), 1)
        finally:
            server.shutdown()
            server.server_close()
            worker.join()

    def test_http_503_hides_upstream_details(self):
        def fetch():
            raise RuntimeError('SECRET credentials in an upstream error')
        server = self.q.make_server(('127.0.0.1', 0), 'code', self.q.QuotaCache(fetch))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            request = urllib.request.Request(f'http://127.0.0.1:{server.server_port}/v1/quota',
                headers={'Authorization': 'Bearer code'})
            with self.assertRaises(urllib.error.HTTPError) as caught:
                urllib.request.urlopen(request)
            self.assertEqual(caught.exception.code, 503)
            self.assertNotIn('SECRET', caught.exception.read().decode())
            caught.exception.close()
        finally:
            server.shutdown()
            server.server_close()
            worker.join()


if __name__ == '__main__':
    unittest.main()
