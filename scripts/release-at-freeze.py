#!/usr/bin/env python3
"""Wait locally for the authorized freeze, then package and request a helper commit.
Uses no model/API during the wait. Never writes git internals or publishes a release.
"""
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGET = dt.datetime(2026, 10, 11, 11, 0, tzinfo=dt.timezone(dt.timedelta(hours=8)))
STATE = ROOT / 'build/release-job.json'

def state(status, **values):
    STATE.write_text(json.dumps({'pid': os.getpid(), 'status': status, 'target': TARGET.isoformat(), **values}, ensure_ascii=False, indent=2) + '\n')

def run(args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, text=True, **kwargs)

def git(*args):
    return run(['git', *args], capture_output=True).stdout.strip()

def main():
    os.chdir(ROOT)
    state('waiting')
    print('Waiting for Taipei 2026-10-11 11:00 freeze', flush=True)
    while True:
        remaining = (TARGET - dt.datetime.now(TARGET.tzinfo)).total_seconds()
        if remaining <= 0: break
        time.sleep(min(60, remaining))
    # Do not package or commit someone else's unfinished edits.
    if git('branch', '--show-current') != 'feat/that-mirroring-1.4':
        raise RuntimeError('Branch changed; manual handoff required')
    if git('status', '--porcelain'):
        raise RuntimeError('Worktree has new edits; manual handoff required')
    request = ROOT / '.codex-git-request'
    if request.exists(): raise RuntimeError('Another git request is pending')
    state('packaging')
    run(['scripts/release.sh'])
    zip_path = ROOT / 'build/ThatMirroring_v1.4.0.zip'
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    progress = ROOT / 'docs/PROGRESS_1.4.md'
    text = progress.read_text()
    text = re.sub(r'更新：[^。]+台北', "更新：" + dt.datetime.now(TARGET.tzinfo).strftime("%Y-%m-%d %H:%M") + " 台北", text)
    text = re.sub(r'\| 11:00 後 Release \|.*', '| 11:00 後 Release | 完成 | 1.4.0/8；ZIP 解壓 strict 簽章通過，SHA 與位置見封裝結果。未製作可選 DMG。 |', text)
    text = re.sub(r'版本暫留 1\.3\.3/7', '版本已封為 1.4.0/8', text)
    text = re.sub(r'## 下一步\n.*?(?=\n## |\Z)', '## 下一步\n\n- Andy 實測 Apple／Android／權限／聲音／Thatcaster 畫面來源，換強尼最終 icon；不 merge、不 ready、不 tag、不發 GitHub Release。\n- 若實機發現缺陷，只修阻擋驗收的問題並跑受影響檢查。\n', text, flags=re.S)
    text += '\n## 定時封版執行\n\n本機工作於 11:00 後完成封裝，接著請 helper commit＋push並更新 draft PR #4；實際結果記於 `build/release-job.json`／`build/release-job.log`。\n'
    text = text.replace("尚需秘密掃描、git 請求 commit＋push，並更新 draft PR #4", "秘密掃描、git helper commit＋push及 draft PR #4 更新結果見定時工作紀錄")
    progress.write_text(text)
    memory = ROOT / 'AI_MEMORY.md'
    text = memory.read_text().replace('現仍早於 freeze；版本暫留 1.3.3/7。11:00 後跑', '已於 freeze 後封版 1.4.0/8。重建封裝用')
    memory.write_text(text)
    gates = ROOT / 'GATES.md'
    text = gates.read_text().replace('- [ ] G8:', '- [x] G8:').replace('  EVIDENCE: pending; 11:00 freeze not reached', f'  EVIDENCE: {dt.datetime.now(TARGET.tzinfo).isoformat()}; version=1.4.0; build=8; ZIP round-trip strict verified; zip-sha256={digest}; DMG optional not requested')
    gates.write_text(text)
    # Version/signature inputs changed: refresh the five automated acceptance records.
    env = os.environ.copy()
    env['UNLAZY_APPROVAL_DIR'] = '/Users/zhuangzheyun/.cache/thatmirroring-unlazy-approvals'
    checker = subprocess.run(['node', '/Users/zhuangzheyun/.agents/skills/unlazy/scripts/gate-check.mjs', '--reverify', 'GATES.md'], cwd=ROOT, env=env, text=True, capture_output=True)
    print(checker.stdout, flush=True)
    for gate in ['G1','G2','G3','G4','G5']:
        if f'PASS GATES:{gate}:' not in checker.stdout: raise RuntimeError(f'{gate} did not verify')
    # G6/G7 are explicitly physical-device acceptance, never marked as passed here.
    result = run(['python3','scripts/check-secrets.py'],capture_output=True)
    print(result.stdout.strip(), flush=True)
    run(['git','diff','--check'])
    request_started = time.time()
    request.write_text('commit\n[1.4 #3] 封版 1.4.0 build 8 與驗證 ZIP（build／test：通過，68 assertions）\n')
    state('awaiting_git_helper', zip=str(zip_path), sha256=digest)
    result_path = ROOT / '.codex-git-result'
    for _ in range(10):
        time.sleep(30)
        if result_path.exists() and result_path.stat().st_mtime >= request_started:
            result = result_path.read_text()
            if 'OK commit' in result and 'pushed origin/feat/that-mirroring-1.4' in result: break
            raise RuntimeError('Automatic git helper reported failure; inspect .codex-git-result')
    else: raise RuntimeError('Automatic git helper timed out')
    body = ROOT / 'build/release-pr-body.md'
    body.write_text(f'''Refs #3

移除 GIF 錄製與相關權限，只保留即時畫面；Android 清單與中文連線提示啟動指定 scrcpy 裝置，保留滑鼠／鍵盤控制。Apple USB／擷取卡核心保留，切到 Android 時暫停隱藏 session。

官方 scrcpy 4.0 aarch64＋adb 37.0.0 自包含打包，SHA 驗證及完整第三方授權；icon 一步換檔、arm64 swiftc 建置和每個 Mach-O／App 的 ad-hoc strict 驗證完成。

驗證：build 通過、68 assertions、自動驗收 5/5。11:00 後封版 1.4.0 build 8；ZIP 解壓簽章驗證通過。
ZIP：build/ThatMirroring_v1.4.0.zip
SHA-256：{digest}

待 Andy：真實 Apple／Android 畫面、授權、聲音、視窗控制與 Thatcaster 來源；強尼最終 icon。Sandbox 直接啟動 .app 在 AppKit 註冊中止，最小 Cocoa bundle 控制也中止，未算 GUI 通過。

詳見 docs/PROGRESS_1.4.md。保持 draft，不合併、不打 tag、不發 GitHub Release。
''')
    run(['gh','pr','edit','4','-R','AndyJuang/That-Mirroring-App','--body-file',str(body)])
    state('complete', commit=git('rev-parse','HEAD'), zip=str(zip_path), sha256=digest, pr='https://github.com/AndyJuang/That-Mirroring-App/pull/4')
    print('Release package committed and pushed; draft PR updated', flush=True)

if __name__ == '__main__':
    try: main()
    except Exception as error:
        state('failed', reason=str(error))
        print(f'Release job stopped: {error}', flush=True)
        raise
