#!/usr/bin/env python3
"""Freeze the complete current App and build Release for iOS and/or Simulator.

Requires a successful Native package proof whose compiled inputs match the
workspace. Does not sign, install, launch, or claim garment/UI acceptance.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import time


EXCLUDED = {'.git', '.build', '.swiftpm', 'DerivedData', 'xcuserdata',
            '__pycache__', '.cache', 'ModuleCache.noindex', 'SourcePackages',
            'SDKStatCaches.noindex', '.DS_Store'}
PARTS = ['TrailorAss.xcodeproj', 'TrailorAss', 'NativeClothCollision']


def ignored(name):
    return name in EXCLUDED or name.endswith('.xcuserstate')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(root):
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(n for n in dirs if not ignored(n))
        for name in dirs:
            if (Path(directory)/name).is_symlink():
                raise RuntimeError('Unreviewed symbolic link: '+str(Path(directory)/name))
        for name in sorted(files):
            if ignored(name):
                continue
            path = Path(directory)/name
            if path.is_symlink():
                raise RuntimeError('Unreviewed symbolic link: '+str(path))
            result[str(path.relative_to(root))] = sha(path)
    return result


def manifest(root):
    return {part+'/'+name: digest for part in PARTS
            for name, digest in hashes(root/part).items()}


def write(path, data):
    path.write_text(json.dumps(data, indent=2, sort_keys=True)+'\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--package-proof', type=Path, required=True)
    parser.add_argument('--platform', choices=['ios', 'simulator', 'all'], default='all')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    out, proof = args.output.resolve(), args.package_proof.resolve()
    if out == repo or repo in out.parents or out == proof or proof in out.parents:
        parser.error('Output must be a new directory outside the repository and Native proof')
    native_summary = json.loads((proof/'summary.json').read_text())
    if not native_summary['passed']:
        parser.error('The Native package proof did not pass')
    package = hashes(repo/'NativeClothCollision')
    reference = hashes(proof/'snapshot')
    compiled = lambda entries: {n: s for n, s in entries.items()
                                if n.startswith('Sources/') or n == 'Package.swift'}
    if compiled(package) != compiled(reference):
        parser.error('Current Native compiled sources differ from the verified package')
    out.mkdir(parents=True, exist_ok=False)
    before = manifest(repo)
    snapshot = out/'source'
    snapshot.mkdir()
    for part in PARTS:
        shutil.copytree(repo/part, snapshot/part,
                        ignore=lambda _path, names: [n for n in names if ignored(n)])
    after, copied = manifest(repo), manifest(snapshot)
    stable = before == after == copied
    native_match = compiled(hashes(snapshot/'NativeClothCollision')) == compiled(reference)
    binding = {'scope': 'Complete App Release build only; no install, UI, phone or garment acceptance',
               'sourceDirectory': str(repo), 'snapshotDirectory': str(snapshot),
               'stableBeforeAfterCopy': stable, 'sha256': copied,
               'originalBeforeSHA256': before, 'originalAfterCopySHA256': after,
               'nativeReference': str(proof/'snapshot'),
               'nativeProofSummarySHA256': sha(proof/'summary.json'),
               'nativeProofDeliverySHA256': sha(proof/'delivery-manifest.json'),
               'nativeCompiledInputsMatchReference': native_match,
               'nativeProofMacTestsExecuted': native_summary['macTestsExecuted'],
               'nativeTestsExecutedByAppBuild': False,
               'runnerSHA256': sha(Path(__file__)),
               'createdAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    write(out/'source-manifest.json', binding)
    shutil.copy2(Path(__file__), out/'build-app-release.py')
    if not stable or not native_match:
        raise RuntimeError('Inputs changed during copy; no mixed-source build started')
    results = []
    for kind in (['ios', 'simulator'] if args.platform == 'all' else [args.platform]):
        work = out/kind
        work.mkdir()
        (work/'tmp').mkdir()
        destination = 'generic/platform=iOS' + (' Simulator' if kind == 'simulator' else '')
        command = ['xcodebuild', '-project', str(snapshot/'TrailorAss.xcodeproj'),
                   '-scheme', 'TrailorAss', '-configuration', 'Release',
                   '-destination', destination, '-derivedDataPath', str(work/'DerivedData'),
                   '-resultBundlePath', str(work/'build.xcresult'),
                   '-clonedSourcePackagesDirPath', str(work/'SourcePackages'),
                   '-packageCachePath', str(work/'PackageCache'),
                   '-disableAutomaticPackageResolution', '-skipPackageUpdates', '-jobs', '2',
                   'CODE_SIGNING_ALLOWED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO',
                   'CLANG_MODULE_CACHE_PATH='+str(work/'ModuleCache.noindex'),
                   'SWIFT_MODULE_CACHE_PATH='+str(work/'SwiftModuleCache.noindex'),
                   'SDK_STAT_CACHE_DIR='+str(work/'SDKStatCaches.noindex'), 'build']
        env = dict(os.environ, TMPDIR=str(work/'tmp')+'/',
                   SWIFTPM_MODULECACHE_OVERRIDE=str(work/'ManifestModuleCache'),
                   CLANG_MODULE_CACHE_PATH=str(work/'ManifestModuleCache'))
        began = time.monotonic()
        print('START '+kind, flush=True)
        with (work/'build.log').open('w') as log:
            log.write(json.dumps(command)+'\n')
            log.flush()
            process = subprocess.run(command, cwd=snapshot, env=env,
                                     stdout=log, stderr=subprocess.STDOUT)
        result = {'platform': kind, 'exitCode': process.returncode, 'command': command,
                  'seconds': time.monotonic()-began,
                  'snapshotUnchanged': manifest(snapshot) == copied}
        app = work/'DerivedData/Build/Products'/(
            'Release-iphonesimulator' if kind == 'simulator' else 'Release-iphoneos')/'TrailorAss.app'
        if process.returncode == 0:
            if not (app/'TrailorAss').is_file():
                raise RuntimeError('Build returned success without the App executable')
            result['appPath'] = str(app)
            write(work/'app-manifest.json', hashes(app))
        write(work/'result.json', result)
        results.append(result)
        print('TERMINAL '+json.dumps({k: v for k, v in result.items() if k != 'command'}), flush=True)
        if process.returncode or not result['snapshotUnchanged']:
            break
    expected = 2 if args.platform == 'all' else 1
    passed = len(results) == expected and all(r['exitCode'] == 0 and r['snapshotUnchanged'] for r in results)
    write(out/'summary.json', {'passed': passed, 'results': results,
                              'workspaceUnchangedAfterBuild': manifest(repo) == copied,
                              'installedOrLaunched': False, 'uiOrGarmentAccepted': False})
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
