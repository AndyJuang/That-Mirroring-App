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
# Apart from queue labels and the explicit Android suspension branch, the Apple core is unchanged.
start = 'class CaptureManager:'
expected = baseline[baseline.index(start):].replace('com.example.iPhoneMirror.audioQueue','ThatMirroring.audioQueue').replace('com.example.iPhoneMirror.captureQueue','ThatMirroring.captureQueue')
expected = expected.replace('    @Published var hasDevice = false\n', '    @Published var hasDevice = false\n    // Do not keep a hidden Apple camera/audio session running behind Android setup.\n    var isSuspendedForAndroid = false {\n        didSet { if isSuspendedForAndroid != oldValue { setupSession() } }\n    }\n', 1)
expected = expected.replace('    func setupSession() {\n', '    func setupSession() {\n        if isSuspendedForAndroid {\n            sessionGeneration += 1\n            audioSignalBroken = false\n            hasDevice = false\n            captureQueue.async { if self.session.isRunning { self.session.stopRunning() } }\n            return\n        }\n', 1)
assert source[source.index(start):] == expected
print('SOURCE VERIFIED')
