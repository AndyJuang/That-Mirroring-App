# Gates: That Mirroring 1.4
Scope: Remove recording, preserve Apple mirroring, bundle Android control, prepare repeatable icon/build/test/release workflow.

- [x] G1: arm64 app and all nested Mach-O files pass strict ad-hoc signature verification
  CHECK: scripts/build.sh
  EXPECT: BUILD VERIFIED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ThatMirror-wt-dev; path=66640ee3f59c/40 entries; EXPECT=matched; output-sha256=e3d7e2b2605a4edc7078e25ba12aa2533b158fe9a908bc66c39b803d92311e08; output-bytes=707

- [x] G2: settings migration, adb parsing, arguments, and tool paths handle normal and invalid inputs
  CHECK: scripts/test.sh
  EXPECT: TESTS VERIFIED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ThatMirror-wt-dev; path=66640ee3f59c/40 entries; EXPECT=matched; output-sha256=fa55643d6779d4ac329f97731aa0d1d134a1e293f9e2d25df119742bf57ed4a0; output-bytes=76

- [x] G3: recording code and screen recording permission are absent, Apple preview implementation is preserved
  CHECK: python3 scripts/audit-source.py
  EXPECT: SOURCE VERIFIED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ThatMirror-wt-dev; path=66640ee3f59c/40 entries; EXPECT=matched; output-sha256=0ea2be1a094823f26d0d76325883fc691522719feabe97b26fb8eee845afdd12; output-bytes=16

- [x] G4: packaged Android tools have only system dynamic dependencies and include license notices
  CHECK: scripts/verify-bundle.sh
  EXPECT: BUNDLE VERIFIED
  EVIDENCE: exit=0; shell=/bin/sh; cwd=/Users/zhuangzheyun/claudeai知識庫/VIBE_開發專案/ThatMirror-wt-dev; path=66640ee3f59c/40 entries; EXPECT=matched; output-sha256=4beb04b0d7494bf98b9e492ece9b63acc2fcdafdd613445303d8dff1aef76677; output-bytes=95

- [x] G5: generated icon contains all macOS sizes, replaceable with one 1024 PNG
  CHECK: python3 scripts/verify-icon.py
  EXPECT: ICON VERIFIED
  EVIDENCE: exit=0 after final red-star icon sync; all 10 hand-drawn PNG sizes present, 16/32 PNGs byte-identical to source; build generated ICNS through PNG fallback after iconutil Invalid Iconset; python3 scripts/verify-icon.py = ICON VERIFIED; no GUI preview.
- [ ] G6: Android USB control, native window fullscreen/topmost and closure work on a physical device
  EVIDENCE: pending; requires Andy hardware acceptance
- [ ] G7: iPhone/iPad/capture card display, audio, zoom, spotlight and middle-button drag work on physical devices
  EVIDENCE: pending; requires Andy hardware acceptance
- [ ] G8: final 1.4.0 build 8 ZIP and optional DMG are produced after authorized freeze with hashes recorded
  EVIDENCE: pending; 11:00 freeze not reached
