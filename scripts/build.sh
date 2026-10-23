#!/bin/bash
set -euo pipefail
unset TMPDIR
cd "$(dirname "$0")/.."
python3 scripts/check-strings.py
app=build/ThatMirroring.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/ModuleCache
scripts/make-icon.sh
scripts/fetch-scrcpy.sh
xcrun swiftc -O -target arm64-apple-macos14.0 -module-cache-path build/ModuleCache \
    MirrorApp.swift MirrorLogic.swift AndroidManager.swift -parse-as-library -o "$app/Contents/MacOS/ThatMirroring"
cp Info.plist "$app/Contents/Info.plist"
for lang in en zh-Hant; do
    mkdir -p "$app/Contents/Resources/$lang.lproj"
    cp "$lang.lproj/Localizable.strings" "$lang.lproj/InfoPlist.strings" "$app/Contents/Resources/$lang.lproj/"
done
cp AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
resources="$app/Contents/Resources/scrcpy"
rm -rf "$resources"
mkdir -p "$resources"
cp vendor/scrcpy-macos-aarch64-v4.0/{adb,scrcpy-server,disconnected.png,scrcpy.1} "$resources/"
helper="$resources/ThatMirroringAndroid.app"
mkdir -p "$helper/Contents/MacOS" "$helper/Contents/Resources"
cp vendor/scrcpy-macos-aarch64-v4.0/scrcpy "$helper/Contents/MacOS/scrcpy"
cp native/AndroidHelper-Info.plist "$helper/Contents/Info.plist"
for key in CFBundleShortVersionString CFBundleVersion; do
    /usr/libexec/PlistBuddy -c "Set :$key $(/usr/libexec/PlistBuddy -c "Print :$key" Info.plist)" "$helper/Contents/Info.plist"
done
cp AppIcon.icns "$helper/Contents/Resources/AppIcon.icns"
cp licenses/scrcpy/LICENSE "$helper/Contents/Resources/LICENSE"
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
codesign --sign - --force "$helper"
codesign --sign - --force "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/ThatMirroring" -verify_arch arm64
scripts/verify-bundle.sh
printf 'BUILD VERIFIED\n'
