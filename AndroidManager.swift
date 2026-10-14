import SwiftUI
import Darwin

// This object owns only its launched scrcpy Process. The shared adb server is
// never killed (other apps may be using it).
final class AndroidManager: ObservableObject {
    @Published private(set) var devices: [AndroidDevice] = []
    @Published private(set) var selectedSerial: String?
    @Published private(set) var status = localizedText("Looking for Android devices…")
    @Published private(set) var isRefreshing = false
    @Published var showSetup = false
    @Published var options = AndroidWindowOptions.stored() {
        didSet {
            if options.turnScreenOff != oldValue.turnScreenOff { options.save() }
        }
    }
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
            devices = []; status = localizedText("Android tools are missing. Download That Mirroring again."); return
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
                        self.status = !ok ? localizedText("Can't list Android devices. Check the connection, then click Refresh.") :
                            self.devices.contains(where: \.isAuthorized) ? localizedText("Choose an Android device to start.") : localizedText("No authorized USB device. Check the four steps below.")
                    }
                    if tools.isFallback { self.status = localizedText("%@ (Using backup tools.)", self.status) }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self, !self.stopped else { return }
                    self.isRefreshing = false; self.devices = []; self.status = localizedText("Can't start the Android tools. Download That Mirroring again.")
                }
            }
        }
    }

    func start(_ device: AndroidDevice) {
        showSetup = true
        guard device.isAuthorized else {
            status = localizedText("%@: %@. Follow the steps below, then click Refresh.", device.model, device.statusLabel); return
        }
        guard let tools = resolveAndroidTools(resources: Bundle.main.resourceURL) else {
            status = localizedText("Android tools are missing. Download That Mirroring again."); return
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
                    self.status = localizedText("Android mirroring is off.")
                } else if error.localizedCaseInsensitiveContains("unauthorized") {
                    self.status = localizedText("Allow USB debugging on the phone. Unlock it and allow this Mac.")
                } else {
                    self.status = localizedText("Android mirroring stopped. Check the cable, USB debugging, and permission, then connect again.")
                }
                self.refresh()
            }
        }
        do {
            mirror = process; outputPipe = pipe
            try process.run()
            selectedSerial = device.serial
            status = localizedText("%@ is open in That Mirroring. Use the Mac mouse and keyboard.", device.model)
            if tools.isFallback { status = localizedText("%@ (Using backup tools.)", status) }
        } catch {
            mirror = nil; outputPipe = nil
            pipe.fileHandleForReading.readabilityHandler = nil
            status = localizedText("Can't start Android mirroring. Download That Mirroring again.")
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
        status = localizedText("Android mirroring is off.")
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
                Label("Android over USB", systemImage: "smartphone").font(.title2.bold())
                Text(manager.status).textSelection(.enabled)
                Text("Use your mouse and keyboard to control the phone.").font(.callout).foregroundStyle(.secondary)
                ForEach(manager.devices) { device in
                    Button { manager.start(device) } label: {
                        HStack {
                            Text(localizedText("Android · %@", device.model))
                            Spacer()
                            Text(device.statusLabel).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(localizedText(androidConnectionSteps)).font(.body).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Refresh") { manager.refresh() }.disabled(manager.isRefreshing)
                    if manager.selectedSerial != nil { Button("Stop Android Mirroring") { manager.stopMirror() } }
                }
                Divider()
                Text("Window options apply the next time you connect.").font(.headline)
                Toggle("Keep Window on Top", isOn: $manager.options.alwaysOnTop)
                Toggle("Open in Full Screen", isOn: $manager.options.fullscreen)
                Toggle("Play Android Audio", isOn: $manager.options.audio)
                Toggle("Turn Off Phone Screen", isOn: $manager.options.turnScreenOff)
                Text("In the mirror window, press F11 or Option-F for full screen. Closing the window stops mirroring. Quitting That Mirroring also stops it. Audio is off by default. Some older phones cannot send audio.").font(.callout).foregroundStyle(.secondary)
                Button("Back to iPhone, iPad, or Capture Card") { manager.stopMirror(); manager.showSetup = false }
            }.padding(24)
        }.frame(minWidth: 380, minHeight: 420).preferredColorScheme(.dark)
    }
}
