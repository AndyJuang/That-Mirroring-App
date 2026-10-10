# That Mirroring App 📱🖥️

[English](#english) | [繁體中文](#繁體中文)

---

## English

A native, lightweight macOS application built with Swift and SwiftUI that allows you to mirror your iPhone, iPad, or Android screen directly to your Mac via USB at near-zero latency. Perfect for presentations and live streaming. That Mirroring only displays live screens; it does not record.

### ✨ Features

- **USB Plug & Play**: Simply connect your iPhone/iPad to your Mac via USB to start mirroring.
- **Dynamic Aspect Ratio & Auto-Resizing**: 
  - The window automatically adapts to the exact aspect ratio of your device's screen.
  - No letterboxing (black bars).
  - Instantly responds to device rotation (portrait to landscape).
- **Presentation Highlights**:
  - Show visual effects when you click your mouse to highlight actions on the screen during a presentation or tutorial.
  - Choose between: **Giant Cursor**, **Giant Hand**, **Giant Circle**, or **None (Off)**.
- **Menu Bar Integration**: Easily switch between your iPhone, iPad, or any other camera directly from the macOS Menu Bar.
- **Borderless Draggable Window**: Drag the app window seamlessly from anywhere on its background without a clunky title bar.
- **Capture Card Support (e.g. Elgato Cam Link)**: Black bars around the iPhone picture are detected and cropped automatically (Device → Auto Crop Black Bars). When the phone rotates, the window enlarges to fit the screen and re-centers.
- **Presentation Zoom & Spotlight**: Scroll (or pinch) to zoom in around the cursor, up to 4×. Hold the middle mouse button and drag to move around while zoomed. Right-click toggles a spotlight that follows the cursor.
- **Device Audio**: Device → Play Device Audio (⇧⌘S) plays the phone's sound through your Mac (HDMI audio from a capture card, or USB audio from the iPhone). Off by default.

### 🚀 How to Use

1. **Download the app** from the [Releases page](https://github.com/AndyJuang/That-Mirroring-App/releases) or build it yourself.
2. **Connect** your iPhone or iPad to your Mac using a Lightning or USB-C cable.
3. **Launch** `ThatMirroring.app`.
4. If this is your first time, you may need to unlock your iOS device and tap **"Trust This Computer"**.
5. The app will automatically detect your device and display its screen.
6. If you have multiple devices connected (or want to select a camera), navigate to the top macOS Menu Bar and click on **Device** to select your input.

**Using Highlights**
To toggle the click highlight effect:
- Go to the top macOS Menu Bar -> **Highlight** -> Select your preferred animation style or turn it off.

### 🛠️ Build from Source

This app compiles Swift source files directly without an Xcode project.

**Requirements:**
- macOS 14.0+
- Swift Compiler (`swiftc`) installed (usually via Xcode Command Line Tools)

**Compilation Command (arm64, macOS 14+):**

```bash
scripts/build.sh
scripts/test.sh
```

The script compiles with `swiftc -O`, regenerates the icon, and ad-hoc signs
`build/ThatMirroring.app`. No Xcode project or developer signing certificate is needed. The first build downloads the pinned official scrcpy 4.0 arm64 archive into ignored `vendor/`, checks SHA-256, and packages its self-contained scrcpy/server/adb with complete license notices. Subsequent builds use the verified cache.

### 💡 How it Works (Under the Hood)
- By default, macOS does not treat USB-connected iOS devices as standard webcams.
- This app uses the low-level `CoreMediaIO` API to enable `kCMIOHardwarePropertyAllowScreenCaptureDevices`.
- Once enabled, the generic `AVCaptureDevice` system can natively read the uncompressed video stream from your iPhone's screen.

---

## 繁體中文

這是一款使用原生 Swift 與 SwiftUI 打造的輕量級 macOS 應用程式，它能讓你透過 USB 線以「接近零延遲」的速度，將 iPhone 或 iPad 的螢幕直接投射到你的 Mac 畫面上。適合用於教學簡報及直播實況。That Mirroring 只顯示即時畫面，不提供錄製功能。

### ✨ 核心功能

- **隨插即用**: 只需要將 iOS 設備接上 Mac 的 USB，開啟 App 就能自動連接。
- **動態比例自動縮放**: 
  - 視窗會自動死死扣住你的手機螢幕比例，永遠不會出現黑邊（Letterboxing）。
  - 對手機畫面的直向或橫向旋轉，能做到瞬間無縫變形。
- **點擊特效與輔助指示**:
  - 專為教學與簡報設計，用滑鼠點擊 App 中展示的手機畫面時會跳出特殊動畫，讓觀眾知道你點哪裡！
  - 可從選單列選擇：**巨型游標**、**點擊的巨手**、**巨大紅圈** 或是 **關閉 (None)**。
- **選單列無縫切換裝置**: 如果有其他攝影機或多台 iOS 設備，你可以直接從 Mac 的系統頂部工具列（Menu Bar）隨時自由切換輸入來源。
- **無邊框全區拖曳**: 我們拔掉了笨重的應用程式標題列。想要移動畫面，點擊畫面上任何一處（或是三指）都能輕鬆把整個視窗拖著走。
- **支援擷取卡（例如 Elgato Cam Link）**：自動偵測並裁掉 iPhone 畫面四周的黑邊（Device → Auto Crop Black Bars）。手機轉向時，視窗會放大到適合螢幕的大小並移到正中央。
- **簡報放大與聚光燈**：滾動滑鼠滾輪（或觸控板捏合）以游標為中心放大，最多 4 倍。放大後按住滾輪鍵拖曳可以移動畫面。按右鍵開關跟著游標移動的聚光燈。
- **播放手機聲音**：Device → Play Device Audio（⇧⌘S）把手機的聲音從 Mac 播出（擷取卡的 HDMI 聲音，或 iPhone 的 USB 聲音）。預設關閉。

### 🚀 如何使用

1. 到本專案的 [Releases 頁面](https://github.com/AndyJuang/That-Mirroring-App/releases) 下載最新的 `.dmg` 檔案，或是從原始碼自己編譯。
2. 使用傳輸線將 iPhone / iPad **連上 Mac**。
3. **開啟** `ThatMirroring.app`。
4. 第一次使用時，請解鎖手機畫面並點選 **「信任這部電腦」**。
5. App 打開後，就會自動抓取你的手機實時螢幕。
6. 前往 Mac 螢幕頂部的「Menu Bar」，你可以：
   - 到 **Device** 欄位切換你要觀看的設備。
   - 到 **Highlight** 指定你要點擊的滑鼠動畫效果！

### 🛠️ 如何從原始碼編譯打包

本專案以 SwiftUI 與少量可測試的純邏輯檔案組成，不需要 Xcode 專案。
需要 macOS 14.0 以上、arm64 Mac、Xcode 指令列工具：

```bash
scripts/build.sh
scripts/test.sh
```

輸出：`build/ThatMirroring.app`。每次建置重新產生圖示、以 `swiftc -O` 編譯，
並對內含 Mach-O 與 App 做 ad-hoc 簽章及嚴格驗證。

最終 icon：把 1024×1024 PNG 覆蓋 `icon/AppIcon-1024.png`，跑 `scripts/build.sh`。
如有手工製作的 `icon/AppIcon.iconset/`，則優先使用該目錄各尺寸圖檔。
`sips` 產生各尺寸，再用 `iconutil` 編碼；若系統編碼器不可用，會使用已驗證尺寸的
PNG-backed ICNS 封裝備援。目前使用強尼提供的紅色星星版手繪 iconset；更換最終圖時覆蓋
`icon/AppIcon-1024.png`，若有手工尺寸圖則同步更新 `icon/AppIcon.iconset/`。

### 💡 原理解析
基於蘋果對於隱私的限制，macOS 內建並不把透過 USB 連接的手機視為普通的網路攝影機（Webcam）。
這支 App 在背後利用了極底層的 `CoreMediaIO` API 強制啟用 `kCMIOHardwarePropertyAllowScreenCaptureDevices` 硬體標記參數。將隱藏在底層的 USB 螢幕視窗釋放後，我們才得以用非常標準的 `AVCaptureDevice` 把 iOS 極高速的無損視訊串流拉出來播放！

## Android USB mirroring / Android USB 鏡像

Android uses scrcpy's mouse/keyboard control in its own That Mirroring window.
Select an **Android** device from **Device**; **Android：連線步驟／視窗選項**
shows authorization state, the four setup steps, refresh, and launch options.

1. 用可傳輸資料的 USB 線接上 Android 與 Mac。
2. 設定 > 關於手機 > 連點「組建編號」7 次，開啟開發人員選項。
3. 設定 > 系統 > 開發人員選項 > 開啟「USB 偵錯」。
4. 解鎖手機，允許 USB 偵錯，勾選「一律允許使用這台電腦」。

選單與 App 內清單會標示「尚未授權」「離線」等狀態。選擇已授權裝置後，
Mac 滑鼠／鍵盤由 scrcpy 直接操作 Android。iPhone／iPad 維持即時顯示，
滑鼠只提供既有簡報特效、縮放及視窗拖曳。

Android 視窗沿用黑底、隱藏標題列與 Mac 視窗控制鈕；可設定置頂、以全螢幕開啟、
播放裝置聲音（下一次連線套用）。F11 或 Option＋F 在鏡像視窗切換全螢幕。
關閉鏡像視窗、關閉 That Mirroring 主視窗、停止鏡像或離開 App 都會結束該
scrcpy 程序；主程序意外退出時，視窗樣式模組也會結束鏡像。共用 adb server
不會被停止。Android 聲音預設關閉，支援情形依 Android 版本與裝置而定。

### Bundled tools and licenses / 打包與授權

`scripts/fetch-scrcpy.sh` 固定下載 [官方 scrcpy 4.0 macOS aarch64 套件](https://github.com/Genymobile/scrcpy/releases/tag/v4.0)，
SHA-256：`f5167fe047fe4a2ae2c2ea8634c7145a4d64d0b6005f24bb45639a965b8c60d4`。
內含 scrcpy 4.0、同版本 scrcpy-server、adb 37.0.0（含 arm64）。
不需要 Homebrew；build 會檢查所有非系統動態依賴與 Mach-O 簽章。
`scripts/test.sh` 不需要手機、權限或 adb server。

App 優先使用 `Contents/Resources/scrcpy/` 完整工具組。只有 bundle 缺檔時，
才使用 `/opt/homebrew/bin/scrcpy`、`/opt/homebrew/bin/adb` 與
`/opt/homebrew/share/scrcpy/scrcpy-server` 的完整備援組，並在 App 內提示。
建議重新建置或重新下載完整 App，讓版本保持一致。

scrcpy 為 Apache-2.0；App 內附 `Contents/Resources/scrcpy/LICENSE`。
adb 屬 Android SDK platform-tools，完整多元件授權文字附於
`Contents/Resources/scrcpy/licenses/adb/NOTICE.txt`，來自 Google 官方
platform-tools 37.0.0 ZIP。亦附 FFmpeg、SDL、dav1d、libusb、zlib 授權及
[第三方聲明與原始碼來源](licenses/THIRD-PARTY-NOTICES.md)。下載二進位全部在忽略的
`vendor/`；git 只包含取得與驗證腳本、授權和我們的原始碼。

### Thatcaster 畫面來源

在 Thatcaster 的視窗來源選擇 That Mirroring（Apple 擷取視窗）或
「That Mirroring — Android · 裝置型號」（scrcpy 視窗）。Android 的控制繼續在
鏡像視窗操作；來源擷取與聲音配置由 Thatcaster 管理。跨 App 實機驗收見
[1.4 開發進度](docs/PROGRESS_1.4.md)。
