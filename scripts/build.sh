#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/ThatMirroring.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/ModuleCache
scripts/make-icon.sh
scripts/fetch-scrcpy.sh
xcrun swiftc -O -target arm64-apple-macos14.0 -module-cache-path build/ModuleCache \
    MirrorApp.swift MirrorLogic.swift AndroidManager.swift -parse-as-library -o "$app/Contents/MacOS/ThatMirroring"
cp Info.plist "$app/Contents/Info.plist"
cp AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
resources="$app/Contents/Resources/scrcpy"
mkdir -p "$resources"
cp vendor/scrcpy-macos-aarch64-v4.0/{scrcpy,adb,scrcpy-server,disconnected.png,scrcpy.1} "$resources/"
if [[ -d icon/AppIcon.iconset ]]; then
    cp icon/AppIcon.iconset/icon_512x512@2x.png "$resources/scrcpy.png"
else
    cp icon/AppIcon-1024.png "$resources/scrcpy.png"
fi
cp licenses/scrcpy/LICENSE "$resources/LICENSE"
cp licenses/THIRD-PARTY-NOTICES.md "$resources/"
cp -R licenses "$resources/"
xcrun clang -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -dynamiclib \
    native/ScrcpyWindow.m -framework Cocoa \
    -Wl,-install_name,@executable_path/ThatMirroringWindow.dylib \
    -o "$resources/ThatMirroringWindow.dylib"
while IFS= read -r -d '' file; do
    if /usr/bin/file -b "$file" | /usr/bin/grep -q 'Mach-O'; then
        codesign --sign - --force "$file"
    fi
done < <(find "$app/Contents" -type f -print0)
codesign --sign - --force "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/ThatMirroring" -verify_arch arm64
scripts/verify-bundle.sh
printf 'BUILD VERIFIED\n'
