#!/usr/bin/env python3
"""Upload prepared DartNative release artifacts after marketplace registration."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('package', type=Path, nargs='?', default=Path(__file__).resolve().parents[1])
args = parser.parse_args()
root = args.package.resolve()
artifacts = list((root / 'dist').glob('*/manifest.json'))
assert len(artifacts) == 1, 'Expected exactly one prepared artifact'
manifest = json.loads(artifacts[0].read_text())
name, version = manifest['name'], manifest['version']
assert manifest['owner'] == 'tayormi'
response_file = root / 'dist/publish-response.json'
if response_file.exists():
    prior = json.loads(response_file.read_text())
    if isinstance(prior.get('version'), dict):
        raise SystemExit('An accepted response already exists. Verify registry visibility before retrying.')
check = subprocess.check_output(['curl', '--silent', '--show-error',
    f'https://dartpub.dev/api/plugins/check-name?owner=tayormi&name={name}'], text=True)
assert json.loads(check).get('code') == 'taken', 'Register the package and accept the publishing agreement first'
token = os.environ.get('DN_PUBLISH_TOKEN')
if not token:
    for file in (Path.home() / '.flutter_settings', Path.home() / '.config/flutter/settings'):
        if file.exists():
            token = json.loads(file.read_text()).get('publish-token')
            if token: break
assert token, 'No DartNative publish token configured'
binary = root / 'dist' / f'{name}-{version}.tar.gz'
source = root / 'dist' / f'{name}-{version}-source.tar.gz'
fields = {
    'owner': 'tayormi', 'name': name, 'version': version,
    'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
    'readme': (root / 'README.md').read_text(),
    'changelog': (root / 'CHANGELOG.md').read_text(),
    'examples': '```dart\n' + (root / 'example/lib/main.dart').read_text() + '```\n',
    'manifest': artifacts[0].read_text(),
    'source_b64': base64.b64encode(source.read_bytes()).decode(),
}
command = ['curl', '--silent', '--show-error', '--header', '@-',
    '--output', str(response_file), '--write-out', '%{http_code}',
    '--form', f'tarball=@{binary}']
for key, value in fields.items():
    command += ['--form-string', f'{key}={value}']
command += ['https://dartpub.dev/api/plugins/publish']
result = subprocess.run(command, input=f'Authorization: Bearer {token}\n',
                        capture_output=True, text=True, check=True)
response = json.loads(response_file.read_text())
if result.stdout != '200' or not isinstance(response.get('version'), dict):
    print('Upload not confirmed:', result.stdout, response)
    raise SystemExit(1)
print(json.dumps({'name': name, 'status': result.stdout, 'response': response}, indent=2))
