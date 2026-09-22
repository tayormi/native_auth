#!/usr/bin/env python3
"""Build local DartNative archives from a Git checkout, with source and MIT metadata."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--dn', default='dn', help='Path to the DartNative CLI')
parser.add_argument('--reuse-build', action='store_true', help='Package an existing dist build')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
if not args.reuse_build:
    subprocess.run([args.dn, 'plugin', 'build', '--owner', 'tayormi'], cwd=root, check=True)
artifacts = list((root / 'dist').glob('*/manifest.json'))
if len(artifacts) != 1:
    raise SystemExit('Expected one dist artifact. Move old builds out of dist first.')
artifact = artifacts[0].parent
manifest = json.loads(artifacts[0].read_text())
name, version = manifest['name'], manifest['version']
# The SDK currently emits first-party Commercial metadata for all plugins.
spec = artifact / f'{name}.podspec'
if spec.exists():
    text = spec.read_text()
    text = text.replace("{ :type => 'Commercial' }", "{ :type => 'MIT', :file => 'LICENSE' }")
    text = text.replace("{ 'DartNative' => 'hello@dartnative.com' }", "'tayormi'")
    spec.write_text(text)
for filename in ('LICENSE',):
    if (root / filename).exists():
        shutil.copyfile(root / filename, artifact / filename)
# Copy only nonignored checkout files, including native sources needed by consumers.
# Build output, local SDK paths, signing material, and generated files stay out.
source = root / 'dist' / f'{name}-{version}-src'
if source.exists():
    shutil.rmtree(source)
source.mkdir(parents=True)
files = subprocess.check_output(
    ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root
).decode().split('\0')
for filename in sorted(set(files) - {''}):
    path = root / filename
    if path.is_symlink() or not path.is_file():
        continue
    target = source / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, target)
# Refresh the Dart files in the binary distribution too.
shutil.copytree(root / 'lib', artifact / 'lib', dirs_exist_ok=True)
for filename in ('README.md', 'CHANGELOG.md', 'LICENSE'):
    shutil.copyfile(root / filename, artifact / filename)

def pack(directory, output, prefix=''):
    with tarfile.open(output, 'w:gz') as archive:
        for path in sorted(directory.rglob('*')):
            if path.is_file():
                info = archive.gettarinfo(str(path), arcname=prefix + path.relative_to(directory).as_posix())
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                with path.open('rb') as data:
                    archive.addfile(info, data)

checks = artifact / 'CHECKSUMS.txt'
checks.write_text(''.join(
    f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(artifact).as_posix()}\n'
    for path in sorted(artifact.rglob('*')) if path.is_file() and path != checks
))
binary = root / 'dist' / f'{name}-{version}.tar.gz'
source_archive = root / 'dist' / f'{name}-{version}-source.tar.gz'
pack(artifact, binary, artifact.name + '/')
pack(source, source_archive)
summary = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in (binary, source_archive)}
(root / 'dist/release-sha256.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
