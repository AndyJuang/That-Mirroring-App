# That Mirroring 1.4 開發進度

更新：2026-10-11 01:31 台北。分支 `feat/that-mirroring-1.4`，基線 `df9f42d`（1.3.3）。
只在 ThatMirror-wt-dev 工作；未操作主 checkout、已安裝 App、Pixel Cast 或 grok。

## Issue #3 驗收對照

| 項目 | 狀態 | 驗收／證據 |
| --- | --- | --- |
| That Mirroring 改名 | 完成 | 顯示名稱既有正確；App 型別與 queue 已改名。保留 `com.example.iPhoneMirror` 作為既有設定／權限識別，不作 App 名稱；裝置說明中的 iPhone/iPad 是產品名稱。 |
| 移除錄製 | 完成 | Record 選單、錄製倒數、GifRecorder、ScreenCaptureKit、GIF/VideoToolbox imports 及 NSScreenCaptureUsageDescription 已移除。基線沒有 AVAssetWriter。 |
| 舊錄製設定 | 完成 | 啟動時移除已知錄製設定；未知舊 key 永不讀取。68 項 assertions 包含格式錯誤、重複遷移及保留裝置／音訊／特效／裁切設定。 |
| iPhone/iPad／擷取卡 | 部分 | preview、crop、音訊分析、縮放／聚光燈／中鍵拖曳實作與基線逐段一致；USB／權限／聲音需要實機。 |
| Android UX／控制 | 部分 | Device 選單與 App 內中文清單／四點提示完成；狀態、指定 serial、全螢幕／置頂／聲音選項、關閉／Quit 的 owned Process 結束完成。實機未驗收。 |
| scrcpy/adb 打包與授權 | 完成 | 固定官方 scrcpy 4.0，自含 adb 37.0.0；fetch SHA 驗證、bundle 複製、Apache LICENSE、adb NOTICE 及靜態依賴授權全部完成。每個 Mach-O arm64／strict 簽章／otool 系統依賴驗證通過。 |
| 新 icon | 部分 | 可換檔流程完成；強尼最終圖未到，先從 1.3.3 icns 匯出最大 1024 PNG。 |
| Thatcaster 畫面來源 | 部分 | 本 App 仍輸出一般 macOS 視窗，需 Andy 在 Thatcaster 選取並確認 USB／Android 視窗畫面。 |
| 建置／測試 | 完成（自動化） | arm64／ad-hoc／deep strict 通過；68 assertions（adb 解析、設定遷移、scrcpy 參數、bundle 路徑及程序生命週期）。GATES:G1–G5 已有成功執行證據。GUI／USB 仍需 Andy。 |
| 11:00 後 Release | 未做（時間未到） | `scripts/release.sh [--dmg]` 已備妥，11:00 前明確拒絕且不修改版本。Info.plist 仍 1.3.3/7；11:00 後會設為 1.4.0/8，build＋test、ZIP 解壓簽章驗證、SHA 自動寫回本檔。 |

## 修改檔案／本輪驗證

- `MirrorApp.swift`、`MirrorLogic.swift`、`Info.plist`：移除錄製、啟動遷移；保留 Apple 擷取核心。
- `scripts/build.sh`／`test.sh`／`make-icon.sh`／`pack-icon.py`／`audit-source.py`／`check-secrets.py`、`tests/main.swift`、`icon/AppIcon-1024.png`、`AppIcon.icns`、README、.gitignore、GATES。
- `scripts/build.sh`：成功，`codesign --verify --deep --strict` 成功，arm64 成功；輸出 `build/ThatMirroring.app`。
- `scripts/test.sh`：68 assertions 成功（含 SIGTERM 無反應時僅對自己子程序 SIGKILL、adb 逾時與兩個超過 pipe 容量的輸出串流）；`scripts/audit-source.py`：成功，包含禁用符號正控制與基線比對。
- Xcode 27 的 `@State` 改用同一 property wrapper 的別名 `@ViewState`，避免巨集 plugin 在 Codex sandbox 的 nested sandbox 失敗；未停用／繞過 sandbox。
- 這台環境 `iconutil -c icns` 對原 icns 匯出的各尺寸也回 Invalid Iconset。流程仍優先用 iconutil，失敗才直接封裝經驗證的 PNG ICNS chunks。`iconutil -c iconset` 解碼備援輸出成功，最大尺寸確為 1024×1024。
- 秘密掃描：沒有（commit 前執行，僅記有／沒有）。

## scrcpy 打包決策

固定官方 [v4.0 macOS aarch64 release](https://github.com/Genymobile/scrcpy/releases/tag/v4.0)，沿用機器既有主版本，未升級／brew install。
下載：`vendor/scrcpy-macos-aarch64-v4.0.tar.gz`。
SHA-256：`f5167fe047fe4a2ae2c2ea8634c7145a4d64d0b6005f24bb45639a965b8c60d4`。
含 adb 37.0.0（universal、含 arm64）。只讀取 Homebrew 版本作參考；不使用其 dylib。
Android SDK platform-tools 37.0.0 ZIP（官方 Google）：`094a1395683c509fd4d48667da0d8b5ef4d42b2abfcd29f2e8149e2f989357c7`，供提取 adb 原始授權聲明。
`vendor/` 已忽略；`scripts/fetch-scrcpy.sh` 每次核對 archive SHA，再重新解壓，避免使用改動後的快取二進位。
套件位置：`build/ThatMirroring.app/Contents/Resources/scrcpy/`。
App 只取 bundle 的完整 scrcpy／adb／server 工具組；缺檔才退回 `/opt/homebrew/bin`＋`/opt/homebrew/share/scrcpy/scrcpy-server`，App 內明示備援。實際 build 未用 Homebrew，未需 install_name_tool。
授權：`LICENSE`（Apache-2.0）、`THIRD-PARTY-NOTICES.md`、`licenses/adb/NOTICE.txt`（Google ZIP 內完整多元件授權），及 FFmpeg LGPL2.1、SDL/zlib、dav1d BSD、libusb LGPL。完整來源與重建路徑記於聲明；未將上游 static code 接入本 App。
另有本專案 `native/ScrcpyWindow.m` 編出的獨立 ad-hoc `ThatMirroringWindow.dylib`，只在自己啟動的 scrcpy 注入，保持 SDL 控制、隱藏標題列／深色／交通燈；監測 host 結束以防殘留視窗。dyld 載入檢查通過，硬體視窗外觀需實測。

## 2026-10-11 第二步結果

- 已推送：`fb96889`（移除錄製與基礎建置）、`e13990c`（Android／授權與封版腳本）、`8dc143d`（切換時暫停 Apple 與交接）；draft PR：<https://github.com/AndyJuang/That-Mirroring-App/pull/4>（Refs #3）。
- 新增 `AndroidManager.swift`、`native/ScrcpyWindow.m`、`scripts/fetch-scrcpy.sh`、bundle／icon 驗證腳本、第三方 `licenses/`；擴充 `MirrorLogic.swift`、測試、build、README。
- 最新 App 執行檔 SHA-256：`0e133510c64182dab4cf1b1796436048f05b7c358370c7342d713f3aeb4b9e7b`（開發版本，非 Release ZIP）。
- 最新 gate checker：5 met（G1–G5）、3 unmet（G6 Android 實機、G7 Apple 實機、G8 尚未到 11:00 Release）；沒有 abandoned。
- GUI 煙霧：嘗試直接執行自己 build 的 App，3 秒內 SIGABRT；診斷在 HIServices `_RegisterApplication`／AppKit 初始化，尚未進入擷取或 UI。Codex sandbox 中 GUI 註冊不可用，未驗證畫面；該次程序已結束，未操作已安裝版，未允許／變更相機權限。沒有以其他方式繞過 sandbox。
- 環境控制實驗：只呼叫 `NSApplication.sharedApplication` 的最小 Cocoa executable 可初始化；同一程式放進獨立 ad-hoc `.app` bundle 直接執行也 SIGABRT（-6），支持 bundle 的系統註冊限制，不是鏡像程式碼造成。兩次控制程序均結束，無相機／USB 程式碼。
- 所有自動檢查成功，但不能把上述 smoke 計為通過。需要 Andy 用 Finder 開 `build/ThatMirroring.app` 做真正 GUI／權限／實機驗收。

## 最後整合修正與交接

- Android 面板顯示時暫停 Apple session，返回 Apple 畫面時以原 setupSession 恢復，避免隱藏攝影機占用／聲音混播；未更改 Apple 擷取／裁切／zoom／spotlight／audio monitor 的原實作。
- 修正後 build／68 assertions／基線比對均通過，strict 簽章與 bundle 驗證通過；GUI／USB 切換仍需 Andy 實機。
- 新增專案 `AI_MEMORY.md`，供 11:00 後續跑。中樞 agent-worklog 未有此任務索引，且位於 sandbox 可寫範圍外；交接保留在此 worktree，未寫入中樞或無關任務。
- `scripts/release.sh` 的提前執行負測試通過：明確拒絕、Info.plist 原樣、無 1.4.0 ZIP。

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

1. 開發與最後整合修正已完成，透過 helper commit＋push；既有 draft PR #4 更新為待實機／11:00 封版（不另開）。
2. 本機實際時間仍早於 11:00；不要提前變更 Info.plist／宣稱 Release 已完成。已備妥不使用模型的本機定時封版工作，等待期間不消耗共享模型額度。
3. 若定時工作失敗／手動續跑：11:00 後先讀本檔、`AI_MEMORY.md`、`git log --oneline origin/main..HEAD`、`git status`。若最終 icon 已到，先依換檔步驟；code freeze 後只修阻擋 build／test 的問題。
4. 跑 `scripts/release.sh`（ZIP；若需要 DMG 用 `scripts/release.sh --dmg`），更新本表 Release 狀態與 G8 實測證據、SHA、下一步；秘密掃描只記有／沒有，再用 `.codex-git-request` commit＋push。helper 結果成功後更新 PR #4。11:30 前完成，不發 release、不打 tag。
5. Andy 於中午測 Apple／Android／Thatcaster。正式 icon、畫面／控制／聲音／權限皆不能以自動化純邏輯代替。

## 11:00 定時封版工作

- `scripts/release-at-freeze.py` 在本機等待台北 2026-10-11 11:00，然後依序執行 `scripts/release.sh`、更新 Release 驗收證據、秘密掃描、請 helper commit＋push，更新 draft PR #4。沒有模型/API 呼叫；不做 DMG（可選項）、tag／GitHub Release。
- 額外 3 個定時封版負控制通過：分支被換、worktree 有未完成修改、另一 git 請求存在時都不執行封裝／覆寫版本／請求 commit。`scripts/test.sh` 一併執行（68 Swift assertions＋3 個封版保護案例）。
- 啟動前先 commit 此腳本；工作只在分支正確、工作目錄乾淨、沒有既有 git request 時執行。有人新增未 commit 的 final icon／程式修改時，會停下留下交接，不會把他人的未完成修改一起 commit。
- 等待／完成／失敗與 PID：`build/release-job.json`。執行紀錄：`build/release-job.log`。兩檔都在忽略的 build/。
- 定時工作沒有取代實機驗收；G6／G7 保持 pending。若 Mac 休眠，恢復後才執行；若程序／sandbox session被終止，必須讀紀錄並手動續跑。11:00 前 ZIP 仍未產生，版本仍 1.3.3/7。
