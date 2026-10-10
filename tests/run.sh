#!/usr/bin/env bash
# Runs the checks: each loads an addon (or a part of winxi) against a stand-in for Ashita and prints
# what it finds. Read the output: a line ending in false, or an error, is something to look at.
cd "$(dirname "$0")/.." || exit 1
run() { echo "== $1"; luajit tests/harness.lua "$1" "$2" "tests/$3" 2>&1; echo; }
run inv        addons/inv/inv.lua       inv_check.lua
run treas      addons/treas/treas.lua   treas_check.lua
run controller tests/empty.lua          controller_check.lua
run debuffs    tests/empty.lua          debuffs_check.lua
run xiframes   addons/xiframes/xiframes.lua xiframes_check.lua
run chime      addons/chime/chime.lua   chime_check.lua
run puppet     addons/puppet/puppet.lua puppet_check.lua

# What xiframes draws, call for call, against a kept copy: any difference is printed. After a change
# that is meant to alter what is drawn, look the difference over and keep the new copy with
#   ./tests/run.sh keep
scene() {
    local out; out="$(luajit tests/capture.lua xiframes addons/xiframes/xiframes.lua tests/xiframes_scene.lua tests/fixtures/xiframes_v1_settings.lua "$1" 2>&1)"
    if [[ "$2" == keep ]]; then echo "$out" > "tests/golden/xiframes_scene_$1.txt"; echo "xiframes drawn ($1): kept"; return; fi
    if diff <(echo "$out") "tests/golden/xiframes_scene_$1.txt" > /tmp/xiframes_scene_diff.$$ 2>&1; then echo "xiframes drawn ($1): as kept	true"
    else echo "xiframes drawn ($1): as kept	false"; head -20 /tmp/xiframes_scene_diff.$$; fi
    rm -f /tmp/xiframes_scene_diff.$$
}
# What a frame of xiframes costs, counted over the same scene:
#   ./tests/run.sh measure
if [[ "$1" == measure ]]; then
    luajit tests/capture.lua xiframes addons/xiframes/xiframes.lua tests/xiframes_scene.lua tests/fixtures/xiframes_v1_settings.lua plain measure 2>&1
    exit
fi
echo "== xiframes scene"
scene plain "$1"
scene bare "$1"
