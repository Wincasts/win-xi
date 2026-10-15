#!/usr/bin/env bash
# Runs the checks: each loads an addon (or a part of winxi) against a stand-in for Ashita and prints
# what it finds. Read the output: a line ending in false, or an error, is something to look at.
cd "$(dirname "$0")/.." || exit 1
run() { echo "== $1"; luajit tests/harness.lua "$1" "$2" "tests/$3" 2>&1; echo; }
run inventory  addons/inventory/inventory.lua inventory_check.lua
run treas      addons/treas/treas.lua   treas_check.lua
run mark       addons/mark/mark.lua     mark_check.lua
run mark       addons/mark/mark.lua     mark_performance_check.lua
run mark       addons/mark/mark.lua     mark_persistence_check.lua
run mark       addons/mark/mark.lua     mark_map_check.lua
run mark       addons/mark/mark.lua     mark_stats_ui_check.lua
run mark       addons/mark/mark.lua     mark_database_check.lua
luajit tests/mark_stats_check.lua
luajit tests/mark_map_view_check.lua
python3 tools/test_build_mark_maps.py
luajit tests/mark_data_check.lua
echo
run controller tests/empty.lua          controller_check.lua
run debuffs    tests/empty.lua          debuffs_check.lua
run statusicons tests/empty.lua         winxi_statusicons_mixed_check.lua
run party      addons/party/party.lua party_check.lua
run party      addons/party/party.lua party_borders_check.lua
run party      addons/party/party.lua party_dropdowns_check.lua
run party      addons/party/party.lua winxi_fonts_check.lua
run party      addons/party/party.lua winxi_settings_window_check.lua
run party      addons/party/party.lua winxi_backgrounds_check.lua
run inventory  addons/inventory/inventory.lua winxi_tabs_check.lua
luajit tests/winxi_mapdat_check.lua
luajit tests/winxi_cursor_check.lua
luajit tests/hideparty_cursor_check.lua
luajit tests/hidechatbg_check.lua
luajit tests/map_files_check.lua
echo
run winxisettings addons/winxisettings/winxisettings.lua winxisettings_check.lua
run trigger    addons/trigger/trigger.lua trigger_check.lua
run trigger-winxi addons/trigger/trigger.lua trigger_winxi_check.lua
luajit tests/trigger_queue_check.lua
luajit tests/trigger_overlap_check.lua
luajit tests/trigger_volume_check.lua
luajit tests/trigger_wav_check.lua
python3 tests/trigger_sound_volumes_check.py
run puppet     addons/puppet/puppet.lua puppet_check.lua
run buff       addons/buff/buff.lua     buff_check.lua
run buff       addons/buff/buff.lua     buff_performance_check.lua
run zoneinfo   tests/zoneinfo_fixture.lua zoneinfo_check.lua
run zoneinfo-presentation tests/zoneinfo_fixture.lua zoneinfo_presentation_ui_check.lua
run zoneinfo-background tests/zoneinfo_background_fixture.lua zoneinfo_background_check.lua
echo '== zoneinfo geometry and map adapter'
luajit tests/zoneinfo_math_check.lua
luajit tests/zoneinfo_banner_check.lua
luajit tests/zoneinfo_editor_check.lua
luajit tests/zoneinfo_catalog_check.lua
luajit tests/zoneinfo_geometry_regression_check.lua
run zoneinfo-editor tests/zoneinfo_fixture.lua zoneinfo_editor_ui_check.lua
run zoneinfo-browser tests/zoneinfo_fixture.lua zoneinfo_browser_ui_check.lua
run zoneinfo-zoom tests/zoneinfo_fixture.lua zoneinfo_zoom_ui_check.lua
run zoneinfo-performance tests/zoneinfo_fixture.lua zoneinfo_performance_ui_check.lua
run zoneinfo-subzone tests/zoneinfo_fixture.lua zoneinfo_subzone_check.lua
run zoneinfo-gdi tests/zoneinfo_fixture.lua zoneinfo_gdi_check.lua
luajit tests/zoneinfo_gdi_families_check.lua
luajit tests/zoneinfo_height_check.lua
luajit tests/zoneinfo_exact_check.lua
run zoneinfo-features tests/zoneinfo_background_fixture.lua zoneinfo_features_check.lua
echo
run name addons/name/name.lua name_check.lua
run name-resolution addons/name/name.lua name_resolution_check.lua
run name-performance addons/name/name.lua name_performance_check.lua
run name-menus addons/name/name.lua name_menu_check.lua
run name-tracking addons/name/name.lua name_track_check.lua
run name-statuses addons/name/name.lua name_statuses_check.lua
echo '== name bundled player icons'
luajit tests/name_icons_check.lua
luajit tests/name_format_check.lua
luajit tests/name_letters_check.lua
luajit tests/name_badges_check.lua
echo '== name badge atlas'
luajit tests/name_gdi_texture_check.lua
echo

# What party draws, call for call, against a kept copy: any difference is printed. After a change
# that is meant to alter what is drawn, look the difference over and keep the new copy with
#   ./tests/run.sh keep
scene() {
    local out; out="$(luajit tests/capture.lua party addons/party/party.lua tests/party_scene.lua tests/fixtures/party_v1_settings.lua "$1" 2>&1)"
    if [[ "$2" == keep ]]; then echo "$out" > "tests/golden/party_scene_$1.txt"; echo "party drawn ($1): kept"; return; fi
    if diff <(echo "$out") "tests/golden/party_scene_$1.txt" > /tmp/party_scene_diff.$$ 2>&1; then echo "party drawn ($1): as kept	true"
    else echo "party drawn ($1): as kept	false"; head -20 /tmp/party_scene_diff.$$; fi
    rm -f /tmp/party_scene_diff.$$
}
# What a frame of party costs, counted over the same scene:
#   ./tests/run.sh measure
if [[ "$1" == measure ]]; then
    luajit tests/capture.lua party addons/party/party.lua tests/party_scene.lua tests/fixtures/party_v1_settings.lua plain measure 2>&1
    exit
fi
echo "== party scene"
scene plain "$1"
scene bare "$1"
