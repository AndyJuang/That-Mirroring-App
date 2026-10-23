# That Mirroring — 交接

- 2026-10-23 1.4.2／build 10：合併 `feat/i18n`（PGM 監看、啟動閃退修正、Meet 黑畫面修正）進 main 線，保留 1.4.1 的關閉手機螢幕、Android 畫面改版與巢狀 helper app。`scripts/test.sh` 157 assertions、3 guards；`scripts/build.sh` BUNDLE VERIFIED、BUILD VERIFIED。沒有開 GUI，沒有 push。
- 2026-10-16 #12：PGM 監看在來源超過 2 秒沒有新畫面，或影格內容沒有變時，左下角顯示「畫面停住了。」。新的畫面內容出現後提示消失。提示不常駐，也不擋 1、F、Esc。偵測在 `MirrorLogic.swift`，時間由呼叫端傳入。`scripts/test.sh` 132 assertions。xcodebuild（macOS、arm64、macOS 14）通過，產物在系統暫存。沒有開 App，沒有安裝。沒有自動重新擷取。不要合併 PR #13。
- 2026-10-15 #12：PGM 監看在工作區 `ThatMirror-wt-pgm-monitor`，分支 `feat/pgm-monitor`，提交 `bda5c43`。PR https://github.com/AndyJuang/That-Mirroring-App/pull/13 ，目標 `feat/i18n`，未合併。來源是 ScreenCaptureKit 擷取標題「Thatcaster — PGM 監看」與「Thatcaster — Program」，畫在一般 CALayer。不採用本機串流，也不採用 Syphon。手機投影的擷取沒有改。`scripts/test.sh` 117 assertions。xcodebuild 通過。沒有開 GUI，沒有安裝。不要合併 PR #13。實機的外接螢幕與延遲還沒看過。
- i18n 工作區是 `ThatMirror-wt-i18n`，分支 `feat/i18n`，基底是 `feat/that-mirroring-1.4`（PR #4，1.4.0／build 8）。介面語系見下方 2026-10-13 決策。1.4 進度與實機 DEFERRED 仍在 `docs/PROGRESS_1.4.md`。自動化證據：`GATES.md`。
- 目前工作區是 `ThatMirror-wt-141`，分支 `feat/1.4.1-android-polish`，基底 main（1.4.0／build 8，已含 Android／scrcpy 與介面語系）。這次是 1.4.1／build 9：Android「投影時關閉手機螢幕」與操控提示。實機 DEFERRED 仍在 `docs/PROGRESS_1.4.md`。自動化證據：`GATES.md`。
- 2026-10-14 1.4.1：選項跟置頂、全螢幕、聲音放在同一區，預設關，只把這一項寫進 `AndroidTurnScreenOff`。下次連線才套用。開啟時才加 `--turn-screen-off`。參數沒有 `--no-control`、`--no-mouse`、`--no-keyboard`。連線畫面提示可用滑鼠與鍵盤操作手機。iPhone／iPad 的 AVCapture 核心沒改。`scripts/test.sh` 94 assertions、3 guards、字串對齊；`scripts/build.sh` BUILD VERIFIED；`audit-source.py` SOURCE VERIFIED；`verify-icon.py` ICON VERIFIED。秘密掃描沒有。沒有開 GUI、沒有安裝、沒有封裝。PR https://github.com/AndyJuang/That-Mirroring-App/pull/8 ，目標 main，內文 Refs #3。不 merge、不 tag、不發 GitHub Release。
- 1.4 原工作區是 `ThatMirror-wt-dev`，基線 main `df9f42d`（1.3.3）。
- 本線只顯示即時畫面，已移除 GIF 錄製。Apple USB／擷取卡使用原 AVCaptureDevice 核心；Android 面板顯示時暫停 Apple session，返回時恢復，避免隱藏聲音混播；Android 用 scrcpy 的獨立可控制視窗。
- 固定官方 scrcpy 4.0 aarch64 套件，內含 adb 37.0.0；`scripts/fetch-scrcpy.sh` 核 SHA，vendor 二進位不入 git。完整 Apache、adb 與靜態依賴授權在 `licenses/`。
- 工具只用 bundle 的完整組合；缺檔才用 /opt/homebrew 完整備援。介面只說正在使用備用工具，不顯示路徑或建置指令。沒有 brew install／修改 Homebrew。
- 2026-10-13 #6：介面語系的英文是 key，`en.lproj`／`zh-Hant.lproj`。選單「語言」預設跟隨系統；繁體中文與 English 只寫進這個 App 的 `AppleLanguages`，重新開啟後生效。視窗標題不翻譯。沒有改輸出內容語系。GIF 倒數已在 1.4 移除，沒有加回。`scripts/test.sh` 85 assertions、3 guards、字串對齊通過；`scripts/build.sh` BUILD VERIFIED；`audit-source.py` SOURCE VERIFIED。沒有開 GUI。
- 保留既有 bundle identifier `com.example.iPhoneMirror` 以沿用設定與權限；App 對外名稱 That Mirroring。
- 建置／測試：`scripts/build.sh`（arm64、macOS 14+、swiftc -O、ad-hoc strict）與 `scripts/test.sh`。Xcode 27 在 sandbox 不能執行 SwiftUI State 巨集，所以使用相同 property wrapper 別名 ViewState；不繞過 sandbox。
- Icon：1024 PNG 覆蓋 `icon/AppIcon-1024.png` 後 build；手工 `icon/AppIcon.iconset/` 優先。目前是佔位圖。sips／iconutil 優先，iconutil 無法編碼時用標準 PNG ICNS 封裝備援；Apple 解碼器已驗證各尺寸。
- 1.4 draft PR：https://github.com/AndyJuang/That-Mirroring-App/pull/4 （Refs #3）。#6 介面語系：https://github.com/AndyJuang/That-Mirroring-App/pull/7 ，分支 `feat/i18n` `e1bb176`，目標 `feat/that-mirroring-1.4`。不 merge、不 tag、不發 GitHub Release。
- 1.4 封版用 `.codex-git-request`。#6 依任務直接 commit 與 `git push -u origin feat/i18n`。commit 前跑 build、test 與秘密掃描（只記有／沒有）。
- 2026-10-11 10:30 後不開大項、11:00 freeze，11:30 前封装與 push。實際開發開始 01:09，已於 freeze 後封版 1.4.0/8。重建封裝用 `scripts/release.sh [--dmg]` 才設 1.4.0/8、封裝 ZIP／可選 DMG、驗證與記錄 SHA。
- GUI 煙霧在 sandbox 的 AppKit `_RegisterApplication` 中止，沒有通過畫面驗收；Apple／Android USB、權限、控制、聲音、視窗外觀與 Thatcaster 畫面來源要由 Andy 實機。最終 icon 等強尼。
- 禁止操作主 checkout `ThatMirroring`、/Applications 已安裝 App、Pixel Cast、~/bin/pixel-cast（後兩者只讀參考），禁止 grok／pkill／killall／破壞性 git。
- 續跑先讀 PROGRESS、本檔、`git log --oneline origin/main..HEAD`、`git status`；已通過且輸入沒變的檢查可沿用，不要重做已推送內容。

- 已準備 `scripts/release-at-freeze.py` 本機定時封版（不使用模型），11:00 後先檢查 branch／clean／git request，再執行 Release、helper commit＋push和 PR 更新。狀態／PID：`build/release-job.json`，紀錄：`build/release-job.log`；讀紀錄確認成功，不能把 queued 算成 Release 完成。有人新增未 commit 修改會停下，避免自動帶入他人的未完成修改。
