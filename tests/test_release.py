"""Host regression tests for release validation, including malformed input controls.

Synthetic Mach-O fixtures test the parser, not signing trust or iOS execution.
"""
from contextlib import redirect_stdout
import io
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import macho
import verify_release as verify


def thin(arch='arm64', app=True, ent=None, deps=('/usr/lib/libSystem.B.dylib',), minimum=15 << 16, signed=True, platform=2):
    commands = [struct.pack('<6I', 0x32, 24, platform, minimum, 0, 0)]
    for dep in deps:
        name = dep.encode() + b'\0'
        name += b'\0' * (-(24 + len(name)) % 8)
        commands.append(struct.pack('<6I', 0xc, 24 + len(name), 24, 0, 0, 0) + name)
    if ent is None:
        ent = {key: True for key in verify.REQUIRED_ENTITLEMENTS}
    xml = plistlib.dumps(ent)
    cd = struct.pack('>II', 0xfade0c02, 44) + b'\0' * 36
    entitlement_blob = struct.pack('>II', 0xfade7171, 8 + len(xml)) + xml
    size = 28 + len(cd) + len(entitlement_blob)
    signature = struct.pack('>III4I', 0xfade0cc0, size, 2, 0, 28, 5, 28 + len(cd)) + cd + entitlement_blob
    if signed:
        commands.append(struct.pack('<4I', 0x1d, 16, 32 + sum(map(len, commands)) + 16, len(signature) + 8))
    header = struct.pack('<8I', 0xfeedfacf, 0x100000c, {'arm64': 0, 'arm64e': 2}[arch], 2 if app else 6, len(commands), sum(map(len, commands)), 0, 0)
    return header + b''.join(commands) + (signature + b'\0' * 8 if signed else b'')


def fat(a, b):
    start = 48
    return struct.pack('>II', 0xcafebabe, 2) + struct.pack('>5I', 0x100000c, 0, start, len(a), 0) + struct.pack('>5I', 0x100000c, 2, start + len(a), len(b), 0) + a + b


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def file(self, data):
        path = self.root / 'binary'
        path.write_bytes(data)
        return path

    def cli(self, *args):
        return subprocess.run([sys.executable, str(ROOT / 'tools/verify_release.py'), *map(str, args)], capture_output=True, text=True)

    def test_source(self):
        with redirect_stdout(io.StringIO()):
            verify.source(ROOT)

    def test_multi_output_request_registry_contract(self):
        engine = (ROOT / 'Core/ICFrameEngine.m').read_text(encoding='utf-8')
        callback = engine.split('- (CVPixelBufferRef)copyFrameForWidth:', 1)[1].split('- (void)clearFrames', 1)[0]
        self.assertIn('ICRecordRequest(_requests,width,height,format,_lastRequest)', callback)
        self.assertIn('memcpy(requests,_requests,sizeof(requests))', engine)
        self.assertIn('ICRequestLive(requests[i],now)', engine)
        self.assertNotIn('_requestedWidth', engine)
        self.assertNotIn('_requestedHeight', engine)
        registry = (ROOT / 'Core/ICRequests.h').read_text(encoding='utf-8')
        self.assertIn('slots[3]', registry)
        self.assertIn('slots[i].format==format', registry)
        self.assertIn('now-slot.time<=2', registry)

    def test_sample_format_derived_from_replacement(self):
        sample = (ROOT / 'Core/ICSample.m').read_text(encoding='utf-8')
        self.assertIn('CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,pixels,&format)', sample)
        self.assertLess(sample.index('CMVideoFormatDescriptionCreateForImageBuffer'), sample.index('CMSampleBufferCreateForImageBuffer'))
        self.assertNotIn('CMSampleBufferGetFormatDescription(original)', sample)
        for token in ('CVPixelBufferGetWidth', 'CVPixelBufferGetHeight', 'CVPixelBufferGetPixelFormatType',
                      'CMSampleBufferGetSampleTimingInfo', 'CMCopyDictionaryOfAttachments',
                      'CMSampleBufferGetSampleAttachmentsArray', '@finally', 'if(format)CFRelease(format)'):
            self.assertIn(token, sample)
        self.assertNotIn('CVBufferSetAttachment', sample)
        self.assertNotIn('CVPixelBufferLockBaseAddress', sample)
        self.assertIn('../Core/ICSample.m', (ROOT / 'Camera/Makefile').read_text(encoding='utf-8'))

    def test_native_feature_tests_are_in_workflow(self):
        workflow = (ROOT / '.github/workflows/build-deb.yml').read_text(encoding='utf-8')
        for file in ('tests/geometry.c', 'tests/requests.c', 'tests/storage.m', 'tests/sample.m'):
            self.assertIn(file, workflow)
            self.assertTrue((ROOT / file).is_file())
        self.assertIn('Core/ICSample.m', workflow)

    def test_classic_control_symbols_and_action_mapping(self):
        panel = (ROOT / 'UI/ICAdjustments.m').read_text(encoding='utf-8')
        mapping = {'arrow.up': 1, 'arrow.left': 2, 'arrow.clockwise': 9,
                   'arrow.right': 4, 'arrow.down': 5, 'minus.magnifyingglass': 6,
                   'plus.magnifyingglass': 8, 'arrow.left.and.right': 11,
                   'arrow.counterclockwise': 10, 'chevron.right': 12}
        for symbol, tag in mapping.items():
            self.assertIn(f'button:@"{symbol}" tag:{tag}', panel)
        for action in ('case 1:y-=.08', 'case 2:x-=.08', 'case 4:x+=.08',
                       'case 5:y+=.08', 'case 6:zoom/=1.1', 'case 8:zoom*=1.1',
                       'case 9:s[@"Rotation"]', 'case 10:x=0;y=0;zoom=1',
                       'case 11:s[@"Mirror"]=@(![s[@"Mirror"] boolValue])'):
            self.assertIn(action, panel)
        self.assertIn('ICUpdateSettings', panel)
        self.assertIn('error?@"Lỗi lưu cấu hình"', panel)
        self.assertIn('if(self.didClose)self.didClose()', panel)
        self.assertIn('@interface ICAdjustments : UIView', (ROOT / 'UI/ICAdjustments.h').read_text())

    def test_classic_control_layout_source_coordinates(self):
        # Source-derived coordinate/spacing checks, NOT rendered UIKit UI tests.
        panel = (ROOT / 'UI/ICAdjustments.m').read_text(encoding='utf-8')
        matches = re.findall(r'@(\d+):@\[@(\d+),@(\d+)\]', panel)
        points = {int(tag): (int(x), int(y)) for tag, x, y in matches}
        self.assertEqual(set(points), {1, 2, 9, 4, 5, 6, 8, 11})
        self.assertEqual(points[1][0], points[9][0])
        self.assertEqual(points[5][0], points[9][0])
        self.assertEqual(points[2][1], points[9][1])
        self.assertEqual(points[4][1], points[9][1])
        self.assertLess(points[1][1], points[9][1])
        self.assertGreater(points[5][1], points[9][1])
        for x, y in points.values():
            self.assertGreaterEqual(x, 0)
            self.assertGreaterEqual(y, 0)
            self.assertLessEqual(x + 34, 194)
            self.assertLessEqual(y + 34, 238)
        self.assertLess(points[6][0] + 34, points[8][0])
        self.assertGreater(points[11][1], points[6][1] + 34)

    def test_classic_app_shell_keeps_media_and_controls(self):
        app = (ROOT / 'App/ICMainController.m').read_text(encoding='utf-8')
        self.assertIn('self.title=@"iCamV3"', app)
        self.assertNotIn('self.title=@"iCamV3 · Rebuild"', app)
        self.assertNotIn('UIUserInterfaceStyleDark', app)
        for token in ('toggleControls', 'self.adjustments.didClose', 'self.diagnostics.hidden=YES',
                      'share.popoverPresentationController.sourceView=self.view',
                      'loadFileRepresentationForTypeIdentifier', 'copyItemAtURL',
                      'UISegmentedControl', 'gesture.scale', 'ICUpdateSettings',
                      '480*viewport.height/viewport.width'):
            self.assertIn(token, app)

    def test_floating_lock_guard_and_pass_through(self):
        floating = (ROOT / 'Controls/FloatingControls.m').read_text(encoding='utf-8')
        for token in ('camera.aperture', 'com.apple.springboard.lockstate',
                      'notify_get_state(self.lockToken,&locked)==NOTIFY_STATUS_OK',
                      'generation!=strongSelf.refreshGeneration', '[strongSelf isUnlocked]',
                      'if(![self isUnlocked]){self.bubble.hidden=YES;self.panel.hidden=YES;return;}',
                      'self.view.safeAreaInsets', 'if(self.bubble.hidden || ![self isUnlocked])return',
                      '(hit==self || hit==self.rootViewController.view)?nil:hit',
                      'weakSelf.panel.hidden=YES'):
            self.assertIn(token, floating)

    def test_engine_timer_lifetime_contract(self):
        # Source ownership contract, not a substitute for the native ARC test.
        engine = (ROOT / 'Core/ICFrameEngine.m').read_text(encoding='utf-8')
        self.assertIn('__weak ICFrameEngine *weakSelf=self;', engine)
        handler = engine.split('dispatch_source_set_event_handler(_timer,', 1)[1].split('dispatch_resume(_timer)', 1)[0]
        self.assertIn('ICFrameEngine *strongSelf=weakSelf;', handler)
        self.assertIn('if(!strongSelf)return;', handler)
        self.assertIn('[strongSelf tick]', handler)
        self.assertNotRegex(handler, r'\bself\b')
        self.assertIn('- (void)dealloc {if(_timer)dispatch_source_cancel(_timer);}', engine)

    def test_collapsible_panel_height_contract(self):
        # Simplified source-derived constraint model; does NOT execute UIKit.
        app = (ROOT / 'App/ICMainController.m').read_text(encoding='utf-8')
        self.assertIn('NSLayoutConstraint *panelHeight=[self.adjustments.heightAnchor constraintEqualToConstant:238];', app)
        match = re.search(r'panelHeight\.priority=(\d+);', app)
        self.assertIsNotNone(match)
        priority = int(match.group(1))
        self.assertLess(priority, 1000)
        self.assertGreater(priority, 750)
        self.assertIn('panelHeight.active=YES;', app)
        self.assertIn('self.controlsContainer.hidden=YES', app)
        # A hidden arranged stack collapses to zero. Its preferred child height
        # must yield rather than add a second incompatible REQUIRED value.
        required = {value for p, value in ((1000, 0), (priority, 238)) if p == 1000}
        self.assertEqual(required, {0})

    def test_preview_stop_wins_over_pending_start(self):
        # The test checks the asynchronous completion guard, not iOS scheduling.
        app = (ROOT / 'App/ICMainController.m').read_text(encoding='utf-8')
        self.assertIn('@property(nonatomic) BOOL wantsPreview;', app)
        start = app.split('- (void)start {', 1)[1].split('- (void)stop', 1)[0]
        stop = app.split('- (void)stop', 1)[1].split('- (void)sync', 1)[0]
        self.assertLess(start.index('self.wantsPreview=YES;'), start.index('if(self.booting)return;'))
        self.assertIn('self.wantsPreview=NO;', stop)
        self.assertIn('if(!self.wantsPreview || !self.view.window || self.presentedViewController ||', start)
        self.assertLess(start.index('if(!self.wantsPreview'), start.index('[engine setSuspended:NO]'))
        pick = app.split('- (void)pick {', 1)[1].split('- (void)picker:', 1)[0]
        self.assertIn('[self stop];PHPickerConfiguration', pick)
        self.assertIn('dismissViewControllerAnimated:YES completion:^{[self start];}', app)

    def test_native_engine_lifetime_test_is_wired(self):
        workflow = (ROOT / '.github/workflows/build-deb.yml').read_text(encoding='utf-8')
        native = (ROOT / 'tests/engine.m').read_text(encoding='utf-8')
        for token in ('tests/engine.m', 'Core/ICFrameEngine.m', '-framework CoreImage', 'icam-engine'):
            self.assertIn(token, workflow)
        self.assertIn('__weak ICFrameEngine *released', native)
        self.assertIn('assert(!released)', native)
        self.assertIn('[engine setSuspended:YES]', native)

    def test_thin_signed_app_padding(self):
        result = verify.binary(self.file(thin()), app=True)
        self.assertEqual(result[0]['arch'], 'arm64')
        self.assertTrue(result[0]['entitlements']['platform-application'])

    def test_both_tweak_slices(self):
        result = verify.binary(self.file(fat(thin(app=False), thin('arm64e', app=False))))
        self.assertEqual({r['arch'] for r in result}, {'arm64', 'arm64e'})

    def test_wrong_controller_architectures(self):
        with self.assertRaisesRegex(ValueError, 'architecture'):
            verify.binary(self.file(fat(thin(), thin('arm64e'))), app=True)

    def test_missing_tweak_architecture(self):
        with self.assertRaisesRegex(ValueError, 'architecture'):
            verify.binary(self.file(thin(app=False)))

    def test_missing_entitlement(self):
        with self.assertRaisesRegex(ValueError, 'entitlement'):
            verify.binary(self.file(thin(ent={})), app=True)

    def test_false_and_non_boolean_entitlements(self):
        for bad in (False, 1, 'true'):
            e = {key: True for key in verify.REQUIRED_ENTITLEMENTS}
            e['platform-application'] = bad
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError, 'entitlement'):
                verify.binary(self.file(thin(ent=e)), app=True)

    def test_wrong_entitlement_root(self):
        with self.assertRaisesRegex(ValueError, 'dictionary'):
            macho.slices(thin(ent=[]))

    def test_non_ios_platform(self):
        with self.assertRaisesRegex(ValueError, 'platform'):
            verify.binary(self.file(thin(platform=1)), app=True)

    def test_minimum_too_new(self):
        with self.assertRaisesRegex(ValueError, 'minimum'):
            verify.binary(self.file(thin(minimum=16 << 16)), app=True)

    def test_wrong_filetype(self):
        with self.assertRaisesRegex(ValueError, 'type'):
            verify.binary(self.file(thin(app=False)), app=True)

    def test_unsigned(self):
        with self.assertRaisesRegex(ValueError, 'Unsigned'):
            verify.binary(self.file(thin(signed=False)), app=True)

    def test_loader_dependency(self):
        for dep in ('@loader_path/.jbroot/usr/lib/libroothide.dylib', '/var/jb/usr/lib/libsubstrate.dylib', '/usr/lib/libroothide.dylib'):
            with self.subTest(dep=dep), self.assertRaises(ValueError):
                verify.binary(self.file(thin(deps=(dep,))), app=True)

    def test_truncated_binary(self):
        data = thin()
        for length in (0, 3, 20, 31, 40, 80, len(data) - 20):
            with self.subTest(length=length), self.assertRaises((ValueError, struct.error)):
                macho.slices(data[:length])

    def test_bad_fat_count(self):
        for count in (0, 17, 0xffffffff):
            with self.subTest(count=count), self.assertRaises(ValueError):
                macho.slices(struct.pack('>II', 0xcafebabe, count))

    def test_fat_overlapping_slices(self):
        data = bytearray(fat(thin(), thin('arm64e')))
        struct.pack_into('>I', data, 36, 48)
        with self.assertRaisesRegex(ValueError, 'Overlapping'):
            macho.slices(data)

    def test_fat_header_mismatch(self):
        data = bytearray(fat(thin(), thin('arm64e')))
        struct.pack_into('>I', data, 32, 0)
        with self.assertRaisesRegex(ValueError, 'mismatch'):
            macho.slices(data)

    def test_invalid_load_command(self):
        data = bytearray(thin())
        struct.pack_into('<I', data, 36, 4)
        with self.assertRaisesRegex(ValueError, 'load command'):
            macho.slices(data)

    def test_signature_blob_overlap(self):
        data = bytearray(thin())
        at = data.find(b'\xfa\xde\x0c\xc0')
        struct.pack_into('>I', data, at + 24, 28)
        with self.assertRaisesRegex(ValueError, 'overlapping'):
            macho.slices(data)

    def test_cli_usage_exit_two(self):
        for args in ((), ('package',), ('package', '--data', self.root), ('not-a-command',)):
            with self.subTest(args=args):
                r = self.cli(*args)
                self.assertEqual(r.returncode, 2)
                self.assertIn('usage:', r.stderr)

    def test_cli_bad_source_has_stable_error(self):
        r = self.cli('source', '--root', self.root)
        self.assertEqual(r.returncode, 1)
        self.assertIn('ERROR:', r.stderr)
        self.assertNotIn('Traceback', r.stderr)

    def test_malformed_plists(self):
        for value in (b'', b'<?xml version="1.0" encoding="', plistlib.dumps({}) + plistlib.dumps({}), plistlib.dumps([])):
            (self.root / 'App').mkdir(exist_ok=True)
            (self.root / 'App/Info.plist').write_bytes(value)
            r = self.cli('source', '--root', self.root)
            self.assertEqual(r.returncode, 1)
            self.assertIn('ERROR:', r.stderr)
            self.assertNotIn('Traceback', r.stderr)

    def test_manifest_prunes_git_and_theos(self):
        (self.root / 'file').write_bytes(b'one')
        (self.root / '.git/objects/info').mkdir(parents=True)
        (self.root / 'theos/.git/objects/info').mkdir(parents=True)
        with redirect_stdout(io.StringIO()):
            verify.manifest(self.root, True)
            verify.manifest(self.root)
        (self.root / 'file').write_bytes(b'two')
        with self.assertRaisesRegex(ValueError, 'mismatch'):
            verify.manifest(self.root)

    def test_package_fixture_and_negative_missing_info(self):
        data, maint = self.root / 'data', self.root / 'control'
        app = data / 'Applications/ICamController.app'
        base = data / 'Library/MobileSubstrate/DynamicLibraries'
        app.mkdir(parents=True)
        base.mkdir(parents=True)
        maint.mkdir()
        shutil.copy2(ROOT / 'App/Info.plist', app / 'Info.plist')
        for p in (ROOT / 'App/Resources').glob('*.png'):
            shutil.copy2(p, app / p.name)
        (app / 'ICamController').write_bytes(thin())
        for name in ('ICamCamera', 'ICamControls'):
            (base / f'{name}.dylib').write_bytes(fat(thin(app=False), thin('arm64e', app=False)))
            shutil.copy2(ROOT / ('Camera' if name == 'ICamCamera' else 'Controls') / f'{name}.plist', base / f'{name}.plist')
        shutil.copy2(ROOT / 'control', maint / 'control')
        for name in ('postinst', 'prerm'):
            shutil.copy2(ROOT / 'layout/DEBIAN' / name, maint / name)
        for p in (app / 'ICamController', maint / 'postinst', maint / 'prerm'):
            p.chmod(0o755)
        with redirect_stdout(io.StringIO()):
            verify.package(data, maint)
        (app / 'Info.plist').unlink()
        r = self.cli('package', '--data', data, '--control', maint)
        self.assertEqual(r.returncode, 1)
        self.assertIn('ERROR:', r.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)
