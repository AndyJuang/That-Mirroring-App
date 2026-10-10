#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/ThatMirroring.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/ModuleCache
scripts/make-icon.sh
xcrun swiftc -O -target arm64-apple-macos14.0 -module-cache-path build/ModuleCache \
    MirrorApp.swift MirrorLogic.swift -parse-as-library -o "$app/Contents/MacOS/ThatMirroring"
cp Info.plist "$app/Contents/Info.plist"
cp AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# Resource packaging is added with the Android integration step.
while IFS= read -r -d '' file; do
    if /usr/bin/file -b "$file" | /usr/bin/grep -q 'Mach-O'; then
        codesign --sign - --force "$file"
    fi
done < <(find "$app/Contents" -type f -print0)
codesign --sign - --force "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/ThatMirroring" -verify_arch arm64
printf 'BUILD VERIFIED\n'
