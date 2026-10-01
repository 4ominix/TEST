#!/usr/bin/env python3
"""One source/manifest/package checker; inspects embedded signatures per Mach-O slice.

Structural validation only: not cryptographic trust or proof of iPhone operation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import struct
import sys

from macho import slices

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_ENTITLEMENTS = (
    'platform-application', 'com.apple.private.security.no-sandbox',
    'com.apple.private.security.storage.AppBundles',
    'com.apple.private.security.storage.AppDataContainers',
)
IGNORED = {'.git', '.theos', 'theos', 'packages', 'build', '__pycache__'}
MANIFEST = 'SOURCE_SHA256.json'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def source_files(root):
    # Prune dependency and Git directories BEFORE walking them.
    files = {}
    for directory, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in IGNORED)
        for name in dirs:
            require(not Path(directory, name).is_symlink(), f'Source directory symlink: {name}')
        for name in sorted(names):
            path = Path(directory, name)
            rel = path.relative_to(root).as_posix()
            if rel == MANIFEST or path.suffix in ('.pyc', '.deb'):
                continue
            require(not path.is_symlink(), f'Source symlink: {rel}')
            files[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    return files


def manifest(root, write=False):
    current = source_files(root)
    if write:
        (root / MANIFEST).write_text(json.dumps(current, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    else:
        recorded = json.loads((root / MANIFEST).read_text(encoding='utf-8'))
        require(isinstance(recorded, dict), 'Manifest must be a dictionary')
        require(recorded == current, 'Source manifest mismatch; upload all changed files, or regenerate after intentional edits')
    print(f'PASS: {len(current)} source hashes {"written" if write else "verified"}')


def plist(path):
    result = plistlib.loads(path.read_bytes())
    require(isinstance(result, dict), f'Plist root must be dictionary: {path}')
    return result


def entitlements(obj):
    require(isinstance(obj, dict), 'Missing entitlement dictionary')
    for key in REQUIRED_ENTITLEMENTS:
        require(obj.get(key) is True, f'Missing true entitlement: {key}')


def metadata(info):
    expected = {
        'CFBundleDisplayName': 'iCamV3', 'CFBundleExecutable': 'ICamController',
        'CFBundleIdentifier': 'com.icamv3.rebuild.controller', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '2.0.0', 'CFBundleVersion': '200', 'MinimumOSVersion': '15.0',
    }
    for key, value in expected.items():
        require(info.get(key) == value, f'Incorrect bundle field: {key}')
    require(info.get('NSPhotoLibraryUsageDescription'), 'Photo usage description missing')
    require('UIApplicationSceneManifest' not in info, 'Unexpected scene manifest: UIWindow launch must agree with delegate')


def png(path, size):
    data = path.read_bytes()
    require(data[:8] == b'\x89PNG\r\n\x1a\n' and len(data) >= 24 and data[12:16] == b'IHDR', f'Bad icon: {path}')
    require(struct.unpack('>II', data[16:24]) == (size, size), f'Bad icon dimensions: {path}')


def control(path):
    fields = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if line and not line[0].isspace():
            key, _, value = line.partition(':')
            require(_ == ':' and key not in fields, f'Invalid/duplicate control field: {key}')
            fields[key] = value.strip()
    for key, value in {'Package': 'com.icamv3.rebuild', 'Version': '2.0.0', 'Architecture': 'iphoneos-arm64e'}.items():
        require(fields.get(key) == value, f'Incorrect control field: {key}')
    require(fields.get('Conflicts') == 'com.icamv3.app' and fields.get('Replaces') == 'com.icamv3.app', 'Old package replacement metadata missing')
    require('mobilesubstrate' in fields.get('Depends', '') and 'rootless-compat' in fields.get('Pre-Depends', ''), 'Runtime dependencies missing')


def scripts(folder):
    for name in ('postinst', 'prerm'):
        data = (folder / name).read_bytes()
        require(data.startswith(b'#!/bin/sh\n') and b'\r' not in data, f'{name}: requires LF shell script')
        require(b'/Applications/ICamController.app' in data, f'{name}: wrong controller path')
        require(b'/var/lib/dpkg' not in data and b'rm -rf' not in data, f'{name}: destructive maintenance is forbidden')
    install = (folder / 'postinst').read_text(encoding='utf-8')
    for token in ('set -eu', 'chown mobile:mobile', 'chmod 0775', 'Settings.lock', 'uicache -p', 'ICamCamera ICamControls'):
        require(token in install, f'postinst: missing {token}')


def source(root):
    metadata(plist(root / 'App/Info.plist'))
    entitlements(plist(root / 'App/Entitlements.plist'))
    control(root / 'control')
    scripts(root / 'layout/DEBIAN')
    for suffix, size in (('', 60), ('@2x', 120), ('@3x', 180)):
        png(root / f'App/Resources/AppIcon60x60{suffix}.png', size)
    appmake = (root / 'App/Makefile').read_text(encoding='utf-8')
    require(re.search(r'^ARCHS\s*=\s*arm64\s*$', appmake, re.M), 'Controller must build arm64 only')
    require('RESOURCE_FILES = Info.plist' in appmake and 'CODESIGN_FLAGS = -SEntitlements.plist' in appmake, 'App resource/signing configuration missing')
    require('LIBRARIES' not in appmake and 'roothide' not in appmake, 'Controller must not hard-link bootstrap dylibs')
    rootmake = (root / 'Makefile').read_text(encoding='utf-8')
    require('SUBPROJECTS = App Camera Controls' in rootmake, 'Aggregator subprojects missing')
    paths = (root / 'Core/ICPaths.m').read_text(encoding='utf-8')
    require('dladdr' in paths and '.jbroot' in paths and 'stringByResolvingSymlinksInPath' in paths, 'RootHide path resolver missing')
    settings = (root / 'Core/ICSettings.m').read_text(encoding='utf-8')
    for token in ('flock(fd,LOCK_EX)', 'NSDataWritingAtomic', '@finally', '@"Floating":@NO'):
        require(token in settings, f'Settings invariant missing: {token}')
    engine = (root / 'Core/ICFrameEngine.m').read_text(encoding='utf-8')
    callback = engine.split('- (CVPixelBufferRef)copyFrameForWidth:', 1)[1].split('- (void)clearFrames', 1)[0]
    require('os_unfair_lock_trylock' in callback, 'Camera callback must not wait for renderer')
    require('_lastRequest-_healthyAt<.75' in callback, 'Worker-stall watchdog missing')
    for token in ('dispatch_sync', 'ICReadSettings', 'imageAtTime', 'render:'):
        require(token not in callback, f'Blocking work in camera callback: {token}')
    require('48*1024*1024' in engine and '_targets.count>=3' in engine, 'Frame-cache budgets missing')
    hook = (root / 'Camera/CameraHooks.mm').read_text(encoding='utf-8')
    sample = (root / 'Core/ICSample.m').read_text(encoding='utf-8')
    require('ICCopySampleFromPixels' in hook and 'CMSampleBufferCreateForImageBuffer' in sample and 'CMVideoFormatDescriptionCreateForImageBuffer' in sample and 'replacement?:sample' in hook and '@finally' in hook, 'Fail-safe replacement contract missing')
    require('ICRecordRequest(_requests' in callback and 'memcpy(requests,_requests' in engine, 'Multi-output request registry missing')
    require('CVPixelBufferLockBaseAddress' not in hook, 'Do not mutate real camera frames')
    delegate = (root / 'App/ICAppDelegate.m').read_text(encoding='utf-8')
    require('ICFrameEngine' not in delegate and 'ICReadSettings' not in delegate, 'Media/storage work at app entrypoint')
    for path in root.rglob('*'):
        if path.suffix not in ('.m', '.mm', '.h') or any(part in IGNORED for part in path.relative_to(root).parts):
            continue
        text = path.read_text(encoding='utf-8')
        require(not any(token in text for token in ('NSURLSession', 'vcnext.corev.bond', 'VCNextNetworkCompat', 'VCNextBrandUI', 'rtmp://', 'http://', 'https://')), f'Unexpected network/legacy code: {path}')
    print('PASS: source metadata, resources, offline and fail-safe structural checks')


def binary(path, app=False):
    items = slices(path.read_bytes())
    require({item['arch'] for item in items} == ({'arm64'} if app else {'arm64', 'arm64e'}), f'Wrong architecture set: {path}')
    for item in items:
        require(item['filetype'] == (2 if app else 6), f'Wrong Mach-O type: {path}')
        require(item['platform'] == 2 and item['minimum'] is not None and item['minimum'] <= (15 << 16), f'Wrong platform/minimum iOS: {path}')
        require(item['signature_present'], f'Unsigned Mach-O: {path}')
        for dependency in item['dependencies']:
            require('/var/jb/' not in dependency, f'Fixed rootless dependency in RootHide package: {dependency}')
            if app:
                system_libraries = {'/usr/lib/libSystem.B.dylib', '/usr/lib/libobjc.A.dylib', '/usr/lib/libc++.1.dylib'}
                require(dependency.startswith('/System/Library/') or dependency in system_libraries, f'Hard bootstrap dependency in controller: {dependency}')
                require('roothide' not in dependency.lower() and 'substrate' not in dependency.lower(), 'Bootstrap library in app')
        if app:
            entitlements(item['entitlements'])
    return items


def package(data, maint):
    app = data / 'Applications/ICamController.app'
    metadata(plist(app / 'Info.plist'))
    control(maint / 'control')
    scripts(maint)
    results = {'app': binary(app / 'ICamController', app=True)}
    for name, host in (('ICamCamera', 'mediaserverd'), ('ICamControls', 'SpringBoard')):
        base = data / 'Library/MobileSubstrate/DynamicLibraries'
        results[name] = binary(base / f'{name}.dylib')
        require(host in (base / f'{name}.plist').read_text(encoding='utf-8'), f'Missing injection target: {name}')
    for suffix, size in (('', 60), ('@2x', 120), ('@3x', 180)):
        png(app / f'AppIcon60x60{suffix}.png', size)
    if os.name != 'nt':
        for path in (app / 'ICamController', maint / 'postinst', maint / 'prerm'):
            require(path.stat().st_mode & 0o111, f'Executable permission missing: {path}')
    print(json.dumps(results, indent=2))
    print('PASS: extracted app, both tweaks, icons, metadata, embedded per-slice entitlements and RootHide paths')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest='command', required=True)
    for name in ('source', 'manifest'):
        command = subs.add_parser(name)
        command.add_argument('--root', type=Path, default=ROOT)
        if name == 'manifest':
            command.add_argument('--write', action='store_true')
    command = subs.add_parser('package')
    command.add_argument('--data', required=True, type=Path)
    command.add_argument('--control', required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == 'source':
            source(args.root)
        elif args.command == 'manifest':
            manifest(args.root, args.write)
        else:
            package(args.data, args.control)
    except (OSError, ValueError, TypeError, KeyError, struct.error, OverflowError, plistlib.InvalidFileException) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 1
    except Exception as error:
        # Includes ExpatError from strict XML parsing. Keep CLI diagnostics stable.
        print(f'ERROR: {type(error).__name__}: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
