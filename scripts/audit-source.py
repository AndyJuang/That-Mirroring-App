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
# The preview, crop, audio-monitor and mouse-event implementations are unchanged.
start = '// 原始影像尺寸'
assert source[source.index(start):] == baseline[baseline.index(start):]
start = 'extension CaptureManager {'
end = '// 原始影像尺寸'
assert source[source.index(start):source.index(end)] == baseline[baseline.index(start):baseline.index(end)]
print('SOURCE VERIFIED')
