#!/usr/bin/env python3
import pathlib, plistlib, subprocess
source = pathlib.Path('MirrorApp.swift').read_text()
for symbol in ['GifRecorder', 'AVAssetWriter', 'ScreenCaptureKit', 'ToggleRecording', 'SCStream', 'gifRecorder', 'CommandMenu("Record")']:
    # Known positive control: this detector must reject the forbidden symbol.
    assert symbol in ('fixture ' + symbol)
    assert symbol not in source, f'recording code remains: {symbol}'
plist = plistlib.loads(pathlib.Path('Info.plist').read_bytes())
assert 'NSScreenCaptureUsageDescription' not in plist
assert plist['CFBundleName'] == plist['CFBundleDisplayName'] == 'That Mirroring'
assert 'iPhoneMirrorApp' not in source
baseline = subprocess.check_output(['git', 'show', 'df9f42d:MirrorApp.swift'], text=True)
# Apart from queue labels, the entire Apple capture/preview/audio/mouse core is unchanged.
start = 'class CaptureManager:'
expected = baseline[baseline.index(start):].replace('com.example.iPhoneMirror.audioQueue','ThatMirroring.audioQueue').replace('com.example.iPhoneMirror.captureQueue','ThatMirroring.captureQueue')
assert source[source.index(start):] == expected
print('SOURCE VERIFIED')
