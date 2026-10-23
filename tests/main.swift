import Foundation

var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    guard condition() else { fatalError(message) }
}
let suiteName = "ThatMirroring.Tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }
for key in legacyRecordingKeys { defaults.set(["old", "malformed"], forKey: key) }
defaults.set(true, forKey: "PlayDeviceAudio")
defaults.set("usb-camera", forKey: "SelectedDeviceID")
defaults.set("Giant Circle", forKey: "SelectedAnimation")
defaults.set(false, forKey: "AutoCropBlackBars")
defaults.set("ignored", forKey: "UnknownLegacyRecordingOption")
migrateLegacyRecordingSettings(defaults)
for key in legacyRecordingKeys { expect(defaults.object(forKey: key) == nil, "legacy key remains") }
expect(defaults.bool(forKey: "PlayDeviceAudio"), "audio setting lost")
expect(defaults.string(forKey: "SelectedDeviceID") == "usb-camera", "device lost")
expect(defaults.string(forKey: "SelectedAnimation") == "Giant Circle", "highlight lost")
expect(defaults.object(forKey: "AutoCropBlackBars") as? Bool == false, "crop lost")
migrateLegacyRecordingSettings(defaults)
expect(defaults.string(forKey: "UnknownLegacyRecordingOption") == "ignored", "unknown option should be harmless")


let adbFixture = """
* daemon not running; starting now at tcp:5037
* daemon started successfully
List of devices attached
USB-A\tdevice usb:1-1 product:sample model:Pixel_Test device:sample transport_id:1
USB-B\tunauthorized usb:1-2 transport_id:2
USB-C\toffline transport_id:3
USB-D\tno permissions (user in plugdev group; are your udev rules wrong?)
192.0.2.1:5555 device product:test model:Tablet_Test transport_id:5
USB-A\tdevice model:Duplicate
malformed
adb: error: fixture failure
"""
let devices = parseADBDevices(adbFixture)
expect(devices.count == 5, "parser must filter headers, daemon chatter, invalid lines and duplicate serials")
expect(devices[0].serial == "USB-A" && devices[0].model == "Pixel Test", "USB model parsing")
expect(devices[0].isUSB && devices[0].isAuthorized, "USB authorized")
expect(devices[1].state == "unauthorized" && !devices[1].isAuthorized, "unauthorized state")
expect(devices[2].state == "offline" && !devices[2].isAuthorized, "offline state")
expect(devices[3].state == "no permissions", "permissions state")
expect(!devices[4].isUSB && devices[4].model == "Tablet Test", "network device")
expect(parseADBDevices("\r\nList of devices attached\r\n").isEmpty, "empty Windows output")
expect(parseADBDevices("   SERIAL    device   model:Test\r\n").first?.serial == "SERIAL", "whitespace output")
expect(parseADBDevices("Serial With Spaces\tdevice model:Test").first?.serial == "Serial With Spaces", "tab-delimited serial with spaces")
expect(parseADBDevices("serial\tno nonsense").isEmpty, "invalid permissions state")
expect(devices[1].model == "Android", "missing model fallback")
expect(devices[0].statusLabel == "Connected over USB", "usb status")
expect(devices[1].statusLabel == "Not authorized", "unauthorized status")
expect(devices[2].statusLabel == "Offline. Reconnect the cable.", "offline status")
expect(devices[3].statusLabel == "Can't access USB", "permissions status")
expect(AndroidDevice(serial: "net", state: "device", model: "Android", isUSB: false).statusLabel == "Connected", "network status")
expect(AndroidDevice(serial: "x", state: "weird", model: "Android", isUSB: false).statusLabel == "Can't connect", "unknown status")
defaults.removeObject(forKey: "AppleLanguages")
expect(AppLanguageSetting.stored(in: defaults, domain: suiteName).code == nil, "missing override follows system")
defaults.set(["ja", "en"], forKey: "AppleLanguages")
expect(AppLanguageSetting.stored(in: defaults, domain: suiteName).code == "ja", "unknown override stays stored")
expect(!AppLanguageSetting.stored(in: defaults, domain: suiteName).followsSystem && !AppLanguageSetting.stored(in: defaults, domain: suiteName).isTraditional && !AppLanguageSetting.stored(in: defaults, domain: suiteName).isEnglish, "unknown override matches no menu item")
defaults.set(["zh-Hant-TW"], forKey: "AppleLanguages")
expect(AppLanguageSetting.stored(in: defaults, domain: suiteName).isTraditional, "regional traditional code")
defaults.set(["zh-TW"], forKey: "AppleLanguages")
expect(AppLanguageSetting.stored(in: defaults, domain: suiteName).isTraditional, "legacy traditional code")
defaults.set(["en-US"], forKey: "AppleLanguages")
expect(AppLanguageSetting.stored(in: defaults, domain: suiteName).isEnglish && !AppLanguageSetting.stored(in: defaults, domain: suiteName).isTraditional, "regional english code")
AppLanguageSetting(code: AppLanguageSetting.traditional).save(to: defaults)
expect(defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hant"], "traditional override saved")
expect(AppLanguageSetting.stored(in: defaults, domain: suiteName).code == "zh-Hant", "traditional read back")
AppLanguageSetting(code: AppLanguageSetting.english).save(to: defaults)
expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"], "english override saved")
AppLanguageSetting(code: nil).save(to: defaults)
expect(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"] == nil, "follow system removes the app override")
expect(localizedText("Connected over USB") == "Connected over USB", "english key is the fallback")
expect(localizedText("%@ (Screen)", "iPhone") == "iPhone (Screen)", "screen suffix")
expect(localizedText("%@ (Camera)", "FaceTime") == "FaceTime (Camera)", "camera suffix")
expect(localizedText("Android · %@ (%@)", "Pixel", "Connected over USB") == "Android · Pixel (Connected over USB)", "android menu label")

let resources = URL(fileURLWithPath: "/fixture/That Mirroring.app/Contents/Resources")
let root = resources.appendingPathComponent("scrcpy")
let fallback = URL(fileURLWithPath: "/fixture/homebrew")
let helperScrcpy = "ThatMirroringAndroid.app/Contents/MacOS/scrcpy"
let bundledFiles = Set([helperScrcpy, "adb", "scrcpy-server"].map { root.appendingPathComponent($0).path })
let fallbackFiles = Set(["bin/scrcpy", "bin/adb", "share/scrcpy/scrcpy-server"].map { fallback.appendingPathComponent($0).path })
func resolve(_ files: Set<String>, resources: URL? = resources) -> AndroidTools? {
    resolveAndroidTools(resources: resources, fallback: fallback,
                        executable: { files.contains($0.path) }, readable: { files.contains($0.path) })
}
let tools = resolve(bundledFiles.union(fallbackFiles))!
expect(!tools.isFallback && tools.directory.path == root.path, "bundle must take precedence")
expect(tools.scrcpy.path == root.appendingPathComponent(helperScrcpy).path, "bundled scrcpy lives in helper app")
expect(tools.adb.path == root.appendingPathComponent("adb").path, "bundled adb")
expect(tools.server.path == root.appendingPathComponent("scrcpy-server").path, "bundled server")
expect(resolve(fallbackFiles)!.isFallback, "missing bundle fallback")
expect(resolve(fallbackFiles, resources: nil)!.isFallback, "nil resource URL fallback")
expect(resolve([]) == nil, "missing tools must fail")
expect(resolve(bundledFiles.subtracting([root.appendingPathComponent(helperScrcpy).path]).union([root.appendingPathComponent("scrcpy").path])) == nil, "old flat scrcpy path must not launch")
for missing in ["adb", helperScrcpy, "scrcpy-server"] {
    let partial = bundledFiles.subtracting([root.appendingPathComponent(missing).path])
    expect(resolve(partial) == nil, "partial bundle must not launch")
    expect(resolve(partial.union(fallbackFiles))!.isFallback, "partial bundle coherent fallback")
}
let readableOnly = resolveAndroidTools(resources: resources, fallback: fallback, executable: { _ in false }, readable: { _ in true })
expect(readableOnly == nil, "tools must be executable")
let options = AndroidWindowOptions()
let args = scrcpyArguments(device: devices[0], options: options)
expect(args.contains("--serial=USB-A"), "select exact serial")
expect(args.contains("--window-title=That Mirroring — Android · Pixel Test"), "own title")
expect(args.contains("--max-fps=60") && args.contains("--video-bit-rate=12M"), "pixel-cast defaults")
expect(args.contains("--no-audio"), "match Apple display-only audio default")
expect(!args.contains("--no-control") && !args.contains("--no-mouse") && !args.contains("--no-keyboard"), "Android must permit control")
expect(!args.contains("--turn-screen-off"), "phone screen stays on by default")
expect(!args.contains("--always-on-top") && !args.contains("--fullscreen"), "normal window default")
expect(!args.contains { $0.hasPrefix("--record") }, "never record")
let customized = scrcpyArguments(device: devices[0], options: AndroidWindowOptions(alwaysOnTop: true, fullscreen: true, audio: true))
expect(customized.contains("--always-on-top") && customized.contains("--fullscreen"), "window options")
expect(customized.contains("--audio-source=output") && !customized.contains("--no-audio"), "audio explicit")
expect(!customized.contains("--turn-screen-off"), "other options leave the phone screen on")
expect(!customized.contains("--no-control") && !customized.contains("--no-mouse") && !customized.contains("--no-keyboard"), "window options still allow control")
let screenOff = scrcpyArguments(device: devices[0], options: AndroidWindowOptions(turnScreenOff: true))
expect(screenOff.contains("--turn-screen-off"), "turn the phone screen off when asked")
expect(!screenOff.contains("--no-control") && !screenOff.contains("--no-mouse") && !screenOff.contains("--no-keyboard"), "screen off still allows control")
expect(screenOff.filter { $0 == "--turn-screen-off" }.count == 1, "screen off flag once")
expect(!AndroidWindowOptions.stored(in: defaults).turnScreenOff, "screen off starts off")
AndroidWindowOptions(turnScreenOff: true).save(to: defaults)
expect(AndroidWindowOptions.stored(in: defaults).turnScreenOff, "screen off is remembered")
AndroidWindowOptions().save(to: defaults)
expect(!AndroidWindowOptions.stored(in: defaults).turnScreenOff, "turning screen off back off is remembered")
let suspicious = AndroidDevice(serial: "--record=/tmp/file; $(echo bad)", state: "device", model: "Quoted ' phone", isUSB: true)
expect(scrcpyArguments(device: suspicious, options: options)[0] == "--serial=\(suspicious.serial)", "serial must stay one argument, no shell")
let env = androidEnvironment(tools: tools, resources: resources, inherited: ["ADB":"wrong", "SCRCPY_SERVER_PATH":"wrong", "ANDROID_SERIAL":"wrong", "DYLD_INSERT_LIBRARIES":"wrong", "ADB_SERVER_SOCKET":"remote", "PATH":"wrong", "SCRCPY_ICON_DIR":"wrong"])
expect(env["ADB"] == tools.adb.path && env["SCRCPY_SERVER_PATH"] == tools.server.path, "explicit bundle environment")
expect(env["ANDROID_SERIAL"] == nil && env["ADB_SERVER_SOCKET"] == nil && env["DYLD_INSERT_LIBRARIES"] == nil, "inherited tool overrides removed")
expect(env["PATH"]!.hasPrefix(root.path + ":"), "bundle path with spaces")
expect(env["SCRCPY_ICON_PATH"] == root.path, "own icon path")
expect(env["SCRCPY_ICON_DIR"] == root.path, "scrcpy icon dir matches icon path, inherited value replaced")
expect(env["THATMIRRORING_PARENT_PID"] == String(ProcessInfo.processInfo.processIdentifier), "parent lifetime binding")
expect(androidConnectionSteps.components(separatedBy: .newlines).count == 4, "four connection steps")

let child = Process()
child.executableURL = URL(fileURLWithPath: "/bin/sleep")
child.arguments = ["30"]
try child.run()
expect(child.isRunning, "owned child started")
terminateOwnedProcess(child)
expect(!child.isRunning, "owned child terminated")
terminateOwnedProcess(child) // idempotent
let resistant = Process()
resistant.executableURL = URL(fileURLWithPath: "/bin/sh")
resistant.arguments = ["-c", "trap '' TERM; exec /bin/sleep 30"]
try resistant.run()
Thread.sleep(forTimeInterval: 0.1)
let startTime = Date()
terminateOwnedProcess(resistant)
expect(!resistant.isRunning && Date().timeIntervalSince(startTime) < 3, "unresponsive child terminated within bound")
expect(resistant.terminationStatus == 9, "unresponsive child requires owned SIGKILL")


let outputQuery = try queryTool(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'fixture output'; printf 'fixture error' >&2"], environment: [:])
expect(outputQuery.stdout == "fixture output" && outputQuery.exitStatus == 0 && !outputQuery.timedOut, "stdout separate from stderr")
let failedQuery = try queryTool(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 7"], environment: [:])
expect(failedQuery.exitStatus == 7, "nonzero exit preserved")
let boundedQuery = try queryTool(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], environment: [:], timeout: 0.05)
expect(boundedQuery.timedOut && boundedQuery.exitStatus != 0, "query timeout closes only owned process")
let noisyQuery = try queryTool(executable: URL(fileURLWithPath: "/usr/bin/awk"), arguments: ["BEGIN { for(i=0;i<10000;i++) { print \"output fixture\"; print \"error fixture\" > \"/dev/stderr\" } }"], environment: [:])
expect(!noisyQuery.timedOut && noisyQuery.exitStatus == 0 && noisyQuery.stdout.count > 65536, "both pipes drained beyond buffer size")
let phoneOK = AndroidDevice(serial: "A1", state: "device", model: "Pixel", isUSB: true)
let phoneOther = AndroidDevice(serial: "B2", state: "device", model: "Galaxy", isUSB: true)
expect(androidMirrorPhase(for: phoneOK, selectedSerial: nil) == .connectedIdle, "authorized unselected device is idle")
expect(androidMirrorPhase(for: phoneOK, selectedSerial: "A1") == .mirroring, "selected authorized device is mirroring")
expect(androidMirrorPhase(for: phoneOther, selectedSerial: "A1") == .connectedIdle, "other device stays idle while one mirrors")
let lostAuth = AndroidDevice(serial: "A1", state: "unauthorized", model: "Pixel", isUSB: true)
expect(androidMirrorPhase(for: lostAuth, selectedSerial: "A1") == .mirroring, "mirrored device stays stoppable after losing authorization")
expect(androidDisplayDevices([], selectedSerial: "A1").map(\.serial) == ["A1"], "vanished mirrored device keeps a card")
expect(androidDisplayDevices([phoneOK], selectedSerial: "A1") == [phoneOK], "present mirrored device is not duplicated")
expect(androidDisplayDevices([phoneOK], selectedSerial: nil) == [phoneOK], "no selection leaves devices unchanged")
for state in ["unauthorized", "offline", "no permissions"] {
    let blocked = AndroidDevice(serial: "A1", state: state, model: "Pixel", isUSB: true)
    expect(androidMirrorPhase(for: blocked, selectedSerial: "B2") == .notConnected, "\(state) device is not connected")
}
expect(androidStepsProminent(devices: []), "setup steps shown with no devices")
expect(androidStepsProminent(devices: [AndroidDevice(serial: "A1", state: "unauthorized", model: "Pixel", isUSB: true)]), "setup steps shown when none authorized")
expect(!androidStepsProminent(devices: [phoneOK]), "setup steps collapse when a device is authorized")

let ownBundle = "com.example.iPhoneMirror"
expect(isThatcasterPGMWindow(title: "Thatcaster — PGM 監看", ownerBundleID: "com.thatcaster.app", ownBundleID: ownBundle), "chinese pgm title")
expect(isThatcasterPGMWindow(title: "Thatcaster — Program", ownerBundleID: nil, ownBundleID: ownBundle), "english pgm title")
expect(!isThatcasterPGMWindow(title: "Thatcaster — 投影輸出", ownerBundleID: nil, ownBundleID: ownBundle), "projector is not pgm")
expect(!isThatcasterPGMWindow(title: "Thatcaster — Projector", ownerBundleID: nil, ownBundleID: ownBundle), "english projector is not pgm")
expect(!isThatcasterPGMWindow(title: "Thatcaster — Prompter", ownerBundleID: nil, ownBundleID: ownBundle), "prompter is not pgm")
expect(!isThatcasterPGMWindow(title: "Thatcaster — PGM 監看", ownerBundleID: ownBundle, ownBundleID: ownBundle), "never capture this app")
expect(!isThatcasterPGMWindow(title: "That Mirroring", ownerBundleID: nil, ownBundleID: ownBundle), "phone window is not pgm")
expect(!isThatcasterPGMWindow(title: "Thatcaster - PGM 監看", ownerBundleID: nil, ownBundleID: ownBundle), "hyphen is not the pgm title")
expect(!loadPGMVisible(defaults), "pgm stays hidden until turned on")
expect(loadPhoneMirrorVisible(defaults), "phone mirror stays visible unless turned off")
expect(loadPGMFitMode(defaults) == .fit, "fit is the default")
defaults.set(PGMFitMode.native.rawValue, forKey: pgmFitModeKey)
expect(loadPGMFitMode(defaults) == .native, "native mode is remembered")
defaults.set("nope", forKey: pgmFitModeKey)
expect(loadPGMFitMode(defaults) == .fit, "unknown mode falls back to fit")
defaults.set(false, forKey: phoneVisibleKey)
expect(!loadPhoneMirrorVisible(defaults), "phone mirror can be hidden")
let savedDisplay = DisplayIdentity(uuid: "AAA", name: "Dell", pixelWidth: 1920, pixelHeight: 1080)
saveDisplayIdentity(savedDisplay, uuidKey: pgmDisplayUUIDKey, nameKey: pgmDisplayNameKey, widthKey: pgmDisplayWidthKey, heightKey: pgmDisplayHeightKey, defaults: defaults)
expect(loadDisplayIdentity(uuidKey: pgmDisplayUUIDKey, nameKey: pgmDisplayNameKey, widthKey: pgmDisplayWidthKey, heightKey: pgmDisplayHeightKey, defaults: defaults) == savedDisplay, "display identity round trip")
saveDisplayIdentity(nil, uuidKey: pgmDisplayUUIDKey, nameKey: pgmDisplayNameKey, widthKey: pgmDisplayWidthKey, heightKey: pgmDisplayHeightKey, defaults: defaults)
expect(loadDisplayIdentity(uuidKey: pgmDisplayUUIDKey, nameKey: pgmDisplayNameKey, widthKey: pgmDisplayWidthKey, heightKey: pgmDisplayHeightKey, defaults: defaults) == nil, "cleared display identity")
let displays = [
    DisplayIdentity(uuid: "BBB", name: "Built-in", pixelWidth: 2560, pixelHeight: 1600),
    DisplayIdentity(uuid: "AAA", name: "Dell", pixelWidth: 1920, pixelHeight: 1080),
]
expect(matchDisplay(savedDisplay, among: displays)?.uuid == "AAA", "uuid match")
let replugged = [DisplayIdentity(uuid: "NEW", name: "Dell", pixelWidth: 1920, pixelHeight: 1080)]
expect(matchDisplay(savedDisplay, among: replugged)?.uuid == "NEW", "name and size fallback")
let ambiguous = [
    DisplayIdentity(uuid: "1", name: "Dell", pixelWidth: 1920, pixelHeight: 1080),
    DisplayIdentity(uuid: "2", name: "Dell", pixelWidth: 1920, pixelHeight: 1080),
]
expect(matchDisplay(DisplayIdentity(uuid: "", name: "Dell", pixelWidth: 1920, pixelHeight: 1080), among: ambiguous) == nil, "ambiguous name is not a guess")
expect(matchDisplay(DisplayIdentity(uuid: "gone", name: "Dell", pixelWidth: 999, pixelHeight: 999), among: [DisplayIdentity(uuid: "9", name: "Dell", pixelWidth: 1280, pixelHeight: 720)])?.uuid == "9", "unique name fallback")
expect(matchDisplay(savedDisplay, among: []) == nil, "missing display waits")
let wide = pgmImageRect(mode: .fit, pixelSize: CGSize(width: 1920, height: 1080), viewSize: CGSize(width: 1000, height: 1000), backingScale: 2, pan: CGPoint(x: 80, y: 40))
let wideStill = pgmImageRect(mode: .fit, pixelSize: CGSize(width: 1920, height: 1080), viewSize: CGSize(width: 1000, height: 1000), backingScale: 2, pan: .zero)
expect(wide == wideStill, "fit ignores pan")
expect(wide.width <= 1000.02 && wide.height <= 1000.02 && wide.minX >= -0.02 && wide.minY >= -0.02, "letterbox stays inside")
expect(abs(wide.midX - 500) < 0.02 && abs(wide.midY - 500) < 0.02, "letterbox centered")
expect(abs((wide.width / wide.height) - (1920.0 / 1080.0)) < 0.01, "letterbox keeps aspect")
let tall = pgmImageRect(mode: .fit, pixelSize: CGSize(width: 1080, height: 1920), viewSize: CGSize(width: 1000, height: 1000), backingScale: 1, pan: .zero)
expect(abs(tall.height - 1000) < 0.02 && tall.width < 1000 && abs((tall.width / tall.height) - (1080.0 / 1920.0)) < 0.01, "tall letterbox does not crop")
let nativeSmall = pgmImageRect(mode: .native, pixelSize: CGSize(width: 100, height: 50), viewSize: CGSize(width: 200, height: 200), backingScale: 1, pan: CGPoint(x: 40, y: 40))
expect(abs(nativeSmall.width - 100) < 0.02 && abs(nativeSmall.height - 50) < 0.02, "native keeps pixel size")
expect(abs(nativeSmall.midX - 100) < 0.02 && abs(nativeSmall.midY - 100) < 0.02, "smaller native picture stays centered")
let nativeLarge = pgmImageRect(mode: .native, pixelSize: CGSize(width: 400, height: 200), viewSize: CGSize(width: 100, height: 100), backingScale: 1, pan: CGPoint(x: 1000, y: -1000))
expect(abs(nativeLarge.minX - 0) < 0.02 && abs(nativeLarge.minY - (-100)) < 0.02, "larger native picture pans inside the edges")
expect(pgmImageRect(mode: .native, pixelSize: CGSize(width: 0, height: 0), viewSize: CGSize(width: 10, height: 10), backingScale: 2, pan: CGPoint(x: 0, y: 0)) == CGRect(x: 0, y: 0, width: 0, height: 0), "empty frame")
let captured = pgmCapturePixelSize(windowPoints: CGSize(width: 1280.2, height: 720), scale: 2)
expect(captured == CGSize(width: 2560, height: 1440), "capture size is the window pixel size")
expect(pgmCapturePixelSize(windowPoints: CGSize(width: 101, height: 51), scale: 1) == CGSize(width: 102, height: 52), "capture size is even")

let stallStart = Date(timeIntervalSince1970: 1_700_000_000)
expect(!pgmShowsStallHint(changedAt: nil, now: stallStart), "stall hint waits until a frame arrives")
var stall = pgmNoteContent(signature: 11, state: PGMStallState(), now: stallStart)
expect(stall.signature == 11 && stall.changedAt == stallStart, "first frame starts the stall clock")
expect(!pgmShowsStallHint(changedAt: stall.changedAt, now: stallStart.addingTimeInterval(pgmStallHintDelay)), "two seconds is not yet a stall")
expect(pgmShowsStallHint(changedAt: stall.changedAt, now: stallStart.addingTimeInterval(pgmStallHintDelay + 0.001)), "stall hint appears after two seconds")
expect(pgmShowsStallHint(changedAt: stallStart, now: stallStart.addingTimeInterval(0.5), delay: 0.4), "stall check accepts an injected time and delay")
let stallHeld = pgmNoteContent(signature: 11, state: stall, now: stallStart.addingTimeInterval(5))
expect(stallHeld == stall, "unchanged content keeps the same clock")
expect(pgmShowsStallHint(changedAt: stallHeld.changedAt, now: stallStart.addingTimeInterval(5)), "unchanged frames stay stalled")
let stallMoved = pgmNoteContent(signature: 12, state: stallHeld, now: stallStart.addingTimeInterval(5))
expect(stallMoved.changedAt == stallStart.addingTimeInterval(5) && stallMoved.signature == 12, "new content restarts the clock")
expect(!pgmShowsStallHint(changedAt: stallMoved.changedAt, now: stallStart.addingTimeInterval(5)), "new content hides the stall hint")
let stallUnread = pgmNoteContent(signature: nil, state: stallMoved, now: stallStart.addingTimeInterval(6))
expect(stallUnread.signature == nil && stallUnread.changedAt == stallStart.addingTimeInterval(6), "unreadable frame still counts as a new frame")
func pgmTestSignature(_ bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> UInt64? {
    bytes.withUnsafeBytes { pgmFrameSignature(bytes: $0, width: width, height: height, bytesPerRow: bytesPerRow) }
}
let stallPixels = [UInt8](repeating: 20, count: 12 * 2)
var stallPixelsChanged = stallPixels
stallPixelsChanged[4] = 21
var stallPadding = stallPixels
stallPadding[8] = 99
expect(pgmTestSignature(stallPixels, width: 2, height: 2, bytesPerRow: 12) == pgmTestSignature(stallPixels, width: 2, height: 2, bytesPerRow: 12), "same pixels share a signature")
expect(pgmTestSignature(stallPixels, width: 2, height: 2, bytesPerRow: 12) == pgmTestSignature(stallPadding, width: 2, height: 2, bytesPerRow: 12), "row padding is not part of the picture")
expect(pgmTestSignature(stallPixels, width: 2, height: 2, bytesPerRow: 12) != pgmTestSignature(stallPixelsChanged, width: 2, height: 2, bytesPerRow: 12), "a changed pixel changes the signature")
expect(pgmTestSignature(stallPixels, width: 0, height: 2, bytesPerRow: 12) == nil, "empty frame has no signature")
expect(pgmTestSignature([UInt8](repeating: 1, count: 4), width: 2, height: 2, bytesPerRow: 12) == nil, "short buffer has no signature")
print("\(assertions) assertions passed")
