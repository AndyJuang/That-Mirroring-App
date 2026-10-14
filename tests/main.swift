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
let bundledFiles = Set(["scrcpy", "adb", "scrcpy-server"].map { root.appendingPathComponent($0).path })
let fallbackFiles = Set(["bin/scrcpy", "bin/adb", "share/scrcpy/scrcpy-server"].map { fallback.appendingPathComponent($0).path })
func resolve(_ files: Set<String>, resources: URL? = resources) -> AndroidTools? {
    resolveAndroidTools(resources: resources, fallback: fallback,
                        executable: { files.contains($0.path) }, readable: { files.contains($0.path) })
}
let tools = resolve(bundledFiles.union(fallbackFiles))!
expect(!tools.isFallback && tools.directory.path == root.path, "bundle must take precedence")
expect(tools.adb.path == root.appendingPathComponent("adb").path, "bundled adb")
expect(tools.server.path == root.appendingPathComponent("scrcpy-server").path, "bundled server")
expect(resolve(fallbackFiles)!.isFallback, "missing bundle fallback")
expect(resolve(fallbackFiles, resources: nil)!.isFallback, "nil resource URL fallback")
expect(resolve([]) == nil, "missing tools must fail")
for missing in ["adb", "scrcpy", "scrcpy-server"] {
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
let env = androidEnvironment(tools: tools, resources: resources, inherited: ["ADB":"wrong", "SCRCPY_SERVER_PATH":"wrong", "ANDROID_SERIAL":"wrong", "DYLD_INSERT_LIBRARIES":"wrong", "ADB_SERVER_SOCKET":"remote", "PATH":"wrong"])
expect(env["ADB"] == tools.adb.path && env["SCRCPY_SERVER_PATH"] == tools.server.path, "explicit bundle environment")
expect(env["ANDROID_SERIAL"] == nil && env["ADB_SERVER_SOCKET"] == nil && env["DYLD_INSERT_LIBRARIES"] == nil, "inherited tool overrides removed")
expect(env["PATH"]!.hasPrefix(root.path + ":"), "bundle path with spaces")
expect(env["SCRCPY_ICON_PATH"] == root.path, "own icon path")
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
print("\(assertions) assertions passed")
