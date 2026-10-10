#!/usr/bin/env python3
"""Negative controls: deferred packaging must reject unrelated or unfinished work."""
import contextlib, datetime, importlib.util, io, pathlib, tempfile
spec = importlib.util.spec_from_file_location('release_job', 'scripts/release-at-freeze.py')
job = importlib.util.module_from_spec(spec)
spec.loader.exec_module(job)
with tempfile.TemporaryDirectory(prefix='thatmirroring-release-guards-') as folder:
    job.ROOT = pathlib.Path(folder)
    (job.ROOT/'build').mkdir()
    job.STATE = job.ROOT/'build/release-job.json'
    job.TARGET = datetime.datetime(2000,1,1,tzinfo=datetime.timezone.utc)
    original = pathlib.Path.cwd()
    try:
        for case, branch, dirty, request in [
            ('Branch changed', 'main', '', False),
            ('Worktree has new edits', 'feat/that-mirroring-1.4', ' M MirrorApp.swift', False),
            ('Another git request', 'feat/that-mirroring-1.4', '', True),
        ]:
            job.git = lambda *args: branch if args[0] == 'branch' else dirty
            def forbidden_run(*args, **kwargs):
                raise AssertionError('Guard allowed packaging or a git mutation')
            job.run = forbidden_run
            pending = job.ROOT/'.codex-git-request'
            if request: pending.write_text('fixture request')
            try:
                with contextlib.redirect_stdout(io.StringIO()): job.main()
            except RuntimeError as error:
                assert case in str(error), (case,error)
            else: raise AssertionError('Missing guard failure')
            assert not (job.ROOT/'Info.plist').exists(), 'Guard wrote version metadata'
            if request: assert pending.read_text() == 'fixture request', 'Guard overwrote another request'
            else: assert not pending.exists(), 'Guard requested a commit'
    finally:
        import os
        os.chdir(original)
print('3 deferred-release safety guards passed')
