#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Hand-authored iconsets take precedence. Generated sizes live only in build/.
if [[ -d icon/AppIcon.iconset ]]; then
    iconset=icon/AppIcon.iconset
else
    source=icon/AppIcon-1024.png
    dimensions=$(sips -g pixelWidth -g pixelHeight "$source")
    [[ "$dimensions" == *'pixelWidth: 1024'* && "$dimensions" == *'pixelHeight: 1024'* ]] || {
        printf 'Icon must be a 1024×1024 PNG\n' >&2; exit 1;
    }
    iconset=build/AppIcon.iconset
    mkdir -p "$iconset"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
fi
if ! iconutil -c icns "$iconset" -o AppIcon.icns; then
    printf 'iconutil encoder unavailable; packing verified PNG ICNS chunks\n' >&2
    python3 scripts/pack-icon.py "$iconset" AppIcon.icns
fi
printf 'ICON GENERATED\n'
