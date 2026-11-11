"""Determine whether a scheduled ARM64 build has new inputs."""
import hashlib
import ipaddress
import json
import os
import re
import subprocess
import sys
import time

LABEL = 'io.github.corekeeper.build-inputs'
MIRROR = 'ports.ubuntu.com'
BUILD_FILES = ('Dockerfile', '.dockerignore', 'scripts', 'fex/install-rootfs.sh',
               'fex/steam-build.sh', '.github/scripts/image-inputs.py',
               '.github/workflows/docker-image.yml', 'tests/fex-image-smoke.sh',
               'tests/entry-smoke.sh', 'tests/setup-stub.sh')


def run(*args, timeout=120):
    return subprocess.run(args, check=True, capture_output=True, text=True,
                          timeout=timeout).stdout.strip()


def arm_reference(ref):
    data = json.loads(run('docker', 'manifest', 'inspect', '--verbose', ref))
    entries = data if isinstance(data, list) else [data]
    digests = {item['Descriptor']['digest'] for item in entries
               if item['Descriptor'].get('platform', {}).get('architecture') == 'arm64'
               and item['Descriptor']['platform'].get('os') == 'linux'}
    if len(digests) != 1 or not re.fullmatch(r'sha256:[0-9a-f]{64}', next(iter(digests))):
        raise ValueError(f'Expected exactly one Linux ARM64 manifest for {ref}')
    return ref.rsplit(':', 1)[0] + '@' + digests.pop()


def mirror_mapping():
    # Use the hosted runner's resolver, without weakening BuildKit isolation or APT signatures.
    for delay in (0, 2, 5):
        time.sleep(delay)
        try:
            addresses = run('getent', 'ahostsv4', MIRROR, timeout=15)
            return f'{MIRROR}={ipaddress.IPv4Address(addresses.split()[0])}'
        except (subprocess.SubprocessError, IndexError, ValueError):
            continue
    raise ValueError(f'Hosted runner could not resolve {MIRROR}')


def fingerprint(inputs):
    return hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()


def build_required(ref, expected, mirror):
    image = arm_reference(ref)
    config = json.loads(run('docker', 'buildx', 'imagetools', 'inspect', image,
                            '--format', '{{json .Image}}'))
    labels = config['config'].get('Labels') or {}
    if labels.get(LABEL) != expected:
        return True, 'base, RootFS, downloader or build inputs changed (or no baseline yet)'
    # Use the exact installed package set and the same upgrade policy as the Dockerfile.
    # Only refresh signed indices and simulate; don't install or start Core Keeper.
    plan = run('docker', 'run', '--rm', '--platform', 'linux/arm64', '--user', '0:0',
               '--add-host', mirror, '--entrypoint', 'bash', image, '-ec',
               'export LC_ALL=C; '
               'apt-get -o Acquire::Retries=3 -o APT::Update::Error-Mode=any update >&2; '
               'apt-get -s upgrade --with-new-pkgs', timeout=600)
    summary = re.search(r'^(\d+) upgraded, (\d+) newly installed, (\d+) to remove and \d+ not upgraded\.$',
                        plan, re.MULTILINE)
    if not summary:
        raise ValueError('APT did not return a recognizable upgrade plan')
    changed = any(int(count) for count in summary.groups())
    return changed, 'APT upgrades available' if changed else 'all checked inputs unchanged'


def main():
    rootfs = arm_reference('docker.io/library/ubuntu:24.04')
    runtime = arm_reference('docker.io/library/ubuntu:26.04')
    guest = json.loads(run('bash', 'fex/install-rootfs.sh', '--metadata-only', timeout=300))
    source = run('git', 'ls-tree', '-r', 'HEAD', '--', *BUILD_FILES)
    expected = fingerprint([rootfs, runtime, guest, os.environ['DEPOT_VERSION'],
                            os.environ['DEPOT_ASSET'], source])
    mirror = mirror_mapping()
    changed, reason = True, 'source change or explicitly requested build'
    if os.environ['CHECK_INPUTS'] == 'true':
        changed, reason = build_required(os.environ['IMAGE'].lower() + ':fex', expected, mirror)
    print(f'Image build required: {changed} ({reason})', flush=True)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in dict(build=str(changed).lower(), fingerprint=expected,
                               rootfs=rootfs, runtime=runtime, mirror=mirror,
                               guest_url=guest['URL'], guest_hash=guest['Hash']).items():
            print(f'{key}={value}', file=output)


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        print(error.stderr[-3000:], file=sys.stderr)
        sys.exit(f'Image input check failed: {error.cmd[0]} exited {error.returncode}')
