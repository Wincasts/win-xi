#!/usr/bin/env bash
# Runs the checks: each loads an addon (or a part of winxi) against a stand-in for Ashita and prints
# what it finds. Read the output: a line ending in false, or an error, is something to look at.
cd "$(dirname "$0")/.." || exit 1
run() { echo "== $1"; luajit tests/harness.lua "$1" "$2" "tests/$3" 2>&1; echo; }
run inv        addons/inv/inv.lua       inv_check.lua
run treas      addons/treas/treas.lua   treas_check.lua
run controller tests/empty.lua          controller_check.lua
run xilite     addons/xilite/xilite.lua xilite_check.lua
