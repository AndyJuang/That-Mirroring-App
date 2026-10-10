#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify-bundle.py
printf 'BUNDLE VERIFIED\n'
