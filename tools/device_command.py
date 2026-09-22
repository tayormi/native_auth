#!/usr/bin/env python3
"""Send a JSON command to a debug example built with AUTH_TEST_DRIVER=true."""
import argparse
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('platform', choices=['ios', 'android'])
parser.add_argument('device', help='Simulator UDID or adb serial')
parser.add_argument('command', help='JSON object with id and action')
parser.add_argument('--adb', default='adb')
parser.add_argument('--wait', type=float, default=10)
args = parser.parse_args()
command = json.loads(args.command)
identifier = command['id']
if not isinstance(identifier, str) or not identifier or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in identifier):
    parser.error('id must contain only letters, digits, underscores, and hyphens')
result_name = f'auth-result-{identifier}.json'
if args.platform == 'ios':
    container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.device,
                                         'dev.tayormi.nativeAuthExample', 'data'], text=True).strip()
    docs = Path(container) / 'Documents'
    result = docs / result_name
    result.unlink(missing_ok=True)
    pending = docs / 'auth-command.tmp'
    pending.write_text(json.dumps(command))
    pending.replace(docs / 'auth-command.json')
    def read():
        return result.read_text() if result.exists() else None
else:
    base = [args.adb, '-s', args.device, 'shell', 'run-as', 'dev.tayormi.native_auth_example']
    subprocess.run(base + ['rm', '-f', 'files/' + result_name], check=True)
    subprocess.run(base + ['sh', '-c', "'cat > files/auth-command.tmp && mv files/auth-command.tmp files/auth-command.json'"],
                   input=json.dumps(command), text=True, check=True)
    def read():
        result = subprocess.run(base + ['cat', 'files/' + result_name], capture_output=True, text=True)
        return result.stdout if result.returncode == 0 else None
if args.wait == 0:
    print(json.dumps({'sent': identifier}))
else:
    deadline = time.monotonic() + args.wait
    while time.monotonic() < deadline:
        value = read()
        if value:
            print(json.dumps(json.loads(value), indent=2))
            break
        time.sleep(.2)
    else:
        raise SystemExit('No result before the command deadline.')
