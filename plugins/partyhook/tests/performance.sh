#!/usr/bin/env bash
# Host CPU-only benchmark and regression checks for shared production helpers; no client/SDK needed.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$HERE/build/tests"
"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Werror "$HERE/tests/performance.cpp" -o "$HERE/build/tests/performance"
"$HERE/build/tests/performance"
