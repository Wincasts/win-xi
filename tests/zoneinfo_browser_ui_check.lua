local imgui = require('imgui');
local catalog = require('map_catalog');
local view = require('debug_view');
local path = os.tmpname(); os.remove(path);
local e = require('boundary_editor').new(catalog, path);
local requested, combo, choice = {}, nil, nil;
e.reader = { get_entry = function(_, zone, key)
    requested[#requested + 1] = { zone, key };
    return { scale = 5, floor_id = catalog.maps[key].floor_id, offset_x = -256, offset_y = -256 };
end };
local combos = {};
imgui.BeginCombo = function(label) combos[label] = (combos[label] or 0) + 1; return label == combo; end;
imgui.Selectable = function(label) return label == choice; end;
imgui.GetMousePos = function() return 0, 0; end;
local s = { debug = true, enabled = true, zone = 100, map_key = catalog[100].key,
    map_x = 238, map_y = 337, approach_yalms = 30, approach_pixels = 30,
    entry = { scale = 5, floor_id = 0, offset_x = -256, offset_y = -256 } };
local checks = 0;
local function check(label, ok) H.print(label, ok); assert(ok, label); checks = checks + 1; end
view.browser.follow[1] = true; view.draw(s, e);
check('live map selected initially', e.map_key == s.map_key);
local marker_calls = H.calls['draw.AddCircleFilled'];
combo, choice = 'Zone', "Carpenters' Landing [2]";
view.draw(s, e); combo, choice = nil, nil;
check('zone dropdown chooses remote map and turns off follow', view.browser.zone_id == 2 and not view.browser.follow[1]);
check('remote browsing never draws live player marker', H.calls['draw.AddCircleFilled'] == marker_calls);
local remote = catalog.by_zone[2][#catalog.by_zone[2]];
combo, choice = 'Map / floor / variant', ('Map %d | %s%s'):format(remote.floor_id, remote.dat, remote.table_index and '' or ' [editor only]');
view.draw(s, e); combo, choice = nil, nil;
check('map dropdown chooses independent floor/variant', e.map_key == remote.key);
check('preview requests the viewed map transform', requested[#requested][1] == 2 and requested[#requested][2] == remote.key);
check('browsing leaves live selection unchanged', s.map_key == catalog[100].key and not e.reader.live_map);
e.edit_mode[1] = true;
e:begin(1); e:move(e.selected.polygon[1][1] - 2, e.selected.polygon[1][2]);
imgui.IsMouseDown = function() return true; end;
view.draw(s, e);
check('remote drag does not pause live classification', not s.editing);
e:finish();
check('remote edits identified separately from live map', e.changed_map == remote.key and e.changed_map ~= s.map_key);
view.browser.follow[1] = true; view.draw(s, e);
check('follow checkbox returns to live map', e.map_key == s.map_key);
check('zone/map dropdowns rendered', combos.Zone >= 3 and combos['Map / floor / variant'] >= 3);
view.clear(); os.remove(path); os.remove(path .. '.tmp'); os.remove(path .. '.bak');
