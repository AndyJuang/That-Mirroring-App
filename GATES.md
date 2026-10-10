# Gates: That Mirroring 1.4
Scope: Remove recording, preserve Apple mirroring, bundle Android control, prepare repeatable icon/build/test/release workflow.

- [ ] G1: arm64 app and all nested Mach-O files pass strict ad-hoc signature verification
  CHECK: scripts/build.sh
  EXPECT: BUILD VERIFIED
  EVIDENCE: pending
- [ ] G2: settings migration, adb parsing, arguments, and tool paths handle normal and invalid inputs
  CHECK: scripts/test.sh
  EXPECT: TESTS VERIFIED
  EVIDENCE: pending
- [ ] G3: recording code and screen recording permission are absent, Apple preview implementation is preserved
  CHECK: python3 scripts/audit-source.py
  EXPECT: SOURCE VERIFIED
  EVIDENCE: pending
- [ ] G4: packaged Android tools have only system dynamic dependencies and include license notices
  CHECK: scripts/verify-bundle.sh
  EXPECT: BUNDLE VERIFIED
  EVIDENCE: pending
- [ ] G5: generated icon contains all macOS sizes, replaceable with one 1024 PNG
  EVIDENCE: pending
- [ ] G6: Android USB control, native window fullscreen/topmost and closure work on a physical device
  EVIDENCE: pending; requires Andy hardware acceptance
- [ ] G7: iPhone/iPad/capture card display, audio, zoom, spotlight and middle-button drag work on physical devices
  EVIDENCE: pending; requires Andy hardware acceptance
- [ ] G8: final 1.4.0 build 8 ZIP and optional DMG are produced after authorized freeze with hashes recorded
  EVIDENCE: pending; 11:00 freeze not reached
