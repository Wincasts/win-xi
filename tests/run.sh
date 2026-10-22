#!/usr/bin/env bash
# Runs the checks: each loads an addon (or a part of winxi) against a stand-in for Ashita and prints
# what it finds. Read the output: a line ending in false, or an error, is something to look at.
cd "$(dirname "$0")/.." || exit 1
run() { echo "== $1"; luajit tests/harness.lua "$1" "$2" "tests/$3" 2>&1; echo; }
run inventory  addons/inventory/inventory.lua inventory_check.lua
run inventory  addons/inventory/inventory.lua inventory_grid_check.lua
run inventory  addons/inventory/inventory.lua inventory_bag_tabs_check.lua
run inventory  addons/inventory/inventory.lua inventory_drag_check.lua
run inventory  addons/inventory/inventory.lua inventory_menu_check.lua
run inventory  addons/inventory/inventory.lua inventory_scrollbar_check.lua
run inventory  addons/inventory/inventory.lua inventory_currency_check.lua
run inventory  addons/inventory/inventory.lua inventory_sort_check.lua
run inventory  addons/inventory/inventory.lua inventory_settings_check.lua
run inventory  addons/inventory/inventory.lua inventory_equipment_check.lua
run inventory  addons/inventory/inventory.lua inventory_equipment_decorations_check.lua
run inventory  addons/inventory/inventory.lua inventory_equipment_performance_check.lua
run inventory  addons/inventory/inventory.lua inventory_performance_check.lua
run mark       addons/mark/mark.lua     mark_check.lua
run mark       addons/mark/mark.lua     mark_performance_check.lua
run mark       addons/mark/mark.lua     mark_persistence_check.lua
run mark       addons/mark/mark.lua     mark_map_check.lua
run mark       addons/mark/mark.lua     mark_stats_ui_check.lua
run mark       addons/mark/mark.lua     mark_database_check.lua
luajit tests/mark_stats_check.lua
luajit tests/winxi_version_check.lua
luajit tests/winxi_gamedata_check.lua
luajit tests/winxi_items_check.lua || exit 1
python3 tools/test_build_item_data.py || exit 1
python3 tools/test_build_catalog_data.py || exit 1
luajit tests/winxi_catalogs_check.lua || exit 1
luajit tests/winxi_autotranslate_check.lua || exit 1
python3 tools/test_build_quest_data.py || exit 1
luajit tests/winxi_quests_check.lua || exit 1
luajit tests/parse_check.lua || exit 1
luajit tests/parse_accuracy_check.lua || exit 1
luajit tests/harness.lua parse tests/parse_stand_in.lua tests/parse_ui_check.lua || exit 1
luajit tools/parse_replay.lua tests/fixtures/parse_capture.txt || exit 1
luajit tools/parse_replay.lua tests/fixtures/parse_accuracy_capture.txt || exit 1
luajit tests/nativehud_check.lua
luajit tests/nativechat_check.lua || exit 1
luajit tests/chatbox_log_check.lua || exit 1
luajit tests/chatbox_optimization_check.lua || exit 1
luajit tests/chatbox_encoding_check.lua || exit 1
luajit tests/chatbox_inline_check.lua || exit 1
luajit tests/chatbox_appearance_check.lua || exit 1
luajit tests/chatbox_scrollbar_check.lua || exit 1
luajit tests/chatbox_render_check.lua || exit 1
luajit tests/chatbox_ui_check.lua || exit 1
luajit tests/chatbox_visibility_check.lua || exit 1
luajit tests/chatbox_input_check.lua || exit 1
luajit tests/chatbox_translate_check.lua || exit 1
luajit tests/chatbox_layout_check.lua || exit 1
luajit tests/chatbox_browse_check.lua || exit 1
luajit tests/harness.lua party addons/party/party.lua tests/winxi_capture_check.lua || exit 1
run clock      tests/clock_stand_in.lua clock_check.lua
luajit tests/clock_panel_check.lua || exit 1
luajit tests/infopanel_source_check.lua || exit 1
luajit tests/infopanel_tooltips_check.lua || exit 1
luajit tests/winxi_frame_check.lua || exit 1
luajit tests/winxi_layouts_check.lua || exit 1
luajit tests/nativemenus_check.lua || exit 1
luajit tests/nativehistory_check.lua || exit 1
luajit tests/nativetext_check.lua || exit 1
run sct        addons/sct/sct.lua       sct_check.lua
luajit tests/sct_acquisitions_check.lua || exit 1
run mapoverlay addons/mapoverlay/mapoverlay.lua mapoverlay_check.lua
run mobcast    addons/mobcast/mobcast.lua mobcast_check.lua
run drawscale  addons/drawscale/drawscale.lua drawscale_check.lua
luajit tests/drawscale_detail_check.lua || exit 1
luajit tests/drawscale_view_check.lua || exit 1
luajit tests/drawscale_fov_check.lua || exit 1
luajit tests/occlusionfix_check.lua || exit 1
run atlas      addons/atlas/atlas.lua   atlas_check.lua
run atlas      addons/atlas/atlas.lua   shell_logout_check.lua
luajit tests/tcrossbar_shadow_check.lua
luajit tests/tcrossbar_border_check.lua
luajit tests/tcrossbar_gloss_check.lua
luajit tests/tcrossbar_cooldown_check.lua
luajit tests/tcrossbar_backdrop_check.lua
luajit tests/tcrossbar_recast_check.lua
luajit tests/mark_map_view_check.lua
python3 tools/test_build_mark_maps.py
(cd tools && python3 -m unittest test_trace_walkable_maps)
luajit tests/mark_data_check.lua
echo
run simplelog  tests/empty.lua          simplelog_ui_check.lua
run controller tests/empty.lua          controller_check.lua
run debuffs    tests/empty.lua          debuffs_check.lua
run game       tests/empty.lua          winxi_game_check.lua
run widgets    tests/empty.lua          winxi_widgets_check.lua
luajit tests/winxi_statusdat_check.lua || exit 1
run statusicons tests/empty.lua         winxi_statusicons_mixed_check.lua
run party      addons/party/party.lua party_check.lua
run party      addons/party/party.lua party_lifecycle_check.lua
run party      addons/party/party.lua party_solo_state_check.lua
run party      addons/party/party.lua party_performance_check.lua
run party      addons/party/party.lua party_optimization_check.lua
run party      addons/party/party.lua party_customization_check.lua
run party      addons/party/party.lua party_fantasy_styles_check.lua
run party      addons/party/party.lua party_organize_statuses_check.lua
run party      addons/party/party.lua party_tracking_check.lua
run party      addons/party/party.lua party_borders_check.lua
run party      addons/party/party.lua party_resolution_check.lua
run party      addons/party/party.lua party_rearrange_check.lua
luajit tests/party_hook_check.lua
luajit tests/party_hook_performance_check.lua
run party      addons/party/party.lua party_hook_integration_check.lua
run party      addons/party/party.lua party_native_shadow_check.lua
run party      addons/party/party.lua party_native_positioning_check.lua
run party      addons/party/party.lua party_cursor_check.lua
run party      addons/party/party.lua party_dropdowns_check.lua
run party      addons/party/party.lua winxi_fonts_check.lua
run party      addons/party/party.lua winxi_settings_window_check.lua
run party      addons/party/party.lua winxi_backgrounds_check.lua
run inventory  addons/inventory/inventory.lua winxi_tabs_check.lua
run inventory  addons/inventory/inventory.lua winxi_child_background_check.lua
luajit tests/winxi_mapdat_check.lua
luajit tests/winxi_cursor_check.lua
luajit tests/winxi_font_texture_check.lua
luajit tests/chatbubbles_world_check.lua
luajit tests/chatbubbles_check.lua
luajit tests/chatbubbles_npc_check.lua
luajit tests/chatbubbles_colors_check.lua
run chatbubbles addons/chatbubbles/chatbubbles.lua chatbubbles_config_check.lua
luajit tests/hideparty_cursor_check.lua
luajit tests/winxi_lens_check.lua || exit 1
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
luajit tests/harness.lua cooldowns tests/cooldowns_stand_in.lua tests/cooldowns_check.lua || exit 1
luajit tests/harness.lua cooldowns tests/cooldowns_migration_stand_in.lua tests/cooldowns_migration_check.lua || exit 1
luajit tests/harness.lua cooldowns tests/cooldowns_stand_in.lua tests/cooldowns_performance_check.lua || exit 1
luajit tests/harness.lua cooldowns tests/cooldowns_stand_in.lua tests/cooldowns_optimization_check.lua || exit 1
run puppet     addons/puppet/puppet.lua puppet_check.lua
luajit tests/harness.lua puppet addons/puppet/puppet.lua tests/puppet_regression_check.lua || exit 1
run buff       addons/buff/buff.lua     buff_check.lua
run buff       addons/buff/buff.lua     buff_performance_check.lua
run buff       addons/buff/buff.lua     buff_hook_check.lua
run buff       addons/buff/buff.lua     buff_hook_performance_check.lua
run zone       tests/zoneinfo_fixture.lua zoneinfo_check.lua
run zoneinfo-presentation tests/zoneinfo_fixture.lua zoneinfo_presentation_ui_check.lua
run zoneinfo-background tests/zoneinfo_background_fixture.lua zoneinfo_background_check.lua
echo '== zone geometry and map adapter'
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
run zoneinfo-styles tests/zoneinfo_fixture.lua zoneinfo_styles_check.lua
luajit tests/zoneinfo_gdi_families_check.lua
luajit tests/zoneinfo_height_check.lua
luajit tests/zoneinfo_exact_check.lua
run zoneinfo-features tests/zoneinfo_background_fixture.lua zoneinfo_features_check.lua
echo
run name addons/name/name.lua name_check.lua
run name addons/name/name.lua name_token_options_check.lua
run name addons/name/name.lua name_types_check.lua
run name addons/name/name.lua name_colours_check.lua
run name-extensions addons/name/name.lua name_extensions_check.lua
run name addons/name/name.lua name_healthbar_check.lua
run name addons/name/name.lua name_healthbar_render_check.lua
run name-resolution addons/name/name.lua name_resolution_check.lua
run name-performance addons/name/name.lua name_performance_check.lua
run name-menus addons/name/name.lua name_menu_check.lua
run name-tracking addons/name/name.lua name_track_check.lua
run name-statuses addons/name/name.lua name_statuses_check.lua
run name-diag  addons/name/name.lua name_diag_check.lua
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
