import Foundation

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
        case "device": return isUSB ? "USB 已連線" : "已連線"
        case "unauthorized": return "尚未授權"
        case "offline": return "離線，請重新插拔"
        case "no permissions": return "無法存取 USB"
        default: return "無法連線"
        }
    }
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
                             model: model ?? "Android 裝置", isUSB: detail.contains { $0.hasPrefix("usb:") })
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
        let scrcpy = directory.appendingPathComponent("scrcpy"), adb = directory.appendingPathComponent("adb")
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
    var alwaysOnTop = false
    var fullscreen = false
    var audio = false
}
func scrcpyArguments(device: AndroidDevice, options: AndroidWindowOptions) -> [String] {
    var result = ["--serial=\(device.serial)", "--window-title=That Mirroring — Android · \(device.model)",
                  "--stay-awake", "--disable-screensaver", "--max-fps=60", "--video-bit-rate=12M",
                  "--background-color=000000"]
    result.append(options.audio ? "--audio-source=output" : "--no-audio")
    if options.alwaysOnTop { result.append("--always-on-top") }
    if options.fullscreen { result.append("--fullscreen") }
    return result
}

func androidEnvironment(tools: AndroidTools, resources: URL?, inherited: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
    var env = inherited
    // Explicit local tool paths, independent of shell setup or inherited overrides.
    for key in ["ANDROID_SERIAL", "ADB_SERVER_SOCKET", "ANDROID_ADB_SERVER_ADDRESS", "ANDROID_ADB_SERVER_PORT", "DYLD_INSERT_LIBRARIES"] {
        env.removeValue(forKey: key)
    }
    env["ADB"] = tools.adb.path
    env["SCRCPY_SERVER_PATH"] = tools.server.path
    env["PATH"] = tools.directory.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
    env["SDL_APP_NAME"] = "That Mirroring"
    env["SDL_VIDEO_MAC_FULLSCREEN_SPACES"] = "1"
    if let resources = resources {
        env["SCRCPY_ICON_PATH"] = resources.appendingPathComponent("scrcpy").path
        let style = resources.appendingPathComponent("scrcpy/ThatMirroringWindow.dylib")
        if FileManager.default.isReadableFile(atPath: style.path) { env["DYLD_INSERT_LIBRARIES"] = style.path }
    }
    env["THATMIRRORING_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
    return env
}

let androidConnectionSteps = """
1) 手機用「傳輸線」（非純充電線）接上 Mac。
2) 手機：設定 > 關於手機 > 連點「組建編號」7 次，開啟開發人員選項。
3) 手機：設定 > 系統 > 開發人員選項 > 開啟「USB 偵錯」。
4) 手機跳出「允許 USB 偵錯」時，勾選「一律允許使用這台電腦」並按確定。
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
