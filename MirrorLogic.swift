import Foundation
import CoreGraphics

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

// Thatcaster 的節目視窗標題。中文介面與英文介面各一個，必須整句相同。
// 投影輸出、提詞機和這個 App 自己的視窗都不是節目畫面。
let thatcasterPGMTitles = ["Thatcaster — PGM 監看", "Thatcaster — Program"]

func isThatcasterPGMWindow(title: String, ownerBundleID: String?, ownBundleID: String) -> Bool {
    guard thatcasterPGMTitles.contains(title) else { return false }
    if let ownerBundleID, ownerBundleID == ownBundleID { return false }
    return true
}

enum PGMFitMode: String, Equatable {
    case native
    case fit
}

let pgmFitModeKey = "PGMFitMode"
let pgmVisibleKey = "PGMMonitorVisible"
let pgmDisplayUUIDKey = "PGMDisplayUUID"
let pgmDisplayNameKey = "PGMDisplayName"
let pgmDisplayWidthKey = "PGMDisplayPixelWidth"
let pgmDisplayHeightKey = "PGMDisplayPixelHeight"
let phoneVisibleKey = "PhoneMirrorVisible"
let phoneDisplayUUIDKey = "PhoneDisplayUUID"
let phoneDisplayNameKey = "PhoneDisplayName"
let phoneDisplayWidthKey = "PhoneDisplayPixelWidth"
let phoneDisplayHeightKey = "PhoneDisplayPixelHeight"

func loadPGMFitMode(_ defaults: UserDefaults) -> PGMFitMode {
    PGMFitMode(rawValue: defaults.string(forKey: pgmFitModeKey) ?? "") ?? .fit
}

func loadPGMVisible(_ defaults: UserDefaults) -> Bool {
    defaults.object(forKey: pgmVisibleKey) as? Bool ?? false
}

func loadPhoneMirrorVisible(_ defaults: UserDefaults) -> Bool {
    defaults.object(forKey: phoneVisibleKey) as? Bool ?? true
}

struct DisplayIdentity: Equatable {
    var uuid: String
    var name: String
    var pixelWidth: Int
    var pixelHeight: Int

    var id: String {
        if !uuid.isEmpty { return uuid }
        return "\(name) \(pixelWidth)x\(pixelHeight)"
    }
}

func saveDisplayIdentity(_ identity: DisplayIdentity?, uuidKey: String, nameKey: String, widthKey: String, heightKey: String, defaults: UserDefaults) {
    guard let identity else {
        for key in [uuidKey, nameKey, widthKey, heightKey] { defaults.removeObject(forKey: key) }
        return
    }
    defaults.set(identity.uuid, forKey: uuidKey)
    defaults.set(identity.name, forKey: nameKey)
    defaults.set(identity.pixelWidth, forKey: widthKey)
    defaults.set(identity.pixelHeight, forKey: heightKey)
}

func loadDisplayIdentity(uuidKey: String, nameKey: String, widthKey: String, heightKey: String, defaults: UserDefaults) -> DisplayIdentity? {
    guard defaults.object(forKey: uuidKey) != nil || defaults.object(forKey: nameKey) != nil else { return nil }
    return DisplayIdentity(uuid: defaults.string(forKey: uuidKey) ?? "", name: defaults.string(forKey: nameKey) ?? "",
                           pixelWidth: defaults.integer(forKey: widthKey), pixelHeight: defaults.integer(forKey: heightKey))
}

// uuid 先對。拔掉再插上時，系統可能給新的暫用編號，uuid 仍在就用 uuid。
// uuid 對不到時，名稱加像素尺寸只有一台才算。再不行，名稱只有一台才算。多台同名不猜。
func matchDisplay(_ saved: DisplayIdentity, among displays: [DisplayIdentity]) -> DisplayIdentity? {
    if !saved.uuid.isEmpty, let exact = displays.first(where: { $0.uuid == saved.uuid }) { return exact }
    let sized = displays.filter { $0.name == saved.name && !$0.name.isEmpty && $0.pixelWidth == saved.pixelWidth && $0.pixelHeight == saved.pixelHeight }
    if sized.count == 1 { return sized[0] }
    let named = displays.filter { $0.name == saved.name && !$0.name.isEmpty }
    if named.count == 1 { return named[0] }
    return nil
}

func pgmCapturePixelSize(windowPoints: CGSize, scale: CGFloat) -> CGSize {
    let factor = max(scale, 1)
    func even(_ value: CGFloat) -> CGFloat {
        let rounded = max(2, Int(value.rounded()))
        return CGFloat(rounded % 2 == 0 ? rounded : rounded + 1)
    }
    return CGSize(width: even(windowPoints.width * factor), height: even(windowPoints.height * factor))
}

func pgmNativePointSize(pixelSize: CGSize, backingScale: CGFloat) -> CGSize {
    let scale = max(backingScale, 1)
    return CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
}

func pgmClampedPan(content: CGSize, view: CGSize, pan: CGPoint) -> CGPoint {
    func axis(content: CGFloat, view: CGFloat, proposed: CGFloat) -> CGFloat {
        let overflow = content - view
        if overflow <= 0 { return 0 }
        let limit = overflow / 2
        return min(max(proposed, -limit), limit)
    }
    return CGPoint(x: axis(content: content.width, view: view.width, proposed: pan.x),
                   y: axis(content: content.height, view: view.height, proposed: pan.y))
}

// 原點在左下。1:1 是一個來源像素對一個螢幕像素。縮放全畫面用等比例塞進視窗，四周留黑，不裁切。
func pgmImageRect(mode: PGMFitMode, pixelSize: CGSize, viewSize: CGSize, backingScale: CGFloat, pan: CGPoint) -> CGRect {
    guard pixelSize.width > 0, pixelSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
        return CGRect(x: 0, y: 0, width: 0, height: 0)
    }
    let native = pgmNativePointSize(pixelSize: pixelSize, backingScale: backingScale)
    switch mode {
    case .native:
        let clamped = pgmClampedPan(content: native, view: viewSize, pan: pan)
        let origin = CGPoint(x: (viewSize.width - native.width) / 2 + clamped.x,
                             y: (viewSize.height - native.height) / 2 + clamped.y)
        return CGRect(origin: origin, size: native)
    case .fit:
        let fittedScale = min(viewSize.width / native.width, viewSize.height / native.height)
        let size = CGSize(width: native.width * fittedScale, height: native.height * fittedScale)
        let origin = CGPoint(x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2)
        return CGRect(origin: origin, size: size)
    }
}

// 來源超過這段時間沒有新內容，監看視窗才顯示停住提示。時間由呼叫端傳入。
let pgmStallHintDelay: TimeInterval = 2

struct PGMStallState: Equatable {
    var signature: UInt64?
    var changedAt: Date?
}

// changedAt 是最近一次內容有變、或讀不到簽章的時刻。沒有影格時不顯示。
func pgmShowsStallHint(changedAt: Date?, now: Date, delay: TimeInterval = pgmStallHintDelay) -> Bool {
    guard let changedAt else { return false }
    return now.timeIntervalSince(changedAt) > delay
}

// 簽章相同代表這張畫面沒變，時鐘留在原處。簽章是 nil 代表讀不到像素，仍算有新影格。
func pgmNoteContent(signature: UInt64?, state: PGMStallState, now: Date) -> PGMStallState {
    guard let signature else { return PGMStallState(signature: nil, changedAt: now) }
    if state.signature == signature, state.changedAt != nil { return state }
    return PGMStallState(signature: signature, changedAt: now)
}

// BGRA 影格的內容簽章。列尾填補不計。寬高或緩衝不足時沒有簽章。
func pgmFrameSignature(bytes: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int) -> UInt64? {
    guard width > 0, height > 0, bytesPerRow >= width * 4 else { return nil }
    let needed = (height - 1) * bytesPerRow + width * 4
    guard bytes.count >= needed, let base = bytes.baseAddress else { return nil }
    var hash: UInt64 = 14695981039346656037
    hash ^= UInt64(width)
    hash &*= 1099511628211
    hash ^= UInt64(height)
    hash &*= 1099511628211
    for y in 0..<height {
        let row = base.advanced(by: y * bytesPerRow)
        for x in 0..<width {
            let pixel = row.advanced(by: x * 4).loadUnaligned(as: UInt32.self) & 0x00ff_ffff
            hash ^= UInt64(pixel)
            hash &*= 1099511628211
        }
    }
    return hash
}
