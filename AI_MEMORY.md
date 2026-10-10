# That Mirroring 1.4 — 專案交接

- 專案／分支：本 worktree `ThatMirror-wt-dev`，`feat/that-mirroring-1.4`；基線 main `df9f42d`（1.3.3）。主要進度與驗收：`docs/PROGRESS_1.4.md`，自動化證據：`GATES.md`。
- 本線只顯示即時畫面，已移除 GIF 錄製。Apple USB／擷取卡使用原 AVCaptureDevice 核心；Android 面板顯示時暫停 Apple session，返回時恢復，避免隱藏聲音混播；Android 用 scrcpy 的獨立可控制視窗。
- 固定官方 scrcpy 4.0 aarch64 套件，內含 adb 37.0.0；`scripts/fetch-scrcpy.sh` 核 SHA，vendor 二進位不入 git。完整 Apache、adb 與靜態依賴授權在 `licenses/`。
- 工具只用 bundle 的完整組合；缺檔才用 /opt/homebrew 完整備援，UI 明示。沒有 brew install／修改 Homebrew。
- 保留既有 bundle identifier `com.example.iPhoneMirror` 以沿用設定與權限；App 對外名稱 That Mirroring。
- 建置／測試：`scripts/build.sh`（arm64、macOS 14+、swiftc -O、ad-hoc strict）與 `scripts/test.sh`。Xcode 27 在 sandbox 不能執行 SwiftUI State 巨集，所以使用相同 property wrapper 別名 ViewState；不繞過 sandbox。
- Icon：1024 PNG 覆蓋 `icon/AppIcon-1024.png` 後 build；手工 `icon/AppIcon.iconset/` 優先。目前是佔位圖。sips／iconutil 優先，iconutil 無法編碼時用標準 PNG ICNS 封裝備援；Apple 解碼器已驗證各尺寸。
- Draft PR 唯一一個： https://github.com/AndyJuang/That-Mirroring-App/pull/4 （Refs #3）。不 merge、不 ready、不 tag、不 GitHub Release、不關 issue。
- git 寫入僅 `.codex-git-request` helper；commit 會自動 push 此分支。commit 前 build＋test、秘密掃描（只記有／沒有），寫 request 後等 30 秒並確認 `.codex-git-result` 成功。
- 2026-10-11 10:30 後不開大項、11:00 freeze，11:30 前封装與 push。實際開發開始 01:09，現仍早於 freeze；版本暫留 1.3.3/7。11:00 後跑 `scripts/release.sh [--dmg]` 才設 1.4.0/8、封裝 ZIP／可選 DMG、驗證與記錄 SHA。
- GUI 煙霧在 sandbox 的 AppKit `_RegisterApplication` 中止，沒有通過畫面驗收；Apple／Android USB、權限、控制、聲音、視窗外觀與 Thatcaster 畫面來源要由 Andy 實機。最終 icon 等強尼。
- 禁止操作主 checkout `ThatMirroring`、/Applications 已安裝 App、Pixel Cast、~/bin/pixel-cast（後兩者只讀參考），禁止 grok／pkill／killall／破壞性 git。
- 續跑先讀 PROGRESS、本檔、`git log --oneline origin/main..HEAD`、`git status`；已通過且輸入沒變的檢查可沿用，不要重做已推送內容。
