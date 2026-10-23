#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Release packaging is authorized only after the 2026-10-11 11:00 Taipei freeze.
now=$(TZ=Asia/Taipei date +%Y%m%d%H%M)
if [[ "$now" -lt 202610111100 ]]; then
    printf '尚未到台北 2026-10-11 11:00 code freeze；不變更版本、不產生 Release。\n' >&2
    exit 1
fi
[[ $# -eq 0 || ( $# -eq 1 && "$1" == --dmg ) ]] || { printf 'Usage: scripts/release.sh [--dmg]\n' >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)
export VERSION BUILD
scripts/build.sh
scripts/test.sh
python3 scripts/audit-source.py
python3 scripts/verify-icon.py
ditto -c -k --keepParent build/ThatMirroring.app build/ThatMirroring_v${VERSION}.zip
# Verify archive can round-trip and retain its ad-hoc signatures.
mkdir -p build/release-verify
ditto -x -k build/ThatMirroring_v${VERSION}.zip build/release-verify
codesign --verify --deep --strict build/release-verify/ThatMirroring.app
if [[ "${1:-}" == --dmg ]]; then
    mkdir -p build/dmg-root
    ditto build/ThatMirroring.app build/dmg-root/ThatMirroring.app
    ln -sfn /Applications build/dmg-root/Applications
    hdiutil create -volname "That Mirroring ${VERSION}" -srcfolder build/dmg-root -ov -format UDZO build/ThatMirroring_v${VERSION}.dmg
    hdiutil verify build/ThatMirroring_v${VERSION}.dmg
fi
python3 - <<'PY'
import hashlib, pathlib, datetime
progress=pathlib.Path('docs/PROGRESS_1.4.md')
import os
version,build=os.environ['VERSION'],os.environ['BUILD']
paths=[pathlib.Path(f'build/ThatMirroring_v{version}.zip')]
dmg=pathlib.Path(f'build/ThatMirroring_v{version}.dmg')
if dmg.exists(): paths.append(dmg)
lines=['## Release 封裝結果','', f'版本：{version}；build：{build}。ZIP 解壓後 deep strict 簽章驗證通過。','']
for file in paths:
    digest=hashlib.sha256(file.read_bytes()).hexdigest()
    lines.append(f'- `{file}`（{file.resolve()}），SHA-256：`{digest}`。')
    print(f'{file}: {digest}')
lines += ['', '尚需秘密掃描、git 請求 commit＋push，並更新 draft PR；未建立 tag／GitHub Release。','']
text=progress.read_text()
if '## Release 封裝結果' in text: text=text[:text.index('## Release 封裝結果')]
progress.write_text(text.rstrip()+'\n\n'+'\n'.join(lines))
PY
printf 'RELEASE PACKAGED\n'
