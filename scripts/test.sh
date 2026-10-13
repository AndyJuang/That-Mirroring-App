#!/bin/bash
set -euo pipefail
unset TMPDIR
cd "$(dirname "$0")/.."
python3 scripts/check-strings.py
mkdir -p build/ModuleCache build/tests
xcrun swiftc MirrorLogic.swift tests/main.swift -module-cache-path build/ModuleCache -o build/tests/logic
build/tests/logic
python3 tests/test-release-job.py
printf 'TESTS VERIFIED\n'
