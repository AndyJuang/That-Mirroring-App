import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit

// 節目畫面只從 Thatcaster 的 PGM 視窗擷取（ScreenCaptureKit 的視窗濾鏡）。
// 影格的 IOSurface 畫在一般 CALayer。不錄影，也不走預覽層。
// 手機投影視窗的開關和螢幕只搬位置或隱藏，不改它的擷取與操作。

struct DisplayMenuItem: Identifiable, Equatable {
    var id: String
    var title: String
    var identity: DisplayIdentity
}

private enum PGMCaptureProblem {
    case none
    case permission
    case waiting
}

@MainActor
final class PGMMonitorController: ObservableObject {
    @Published private(set) var pgmVisible: Bool
    @Published private(set) var phoneVisible: Bool
    @Published private(set) var screens: [DisplayMenuItem] = []
    @Published private(set) var pgmScreenID = ""
    @Published private(set) var phoneScreenID = ""

    private var fitMode: PGMFitMode
    private var pgmIdentity: DisplayIdentity?
    private var phoneIdentity: DisplayIdentity?
    private var panel: PGMPanel?
    private var videoView: PGMVideoView?
    private var popover: NSPopover?
    private var infoLabel: NSTextField?
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var didRequestAccess = false
    private var problem: PGMCaptureProblem = .waiting
    private var pixelSize: CGSize = .zero
    private var captureTask: Task<Void, Never>?
    private var stream: SCStream?
    private var streamOutput: PGMStreamOutput?
    private var sourceWindowID: CGWindowID?
    private var sourcePixelSize: CGSize = .zero
    private let captureQueue = DispatchQueue(label: "ThatMirroring.pgmCapture", qos: .userInteractive)
    private let pump = PGMFramePump()

    init() {
        let defaults = UserDefaults.standard
        pgmVisible = loadPGMVisible(defaults)
        phoneVisible = loadPhoneMirrorVisible(defaults)
        fitMode = loadPGMFitMode(defaults)
        pgmIdentity = loadDisplayIdentity(uuidKey: pgmDisplayUUIDKey, nameKey: pgmDisplayNameKey, widthKey: pgmDisplayWidthKey, heightKey: pgmDisplayHeightKey, defaults: defaults)
        phoneIdentity = loadDisplayIdentity(uuidKey: phoneDisplayUUIDKey, nameKey: phoneDisplayNameKey, widthKey: phoneDisplayWidthKey, heightKey: phoneDisplayHeightKey, defaults: defaults)
        pgmScreenID = pgmIdentity?.id ?? ""
        phoneScreenID = phoneIdentity?.id ?? ""
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func start() {
        guard observers.isEmpty else { return }
        pump.onFrame = { [weak self] buffer in
            self?.present(buffer)
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow, window.title == "That Mirroring" else { return }
                self?.phoneWindowBecameVisible(window)
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setPGMVisible(false) }
        })
        publishScreens()
        applyPhoneVisibility()
        if pgmVisible {
            syncPGMWindow()
            startCaptureLoop()
        }
    }

    func togglePGM() { setPGMVisible(!pgmVisible) }
    func togglePhone() { setPhoneVisible(!phoneVisible) }

    func setPGMVisible(_ visible: Bool) {
        guard pgmVisible != visible else {
            if visible { syncPGMWindow() }
            return
        }
        pgmVisible = visible
        UserDefaults.standard.set(visible, forKey: pgmVisibleKey)
        if visible {
            syncPGMWindow()
            startCaptureLoop()
        } else {
            captureTask?.cancel()
            captureTask = nil
            popover?.performClose(nil)
            panel?.orderOut(nil)
            clearPicture()
            Task { await self.stopStream() }
        }
    }

    func setPhoneVisible(_ visible: Bool) {
        phoneVisible = visible
        UserDefaults.standard.set(visible, forKey: phoneVisibleKey)
        applyPhoneVisibility()
    }

    func choosePGM(id: String) {
        guard let item = screens.first(where: { $0.id == id }) else { return }
        pgmIdentity = item.identity
        pgmScreenID = item.identity.id
        saveDisplayIdentity(item.identity, uuidKey: pgmDisplayUUIDKey, nameKey: pgmDisplayNameKey, widthKey: pgmDisplayWidthKey, heightKey: pgmDisplayHeightKey, defaults: .standard)
        if pgmVisible { syncPGMWindow() }
    }

    func choosePhone(id: String) {
        guard let item = screens.first(where: { $0.id == id }) else { return }
        phoneIdentity = item.identity
        phoneScreenID = item.identity.id
        saveDisplayIdentity(item.identity, uuidKey: phoneDisplayUUIDKey, nameKey: phoneDisplayNameKey, widthKey: phoneDisplayWidthKey, heightKey: phoneDisplayHeightKey, defaults: .standard)
        movePhone(to: item.identity)
    }

    func setFitMode(_ mode: PGMFitMode) {
        guard fitMode != mode else { return }
        fitMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: pgmFitModeKey)
        videoView?.mode = mode
        videoView?.pan = .zero
        videoView?.layoutVideo()
        refreshInfo()
    }

    private func screensChanged() {
        publishScreens()
        if pgmVisible { syncPGMWindow() }
        if let phoneIdentity { movePhone(to: phoneIdentity) }
    }

    private func publishScreens() {
        var seen: [String: Int] = [:]
        screens = NSScreen.screens.enumerated().map { index, screen in
            let identity = identity(of: screen)
            var id = identity.id
            let count = seen[id, default: 0]
            seen[id] = count + 1
            if count > 0 { id += "#\(count)" }
            let title = screen.localizedName.isEmpty ? localizedText("Screen %d", index + 1) : screen.localizedName
            return DisplayMenuItem(id: id, title: title, identity: identity)
        }
        if let pgmIdentity { pgmScreenID = pgmIdentity.id }
        if let phoneIdentity { phoneScreenID = phoneIdentity.id }
    }

    private func identity(of screen: NSScreen) -> DisplayIdentity {
        let scale = max(screen.backingScaleFactor, 1)
        return DisplayIdentity(uuid: displayUUID(screen), name: screen.localizedName,
                               pixelWidth: Int((screen.frame.width * scale).rounded()),
                               pixelHeight: Int((screen.frame.height * scale).rounded()))
    }

    private func displayUUID(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return "" }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) else { return "" }
        return CFUUIDCreateString(nil, unmanaged.takeRetainedValue()) as String
    }

    private func resolvedScreen(_ identity: DisplayIdentity?) -> NSScreen? {
        guard let identity else { return nil }
        let pairs = NSScreen.screens.map { ($0, self.identity(of: $0)) }
        guard let match = matchDisplay(identity, among: pairs.map(\.1)) else { return nil }
        return pairs.first { $0.1 == match }?.0
    }

    private func defaultScreen() -> NSScreen? {
        NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.screens.first
    }

    private func ensurePanel() -> PGMPanel {
        if let panel { return panel }
        let panel = PGMPanel(contentRect: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 720),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.title = "That Mirroring PGM"
        panel.titleVisibility = .hidden
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        let view = PGMVideoView(frame: panel.contentView?.bounds ?? .zero)
        view.autoresizingMask = [.width, .height]
        view.mode = fitMode
        view.onInfo = { [weak self] in self?.toggleInfo(from: view.infoButton) }
        panel.contentView = view
        self.panel = panel
        self.videoView = view
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let windowNumber = event.window?.windowNumber ?? -1
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers
            let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel?.windowNumber == windowNumber else { return false }
                return self.handleKey(keyCode: keyCode, characters: characters, plain: plain)
            }
            return handled ? nil : event
        }
        return panel
    }

    private func handleKey(keyCode: UInt16, characters: String?, plain: Bool) -> Bool {
        if keyCode == 53 {
            setPGMVisible(false)
            return true
        }
        guard plain, let chars = characters?.lowercased() else { return false }
        if chars == "1" {
            setFitMode(.native)
            return true
        }
        if chars == "f" {
            setFitMode(.fit)
            return true
        }
        return false
    }

    private func syncPGMWindow() {
        guard pgmVisible else {
            panel?.orderOut(nil)
            return
        }
        let screen = resolvedScreen(pgmIdentity) ?? (pgmIdentity == nil ? defaultScreen() : nil)
        guard let screen else {
            panel?.orderOut(nil)
            return
        }
        if pgmIdentity == nil {
            let identity = identity(of: screen)
            pgmIdentity = identity
            pgmScreenID = identity.id
            saveDisplayIdentity(identity, uuidKey: pgmDisplayUUIDKey, nameKey: pgmDisplayNameKey, widthKey: pgmDisplayWidthKey, heightKey: pgmDisplayHeightKey, defaults: .standard)
        }
        let panel = ensurePanel()
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        videoView?.layoutVideo()
    }

    private func phoneWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.title == "That Mirroring" }
    }

    private func applyPhoneVisibility() {
        for window in phoneWindows() {
            if phoneVisible {
                if !window.isVisible { window.orderFrontRegardless() }
            } else if window.isVisible {
                window.orderOut(nil)
            }
        }
    }

    private func phoneWindowBecameVisible(_ window: NSWindow) {
        if !phoneVisible {
            window.orderOut(nil)
            return
        }
        guard let phoneIdentity else { return }
        movePhone(to: phoneIdentity)
    }

    private func movePhone(to identity: DisplayIdentity) {
        guard let screen = resolvedScreen(identity) else { return }
        for window in phoneWindows() {
            if window.styleMask.contains(.fullScreen) || window.screen == screen { continue }
            let visible = screen.visibleFrame
            var frame = window.frame
            if frame.width > visible.width || frame.height > visible.height {
                let scale = min(visible.width / frame.width, visible.height / frame.height)
                frame.size.width *= scale
                frame.size.height *= scale
            }
            frame.origin = CGPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func startCaptureLoop() {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                let stillVisible = await MainActor.run { self?.pgmVisible ?? false }
                if !stillVisible { break }
                await self?.refreshCapture()
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refreshCapture() async {
        guard pgmVisible else { return }
        if !CGPreflightScreenCaptureAccess() {
            if !didRequestAccess {
                didRequestAccess = true
                CGRequestScreenCaptureAccess()
            }
            problem = .permission
            refreshInfo()
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let own = Bundle.main.bundleIdentifier ?? "com.example.iPhoneMirror"
            guard let window = content.windows.first(where: {
                isThatcasterPGMWindow(title: $0.title ?? "", ownerBundleID: $0.owningApplication?.bundleIdentifier, ownBundleID: own)
            }) else {
                problem = .waiting
                sourceWindowID = nil
                clearPicture()
                await stopStream()
                refreshInfo()
                return
            }
            let pixels = pgmCapturePixelSize(windowPoints: window.frame.size, scale: scale(for: window, displays: content.displays))
            if stream != nil, sourceWindowID == window.windowID, sourcePixelSize == pixels {
                if problem != .none {
                    problem = .none
                    refreshInfo()
                }
                return
            }
            try await startStream(window: window, pixels: pixels)
        } catch {
            problem = .permission
            refreshInfo()
        }
    }

    private func scale(for window: SCWindow, displays: [SCDisplay]) -> CGFloat {
        let hit = displays.first { $0.frame.intersects(window.frame) } ?? displays.first
        guard let hit, hit.frame.width > 0 else { return NSScreen.main?.backingScaleFactor ?? 2 }
        return max(1, CGFloat(hit.width) / hit.frame.width)
    }

    private func startStream(window: SCWindow, pixels: CGSize) async throws {
        await stopStream()
        guard pgmVisible, !Task.isCancelled else { return }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(pixels.width)
        config.height = Int(pixels.height)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.queueDepth = 3
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        let output = PGMStreamOutput()
        let pump = self.pump
        output.onBuffer = { buffer in
            pump.push(buffer)
        }
        output.onStop = { [weak self] in
            Task { @MainActor in
                self?.stream = nil
                self?.sourceWindowID = nil
            }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()
        guard pgmVisible, !Task.isCancelled else {
            try? await stream.stopCapture()
            return
        }
        self.stream = stream
        self.streamOutput = output
        self.sourceWindowID = window.windowID
        self.sourcePixelSize = pixels
        problem = .none
        refreshInfo()
    }

    private func stopStream() async {
        guard let stream else { return }
        self.stream = nil
        streamOutput = nil
        sourceWindowID = nil
        try? await stream.stopCapture()
    }

    private func present(_ buffer: CVPixelBuffer) {
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let sizeChanged = size != pixelSize
        pixelSize = size
        if problem != .none { problem = .none }
        videoView?.pixelSize = size
        videoView?.show(buffer)
        if sizeChanged || infoLabel?.window != nil { refreshInfo() }
    }

    private func clearPicture() {
        pixelSize = .zero
        videoView?.pixelSize = .zero
        videoView?.clearFrame()
    }

    private func toggleInfo(from button: NSButton) {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let label = NSTextField(wrappingLabelWithString: infoText())
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = 320
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 344, height: 180))
        label.frame = host.bounds.insetBy(dx: 12, dy: 12)
        label.autoresizingMask = [.width, .height]
        host.addSubview(label)
        let controller = NSViewController()
        controller.view = host
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = host.frame.size
        popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
        self.infoLabel = label
    }

    private func refreshInfo() {
        infoLabel?.stringValue = infoText()
    }

    private func fitModeTitle() -> String {
        switch fitMode {
        case .native: return localizedText("Native (1:1)")
        case .fit: return localizedText("Fit to Screen")
        }
    }

    private func infoText() -> String {
        var lines = [fitModeTitle()]
        if pixelSize.width > 0, pixelSize.height > 0 {
            lines.append(localizedText("%d × %d", Int(pixelSize.width), Int(pixelSize.height)))
        } else {
            lines.append(localizedText("No picture yet."))
        }
        switch problem {
        case .none:
            break
        case .permission:
            lines.append(localizedText("Allow screen recording in System Settings, then show the monitor again."))
        case .waiting:
            lines.append(localizedText("Waiting for the Thatcaster PGM window."))
        }
        lines.append(localizedText("Press 1 for native pixels. Press F to fit the screen. Drag to pan when the picture is larger than the screen. Press Esc to close."))
        return lines.joined(separator: "\n")
    }
}

private final class PGMPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PGMFramePump {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var scheduled = false
    var onFrame: ((CVPixelBuffer) -> Void)?

    func push(_ buffer: CVPixelBuffer) {
        lock.lock()
        latest = buffer
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        guard needsSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let frame = self.latest
            self.latest = nil
            self.scheduled = false
            self.lock.unlock()
            if let frame {
                MainActor.assumeIsolated { self.onFrame?(frame) }
            }
        }
    }
}

private final class PGMStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    var onBuffer: ((CVPixelBuffer) -> Void)?
    var onStop: (@Sendable () -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer), let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw), status != .complete {
            return
        }
        onBuffer?(buffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?()
    }
}

private final class PGMVideoView: NSView {
    let imageLayer = CALayer()
    let infoButton = NSButton()
    var mode: PGMFitMode = .fit
    var pixelSize: CGSize = .zero
    var pan: CGPoint = .zero
    var onInfo: (() -> Void)?
    private var dragOrigin = CGPoint.zero
    private var dragStart = CGPoint.zero

    override var isOpaque: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        root.masksToBounds = true
        imageLayer.contentsGravity = .resize
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        root.addSublayer(imageLayer)
        return root
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        infoButton.title = "i"
        infoButton.bezelStyle = .circular
        infoButton.font = .systemFont(ofSize: 13, weight: .semibold)
        infoButton.isBordered = true
        infoButton.setAccessibilityLabel(localizedText("Info"))
        infoButton.target = self
        infoButton.action = #selector(showInfo)
        addSubview(infoButton)
    }

    required init?(coder: NSCoder) { nil }

    func show(_ buffer: CVPixelBuffer) {
        guard let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = surface
        CATransaction.commit()
        layoutVideo()
    }

    func clearFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = nil
        CATransaction.commit()
        layoutVideo()
    }

    override func layout() {
        super.layout()
        layoutVideo()
    }

    func layoutVideo() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let rect = pgmImageRect(mode: mode, pixelSize: pixelSize, viewSize: bounds.size, backingScale: scale, pan: pan)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = rect
        imageLayer.contentsScale = scale
        CATransaction.commit()
        let side: CGFloat = 28
        infoButton.frame = CGRect(x: bounds.width - side - 12, y: bounds.height - side - 12, width: side, height: side)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = pan
        dragStart = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .native else { return }
        let point = convert(event.locationInWindow, from: nil)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let native = pgmNativePointSize(pixelSize: pixelSize, backingScale: scale)
        pan = pgmClampedPan(content: native, view: bounds.size,
                            pan: CGPoint(x: dragOrigin.x + point.x - dragStart.x, y: dragOrigin.y + point.y - dragStart.y))
        layoutVideo()
    }

    @objc private func showInfo() { onInfo?() }
}
