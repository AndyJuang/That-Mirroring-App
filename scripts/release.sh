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
python3 - <<'PY'
import pathlib, plistlib
path = pathlib.Path('Info.plist')
plist = plistlib.loads(path.read_bytes())
assert plist['CFBundleShortVersionString'] in ['1.3.3','1.4.0']
assert plist['CFBundleVersion'] in ['7','8']
plist['CFBundleShortVersionString'] = '1.4.0'
plist['CFBundleVersion'] = '8'
path.write_bytes(plistlib.dumps(plist,sort_keys=False))
PY
scripts/build.sh
scripts/test.sh
python3 scripts/audit-source.py
python3 scripts/verify-icon.py
ditto -c -k --keepParent build/ThatMirroring.app build/ThatMirroring_v1.4.0.zip
# Verify archive can round-trip and retain its ad-hoc signatures.
mkdir -p build/release-verify
ditto -x -k build/ThatMirroring_v1.4.0.zip build/release-verify
codesign --verify --deep --strict build/release-verify/ThatMirroring.app
if [[ "${1:-}" == --dmg ]]; then
    mkdir -p build/dmg-root
    ditto build/ThatMirroring.app build/dmg-root/ThatMirroring.app
    ln -sfn /Applications build/dmg-root/Applications
    hdiutil create -volname 'That Mirroring 1.4.0' -srcfolder build/dmg-root -ov -format UDZO build/ThatMirroring_v1.4.0.dmg
    hdiutil verify build/ThatMirroring_v1.4.0.dmg
fi
python3 - <<'PY'
import hashlib, pathlib, datetime
progress=pathlib.Path('docs/PROGRESS_1.4.md')
paths=[pathlib.Path('build/ThatMirroring_v1.4.0.zip')]
dmg=pathlib.Path('build/ThatMirroring_v1.4.0.dmg')
if dmg.exists(): paths.append(dmg)
lines=['## Release 封裝結果','', '版本：1.4.0；build：8。ZIP 解壓後 deep strict 簽章驗證通過。','']
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
