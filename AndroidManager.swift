import SwiftUI
import Darwin

// This object owns only its launched scrcpy Process. The shared adb server is
// never killed (other apps may be using it).
final class AndroidManager: ObservableObject {
    @Published private(set) var devices: [AndroidDevice] = []
    @Published private(set) var selectedSerial: String?
    @Published private(set) var status = "正在尋找 Android 裝置…"
    @Published private(set) var isRefreshing = false
    @Published var showSetup = false
    @Published var options = AndroidWindowOptions()
    private let queue = DispatchQueue(label: "ThatMirroring.adb")
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var mirror: Process?
    private var outputPipe: Pipe?
    private var lastError = ""
    private let errorLock = NSLock()
    private var stopped = false

    init() {
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.shutdown() })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, window.title == "That Mirroring" else { return }
            self?.stopMirror()
        })
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        guard !stopped, !isRefreshing else { return }
        guard let tools = resolveAndroidTools(resources: Bundle.main.resourceURL) else {
            devices = []; status = "找不到 Android 工具，請重新下載完整 App 或重新執行 scripts/build.sh。"; return
        }
        isRefreshing = true
        queue.async { [weak self] in
            do {
                var environment = androidEnvironment(tools: tools, resources: Bundle.main.resourceURL)
                // The window adapter is for scrcpy only, never for adb.
                environment.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
                let result = try queryTool(executable: tools.adb, arguments: ["devices", "-l"], environment: environment)
                let text = result.stdout
                let ok = !result.timedOut && result.exitStatus == 0
                DispatchQueue.main.async {
                    guard let self = self, !self.stopped else { return }
                    self.isRefreshing = false
                    self.devices = ok ? parseADBDevices(text) : []
                    if self.mirror == nil {
                        self.status = !ok ? "無法取得 Android 裝置清單，請確認連線後按「重新整理」。" :
                            self.devices.contains(where: \.isAuthorized) ? "請選擇 Android 裝置開始鏡像。" : "找不到已授權的 USB 裝置，請確認下方四個步驟。"
                    }
                    if tools.isFallback { self.status += "（目前使用 /opt/homebrew 備援工具。）" }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self, !self.stopped else { return }
                    self.isRefreshing = false; self.devices = []; self.status = "無法啟動 adb，請重新下載完整 App。"
                }
            }
        }
    }

    func start(_ device: AndroidDevice) {
        showSetup = true
        guard device.isAuthorized else {
            status = "\(device.model)：\(device.statusLabel)。請依下方步驟操作，再按「重新整理」。"; return
        }
        guard let tools = resolveAndroidTools(resources: Bundle.main.resourceURL) else {
            status = "找不到 Android 工具，請重新下載完整 App。"; return
        }
        stopMirror()
        let process = Process(), pipe = Pipe()
        process.executableURL = tools.scrcpy
        process.arguments = scrcpyArguments(device: device, options: options)
        process.environment = androidEnvironment(tools: tools, resources: Bundle.main.resourceURL)
        process.standardOutput = pipe; process.standardError = pipe
        errorLock.lock(); lastError = ""; errorLock.unlock()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }
            self.errorLock.lock()
            self.lastError = String((self.lastError + String(decoding: data, as: UTF8.self)).suffix(8192))
            self.errorLock.unlock()
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self = self, self.mirror === process else { return }
                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.mirror = nil; self.outputPipe = nil; self.selectedSerial = nil
                self.errorLock.lock(); let error = self.lastError; self.errorLock.unlock()
                if process.terminationStatus == 0 {
                    self.status = "Android 鏡像已關閉。"
                } else if error.localizedCaseInsensitiveContains("unauthorized") {
                    self.status = "手機尚未授權 USB 偵錯，請解鎖並允許這台 Mac。"
                } else {
                    self.status = "Android 鏡像已中斷，請確認傳輸線、USB 偵錯與授權後重新連線。"
                }
                self.refresh()
            }
        }
        do {
            mirror = process; outputPipe = pipe
            try process.run()
            selectedSerial = device.serial
            status = "\(device.model) 已在 That Mirroring 視窗開啟，可用 Mac 滑鼠與鍵盤操作。" + (tools.isFallback ? "（/opt/homebrew 備援）" : "")
        } catch {
            mirror = nil; outputPipe = nil
            pipe.fileHandleForReading.readabilityHandler = nil
            status = "無法啟動 Android 鏡像，請重新下載完整 App。"
        }
    }

    func stopMirror() {
        guard let process = mirror else { return }
        mirror = nil; selectedSerial = nil
        process.terminationHandler = nil
        // Continue draining output until the child exits.
        terminateOwnedProcess(process)
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        status = "Android 鏡像已關閉。"
    }
    func shutdown() {
        stopped = true; refreshTimer?.invalidate(); refreshTimer = nil; stopMirror()
    }
    deinit {
        refreshTimer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}

struct AndroidSetupView: View {
    @ObservedObject var manager: AndroidManager
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Android USB 鏡像", systemImage: "smartphone").font(.title2.bold())
                Text(manager.status).textSelection(.enabled)
                ForEach(manager.devices) { device in
                    Button { manager.start(device) } label: {
                        HStack {
                            Text("Android · \(device.model)")
                            Spacer()
                            Text(device.statusLabel).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(androidConnectionSteps).font(.body).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("重新整理") { manager.refresh() }.disabled(manager.isRefreshing)
                    if manager.selectedSerial != nil { Button("停止 Android 鏡像") { manager.stopMirror() } }
                }
                Divider()
                Text("視窗選項（下一次連線套用）").font(.headline)
                Toggle("視窗置頂", isOn: $manager.options.alwaysOnTop)
                Toggle("以全螢幕開啟", isOn: $manager.options.fullscreen)
                Toggle("播放 Android 裝置聲音", isOn: $manager.options.audio)
                Text("鏡像視窗：F11 或 Option＋F 切換全螢幕；左上關閉鍵結束鏡像。關閉 That Mirroring 主視窗或離開 App 也會停止 Android 鏡像。聲音預設關閉，部分舊版 Android 不支援轉送。").font(.callout).foregroundStyle(.secondary)
                Button("返回 iPhone／iPad／擷取卡") { manager.stopMirror(); manager.showSetup = false }
            }.padding(24)
        }.frame(minWidth: 380, minHeight: 420).preferredColorScheme(.dark)
    }
}
