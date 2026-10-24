#!/usr/bin/env python3
"""Read-only facade over the existing local Codex account. Standard library only."""
import argparse
import copy
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
import queue
import subprocess
import threading
import time
from urllib.parse import urlsplit


class QuotaUnavailable(Exception):
    pass


def finite_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def normalize(result, now=None):
    bucket = (result.get('rateLimitsByLimitId') or {}).get('codex') or result.get('rateLimits') or {}
    windows = []
    for key in ('primary', 'secondary'):
        window = bucket.get(key)
        if not isinstance(window, dict):
            continue
        used = window.get('usedPercent')
        if not finite_number(used) or not 0 <= used <= 100:
            continue
        minutes = window.get('windowDurationMins')
        if not finite_number(minutes) or minutes <= 0:
            minutes = None
        reset = window.get('resetsAt')
        if not finite_number(reset) or reset <= 0:
            reset = None
        if minutes == 10080:
            title = '每周额度'
        elif minutes is not None and minutes % 60 == 0:
            title = f'{minutes / 60:g} 小时额度'
        elif minutes is not None:
            title = f'{minutes:g} 分钟额度'
        else:
            title = '主要额度' if key == 'primary' else '次要额度'
        windows.append({'id': key, 'title': title, 'usedPercent': used,
                        'remainingPercent': round(100 - used, 2),
                        'windowMinutes': minutes, 'resetsAt': reset})
    plan = bucket.get('planType')
    return {'version': 1, 'updatedAt': int(time.time() if now is None else now),
            'stale': False, 'plan': plan if isinstance(plan, str) else None, 'windows': windows}


def read_codex(timeout=25):
    """No inference or reset calls. Never log protocol messages or upstream errors."""
    process = subprocess.Popen(
        [os.environ.get('CODEX_BIN', '/usr/local/bin/codex'), 'app-server', '--listen', 'stdio://'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, bufsize=1)
    messages = queue.Queue()

    def drain():
        try:
            for line in process.stdout:
                try:
                    messages.put(json.loads(line))
                except ValueError:
                    continue
        finally:
            messages.put(None)

    reader = threading.Thread(target=drain, daemon=True)
    reader.start()

    def send(message):
        process.stdin.write(json.dumps(message) + '\n')
        process.stdin.flush()

    try:
        send({'id': 1, 'method': 'initialize',
              'params': {'clientInfo': {'name': 'codex_quota_readonly', 'version': '1.0.0'}}})
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise QuotaUnavailable('Codex query timed out')
            try:
                message = messages.get(timeout=remaining)
            except queue.Empty:
                raise QuotaUnavailable('Codex query timed out') from None
            if message is None:
                raise QuotaUnavailable('Codex query ended')
            if message.get('id') in (1, 2) and 'error' in message:
                raise QuotaUnavailable('Codex account unavailable')
            if message.get('id') == 1:
                send({'method': 'initialized'})
                send({'id': 2, 'method': 'account/rateLimits/read'})
            elif message.get('id') == 2:
                result = message.get('result')
                if not isinstance(result, dict):
                    raise QuotaUnavailable('Invalid Codex response')
                return result
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        reader.join(timeout=2)
        process.stdin.close()
        process.stdout.close()


class QuotaCache:
    def __init__(self, fetch=read_codex, ttl=60, clock=time.time):
        self.fetch, self.ttl, self.clock = fetch, ttl, clock
        self.snapshot = None
        self.last_attempt = None
        self.failed = False
        self.lock = threading.Lock()

    def get(self):
        with self.lock:
            now = self.clock()
            if self.last_attempt is None or now - self.last_attempt >= self.ttl:
                self.last_attempt = now
                try:
                    self.snapshot = normalize(self.fetch(), now=self.clock())
                    self.failed = False
                except Exception:
                    self.failed = True
            if self.snapshot is None:
                raise QuotaUnavailable('Quota is temporarily unavailable')
            result = copy.deepcopy(self.snapshot)
            result['stale'] = self.failed or now - result['updatedAt'] > 900
            return result


def make_server(address, access_code, cache):
    if not access_code:
        raise ValueError('A read-only access code is required')

    class Handler(BaseHTTPRequestHandler):
        def send_json(self, status, value):
            data = json.dumps(value, ensure_ascii=False, allow_nan=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = urlsplit(self.path).path
            if path == '/health':
                return self.send_json(200, {'status': 'ok'})
            supplied = self.headers.get('Authorization', '').encode('utf-8')
            expected = ('Bearer ' + access_code).encode('utf-8')
            if not hmac.compare_digest(supplied, expected):
                return self.send_json(401, {'error': 'unauthorized'})
            if path != '/v1/quota':
                return self.send_json(404, {'error': 'not_found'})
            try:
                self.send_json(200, cache.get())
            except QuotaUnavailable:
                self.send_json(503, {'error': 'quota_unavailable'})

        def log_message(self, *args):
            # Do not log request URLs or authentication material.
            pass

    return ThreadingHTTPServer(address, Handler)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=18427)
    args = parser.parse_args()
    access_code = os.environ.get('QUOTA_ACCESS_CODE', '')
    if len(access_code) < 32:
        parser.error('QUOTA_ACCESS_CODE must contain at least 32 characters')
    server = make_server((args.host, args.port), access_code, QuotaCache())
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
