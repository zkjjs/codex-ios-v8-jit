#!/usr/bin/env python3
"""Single-owner Codex quota bridge. Standard library only; never serves token files."""
import argparse
import base64
import hmac
import json
import os
import pathlib
import secrets
import ssl
import socketserver
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann'
AUTH = 'https://auth.openai.com'
USAGE = 'https://chatgpt.com/backend-api/wham/usage'

class UpstreamError(Exception):
    def __init__(self, status, retry=60):
        self.status = status
        self.retry = max(1, retry)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None


def request_json(method, url, body=None, headers=None):
    headers = dict(headers or {})
    headers['Accept'] = 'application/json'
    if body is None: data = None
    elif url.endswith('/oauth/token'):
        data = urllib.parse.urlencode(body).encode()
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    else:
        data = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=25) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
            if len(raw) > 2 * 1024 * 1024: raise UpstreamError(502)
            result = json.loads(raw)
            if not isinstance(result, dict): raise UpstreamError(502)
            return result
    except urllib.error.HTTPError as error:
        try: retry = int(error.headers.get('Retry-After', '60'))
        except ValueError: retry = 60
        raise UpstreamError(error.code, retry) from None
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        raise UpstreamError(502) from None


def jwt_claims(token):
    try:
        part = token.split('.')[1]
        result = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
        return result if isinstance(result,dict) else {}
    except (ValueError, IndexError, TypeError): return {}

class Bridge:
    def __init__(self, directory, key, upstream=request_json, clock=time.time):
        if len(key) < 32: raise ValueError('Gateway key must be at least 32 characters')
        self.directory = pathlib.Path(directory)
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.directory, 0o700)
        self.key, self.upstream, self.clock = key, upstream, clock
        self.lock = threading.RLock()
        self.flows = {}
        self.cache = None
        self.retry_at = 0
        self.account = {}
        path = self.directory / 'account.json'
        if path.exists():
            os.chmod(path, 0o600)
            self.account = json.loads(path.read_text())

    def save(self):
        path = self.directory / 'account.json'
        temporary = self.directory / ('account-' + secrets.token_hex(8) + '.tmp')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            json.dump(self.account, stream)
            stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)

    def dispatch(self, method, path, body, authorization):
        if path == '/health' and method == 'GET': return 200, {'status':'ok','version':'1.1.0'}
        if not hmac.compare_digest(authorization.encode(), ('Bearer ' + self.key).encode()):
            return 401, {'code':'pairing_required','message':'服务器配对密钥不正确，请重新配对。'}
        with self.lock:
            now = self.clock()
            if method == 'POST' and path == '/v1/logout':
                self.account = {}; self.cache = None; self.flows.clear(); self.save()
                return 200, {'status':'logged_out'}
            if self.retry_at > now:
                return 429, {'code':'rate_limited','message':'服务器暂缓请求，请稍后重试。','retry_after':max(1,int(self.retry_at-now))}
            try:
                if method == 'POST' and path == '/v1/login/start': return self.start(now)
                if method == 'POST' and path == '/v1/login/poll': return self.poll(body, now)
                if method == 'GET' and path == '/v1/usage': return self.usage(now)
                return 404, {'code':'not_found','message':'接口不存在。'}
            except UpstreamError as error:
                if error.status == 429:
                    self.retry_at = now + error.retry
                    return 429, {'code':'rate_limited','message':'OpenAI 请求限流，请稍后重试。','retry_after':error.retry}
                if error.status in (400,401):
                    return 409, {'code':'login_required','message':'账号授权已失效，请重新登录。'}
                return 502, {'code':'upstream_unavailable','message':'服务器访问 OpenAI 失败。','upstream_status':error.status}
            except (ValueError, KeyError, TypeError):
                return 502, {'code':'upstream_format','message':'OpenAI 返回的数据格式暂不支持。'}

    def start(self, now):
        result = self.upstream('POST', AUTH + '/api/accounts/deviceauth/usercode', {'client_id':CLIENT_ID})
        code = result.get('user_code') or result['usercode']
        interval = min(60, max(5,int(result.get('interval',5))))
        flow_id = secrets.token_urlsafe(32)
        # Single owner; beginning a new login invalidates abandoned flows.
        self.flows = {flow_id:{'id':result['device_auth_id'],'code':code,'expires':now+900,'next':now+interval,'interval':interval}}
        return 200, {'device_auth_id':flow_id,'user_code':code,'interval':interval}

    def poll(self, body, now):
        flow_id = body.get('flow_id')
        if not isinstance(flow_id,str): return 400, {'code':'invalid_request','message':'缺少授权流程编号。'}
        flow = self.flows.get(flow_id)
        if not flow or flow['expires'] <= now:
            self.flows.pop(flow_id,None)
            return 410, {'code':'login_expired','message':'授权码已过期，请重新生成。'}
        if flow['next'] > now: return 202, {'status':'pending'}
        flow['next'] = now + flow['interval']
        try:
            result = self.upstream('POST', AUTH + '/api/accounts/deviceauth/token', {'device_auth_id':flow['id'],'user_code':flow['code']})
        except UpstreamError as error:
            if error.status in (403,404): return 202, {'status':'pending'}
            raise
        # Authorization codes must not be exchanged twice after an uncertain response.
        self.flows.pop(flow_id,None)
        tokens = self.upstream('POST', AUTH + '/oauth/token', {
            'grant_type':'authorization_code','client_id':CLIENT_ID,
            'code':result['authorization_code'],'code_verifier':result['code_verifier'],
            'redirect_uri':AUTH + '/deviceauth/callback'})
        self.install_tokens(tokens, now)
        self.cache = None
        return 200, {'status':'authenticated'}

    def install_tokens(self, tokens, now):
        access = tokens['access_token']
        refresh = tokens.get('refresh_token') or self.account.get('refresh_token')
        if not isinstance(access,str) or not isinstance(refresh,str): raise ValueError('Missing tokens')
        claims = jwt_claims(access)
        identity = jwt_claims(tokens.get('id_token',''))
        account = claims.get('https://api.openai.com/auth', {}) or identity.get('https://api.openai.com/auth', {})
        self.account = {'access_token':access,'refresh_token':refresh,
                        'account_id':account.get('chatgpt_account_id') or self.account.get('account_id'),
                        'expires_at':claims.get('exp',now+float(tokens.get('expires_in',3600)))}
        self.save()

    def refresh(self, now):
        tokens = self.upstream('POST', AUTH + '/oauth/token', {'grant_type':'refresh_token','client_id':CLIENT_ID,'refresh_token':self.account['refresh_token']})
        self.install_tokens(tokens,now)

    def usage(self, now):
        if not self.account.get('access_token'):
            return 409, {'code':'login_required','message':'请先登录 ChatGPT 账号。'}
        if self.cache and now - self.cache[0] < 30: return 200, self.cache[1]
        if self.account.get('expires_at',0) <= now + 120: self.refresh(now)
        def fetch():
            headers = {'Authorization':'Bearer ' + self.account['access_token']}
            if self.account.get('account_id'): headers['ChatGPT-Account-Id'] = self.account['account_id']
            return self.upstream('GET', USAGE, headers=headers)
        try: result = fetch()
        except UpstreamError as error:
            if error.status != 401: raise
            self.refresh(now); result = fetch()
        if not any(k in result for k in ('plan_type','rate_limit')): raise ValueError('Invalid usage')
        self.cache = (now,result)
        return 200,result

class SecureServer(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, context):
        self.context = context
        self.slots = threading.BoundedSemaphore(32)
        super().__init__(address, Handler)
    def server_bind(self):
        # HTTPServer otherwise performs reverse DNS before listen(), delaying startup
        # on networks without a usable PTR resolver. No hostname discovery is needed.
        socketserver.TCPServer.server_bind(self)
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]
    def get_request(self):
        connection, address = self.socket.accept()
        connection.settimeout(30)
        return self.context.wrap_socket(connection, server_side=True, do_handshake_on_connect=False), address
    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request); return
        try: super().process_request(request,address)
        except Exception:
            self.slots.release(); raise
    def process_request_thread(self, request, address):
        try: super().process_request_thread(request,address)
        finally: self.slots.release()

class Handler(BaseHTTPRequestHandler):
    server_version = 'CodexQuota/1.1'
    def log_message(self, *args): pass  # No authorization codes, headers or bodies in access logs.
    def do_GET(self): self.handle_api()
    def do_POST(self): self.handle_api()
    def handle_api(self):
        self.connection.settimeout(30)
        try:
            length = int(self.headers.get('Content-Length','0'))
            if length < 0 or length > 8192:
                self.reply(413,{'message':'请求过大。'}); return
            body = json.loads(self.rfile.read(length)) if length else {}
            if not isinstance(body,dict): raise ValueError()
        except (ValueError,TimeoutError):
            self.reply(400,{'message':'请求格式不正确。'}); return
        try:
            status,payload = self.server.bridge.dispatch(self.command,self.path,body,self.headers.get('Authorization',''))
            self.reply(status,payload)
        except Exception:
            self.reply(500,{'code':'internal_error','message':'服务器内部错误，请检查本机服务状态。'})
    def reply(self,status,payload):
        data = json.dumps(payload,ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(data)))
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        if status == 429: self.send_header('Retry-After',str(payload.get('retry_after',60)))
        self.end_headers(); self.wfile.write(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory',default='/var/lib/codex-quota-bridge')
    parser.add_argument('--port',type=int,default=8765)
    parser.add_argument('--cert',required=True)
    parser.add_argument('--key',required=True)
    args=parser.parse_args()
    service = Bridge(args.directory,os.environ.get('CODEX_QUOTA_KEY',''))
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version=ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(args.cert,args.key)
    server = SecureServer(('0.0.0.0',args.port),context)
    server.bridge=service
    print('Codex quota bridge ready (HTTPS).',flush=True)
    server.serve_forever()

if __name__ == '__main__': main()
