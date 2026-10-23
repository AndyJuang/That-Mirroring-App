import SwiftUI
import Darwin

// This object owns only its launched scrcpy Process. The shared adb server is
// never killed (other apps may be using it).
private func backupToolsNote(_ status: String) -> String {
    localizedText("%@ (Using backup tools.)", status).trimmingCharacters(in: .whitespaces)
}

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
                        self.status = ok ? "" : localizedText("Can't list Android devices. Check the connection, then click Refresh.")
                        if tools.isFallback { self.status = backupToolsNote(self.status) }
                    }
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
                    self.status = ""
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
            status = tools.isFallback ? backupToolsNote("") : ""
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
        status = ""
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
        AndroidSetupContent(
            devices: manager.devices, selectedSerial: manager.selectedSerial, status: manager.status,
            isRefreshing: manager.isRefreshing, options: $manager.options,
            onStart: { manager.start($0) }, onStop: { manager.stopMirror() }, onRefresh: { manager.refresh() },
            onBack: { manager.stopMirror(); manager.showSetup = false })
    }
}

struct AndroidSetupContent: View {
    let devices: [AndroidDevice]
    let selectedSerial: String?
    let status: String
    let isRefreshing: Bool
    @Binding var options: AndroidWindowOptions
    var scrolls = true
    let onStart: (AndroidDevice) -> Void
    let onStop: () -> Void
    let onRefresh: () -> Void
    let onBack: () -> Void
    @ViewState private var showTips = false
    @ViewState private var showGuide = false

    private let bodyFont = Font.system(size: 15)
    private let placeholder = AndroidDevice(serial: "", state: "", model: "", isUSB: false)

    var body: some View {
        Group {
            if scrolls { ScrollView { content } } else { content }
        }.frame(minWidth: 380, minHeight: 420).preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("Android over USB", systemImage: "smartphone").font(.system(size: 26, weight: .bold))
            if !status.isEmpty {
                Text(status).font(bodyFont).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            deviceSection
            if androidStepsProminent(devices: devices) {
                Text(localizedText(androidConnectionSteps)).font(bodyFont).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    Text("Connection Guide").font(.system(size: 17, weight: .semibold))
                    infoButton(isPresented: $showGuide, label: localizedText("Connection Guide")) {
                        Text(localizedText(androidConnectionSteps)).font(bodyFont).lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true).frame(width: 320, alignment: .leading).padding(16)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Window Options (Applied the Next Time Mirroring Starts)").font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Keep Window on Top", isOn: $options.alwaysOnTop)
                Toggle("Open in Full Screen", isOn: $options.fullscreen)
                Toggle("Play Android Audio", isOn: $options.audio)
                Toggle("Turn Off Phone Screen", isOn: $options.turnScreenOff)
            }.font(bodyFont)
            Button("Back to iPhone, iPad, or Capture Card", action: onBack)
                .font(bodyFont).controlSize(.large).keyboardShortcut(.cancelAction)
        }
        .padding(26)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Android Devices").font(.system(size: 17, weight: .semibold))
                infoButton(isPresented: $showTips, label: localizedText("Mirror Window Tips")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mirror Window Tips").font(.system(size: 17, weight: .semibold))
                        Text("Press F11 or Option-F in the mirror window to toggle full screen.")
                        Text("Closing the mirror window or quitting That Mirroring stops mirroring.")
                        Text("Use your Mac mouse and keyboard to control the phone.")
                        Text("Audio is off by default. Some older phones can't send audio.")
                    }.font(bodyFont).fixedSize(horizontal: false, vertical: true).frame(width: 320, alignment: .leading).padding(16)
                }
                Spacer()
                if isRefreshing { ProgressView().controlSize(.small) }
                Button { onRefresh() } label: { Label("Refresh", systemImage: "arrow.clockwise").font(bodyFont) }
                    .disabled(isRefreshing)
            }
            let shown = androidDisplayDevices(devices, selectedSerial: selectedSerial)
            if shown.isEmpty {
                deviceCard(placeholder, title: localizedText("No Android device"))
            } else {
                ForEach(shown) { deviceCard($0, title: $0.model) }
            }
        }
    }

    private func infoButton<Popover: View>(isPresented: Binding<Bool>, label: String, @ViewBuilder content: @escaping () -> Popover) -> some View {
        Button { isPresented.wrappedValue.toggle() } label: { Image(systemName: "info.circle").font(.system(size: 17)) }
            .buttonStyle(.plain).accessibilityLabel(label)
            .popover(isPresented: isPresented, arrowEdge: .bottom, content: content)
    }

    private func deviceCard(_ device: AndroidDevice, title: String) -> some View {
        let phase = androidMirrorPhase(for: device, selectedSerial: selectedSerial)
        let action = { phase == .mirroring ? onStop() : onStart(device) }
        let info = HStack(alignment: .top, spacing: 12) {
            Image(systemName: "smartphone").font(.system(size: 28)).foregroundStyle(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                pill(phase)
                if phase == .notConnected, !device.state.isEmpty {
                    Text(device.statusLabel).font(.system(size: 14)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        let button = Button(action: action) {
            Text(phase == .mirroring ? localizedText("Stop Mirroring") : localizedText("Start Mirroring")).font(.system(size: 16, weight: .semibold)).padding(.horizontal, 10)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .tint(phase == .mirroring ? .red : .accentColor)
        .disabled(phase == .notConnected)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) { info; Spacer(minLength: 8); button.fixedSize() }
            VStack(alignment: .leading, spacing: 14) { info; button }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func pill(_ phase: AndroidMirrorPhase) -> some View {
        let (text, color): (String, Color) = {
            switch phase {
            case .notConnected: return (localizedText("Not Connected"), .gray)
            case .connectedIdle: return (localizedText("Connected · Not Mirroring"), .blue)
            case .mirroring: return (localizedText("Mirroring"), .green)
            }
        }()
        return Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(color == .gray ? Color.secondary : color)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
    }
}
