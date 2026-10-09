import SwiftUI
import AVFoundation
import CoreMediaIO
import ImageIO
import UniformTypeIdentifiers
import ScreenCaptureKit
import VideoToolbox

@main
struct iPhoneMirrorApp: App {
    @StateObject private var captureManager = CaptureManager()
    @AppStorage("SelectedAnimation") private var selectedAnimation: AnimationType = .cursor
    @AppStorage("AutoCropBlackBars") private var autoCropBlackBars: Bool = true
    
    var body: some Scene {
        WindowGroup {
            ContentView(captureManager: captureManager)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandMenu("Device") {
                Button(action: {
                    captureManager.selectedDeviceID = nil
                }) {
                    Text("Auto Detect")
                    if captureManager.selectedDeviceID == nil {
                        Image(systemName: "checkmark")
                    }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                
                Divider()
                
                // 擷取卡（如 Elgato Cam Link）收到的 iPhone 畫面，四周常帶有黑邊；開啟時自動裁掉。
                Button(action: {
                    autoCropBlackBars.toggle()
                }) {
                    Text("Auto Crop Black Bars")
                    if autoCropBlackBars {
                        Image(systemName: "checkmark")
                    }
                }
                
                Divider()
                
                ForEach(captureManager.availableDevices, id: \.uniqueID) { device in
                    Button(action: {
                        captureManager.selectedDeviceID = device.uniqueID
                    }) {
                        Text(device.localizedName + (device.hasMediaType(.muxed) ? " (Screen)" : " (Camera)"))
                        if captureManager.selectedDeviceID == device.uniqueID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            CommandMenu("Highlight") {
                ForEach(AnimationType.allCases) { type in
                    Button(action: {
                        selectedAnimation = type
                    }) {
                        Text(type.rawValue)
                        if selectedAnimation == type {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            CommandMenu("Record") {
                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleRecording"), object: nil)
                }) {
                    Text("Start / Stop GIF Recording")
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

func enableScreenCaptureDevices() {
    var prop = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(0) // Master/Main element
    )
    var allow: UInt32 = 1
    CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, UInt32(MemoryLayout.size(ofValue: allow)), &allow)
}

enum AnimationType: String, CaseIterable, Identifiable {
    case none = "None (Off)"
    case cursor = "Giant Cursor"
    case hand = "Giant Hand"
    case circle = "Giant Circle"
    
    var id: String { self.rawValue }
}

struct TapData: Identifiable {
    let id = UUID()
    let location: CGPoint
}

struct ClickAnimationView: View {
    let tap: TapData
    let type: AnimationType
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1.0
    
    var body: some View {
        Group {
            switch type {
            case .none:
                EmptyView()
            case .cursor:
                Image(systemName: "cursorarrow")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2)
            case .hand:
                Image(systemName: "hand.point.up.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.yellow)
                    .shadow(color: .black, radius: 2)
            case .circle:
                Circle()
                    .stroke(Color.red, lineWidth: 10)
                    .frame(width: 100, height: 100)
                    .shadow(color: .black, radius: 2)
            }
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .position(tap.location)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                scale = 1.8
                opacity = 0
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var captureManager: CaptureManager
    @StateObject private var gifRecorder = GifRecorder()
    @AppStorage("SelectedAnimation") private var selectedAnimation: AnimationType = .cursor
    @State private var taps: [TapData] = []
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if captureManager.hasDevice {
                PreviewView(session: captureManager.session, geometry: captureManager.geometry)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        ZStack {
                            // 不能用半透明色塊接點擊：在內建 XDR 螢幕上，影片上方疊任何半透明圖層都會讓整個畫面偏灰。
                            Color.clear.contentShape(Rectangle())
                            ForEach(taps) { tap in
                                ClickAnimationView(tap: tap, type: selectedAnimation)
                            }
                            
                            if gifRecorder.isRecording {
                                VStack {
                                    HStack {
                                        Spacer()
                                        Text("\(gifRecorder.timeRemaining)s")
                                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(8)
                                            .padding()
                                    }
                                    Spacer()
                                }
                            }
                        }
                    )
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleRecording"))) { _ in
                        gifRecorder.toggleRecording()
                    }
                    .gesture(
                        selectedAnimation == .none && !gifRecorder.isRecording ? nil :
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let tap = TapData(location: value.location)
                                taps.append(tap)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    taps.removeAll { $0.id == tap.id }
                                }
                            }
                    )
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: 80))
                        .foregroundColor(.gray)
                    Text("Connect your iPhone via USB")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    Text("You can select your camera from the 'Device' menu in the Mac menu bar.\nYou may need to unlock your iPhone and 'Trust' this computer.")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .frame(minWidth: 200, minHeight: 200)
    }
}

class GifRecorder: NSObject, ObservableObject, SCStreamOutput {
    @Published var isRecording = false
    @Published var timeRemaining: Int = 5
    private var images: [CGImage] = []
    private var stream: SCStream?
    private var lastFrameTime: TimeInterval = 0
    private var countdownTimer: Timer?
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        images.removeAll()
        lastFrameTime = 0
        timeRemaining = 5
        
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self = self, let content = content else {
                DispatchQueue.main.async { self?.isRecording = false }
                return
            }
            
            // Find our app's window
            guard let app = content.applications.first(where: { $0.processID == pid_t(ProcessInfo.processInfo.processIdentifier) }),
                  let window = content.windows.first(where: { $0.owningApplication?.processID == app.processID }) else {
                DispatchQueue.main.async { self.isRecording = false }
                return
            }
            
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2) // Retina scale
            config.height = Int(window.frame.height * 2)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
            config.showsCursor = true
            
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            self.stream = stream
            try? stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            stream.startCapture() { error in
                DispatchQueue.main.async {
                    if error == nil {
                        self.isRecording = true
                        self.startCountdown()
                    } else {
                        self.isRecording = false
                    }
                }
            }
        }
    }
    
    private func startCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            }
            if self.timeRemaining <= 0 {
                self.stopRecording()
            }
        }
    }
    
    private func stopRecording() {
        isRecording = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        stream?.stopCapture()
        stream = nil
        
        guard !images.isEmpty else { return }
        
        let path = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("MirrorRecording-\(Int(Date().timeIntervalSince1970)).gif")
        
        guard let dest = CGImageDestinationCreateWithURL(path as CFURL, UTType.gif.identifier as CFString, images.count, nil) else { return }
        
        let frameProp = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 0.1]]
        let gifProp = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        
        CGImageDestinationSetProperties(dest, gifProp as CFDictionary)
        
        for img in images {
            CGImageDestinationAddImage(dest, img, frameProp as CFDictionary)
        }
        
        if CGImageDestinationFinalize(dest) {
            NSWorkspace.shared.activateFileViewerSelecting([path])
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        
        let currentTime = Date().timeIntervalSince1970
        guard currentTime - lastFrameTime >= 0.1 else { return }
        lastFrameTime = currentTime
        
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        
        if let cgImage = cgImage {
            DispatchQueue.main.async {
                self.images.append(cgImage)
            }
        }
    }
}

class CaptureManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var hasDevice = false
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var geometry = VideoGeometry()
    @Published var selectedDeviceID: String? = UserDefaults.standard.string(forKey: "SelectedDeviceID") {
        didSet {
            if selectedDeviceID != oldValue {
                if let id = selectedDeviceID {
                    UserDefaults.standard.set(id, forKey: "SelectedDeviceID")
                } else {
                    UserDefaults.standard.removeObject(forKey: "SelectedDeviceID")
                }
                setupSession()
            }
        }
    }
    
    let session: AVCaptureSession
    private var videoDiscoverySession: AVCaptureDevice.DiscoverySession!
    private var muxedDiscoverySession: AVCaptureDevice.DiscoverySession!
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "com.example.iPhoneMirror.captureQueue", qos: .userInitiated)
    // 以下狀態只在 captureQueue 上存取。
    private var blackBarDetector = BlackBarDetector()
    private var lastDetectTime: CFTimeInterval = 0
    private var detectorResetTime: CFTimeInterval = 0
    private var needsDetectorReset = true
    private var publishedGeometry = VideoGeometry()
    private var lastAutoCrop: Bool?
    
    override init() {
        enableScreenCaptureDevices()
        session = AVCaptureSession()
        super.init()
        
        videoDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera], 
            mediaType: .video,
            position: .unspecified
        )
        
        muxedDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external], 
            mediaType: .muxed,
            position: .unspecified
        )
        
        availableDevices = CaptureManager.getAllDevices(videoSession: videoDiscoverySession, muxedSession: muxedDiscoverySession)
        
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    self.setupSession()
                } else {
                    print("Camera access denied")
                }
            }
        }
        
        // Listen to connection changes
        NotificationCenter.default.addObserver(self, selector: #selector(devicesChanged), name: AVCaptureDevice.wasConnectedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(devicesChanged), name: AVCaptureDevice.wasDisconnectedNotification, object: nil)

    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    static func getAllDevices(videoSession: AVCaptureDevice.DiscoverySession, muxedSession: AVCaptureDevice.DiscoverySession) -> [AVCaptureDevice] {
        var devices = videoSession.devices
        for d in muxedSession.devices {
            if !devices.contains(where: { $0.uniqueID == d.uniqueID }) {
                devices.append(d)
            }
        }
        return devices
    }
    

    
    @objc func devicesChanged(_ notification: Notification) {
        // 重新連接時給 CoreMediaIO 0.5 秒讓裝置完整出現在 discovery session，
        // 否則 setupSession() 會找不到裝置而把畫面變成黑底。
        let delay: TimeInterval = notification.name == AVCaptureDevice.wasConnectedNotification ? 0.5 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.availableDevices = CaptureManager.getAllDevices(videoSession: self.videoDiscoverySession, muxedSession: self.muxedDiscoverySession)
            self.setupSession()
        }
    }
    
    func setupSession() {
        session.beginConfiguration()
        captureQueue.async { self.needsDetectorReset = true }
        
        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }
        
        var selectedDevice: AVCaptureDevice? = nil
        let devices = self.availableDevices
        
        if let id = selectedDeviceID, let device = devices.first(where: { $0.uniqueID == id }) {
            selectedDevice = device
        } else {
            // Auto Select
            if let muxed = devices.first(where: { $0.hasMediaType(.muxed) && ($0.localizedName.contains("iPhone") || $0.localizedName.contains("iPad") || $0.manufacturer.contains("Apple")) }) {
                selectedDevice = muxed
            } else if let iosDevice = devices.first(where: { $0.localizedName.contains("iPhone") || $0.localizedName.contains("iPad") || $0.manufacturer.contains("Apple") }) {
                selectedDevice = iosDevice
            }
            if selectedDevice == nil {
                selectedDevice = devices.first
            }
        }
        
        if let device = selectedDevice, let input = try? AVCaptureDeviceInput(device: device) {
            if session.canAddInput(input) {
                session.addInput(input)
                // Muxed 裝置同時包含 video 與 audio port。
                // 停用 audio port 讓 CoreAudio 不鎖住 iPhone 麥克風，
                // 其他 app 或錄音執行緒才能自由取用。
                for port in input.ports where port.mediaType == .audio {
                    port.isEnabled = false
                }
                hasDevice = true
                print("Added input: \(device.localizedName)")
            } else {
                hasDevice = false
                print("Cannot add input for \(device.localizedName)")
            }
        } else {
            hasDevice = false
            print("No device found")
        }
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.setSampleBufferDelegate(self, queue: captureQueue)
        }

        session.sessionPreset = .high
        session.commitConfiguration()

        // startRunning/stopRunning 都放到背景執行，避免快速 disconnect/reconnect 時
        // 主執行緒的呼叫順序與背景任務交叉導致 session 應啟動卻已被停止。
        if hasDevice {
            if !session.isRunning {
                captureQueue.async { self.session.startRunning() }
            }
        } else {
            if session.isRunning {
                captureQueue.async { self.session.stopRunning() }
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let rawSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let now = CACurrentMediaTime()

        let autoCrop = UserDefaults.standard.object(forKey: "AutoCropBlackBars") as? Bool ?? true
        if needsDetectorReset || rawSize != blackBarDetector.rawSize || autoCrop != lastAutoCrop {
            needsDetectorReset = false
            lastAutoCrop = autoCrop
            blackBarDetector.reset(rawSize: rawSize)
            detectorResetTime = now
            lastDetectTime = 0
            // 先清掉上一個裝置的裁切；預覽層在沒有 geometry 時改用等比顯示，不會套錯比例。
            if publishedGeometry != VideoGeometry() {
                publishedGeometry = VideoGeometry()
                DispatchQueue.main.async { self.geometry = VideoGeometry() }
            }
        }

        var newGeometry = VideoGeometry(raw: rawSize, content: rawSize)
        if autoCrop {
            // 每 0.5 秒掃描一次，避免每幀都讀像素。
            if now - lastDetectTime >= 0.5 {
                lastDetectTime = now
                blackBarDetector.update(with: BlackBarDetector.measure(pixelBuffer))
            }
            // 換裝置後先等偵測穩定（最多 2 秒）再調整視窗，避免視窗先變 16:9 又縮回來。
            if !blackBarDetector.isSettled && now - detectorResetTime < 2 { return }
            newGeometry.content = blackBarDetector.contentSize
        }

        if newGeometry != publishedGeometry {
            publishedGeometry = newGeometry
            DispatchQueue.main.async {
                self.geometry = newGeometry
            }
        }
    }
}

// 原始影像尺寸，以及其中置中、要顯示的內容尺寸（沒有黑邊或關閉裁切時兩者相同）。
struct VideoGeometry: Equatable {
    var raw: CGSize = .zero
    var content: CGSize = .zero
}

// 偵測影像中置中的黑邊。擷取卡固定輸出 16:9，iPhone 會自己在畫面四周補黑邊，黑邊因此是影像的一部分。
// 量測結果以「左右、上下各裁掉多少像素」表示，左右（上下）裁切量相同，所以內容一定置中。
struct BlackBarDetector {
    struct Margins: Equatable {
        var x: Int
        var y: Int
    }
    // 某一個方向量不出可靠結果（例如黑邊不對稱）時為 nil，該方向維持現狀。
    struct Measurement {
        var x: Int?
        var y: Int?
    }

    private(set) var rawSize: CGSize = .zero
    private(set) var margins = Margins(x: 0, y: 0)
    private(set) var isSettled = false
    private var candidate: Margins?
    private var candidateCount = 0

    var contentSize: CGSize {
        CGSize(width: rawSize.width - CGFloat(margins.x * 2), height: rawSize.height - CGFloat(margins.y * 2))
    }

    mutating func reset(rawSize: CGSize) {
        self.rawSize = rawSize
        margins = Margins(x: 0, y: 0)
        isSettled = false
        candidate = nil
        candidateCount = 0
    }

    mutating func update(with measurement: Measurement?) {
        // 全黑畫面、或兩個方向都量不準時，維持現狀。
        guard let m = measurement, m.x != nil || m.y != nil else { return }
        let next = Margins(x: m.x ?? margins.x, y: m.y ?? margins.y)

        // iPhone 畫面一定撐滿其中一個方向的 88% 以上（Cam Link 實測：直向 972/1080=90%，橫向 100%）；
        // 不符合的多半是開機 Logo、直式看橫向照片、暗色介面這類「內容本身邊緣是黑的」，不裁。
        let w = rawSize.width, h = rawSize.height
        let cw = w - CGFloat(next.x * 2), ch = h - CGFloat(next.y * 2)
        guard cw >= w * 0.88 || ch >= h * 0.88 else { return }

        if candidate == next {
            candidateCount += 1
        } else {
            candidate = next
            candidateCount = 1
        }

        if next == margins {
            isSettled = true
            return
        }

        // 內容變大（例如轉成橫向）連續 2 次一致就套用；變小（裁更多）要連續 3 次一致，
        // 而且已經裁過之後，變化太小（不到 2%）的縮小視為暗色內容造成的誤差，不套用。
        let grows = next.x < margins.x || next.y < margins.y
        if grows {
            if candidateCount >= 2 { margins = next; isSettled = true }
        } else if candidateCount >= 3 {
            let dx = next.x - margins.x, dy = next.y - margins.y
            let significant = margins == Margins(x: 0, y: 0)
                || CGFloat(dx) > w * 0.02 || CGFloat(dy) > h * 0.02
            if significant { margins = next }
            isSettled = true
        }
    }

    // 只支援 32BGRA；整張都是黑色時回傳 nil。
    static func measure(_ pixelBuffer: CVPixelBuffer) -> Measurement? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        guard width >= 16, height >= 16 else { return nil }

        // 擷取卡的黑色常帶雜訊，最亮通道超過門檻才算內容。
        let threshold: UInt8 = 40
        func isContent(_ x: Int, _ y: Int) -> Bool {
            let p = ptr + y * bytesPerRow + x * 4
            return max(p[0], p[1], p[2]) > threshold
        }

        let samples = 64
        let sampleRows = (0..<samples).map { ($0 * 2 + 1) * height / (samples * 2) }
        let sampleCols = (0..<samples).map { ($0 * 2 + 1) * width / (samples * 2) }
        func columnHasContent(_ x: Int) -> Bool { sampleRows.contains { isContent(x, $0) } }
        func rowHasContent(_ y: Int) -> Bool { sampleCols.contains { isContent($0, y) } }

        guard let left = (0..<width).first(where: columnHasContent),
              let right = (0..<width).reversed().first(where: columnHasContent),
              let top = (0..<height).first(where: rowHasContent),
              let bottom = (0..<height).reversed().first(where: rowHasContent) else { return nil }

        // 擷取卡的黑邊一定對稱；不對稱多半是內容本身偏暗，該方向回傳 nil。
        func margin(_ a: Int, _ b: Int, _ length: Int) -> Int? {
            let m = min(a, b)
            guard abs(a - b) <= max(4, length / 100) else { return nil }
            return m >= length / 50 ? m : 0
        }
        return Measurement(x: margin(left, width - 1 - right, width),
                           y: margin(top, height - 1 - bottom, height))
    }
}

// 預覽層放在可裁切的容器裡：容器 masksToBounds，預覽層放大到「內容」剛好等比塞進容器並置中，
// 黑邊就落在容器外。視窗比例和內容不同時（例如全螢幕）只會補黑邊，不會裁到內容。
// 預覽層的 frame 在 layoutSublayers 隨容器 bounds 更新，避免 frame 為 zero 導致黑畫面。
class CroppingPreviewLayer: CALayer {
    private(set) var preview = AVCaptureVideoPreviewLayer()
    var geometry = VideoGeometry() {
        didSet { if geometry != oldValue { setNeedsLayout() } }
    }

    override init() {
        super.init()
        masksToBounds = true
        backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resize
        preview.backgroundColor = NSColor.black.cgColor
        addSublayer(preview)
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? CroppingPreviewLayer {
            preview = other.preview
            geometry = other.geometry
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        let raw = geometry.raw, content = geometry.content
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if raw.width > 0, raw.height > 0, content.width > 0, content.height > 0 {
            let k = min(bounds.width / content.width, bounds.height / content.height)
            let w = raw.width * k, h = raw.height * k
            preview.videoGravity = .resize
            preview.frame = CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        } else {
            // 還不知道影像尺寸時，整張等比顯示。
            preview.videoGravity = .resizeAspect
            preview.frame = bounds
        }
        CATransaction.commit()
    }
}

class PreviewNSView: NSView {
    var videoSize: CGSize = .zero {
        didSet {
            guard videoSize.width > 0 && videoSize.height > 0, oldValue != videoSize else { return }
            adjustWindowAspect()
        }
    }

    var previewLayer: AVCaptureVideoPreviewLayer? { (layer as? CroppingPreviewLayer)?.preview }

    // 自訂 backing layer 由 layoutSublayers 排版預覽層，避免 sublayer frame 在
    // layout() 前為 zero 導致黑畫面（在 macOS 26 上更容易觸發）。
    override func makeBackingLayer() -> CALayer {
        CroppingPreviewLayer()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    private var fullScreenObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.window?.isMovableByWindowBackground = true
        if let observer = fullScreenObserver {
            NotificationCenter.default.removeObserver(observer)
            fullScreenObserver = nil
        }
        if let window = self.window {
            // 全螢幕時不調整視窗；離開全螢幕後再依目前畫面方向調整一次。
            fullScreenObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.adjustWindowAspect()
            }
        }
        adjustWindowAspect()
    }

    deinit {
        if let observer = fullScreenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // 依畫面比例調整視窗：
    // - 方向沒變（只是比例微調）時維持高度，跟以前一樣。
    // - 手機轉向（直式↔橫式）時保留視窗的長邊，效果就像把視窗跟著手機一起轉。
    // - 新尺寸一律縮到所在螢幕的可用範圍內，並以原本的中心為準，超出螢幕時往內推。
    private func adjustWindowAspect() {
        guard let window = self.window, videoSize.width > 0 && videoSize.height > 0 else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        window.contentAspectRatio = videoSize

        let current = window.frame
        let ratio = videoSize.width / videoSize.height
        let wasLandscape = current.width >= current.height
        let isLandscape = ratio >= 1

        var size: CGSize
        if wasLandscape != isLandscape {
            let longSide = max(current.width, current.height)
            size = isLandscape
                ? CGSize(width: longSide, height: longSide / ratio)
                : CGSize(width: longSide * ratio, height: longSide)
        } else {
            size = CGSize(width: current.height * ratio, height: current.height)
        }

        // 不小於 ContentView 的最小尺寸（200×200）。
        let minScale = max(1, 200 / size.width, 200 / size.height)
        size = CGSize(width: size.width * minScale, height: size.height * minScale)

        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let scale = min(1, visible.width / size.width, visible.height / size.height)
            size = CGSize(width: size.width * scale, height: size.height * scale)

            // 尺寸沒變就不動視窗，保留使用者刻意擺在螢幕邊緣的位置。
            guard abs(size.width - current.width) > 1 || abs(size.height - current.height) > 1 else { return }
            var frame = CGRect(x: current.midX - size.width / 2, y: current.midY - size.height / 2,
                               width: size.width, height: size.height)
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            window.setFrame(frame, display: true, animate: true)
        } else if abs(size.width - current.width) > 1 || abs(size.height - current.height) > 1 {
            let frame = CGRect(x: current.midX - size.width / 2, y: current.origin.y, width: size.width, height: size.height)
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

struct PreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let geometry: VideoGeometry

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer?.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        if nsView.previewLayer?.session !== session {
            nsView.previewLayer?.session = session
        }
        (nsView.layer as? CroppingPreviewLayer)?.geometry = geometry
        nsView.videoSize = geometry.content
    }
}
