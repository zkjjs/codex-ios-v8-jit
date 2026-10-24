import json
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True).strip()

runtimes = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))['devices']
candidates = [d for runtime, devices in runtimes.items() if 'iOS-26' in runtime or 'iOS-27' in runtime for d in devices if 'iPhone' in d['name']]
if not candidates:
    print('No iOS 26+ simulator installed; UI screenshot unavailable.')
    raise SystemExit(0)
device = candidates[0]['udid']
run('xcrun', 'simctl', 'boot', device)
run('xcrun', 'simctl', 'bootstatus', device, '-b')
run('xcrun', 'simctl', 'status_bar', device, 'override', '--time', '9:41', '--batteryState', 'charged', '--batteryLevel', '100')
run('xcrun', 'simctl', 'install', device, 'build/simulator/Build/Products/Debug-iphonesimulator/CodexQuota.app')
run('xcrun', 'simctl', 'launch', device, 'com.zkjjs.codexquota')
time.sleep(4)
run('xcrun', 'simctl', 'io', device, 'screenshot', 'dist/login.png')
run('xcrun', 'simctl', 'terminate', device, 'com.zkjjs.codexquota')
run('xcrun', 'simctl', 'launch', device, 'com.zkjjs.codexquota', '--ui-preview')
time.sleep(4)
run('xcrun', 'simctl', 'io', device, 'screenshot', 'dist/dashboard-preview.png')
run('xcrun', 'simctl', 'shutdown', device)
