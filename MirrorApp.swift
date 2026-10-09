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
                
                Button(action: {
                    captureManager.playDeviceAudio.toggle()
                }) {
                    Text("Play Device Audio")
                    if captureManager.playDeviceAudio {
                        Image(systemName: "checkmark")
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                
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
    @State private var showAudioHint = false
    @State private var audioHintToken = UUID()
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if captureManager.hasDevice {
                PreviewView(session: captureManager.session, geometry: captureManager.geometry) { location in
                    guard selectedAnimation != .none || gifRecorder.isRecording else { return }
                    let tap = TapData(location: location)
                    taps.append(tap)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        taps.removeAll { $0.id == tap.id }
                    }
                }
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        // 滑鼠操作（拖曳、點擊、滾輪、右鍵）都由 PreviewNSView 處理，這層只負責畫特效，不接收點擊。
                        // 注意：不要在影片上方疊半透明色塊，在內建 XDR 螢幕上會讓整個畫面偏灰。
                        ZStack {
                            Color.clear
                            ForEach(taps) { tap in
                                ClickAnimationView(tap: tap, type: selectedAnimation)
                            }
                            
                            // 只在剛偵測到壞訊號時顯示幾秒；用不透明底色，避免影片在內建 XDR 螢幕上偏灰。
                            if showAudioHint {
                                VStack {
                                    Spacer()
                                    Text("手機聲音沒有從 HDMI 送出。請在手機的控制中心把聲音輸出切回 HDMI；若仍無效，請重新插拔 Cam Link 與 HDMI 轉接器。")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.leading)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Color(white: 0.12))
                                        .cornerRadius(8)
                                        .padding(12)
                                }
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
                        .allowsHitTesting(false)
                    )
                    .onReceive(captureManager.$audioSignalBroken.removeDuplicates()) { broken in
                        showAudioHint = broken
                        guard broken else { return }
                        let token = UUID()
                        audioHintToken = token
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                            if audioHintToken == token { showAudioHint = false }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleRecording"))) { _ in
                        gifRecorder.toggleRecording()
                    }
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

class CaptureManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    @Published var hasDevice = false
    // 收到的手機聲音是壞訊號（見 AudioSignalMonitor）時為 true，期間自動靜音並在畫面上提示。
    @Published var audioSignalBroken = false
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var geometry = VideoGeometry()
    // 把手機的聲音（Cam Link 的 HDMI 音訊，或 USB 連接 iPhone 的音訊）從 Mac 播出。預設關閉：
    // 避免和 OBS 等同時收音的軟體重複播放，也避免佔住 iPhone 麥克風。
    @Published var playDeviceAudio: Bool = UserDefaults.standard.bool(forKey: "PlayDeviceAudio") {
        didSet {
            guard playDeviceAudio != oldValue else { return }
            UserDefaults.standard.set(playDeviceAudio, forKey: "PlayDeviceAudio")
            setupSession()
        }
    }
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
    private let audioPreviewOutput = AVCaptureAudioPreviewOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let audioQueue = DispatchQueue(label: "com.example.iPhoneMirror.audioQueue", qos: .userInitiated)
    private var audioMonitor = AudioSignalMonitor() // 只在 audioQueue 上存取
    // 每次 setupSession 加 1（main 上存取）；音訊判斷帶著當時的版本，過期的結果直接丟掉，避免重新設定後卡在靜音。
    private var sessionGeneration = 0
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
    
    static func matchingAudioDevice(for videoDevice: AVCaptureDevice) -> AVCaptureDevice? {
        let audioDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
        // 只配對名稱完全相同的裝置（擷取卡的影像與聲音同名）。不用型號比對，
        // 以免把接續互通相機或網路攝影機的麥克風當成手機聲音播出，造成回授。
        return audioDevices.first { $0.localizedName == videoDevice.localizedName }
    }

    func setupSession() {
        // 第一次開啟「播放裝置聲音」時先要麥克風權限，拿到結果後再重新設定。
        if playDeviceAudio && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.setupSession() }
            }
            return
        }
        sessionGeneration += 1
        audioSignalBroken = false
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
                // 沒開「播放裝置聲音」時停用 audio port，讓 CoreAudio 不鎖住 iPhone 麥克風，
                // 其他 app 或錄音執行緒才能自由取用。
                // 沒有麥克風權限時不開聲音，避免 session 因權限錯誤停止、連畫面一起中斷。
                let audioOK = playDeviceAudio && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                var hasAudio = false
                for port in input.ports where port.mediaType == .audio {
                    port.isEnabled = audioOK
                    hasAudio = hasAudio || audioOK
                }
                // 擷取卡（如 Cam Link）的聲音是另一個同名的音訊裝置。
                if audioOK, !hasAudio, let audioDevice = CaptureManager.matchingAudioDevice(for: device),
                   let audioInput = try? AVCaptureDeviceInput(device: audioDevice), session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    hasAudio = true
                }
                if hasAudio, session.canAddOutput(audioPreviewOutput) {
                    audioPreviewOutput.volume = 1
                    session.addOutput(audioPreviewOutput)
                    // 另外接一路音訊資料做訊號分析，壞訊號時把播放音量降到 0。
                    if session.canAddOutput(audioDataOutput) {
                        audioDataOutput.audioSettings = [
                            AVFormatIDKey: kAudioFormatLinearPCM,
                            AVLinearPCMBitDepthKey: 32,
                            AVLinearPCMIsFloatKey: true,
                            AVLinearPCMIsNonInterleaved: false,
                        ]
                        audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)
                        session.addOutput(audioDataOutput)
                    }
                }
                let generation = sessionGeneration
                audioQueue.async { self.audioMonitor = AudioSignalMonitor(generation: generation) }
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
        if output === audioDataOutput {
            handleAudio(sampleBuffer)
            return
        }
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

extension CaptureManager {
    // 在 audioQueue 上呼叫。
    func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        var blockBuffer: CMBlockBuffer?
        var list = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let data = list.mBuffers.mData else { return }
        let channels = max(1, Int(list.mBuffers.mNumberChannels))
        let frames = Int(list.mBuffers.mDataByteSize) / (4 * channels)
        let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: frames * channels)

        guard let broken = audioMonitor.process(samples, channels: channels),
              broken != audioMonitor.reportedBroken else { return }
        audioMonitor.reportedBroken = broken
        let generation = audioMonitor.generation
        DispatchQueue.main.async {
            guard generation == self.sessionGeneration else { return }
            self.audioPreviewOutput.volume = broken ? 0 : 1
            self.audioSignalBroken = broken
        }
    }
}

// 判斷擷取卡送來的手機聲音是不是壞訊號。實測的壞訊號都是「大部分取樣剛好是 0，中間夾著被切斷的聲音片段」：
//   - iPhone 用過語音互動（例如 Google Maps 的 Gemini）後改從手機喇叭出聲，HDMI 只剩零星、接近滿音量的單一取樣尖峰。
//   - Cam Link 音訊卡住時，每約 60 毫秒只送出一小段被切斷的聲音。
// 關鍵特徵是起音：真正的音效（包括很小聲的鍵盤按鍵聲）從接近 0 慢慢變大；被切斷的片段在靜音後一開始就接近最大值。
// 以「起音 ÷ 該片段最大值」判斷，不受音量影響（實測中位數：按鍵聲 0.004、Cam Link 卡住 0.28、尖峰 1）。
// 按鍵聲偶爾也會突然起音，所以單一片段不下結論：要嘛是密集的被切斷片段，要嘛是 8 個取樣以內的極短尖峰。
// 整段都是 0 的真正靜音維持現狀。
struct AudioSignalMonitor {
    private var frames = 0
    private var zeros = 0
    private var abruptBursts = 0
    private var spikes = 0
    private var smoothBursts = 0
    private var sawLongSound = false
    private var zeroRun = 0
    private var soundRun = 0
    // 目前這段聲音（中間短於 1 毫秒的 0 視為同一段）。
    private var inBurst = false
    private var burstAfterSilence = false
    private var burstFirst: Float = 0
    private var burstPeak: Float = 0
    private var burstLength = 0
    var reportedBroken = false
    var generation = 0

    init(generation: Int = 0) {
        self.generation = generation
    }

    private static let windowFrames = 24_000   // 48kHz 下 0.5 秒
    private static let silenceRun = 480        // 10 毫秒以上的 0 算「靜音段」
    private static let burstGap = 48           // 1 毫秒以上的 0 才算一段聲音結束
    private static let longSound = 960         // 連續 20 毫秒以上不為 0 算「持續的聲音」
    private static let abruptRatio: Float = 0.2
    private static let maxSpikeLength = 8      // 8 個取樣以內的突然尖峰（Gemini 之後的雜訊是單一取樣）
    private static let minPeak: Float = 0.002  // 約 -54 dBFS，更小的雜點不列入判斷

    // 每累積 0.5 秒判斷一次：true 壞訊號、false 正常；整段靜音時回傳 nil（維持現狀）。
    // 只看第一個聲道。
    mutating func process(_ samples: UnsafeBufferPointer<Float>, channels: Int) -> Bool? {
        var result: Bool?
        var i = 0
        while i < samples.count {
            let x = samples[i]
            frames += 1
            if x == 0 {
                zeros += 1
                soundRun = 0
                zeroRun += 1
                if inBurst && zeroRun >= AudioSignalMonitor.burstGap { endBurst() }
            } else {
                if !inBurst {
                    inBurst = true
                    burstAfterSilence = zeroRun >= AudioSignalMonitor.silenceRun
                    burstFirst = abs(x)
                    burstPeak = 0
                    burstLength = 0
                }
                burstPeak = max(burstPeak, abs(x))
                burstLength += 1
                soundRun += 1
                if soundRun >= AudioSignalMonitor.longSound { sawLongSound = true }
                zeroRun = 0
            }
            if frames >= AudioSignalMonitor.windowFrames {
                let zeroFraction = Double(zeros) / Double(frames)
                if abruptBursts >= 3 && zeroFraction > 0.6 {
                    // 被切斷的片段很密集（Cam Link 卡住），即使夾著較長的片段也算壞訊號。
                    result = true
                } else if spikes > 0 && !sawLongSound && zeroFraction > 0.8 {
                    // 零星的極短尖峰（Gemini 之後）。偶爾也有按鍵聲是突然起音，但它們長得多，不算尖峰。
                    result = true
                } else if abruptBursts == 0 && (sawLongSound || smoothBursts > 0) {
                    // 持續的聲音，或平順起音的短音效（例如按鍵聲）。有任何突然起音的片段時不下結論。
                    result = false
                }
                frames = 0; zeros = 0; abruptBursts = 0; spikes = 0; smoothBursts = 0; sawLongSound = false
            }
            i += channels
        }
        return result
    }

    private mutating func endBurst() {
        inBurst = false
        guard burstAfterSilence, burstPeak >= AudioSignalMonitor.minPeak else { return }
        if burstFirst / burstPeak > AudioSignalMonitor.abruptRatio {
            abruptBursts += 1
            if burstLength <= AudioSignalMonitor.maxSpikeLength { spikes += 1 }
        } else {
            smoothBursts += 1
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

    // 擷取卡縮放後，黑邊與內容之間有 1～2 像素的暗色漸層，上下（左右）黑邊也可能差 1 像素；
    // 有黑邊的方向每邊多裁 3 像素，避免邊緣留下細黑線。
    static let edgeInset = 3

    var contentSize: CGSize {
        let ix = margins.x > 0 ? BlackBarDetector.edgeInset : 0
        let iy = margins.y > 0 ? BlackBarDetector.edgeInset : 0
        return CGSize(width: rawSize.width - CGFloat((margins.x + ix) * 2),
                      height: rawSize.height - CGFloat((margins.y + iy) * 2))
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

// 預覽層放在可裁切的容器裡：容器 masksToBounds，預覽層放大到「內容」對齊容器並置中，黑邊就落在容器外。
// 視窗比例與內容相差 3% 以內時填滿容器（最多裁掉約 1.5% 的邊緣）；相差更多時（例如全螢幕）等比塞入，只補黑邊。
// 預覽層的 frame 在 layoutSublayers 隨容器 bounds 更新，避免 frame 為 zero 導致黑畫面。
class CroppingPreviewLayer: CALayer {
    private(set) var preview = AVCaptureVideoPreviewLayer()
    var geometry = VideoGeometry() {
        didSet {
            guard geometry != oldValue else { return }
            // 手機轉向時取消放大，避免停在奇怪的位置；黑邊偵測的小幅調整則保留放大。
            let wasLandscape = oldValue.content.width >= oldValue.content.height
            let isLandscape = geometry.content.width >= geometry.content.height
            if wasLandscape != isLandscape { zoom = 1; zoomOffset = .zero }
            setNeedsLayout()
        }
    }

    override init() {
        super.init()
        masksToBounds = true
        backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resize
        preview.backgroundColor = NSColor.black.cgColor
        addSublayer(preview)
    }

    // 放大：畫面座標 p 顯示在 p * zoom + zoomOffset（以容器左下角為原點）。
    private(set) var zoom: CGFloat = 1
    private(set) var zoomOffset: CGPoint = .zero
    static let maxZoom: CGFloat = 4

    // 聚光燈：游標周圍保持原樣，其他地方變暗。關閉時整層移除，避免在 XDR 螢幕上讓畫面偏灰。
    private let spotlight = CAShapeLayer()
    var spotlightCenter: CGPoint? {
        didSet { updateSpotlight() }
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? CroppingPreviewLayer {
            preview = other.preview
            geometry = other.geometry
            zoom = other.zoom
            zoomOffset = other.zoomOffset
        }
    }

    // 以 anchor（容器座標）為中心縮放到 newZoom，並限制在畫面範圍內。
    func setZoom(_ newZoom: CGFloat, anchor: CGPoint, animated: Bool = false) {
        let z = min(max(newZoom, 1), CroppingPreviewLayer.maxZoom)
        let q = CGPoint(x: (anchor.x - zoomOffset.x) / zoom, y: (anchor.y - zoomOffset.y) / zoom)
        zoom = z
        zoomOffset = clampedOffset(CGPoint(x: anchor.x - q.x * z, y: anchor.y - q.y * z))
        layoutPreview(animated: animated)
    }

    func pan(by delta: CGPoint) {
        guard zoom > 1 else { return }
        zoomOffset = clampedOffset(CGPoint(x: zoomOffset.x + delta.x, y: zoomOffset.y + delta.y))
        layoutPreview(animated: false)
    }

    private func clampedOffset(_ o: CGPoint) -> CGPoint {
        CGPoint(x: min(0, max(bounds.width * (1 - zoom), o.x)),
                y: min(0, max(bounds.height * (1 - zoom), o.y)))
    }

    private func updateSpotlight() {
        guard let center = spotlightCenter else {
            spotlight.removeFromSuperlayer()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if spotlight.superlayer == nil {
            spotlight.fillRule = .evenOdd
            spotlight.fillColor = NSColor.black.withAlphaComponent(0.65).cgColor
            addSublayer(spotlight)
        }
        spotlight.frame = bounds
        let radius = max(60, min(bounds.width, bounds.height) * 0.22)
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        spotlight.path = path
        CATransaction.commit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        zoomOffset = clampedOffset(zoomOffset)
        layoutPreview(animated: false)
        updateSpotlight()
    }

    private func layoutPreview(animated: Bool) {
        let raw = geometry.raw, content = geometry.content
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.2)
        if raw.width > 0, raw.height > 0, content.width > 0, content.height > 0 {
            // 視窗比例與內容只差一點點（視窗尺寸取整數造成）時用填滿，避免邊緣露出細黑線；
            // 差很多（例如全螢幕）時用等比塞入，不裁到內容。
            let fit = min(bounds.width / content.width, bounds.height / content.height)
            let fill = max(bounds.width / content.width, bounds.height / content.height)
            let k = fill / fit <= 1.03 ? fill : fit
            let w = raw.width * k, h = raw.height * k
            let base = CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
            preview.videoGravity = .resize
            preview.frame = CGRect(x: base.minX * zoom + zoomOffset.x, y: base.minY * zoom + zoomOffset.y,
                                   width: base.width * zoom, height: base.height * zoom)
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
    private var container: CroppingPreviewLayer? { layer as? CroppingPreviewLayer }

    // 單純點擊（沒有拖曳）時回呼，座標以左上角為原點（SwiftUI 座標）。
    var onTap: ((CGPoint) -> Void)?

    private var eventMonitor: Any?
    private var mouseDownEvent: NSEvent?
    private var mouseDownPoint: CGPoint?
    private var isPanning = false
    private var isMiddlePanning = false

    // 視窗拖曳由我們自己用 performDrag 處理，避免放大後平移時視窗也跟著動。
    override var mouseDownCanMoveWindow: Bool { false }

    // 滑鼠操作：
    // - 左鍵按住拖曳：沒放大時移動整個視窗（類似 QuickTime）；放大時平移畫面。單純點擊顯示點擊特效。
    // - 滾輪／觸控板捏合：以游標為中心放大（1～4 倍）。
    // - 滾輪鍵按住拖曳：平移放大後的畫面（縮放只用滾輪調整）。
    // - 右鍵：開關聚光燈。
    // 用 local event monitor 統一處理，不受上方 SwiftUI 疊層攔截影響。
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window = window, event.window === window, let container = container else { return event }
        let point = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(point)

        switch event.type {
        case .leftMouseDown:
            guard inside, !isOverWindowButton(event) else { return event }
            mouseDownEvent = event
            mouseDownPoint = point
            isPanning = false
            return event
        case .leftMouseDragged:
            guard let start = mouseDownPoint, let downEvent = mouseDownEvent else { return event }
            if container.zoom > 1 {
                if isPanning || hypot(point.x - start.x, point.y - start.y) > 3 { isPanning = true }
                container.pan(by: CGPoint(x: event.deltaX, y: -event.deltaY))
            } else if !isPanning, hypot(point.x - start.x, point.y - start.y) > 3 {
                mouseDownPoint = nil
                mouseDownEvent = nil
                window.performDrag(with: downEvent)
            }
            if container.spotlightCenter != nil { container.spotlightCenter = point }
            return event
        case .leftMouseUp:
            defer { mouseDownPoint = nil; mouseDownEvent = nil; isPanning = false }
            if let start = mouseDownPoint, !isPanning, hypot(point.x - start.x, point.y - start.y) <= 3 {
                onTap?(CGPoint(x: point.x, y: bounds.height - point.y))
            }
            return event
        case .scrollWheel:
            guard inside, event.scrollingDeltaY != 0 else { return event }
            let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
            container.setZoom(container.zoom * exp(step), anchor: point)
            return nil
        case .magnify:
            guard inside else { return event }
            container.setZoom(container.zoom * (1 + event.magnification), anchor: point)
            return nil
        case .otherMouseDown:
            guard inside, event.buttonNumber == 2 else { return event }
            isMiddlePanning = true
            return nil
        case .otherMouseDragged:
            guard event.buttonNumber == 2, isMiddlePanning else { return event }
            container.pan(by: CGPoint(x: event.deltaX, y: -event.deltaY))
            if container.spotlightCenter != nil { container.spotlightCenter = point }
            return nil
        case .otherMouseUp:
            guard event.buttonNumber == 2, isMiddlePanning else { return event }
            isMiddlePanning = false
            return nil
        case .rightMouseDown:
            guard inside else { return event }
            container.spotlightCenter = container.spotlightCenter == nil ? point : nil
            return nil
        case .mouseMoved:
            if container.spotlightCenter != nil, inside { container.spotlightCenter = point }
            return event
        default:
            return event
        }
    }

    private func isOverWindowButton(_ event: NSEvent) -> Bool {
        guard let window = window else { return false }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(type), !button.isHidden,
               button.convert(button.bounds, to: nil).insetBy(dx: -4, dy: -4).contains(event.locationInWindow) {
                return true
            }
        }
        return false
    }

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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        // 預覽畫面移除（例如拔掉裝置）後，恢復從背景拖曳視窗。
        if newWindow == nil { window?.isMovableByWindowBackground = true }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.window?.isMovableByWindowBackground = false
        self.window?.acceptsMouseMovedEvents = true
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if window != nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .magnify,
                           .otherMouseDown, .otherMouseDragged, .otherMouseUp, .rightMouseDown, .mouseMoved]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }
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
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // 依畫面比例調整視窗：
    // - 方向沒變（只是比例微調）時維持高度，跟以前一樣。
    // - 手機轉向（直式↔橫式）時自動放大到所在螢幕可用範圍的 95%，並移到螢幕正中央。
    // - 新尺寸一律縮到所在螢幕的可用範圍內，並以原本的中心為準，超出螢幕時往內推。
    private func adjustWindowAspect() {
        guard let window = self.window, videoSize.width > 0 && videoSize.height > 0 else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }
        window.contentAspectRatio = videoSize

        let current = window.frame
        let ratio = videoSize.width / videoSize.height
        let wasLandscape = current.width >= current.height
        let isLandscape = ratio >= 1

        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
        let rotated = wasLandscape != isLandscape
        var size: CGSize
        if rotated, let visible = visibleFrame {
            let k = min(visible.width * 0.95 / ratio, visible.height * 0.95)
            size = CGSize(width: k * ratio, height: k)
        } else {
            size = CGSize(width: current.height * ratio, height: current.height)
        }

        // 不小於 ContentView 的最小尺寸（200×200）。
        let minScale = max(1, 200 / size.width, 200 / size.height)
        size = CGSize(width: size.width * minScale, height: size.height * minScale)

        if let visible = visibleFrame {
            let scale = min(1, visible.width / size.width, visible.height / size.height)
            size = CGSize(width: size.width * scale, height: size.height * scale)

            // 尺寸沒變就不動視窗，保留使用者刻意擺在螢幕邊緣的位置。
            guard abs(size.width - current.width) > 1 || abs(size.height - current.height) > 1 else { return }
            let center = rotated ? CGPoint(x: visible.midX, y: visible.midY) : CGPoint(x: current.midX, y: current.midY)
            var frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
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
    let onTap: (CGPoint) -> Void

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer?.session = session
        view.onTap = onTap
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        if nsView.previewLayer?.session !== session {
            nsView.previewLayer?.session = session
        }
        (nsView.layer as? CroppingPreviewLayer)?.geometry = geometry
        nsView.onTap = onTap
        nsView.videoSize = geometry.content
    }
}
