import Foundation

// English keys live in Localizable.strings. A missing entry returns the key.
func localizedText(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return String(format: format, locale: Locale.current, arguments: args)
}

// nil follows the Mac's preferred-language order. Any other code is an override
// stored in AppleLanguages and applied the next time the app opens.
struct AppLanguageSetting: Equatable {
    var code: String?
    static let traditional = "zh-Hant"
    static let english = "en"

    static func stored(in defaults: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier) -> AppLanguageSetting {
        // string(forKey:) also sees the Mac's global language list. Read only
        // this app's domain so Follow System stays the default.
        guard let domain, let values = defaults.persistentDomain(forName: domain),
              let codes = values["AppleLanguages"] as? [Any], let first = codes.first as? String else {
            return AppLanguageSetting(code: nil)
        }
        return AppLanguageSetting(code: first)
    }

    func save(to defaults: UserDefaults = .standard) {
        if let code {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    var followsSystem: Bool { code == nil }
    var isTraditional: Bool { code == "zh-TW" || code?.hasPrefix(Self.traditional) == true }
    var isEnglish: Bool {
        guard let code else { return false }
        return code == Self.english || code.hasPrefix("en-")
    }
}

// 1.3.3 had no persisted GIF options. Explicitly discard known older recording
// preferences; unknown obsolete keys are never read by the display-only app.
let legacyRecordingKeys = ["IsRecording", "RecordingEnabled", "RecordingFormat", "RecordingQuality",
                           "RecordingPath", "RecordingDuration", "GIFDuration", "GIFFrameRate",
                           "GIFRecordingEnabled", "RecordAudio", "AutoStartRecording"]
func migrateLegacyRecordingSettings(_ defaults: UserDefaults) {
    for key in legacyRecordingKeys { defaults.removeObject(forKey: key) }
}

struct AndroidDevice: Identifiable, Equatable {
    let serial: String
    let state: String
    let model: String
    let isUSB: Bool
    var id: String { serial }
    var isAuthorized: Bool { state == "device" }
    var statusLabel: String {
        switch state {
        case "device": return isUSB ? localizedText("Connected over USB") : localizedText("Connected")
        case "unauthorized": return localizedText("Not authorized")
        case "offline": return localizedText("Offline. Reconnect the cable.")
        case "no permissions": return localizedText("Can't access USB")
        default: return localizedText("Can't connect")
        }
    }
}

enum AndroidMirrorPhase: Equatable { case notConnected, connectedIdle, mirroring }

func androidMirrorPhase(for device: AndroidDevice, selectedSerial: String?) -> AndroidMirrorPhase {
    if selectedSerial == device.serial { return .mirroring }
    return device.isAuthorized ? .connectedIdle : .notConnected
}

func androidDisplayDevices(_ devices: [AndroidDevice], selectedSerial: String?) -> [AndroidDevice] {
    guard let serial = selectedSerial, !devices.contains(where: { $0.serial == serial }) else { return devices }
    return devices + [AndroidDevice(serial: serial, state: "device", model: "Android", isUSB: true)]
}

func androidStepsProminent(devices: [AndroidDevice]) -> Bool {
    !devices.contains(where: \.isAuthorized)
}

func parseADBDevices(_ output: String) -> [AndroidDevice] {
    var seen = Set<String>()
    return output.components(separatedBy: .newlines).compactMap { line in
        let line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("List of devices"), !line.hasPrefix("*") else { return nil }
        let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 2 else { return nil }
        let serial: String, detail: [String]
        if let tab = line.firstIndex(of: "\t") {
            serial = String(line[..<tab])
            detail = line[line.index(after: tab)...].split(whereSeparator: { $0.isWhitespace }).map(String.init)
        } else {
            serial = fields[0]; detail = Array(fields.dropFirst())
        }
        guard let state = detail.first, ["device", "unauthorized", "offline", "no"].contains(state),
              state != "no" || detail.dropFirst().first == "permissions", seen.insert(serial).inserted else { return nil }
        let model = detail.first(where: { $0.hasPrefix("model:") }).map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") }
        return AndroidDevice(serial: serial, state: state == "no" ? "no permissions" : state,
                             model: model ?? "Android", isUSB: detail.contains { $0.hasPrefix("usb:") })
    }
}

struct AndroidTools: Equatable {
    let directory: URL
    let scrcpy: URL
    let adb: URL
    let server: URL
    let isFallback: Bool
}

// Resolve a coherent toolset; never mix bundled scrcpy with another adb/server.
func resolveAndroidTools(resources: URL?, fallback: URL = URL(fileURLWithPath: "/opt/homebrew"),
                         executable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) },
                         readable: (URL) -> Bool = { FileManager.default.isReadableFile(atPath: $0.path) }) -> AndroidTools? {
    if let directory = resources?.appendingPathComponent("scrcpy", isDirectory: true) {
        let scrcpy = directory.appendingPathComponent("ThatMirroringAndroid.app/Contents/MacOS/scrcpy")
        let adb = directory.appendingPathComponent("adb")
        let server = directory.appendingPathComponent("scrcpy-server")
        if executable(scrcpy), executable(adb), readable(server) {
            return AndroidTools(directory: directory, scrcpy: scrcpy, adb: adb, server: server, isFallback: false)
        }
    }
    let bin = fallback.appendingPathComponent("bin")
    let scrcpy = bin.appendingPathComponent("scrcpy"), adb = bin.appendingPathComponent("adb")
    let server = fallback.appendingPathComponent("share/scrcpy/scrcpy-server")
    guard executable(scrcpy), executable(adb), readable(server) else { return nil }
    return AndroidTools(directory: bin, scrcpy: scrcpy, adb: adb, server: server, isFallback: true)
}

struct AndroidWindowOptions {
    // Off until the user asks. Only this option is stored; the others stay session-only.
    static let turnScreenOffKey = "AndroidTurnScreenOff"
    var alwaysOnTop = false
    var fullscreen = false
    var audio = false
    var turnScreenOff = false

    static func stored(in defaults: UserDefaults = .standard) -> AndroidWindowOptions {
        var options = AndroidWindowOptions()
        options.turnScreenOff = defaults.bool(forKey: turnScreenOffKey)
        return options
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(turnScreenOff, forKey: Self.turnScreenOffKey)
    }
}
func scrcpyArguments(device: AndroidDevice, options: AndroidWindowOptions) -> [String] {
    var result = ["--serial=\(device.serial)", "--window-title=That Mirroring — Android · \(device.model)",
                  "--stay-awake", "--disable-screensaver", "--max-fps=60", "--video-bit-rate=12M",
                  "--background-color=000000"]
    result.append(options.audio ? "--audio-source=output" : "--no-audio")
    if options.alwaysOnTop { result.append("--always-on-top") }
    if options.fullscreen { result.append("--fullscreen") }
    if options.turnScreenOff { result.append("--turn-screen-off") }
    return result
}

func androidEnvironment(tools: AndroidTools, resources: URL?, inherited: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
    var env = inherited
    // Explicit local tool paths, independent of shell setup or inherited overrides.
    for key in ["ANDROID_SERIAL", "ADB_SERVER_SOCKET", "ANDROID_ADB_SERVER_ADDRESS", "ANDROID_ADB_SERVER_PORT", "DYLD_INSERT_LIBRARIES", "SCRCPY_ICON_DIR"] {
        env.removeValue(forKey: key)
    }
    env["ADB"] = tools.adb.path
    env["SCRCPY_SERVER_PATH"] = tools.server.path
    env["PATH"] = tools.directory.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
    env["SDL_APP_NAME"] = "That Mirroring"
    env["SDL_VIDEO_MAC_FULLSCREEN_SPACES"] = "1"
    if let resources = resources {
        let scrcpyResources = resources.appendingPathComponent("scrcpy").path
        env["SCRCPY_ICON_PATH"] = scrcpyResources
        // scrcpy's own icon/disconnected.png lookup; its binary now lives inside the helper app.
        env["SCRCPY_ICON_DIR"] = scrcpyResources
        let style = resources.appendingPathComponent("scrcpy/ThatMirroringWindow.dylib")
        if FileManager.default.isReadableFile(atPath: style.path) { env["DYLD_INSERT_LIBRARIES"] = style.path }
    }
    env["THATMIRRORING_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
    return env
}

let androidConnectionSteps = """
1) Use a data cable, not a charge-only cable.
2) On the phone, open Settings > About phone and tap Build number 7 times.
3) Open Settings > System > Developer options and turn on USB debugging.
4) When asked, select Always allow from this computer, then tap Allow.
"""

// Never terminate a process by name or kill the shared adb server.
func terminateOwnedProcess(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    let deadline = Date().addingTimeInterval(0.8)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
}

struct ToolQueryResult {
    let stdout: String
    let exitStatus: Int32
    let timedOut: Bool
}
// Nonblocking pipe reads keep an adb query bounded even when its shared daemon
// inherits output descriptors; no threads are left blocked waiting for EOF.
func queryTool(executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval = 5) throws -> ToolQueryResult {
    let process = Process(), stdout = Pipe(), stderr = Pipe()
    process.executableURL = executable; process.arguments = arguments; process.environment = environment
    process.standardOutput = stdout; process.standardError = stderr
    let outputFD = stdout.fileHandleForReading.fileDescriptor, errorFD = stderr.fileHandleForReading.fileDescriptor
    for fd in [outputFD, errorFD] { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
    try process.run()
    try? stdout.fileHandleForWriting.close(); try? stderr.fileHandleForWriting.close()
    defer { try? stdout.fileHandleForReading.close(); try? stderr.fileHandleForReading.close() }
    var output = Data()
    func drain(_ fd: Int32, retain: Bool) {
        var bytes = [UInt8](repeating: 0, count: 4096)
        // Bound each drain, even if the child produces output continuously.
        for _ in 0..<64 {
            let n = read(fd, &bytes, bytes.count)
            guard n > 0 else { break }
            if retain && output.count < 1_048_576 { output.append(contentsOf: bytes.prefix(min(n, 1_048_576 - output.count))) }
        }
    }
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        drain(outputFD, retain: true); drain(errorFD, retain: false)
        Thread.sleep(forTimeInterval: 0.02)
    }
    let timedOut = process.isRunning
    if timedOut { terminateOwnedProcess(process) }
    process.waitUntilExit()
    drain(outputFD, retain: true); drain(errorFD, retain: false)
    return ToolQueryResult(stdout: String(decoding: output, as: UTF8.self), exitStatus: process.terminationStatus, timedOut: timedOut)
}
