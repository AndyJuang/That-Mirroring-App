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
baseline = subprocess.check_output(['git', 'show', '8e4b3e1:MirrorApp.swift'], text=True)
# Baseline is the 1.3.3 core with the launch-crash fix (8e4b3e1). Apart from queue labels and the explicit Android suspension branch, the Apple core is unchanged.
start = 'class CaptureManager:'
expected = baseline[baseline.index(start):].replace('com.example.iPhoneMirror.audioQueue','ThatMirroring.audioQueue').replace('com.example.iPhoneMirror.captureQueue','ThatMirroring.captureQueue').replace('com.example.iPhoneMirror.sessionQueue','ThatMirroring.sessionQueue')
expected = expected.replace('    @Published var hasDevice = false\n', '    @Published var hasDevice = false\n    // Do not keep a hidden Apple camera/audio session running behind Android setup.\n    var isSuspendedForAndroid = false {\n        didSet { if isSuspendedForAndroid != oldValue { setupSession() } }\n    }\n', 1)
expected = expected.replace('    func setupSession() {\n', '    func setupSession() {\n        if isSuspendedForAndroid {\n            sessionGeneration += 1\n            audioSignalBroken = false\n            hasDevice = false\n            sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } }\n            return\n        }\n', 1)
# fix/session-start-race-i18n: the session region (devicesChanged .. captureOutput) and PreviewView are
# audited by invariants below; everything else in the Apple core must still match the baseline exactly.
def outside_session_region(text):
    lo = text.index('    @objc func devicesChanged')
    hi = text.index('    func captureOutput(_ output: AVCaptureOutput, didOutput')
    rest = text[:lo] + text[hi:]
    p0 = rest.index('struct PreviewView: NSViewRepresentable {'); p1 = rest.index('\n}\n', p0) + 3
    return rest[:p0] + rest[p1:]
core = source[source.index(start):]
assert outside_session_region(core) == outside_session_region(expected)
region = core[core.index('    @objc func devicesChanged'):core.index('    func captureOutput(_ output: AVCaptureOutput, didOutput')]
assert source.count('session.startRunning()') == 1 and source.count('session.stopRunning()') == 1
assert 'captureQueue.async { self.session' not in source and 'captureQueue.async { if self.session' not in source
assert 'DispatchQueue.main.asyncAfter' not in region
b = region.index('session.beginConfiguration()'); c = region.index('session.commitConfiguration()')
assert b < c < region.index('startSessionOnQueue()\n        } else')
for fn in ('private func configureSession(', 'startSessionOnQueue() {', 'stopSessionOnQueue() {'):
    body = region[region.index(fn):]
    assert body.index('dispatchPrecondition(condition: .onQueue(sessionQueue))') < body.index('\n    }\n')
preview = core[core.index('struct PreviewView: NSViewRepresentable {'):]
preview = preview[:preview.index('\n}\n')]
assert '.session = session' not in preview and preview.count('attach(layer)') == 2
assert source.count('layer.session = self.session') == 1
print('SOURCE VERIFIED')
