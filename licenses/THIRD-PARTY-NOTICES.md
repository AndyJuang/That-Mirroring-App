# That Mirroring — Third-party notices

Android mirroring launches unmodified upstream scrcpy 4.0 and its matching
scrcpy-server, plus Android SDK platform-tools adb 37.0.0. Only local ad-hoc
signatures, the window icon, and a separate That Mirroring Cocoa window adapter
are added; upstream executable code is not patched. scrcpy's recording features
are not exposed by That Mirroring.

The macOS aarch64 distribution is the official Genymobile release:
https://github.com/Genymobile/scrcpy/releases/tag/v4.0
SHA-256: f5167fe047fe4a2ae2c2ea8634c7145a4d64d0b6005f24bb45639a965b8c60d4

- scrcpy / scrcpy-server: Copyright (C) Genymobile; Apache License 2.0.
  Full license: LICENSE (and licenses/scrcpy/LICENSE).
  Source: https://github.com/Genymobile/scrcpy/tree/v4.0
- adb: Android Open Source Project / Google, Android SDK platform-tools 37.0.0.
  The complete upstream multi-component copyright and license notice is
  licenses/adb/NOTICE.txt. It includes Apache-2.0, BSD/MIT and other licenses;
  adb is not represented as exclusively Apache-2.0.
  Notice extracted from https://dl.google.com/android/repository/platform-tools_r37.0.0-darwin.zip
  ZIP SHA-256: 094a1395683c509fd4d48667da0d8b5ef4d42b2abfcd29f2e8149e2f989357c7
  adb source: https://android.googlesource.com/platform/packages/modules/adb/
- FFmpeg 8.1.1: LGPL 2.1 or later, licenses/ffmpeg/COPYING.LGPLv2.1.
  Source: https://ffmpeg.org/releases/ffmpeg-8.1.1.tar.xz
- SDL 3.4.8: zlib license, licenses/sdl/LICENSE.txt.
  Source: https://github.com/libsdl-org/SDL/tree/release-3.4.8
- dav1d 1.5.3: BSD 2-clause, licenses/dav1d/COPYING.
  Source: https://code.videolan.org/videolan/dav1d/-/tree/1.5.3
- libusb 1.0.29: LGPL 2.1 or later, licenses/libusb/COPYING.
  Source: https://github.com/libusb/libusb/tree/v1.0.29
- zlib: zlib license, licenses/zlib/LICENSE. macOS upstream build uses the
  build host's zlib; exact version is not specified by the upstream release.
  Source: https://zlib.net/

These libraries are statically linked into upstream scrcpy; all dynamic
references in this release point to macOS system libraries/frameworks.
The original corresponding source and build recipes are available above and
in scrcpy v4.0 `release/build_macos.sh` and `app/deps/`. To rebuild with modified
libraries, follow those recipes and replace the scrcpy executable inside
Contents/Resources/scrcpy, keeping scrcpy-server at the matching version; then
ad-hoc sign the replacement and the app. That Mirroring uses no library
validation or hardened-runtime restriction that prevents replacement. Library
modification and reverse engineering for debugging such changes are permitted
under the applicable LGPL terms. Any future public redistribution must also
supply the corresponding source/relink materials required by those terms.
