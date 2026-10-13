#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=4.0
archive="vendor/scrcpy-macos-aarch64-v${version}.tar.gz"
sha=f5167fe047fe4a2ae2c2ea8634c7145a4d64d0b6005f24bb45639a965b8c60d4
mkdir -p vendor
if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 \
        "https://github.com/Genymobile/scrcpy/releases/download/v${version}/scrcpy-macos-aarch64-v${version}.tar.gz" \
        -o "$archive.part"
    mv "$archive.part" "$archive"
fi
actual=$(shasum -a 256 "$archive" | awk '{print $1}')
[[ "$actual" == "$sha" ]] || { printf 'scrcpy checksum mismatch; remove cached archive and retry\n' >&2; exit 1; }
# Always extract from the verified archive, replacing any changed vendor files.
tar -xzf "$archive" -C vendor
folder="vendor/scrcpy-macos-aarch64-v${version}"
lipo "$folder/scrcpy" -verify_arch arm64
lipo "$folder/adb" -verify_arch arm64
[[ -f "$folder/scrcpy-server" ]]
printf 'SCRCPY 4.0 FETCH VERIFIED\n'
