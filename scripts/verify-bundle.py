#!/usr/bin/env python3
import pathlib, plistlib, subprocess, struct, os
app = pathlib.Path('build/ThatMirroring.app')
root = app / 'Contents/Resources/scrcpy'
plist = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert plist['CFBundleDisplayName'] == 'That Mirroring'
assert plist['CFBundleDevelopmentRegion'] == 'en'
assert plist['CFBundleLocalizations'] == ['en', 'zh-Hant']
assert 'NSScreenCaptureUsageDescription' not in plist
def load_strings(path):
    xml = subprocess.check_output(['plutil', '-convert', 'xml1', '-o', '-', str(path)])
    return plistlib.loads(xml)
packaged = {}
for lang in ('en', 'zh-Hant'):
    folder = app / 'Contents/Resources' / f'{lang}.lproj'
    for name in ('Localizable.strings', 'InfoPlist.strings'):
        assert (folder / name).is_file(), f'{lang}.lproj/{name}'
        packaged[(lang, name)] = load_strings(folder / name)
assert set(packaged[('en', 'Localizable.strings')]) == set(packaged[('zh-Hant', 'Localizable.strings')])
assert packaged[('zh-Hant', 'Localizable.strings')]['Language'] == '語言'
assert packaged[('en', 'Localizable.strings')]['About That Mirroring'] == 'About That Mirroring'
assert packaged[('zh-Hant', 'Localizable.strings')]['About That Mirroring'] == '關於 That Mirroring'
assert packaged[('zh-Hant', 'Localizable.strings')]['Open-Source Licenses'] == '開放原始碼授權'
assert (root/'licenses'/'THIRD-PARTY-NOTICES.md').is_file()
assert packaged[('zh-Hant', 'Localizable.strings')]['%@ (Screen)'] == '%@（畫面）'
assert packaged[('en', 'Localizable.strings')]['Follow System'] == 'Follow System'
assert packaged[('zh-Hant', 'InfoPlist.strings')]['NSCameraUsageDescription'] != packaged[('en', 'InfoPlist.strings')]['NSCameraUsageDescription']
for name in ['scrcpy','adb','scrcpy-server','ThatMirroringWindow.dylib','scrcpy.png','LICENSE','THIRD-PARTY-NOTICES.md']:
    assert (root/name).is_file(), name
for path in pathlib.Path('licenses').glob('*/*'):
    assert (root/'licenses'/path.relative_to('licenses')).read_bytes() == path.read_bytes(), path
for file in app.rglob('*'):
    if not file.is_file(): continue
    kind = subprocess.check_output(['/usr/bin/file','-b',str(file)], text=True)
    if 'Mach-O' not in kind: continue
    subprocess.run(['lipo',str(file),'-verify_arch','arm64'],check=True)
    subprocess.run(['codesign','--verify','--strict',str(file)],check=True)
    linked = subprocess.check_output(['otool','-L',str(file)], text=True)
    for line in linked.splitlines():
        if ' (compatibility version' not in line: continue
        name = line.strip().split(' (')[0]
        # The style dylib's own ID is relative; all dependencies must be system.
        if name == '@executable_path/ThatMirroringWindow.dylib': continue
        assert name.startswith(('/usr/lib/','/System/Library/')), (file,name)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
version = subprocess.check_output([str(root/'scrcpy'),'--version'],text=True)
assert version.startswith('scrcpy 4.0 ')
adb = subprocess.check_output([str(root/'adb'),'version'],text=True)
assert 'Version 37.0.0' in adb
# Parse generated ICNS directly, independently of iconutil's encoding service.
raw = (app/'Contents/Resources/AppIcon.icns').read_bytes()
assert raw[:4] == b'icns' and struct.unpack('>I',raw[4:8])[0] == len(raw)
print('Nested signatures, arm64 architecture, dynamic references and notices verified')

# Confirm dyld can load the separate ad-hoc signed window adapter into bundled scrcpy.
env = os.environ.copy()
env['DYLD_INSERT_LIBRARIES'] = str((root/'ThatMirroringWindow.dylib').resolve())
env['DYLD_PRINT_LIBRARIES'] = '1'
probe = subprocess.run([str(root/'scrcpy'), '--version'], env=env, capture_output=True, text=True, check=True)
assert 'ThatMirroringWindow.dylib' in probe.stderr, 'window adapter did not load'
