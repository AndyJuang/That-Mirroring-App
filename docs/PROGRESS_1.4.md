# That Mirroring 1.4 開發進度

更新：2026-10-11 01:15 台北。分支 `feat/that-mirroring-1.4`，基線 `df9f42d`（1.3.3）。
只在 ThatMirror-wt-dev 工作；未操作主 checkout、已安裝 App、Pixel Cast 或 grok。

## Issue #3 驗收對照

| 項目 | 狀態 | 驗收／證據 |
| --- | --- | --- |
| That Mirroring 改名 | 完成 | 顯示名稱既有正確；App 型別與 queue 已改名。保留 `com.example.iPhoneMirror` 作為既有設定／權限識別，不作 App 名稱；裝置說明中的 iPhone/iPad 是產品名稱。 |
| 移除錄製 | 完成 | Record 選單、錄製倒數、GifRecorder、ScreenCaptureKit、GIF/VideoToolbox imports 及 NSScreenCaptureUsageDescription 已移除。基線沒有 AVAssetWriter。 |
| 舊錄製設定 | 完成 | 啟動時移除已知錄製設定；未知舊 key 永不讀取。16 項 assertions 包含格式錯誤、重複遷移及保留裝置／音訊／特效／裁切設定。 |
| iPhone/iPad／擷取卡 | 部分 | preview、crop、音訊分析、縮放／聚光燈／中鍵拖曳實作與基線逐段一致；USB／權限／聲音需要實機。 |
| Android UX／控制 | 未做 | 下一步加入 adb 清單與 scrcpy 程序管理。 |
| scrcpy/adb 打包與授權 | 部分 | 官方 scrcpy 4.0 aarch64 套件已下载並核對 SHA；只有系統動態依賴。尚未接 build／附授權。 |
| 新 icon | 部分 | 可換檔流程完成；強尼最終圖未到，先從 1.3.3 icns 匯出最大 1024 PNG。 |
| Thatcaster 畫面來源 | 部分 | 本 App 仍輸出一般 macOS 視窗，需 Andy 在 Thatcaster 選取並確認 USB／Android 視窗畫面。 |
| 建置／測試 | 部分 | 首輪 build＋test 成功（arm64，ad-hoc，deep strict）。Android 四類邏輯測試待加。 |
| 11:00 後 Release | 未做 | 尚未到 freeze；Info.plist 仍 1.3.3/7。ZIP/DMG 尚未產出，待時間確認。 |

## 修改檔案／本輪驗證

- `MirrorApp.swift`、`MirrorLogic.swift`、`Info.plist`：移除錄製、啟動遷移；保留 Apple 擷取核心。
- `scripts/build.sh`／`test.sh`／`make-icon.sh`／`pack-icon.py`／`audit-source.py`／`check-secrets.py`、`tests/main.swift`、`icon/AppIcon-1024.png`、`AppIcon.icns`、README、.gitignore、GATES。
- `scripts/build.sh`：成功，`codesign --verify --deep --strict` 成功，arm64 成功；輸出 `build/ThatMirroring.app`。
- `scripts/test.sh`：16 assertions 成功；`scripts/audit-source.py`：成功，包含禁用符號正控制與基線比對。
- Xcode 27 的 `@State` 改用同一 property wrapper 的別名 `@ViewState`，避免巨集 plugin 在 Codex sandbox 的 nested sandbox 失敗；未停用／繞過 sandbox。
- 這台環境 `iconutil -c icns` 對原 icns 匯出的各尺寸也回 Invalid Iconset。流程仍優先用 iconutil，失敗才直接封裝經驗證的 PNG ICNS chunks。`iconutil -c iconset` 解碼備援輸出成功，最大尺寸確為 1024×1024。
- 秘密掃描：沒有（commit 前執行，僅記有／沒有）。

## scrcpy 打包決策

固定官方 [v4.0 macOS aarch64 release](https://github.com/Genymobile/scrcpy/releases/tag/v4.0)，沿用機器既有主版本，未升級／brew install。
下載：`vendor/scrcpy-macos-aarch64-v4.0.tar.gz`。
SHA-256：`f5167fe047fe4a2ae2c2ea8634c7145a4d64d0b6005f24bb45639a965b8c60d4`。
含 adb 37.0.0（universal、含 arm64）。只讀取 Homebrew 版本作參考；不使用其 dylib。
Android SDK platform-tools 37.0.0 ZIP（官方 Google）：`094a1395683c509fd4d48667da0d8b5ef4d42b2abfcd29f2e8149e2f989357c7`，供提取 adb 原始授權聲明。
`vendor/` 已忽略；下載脚本及第三方授權於下一步完成。

## 最終 icon 換檔

**最終 icon：把 1024×1024 PNG 覆蓋 icon/AppIcon-1024.png，跑 scripts/build.sh。**
如 `icon/AppIcon.iconset/` 有手工各尺寸檔，直接優先使用；要回 PNG 流程，移走該目錄。

## 需要 Andy 實機

- 接 iPhone/iPad，授相機權限、信任 Mac；測直／橫向、拔插、裁切、縮放、spotlight、中鍵拖視窗。
- 擷取卡及 USB 裝置聲音開關、麥克風權限、壞訊號提示與恢復。
- Android 未接／USB 偵錯未開／未授權提示、授權後滑鼠／鍵盤、全螢幕、置頂、關閉時結束 scrcpy。
- 在 Thatcaster 桌面版選取 Apple／Android 視窗當畫面來源；iOS Recorder 的測試屬另一線。
- 強尼最終 icon 外觀驗收。

## 待 Andy 確認

- 封版時間：建議照原指示 11:00 後封版；本次實際 01:09 開始，5 小時上限內可先完成開發再交接續跑。
- Bundle identifier：建議保留既有值，避免設定與權限重置。

## 下一步

完成 Android 管理、bundle-only 工具解析／fallback 提示、授權與 fetch 腳本；擴充純邏輯測試，build＋test 綠後小步 commit＋push並開一個 draft PR。
