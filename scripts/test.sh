#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache build/tests
xcrun swiftc MirrorLogic.swift tests/main.swift -module-cache-path build/ModuleCache -o build/tests/logic
build/tests/logic
printf 'TESTS VERIFIED\n'
