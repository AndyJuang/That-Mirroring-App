#!/bin/bash
set -euo pipefail
unset TMPDIR
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache build/render _grok-logs/android-ui/shots
# swiftc only allows top-level code in a file named main.swift.
cp tests/render-android-ui.swift build/render/main.swift
xcrun swiftc -module-cache-path build/ModuleCache AndroidManager.swift MirrorLogic.swift build/render/main.swift \
    -o build/render/render-android-ui
for lang in en zh-Hant; do
    rm -rf build/render/*.lproj
    cp -R "$lang.lproj" build/render/
    mkdir -p "_grok-logs/android-ui/shots/$lang"
    build/render/render-android-ui "_grok-logs/android-ui/shots/$lang" -AppleLanguages "($lang)"
done
