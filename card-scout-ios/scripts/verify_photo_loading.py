#!/usr/bin/env python3
"""Build/run the real photo views in an isolated iOS simulator app. No user data or server calls."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def audit_image_sources(root):
    """Prevent a screen from quietly reintroducing its own display loader."""
    decoder_files = {'ImagePipeline.swift', 'CardArtwork.swift', 'MacClient.swift', 'PreviewData.swift'}
    patterns = [r'\bAsyncImage\b', r'\boriginalPhoto\s*\(', r'\bReferenceImageCache\b',
                r'\bCardArtworkRenderer\b']
    display_decode = r'UIImage\s*\(\s*(?:data|contentsOfFile)\s*:|CGImageSourceCreate|Data\s*\(\s*contentsOf\s*:'
    violations = []
    for path in sorted((root / 'App').glob('*.swift')):
        source = path.read_text()
        for pattern in patterns:
            if re.search(pattern, source):
                violations.append(f'{path.name}: legacy loader {pattern}')
        if path.name not in decoder_files:
            # AppStore validates imported evidence; it does not decode for display.
            if path.name == 'AppStore.swift':
                source = '\n'.join(line for line in source.splitlines() if 'Data(base64Encoded:' not in line)
            if re.search(display_decode, source):
                violations.append(f'{path.name}: display decoding bypasses ImagePipeline')
            if path.name != 'AppStore.swift' and re.search(r'URLSession|NSCache|URLCache', source):
                violations.append(f'{path.name}: independent image network/cache implementation')
    if violations:
        raise SystemExit('\n'.join(violations))
    print('Image source audit passed: no legacy loaders or view-level decoding.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='Booted iOS simulator UUID')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    audit_image_sources(root)
    work = Path(tempfile.mkdtemp(prefix='cardscout-photo-regression-'))
    shutil.copytree(root / 'App', work / 'App')
    shutil.copytree(root / 'CardScout.xcodeproj', work / 'CardScout.xcodeproj')
    (work / 'Core').symlink_to(root / 'Core', target_is_directory=True)
    (work / 'App/CardScoutApp.swift').unlink()
    shutil.copy(root / 'Tests/PhotoLoadingRegression.swift', work / 'App/PhotoLoadingRegression.swift')
    bundle = 'com.tobiaslatta.cardscout.photoregression'
    log = work / 'build.log'
    with log.open('w') as output:
        build = subprocess.run(['xcodebuild', '-project', str(work / 'CardScout.xcodeproj'), '-scheme', 'CardScout',
                                '-configuration', 'Debug', '-sdk', 'iphonesimulator', '-destination', f'id={args.device}',
                                '-derivedDataPath', str(work / 'build'), 'CODE_SIGNING_ALLOWED=NO',
                                f'PRODUCT_BUNDLE_IDENTIFIER={bundle}', 'build'], stdout=output, stderr=subprocess.STDOUT)
    if build.returncode:
        print(log.read_text()[-12000:])
        raise SystemExit(build.returncode)
    run('xcrun', 'simctl', 'install', args.device, str(work / 'build/Build/Products/Debug-iphonesimulator/CardScout.app'))
    # Repeated runs must not consume a stale result file.
    container = Path(run('xcrun', 'simctl', 'get_app_container', args.device, bundle, 'data', capture_output=True).stdout.strip())
    result = container / 'Documents/photo-regression.json'
    result.unlink(missing_ok=True)
    run('xcrun', 'simctl', 'launch', '--terminate-running-process', args.device, bundle)
    for _ in range(180):
        if result.exists():
            data = json.loads(result.read_text())
            print(json.dumps(data, indent=2))
            run('xcrun', 'simctl', 'terminate', args.device, bundle)
            raise SystemExit(0 if data['passed'] else 1)
        time.sleep(0.5)
    raise SystemExit(f'Regression app timed out. Build log: {log}')


if __name__ == '__main__':
    main()
