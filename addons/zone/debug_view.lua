-- All-map browser/editor. Browsing never changes the live map or player marker.
local imgui = require('imgui');
local catalog = require('map_catalog');
local geometry = require('area_geometry');
local tracking = require('area_tracking');
local winxi_style = require('winxi.style');
local mapdat = require('winxi.mapdat');
local browser = require('map_browser').new(catalog);
local zoom = { 1.0 };
local reset_scroll, center_vertex = true, nil;
local M = { browser = browser, zoom = zoom };
local handles, textures, retry_at, outlines, order = {}, {}, {}, {}, {};
local preview, outlined_map = {}, nil;
local SIZE = 512;
local labels = {};
local height_sides = { { label = 'Minimum Height', on = 'z_min_on', field = 'z_min_field' },
    { label = 'Maximum Height', on = 'z_max_on', field = 'z_max_field' } };
local function touch_texture(file)
    for i, cached in ipairs(order) do if cached == file then table.remove(order, i); break; end end
    order[#order + 1] = file;
end
-- A map's picture, from the game's files through pivot (XICombinedMaps' where it is installed); a few kept
local function texture(file)
    if handles[file] then touch_texture(file); return handles[file]; end
    if os.clock() < (retry_at[file] or 0) then return nil; end
    retry_at[file] = os.clock() + 5;
    local ok, kept, handle = pcall(mapdat.Load, file);
    if ok and handle then
        handles[file], textures[file] = handle, kept;
        touch_texture(file);
        if #order > 4 then local old = table.remove(order, 1); handles[old], textures[old] = nil, nil; end
    end
    return handles[file];
end
function M.clear()
    handles, textures, retry_at, outlines, order, preview = {}, {}, {}, {}, {}, {};
    outlined_map, reset_scroll, center_vertex = nil, true, nil;
    zoom[1] = 1.0;
end
local function color(r, g, b) return imgui.GetColorU32({ r, g, b, 1 }); end
local function map_label(map)
    if not labels[map] then labels[map] = ('Map %d | %s%s'):format(map.floor_id, map.dat, map.table_index and '' or ' [editor only]'); end
    return labels[map];
end
local function preview_transform(map, state, editor, live)
    if live and state.entry then return state.entry; end
    if not editor or not editor.reader then return nil; end
    if preview.key ~= map.key then preview = { key = map.key, retry = 0 }; end
    if not preview.entry and os.clock() >= preview.retry then
        preview.entry, preview.error = editor.reader:get_entry(map.zone_id, map.key);
        preview.retry = os.clock() + 5;
    end
    return preview.entry;
end
function M.draw(state, editor)
    if not state.debug then if editor then editor:cancel(); end; state.editing = false; return; end
    imgui.SetNextWindowSize({ 570, 900 }, rawget(_G, 'ImGuiCond_FirstUseEver') or 0);
    winxi_style.PushFull();
    local visible = imgui.Begin('Zone - Map Browser');
    if visible then
        browser:sync(state.zone, state.map_key);
        imgui.Text('Areas are drawn from the map art, not walked in game: check them where you stand.');
        imgui.Checkbox('Follow player zone/map', browser.follow);
        browser:sync(state.zone, state.map_key);
        local zone = catalog[browser.zone_id or 0];
        if imgui.BeginCombo('Zone', zone and (zone.name .. ' [' .. browser.zone_id .. ']') or 'Choose a zone') then
            for _, item in ipairs(catalog.zones) do
                if imgui.Selectable(item.name .. ' [' .. item.id .. ']', browser.zone_id == item.id) then browser:choose_zone(item.id); end
            end
            imgui.EndCombo();
        end
        local definition = catalog.maps[browser.map_key or ''];
        if imgui.BeginCombo('Map / floor / variant', definition and map_label(definition) or 'Choose a map') then
            for _, map in ipairs(catalog.by_zone[browser.zone_id] or {}) do
                if imgui.Selectable(map_label(map), browser.map_key == map.key) then browser:choose_map(map.key); end
            end
            imgui.EndCombo();
        end
        definition = catalog.maps[browser.map_key or ''];
        local live = browser:is_live(state);
        imgui.Text(('Live detection: %s | player zone %s'):format(state.enabled and 'ON' or 'OFF', tostring(state.zone)));
        if definition then
            imgui.Text(('Viewing: %s - %s'):format(definition.name, map_label(definition)));
            imgui.Text(live and 'Viewing live map' or 'BROWSING ONLY: no player marker; live detection is unchanged.');
            if editor and editor.reader and editor.reader.live_map then imgui.Text('Live-map override: ' .. editor.reader.live_map); end
            if definition.zone_id == state.zone and editor and editor.reader then
                if imgui.Button('Use this map for live detection') then editor.reader.live_map = definition.key; editor.live_map_changed = true; end
                imgui.SameLine();
                if imgui.Button('Automatic live floor') then editor.reader.live_map = nil; editor.live_map_changed = true; end
            end
        end
        if state.position then
            imgui.Text(('Live world X/Y: %.2f, %.2f | Z: %.2f'):format(state.position.x, state.position.y, state.position.z));
        end
        local entry = definition and preview_transform(definition, state, editor, live);
        -- The viewed map's own zone sets the distance: a city's is not open country's.
        local approach = definition and tracking.approach_yalms(state, definition.zone_id) or state.approach_yalms;
        local radius = entry and approach * math.abs(entry.scale) / 5 or 0;
        if entry then
            imgui.Text(('Viewed floor %d | scale %.2f | offsets %.2f, %.2f'):format(entry.floor_id, entry.scale, entry.offset_x, entry.offset_y));
        elseif definition then
            imgui.Text('Viewed transform unavailable: edit feature vertices; approach outline cannot be calibrated.');
            if imgui.Button('Retry viewed transform') then preview = {}; end
        end
        if live and state.map_x then imgui.Text(('Live map (512): %.2f, %.2f'):format(state.map_x, state.map_y)); end
        imgui.Text(('Approach: %.0f yalms (viewed map: %.2f pixels)'):format(approach, radius));
        if state.error then imgui.Text('Live status: ' .. state.error); end
        if editor and editor.view_key ~= (definition and definition.key) then
            editor.view_key = definition and definition.key;
            editor:select(editor.catalog and editor.view_key or (definition and definition.zone_id), definition and definition.areas[1].id);
        end
        if definition and editor then
            if not editor.selected then editor:select(editor.catalog and definition.key or definition.zone_id, definition.areas[1].id); end
            imgui.Checkbox('Edit vertices', editor.edit_mode);
            if not editor.edit_mode[1] then editor:cancel(); end
            if editor.edit_mode[1] then
                if imgui.BeginCombo('Area', editor.selected and editor.selected.name or 'Choose an area') then
                    for _, area in ipairs(definition.areas) do
                        if imgui.Selectable(area.name .. '##' .. area.id, editor.selected == area) then editor:select(editor.catalog and definition.key or definition.zone_id, area.id); end
                    end
                    imgui.EndCombo();
                end
                if editor.form_area ~= editor.selected or editor.form_revision ~= editor.revision then
                    editor.form_area, editor.form_revision = editor.selected, editor.revision;
                    editor.name_field = { editor.selected.name or editor.selected.id };
                    editor.enabled_field = { editor.selected.enabled ~= false };
                    editor.exact_field = { editor.selected.exact == true };
                    editor.z_min_on, editor.z_min_field = { editor.selected.z_min ~= nil }, { editor.selected.z_min or 0 };
                    editor.z_max_on, editor.z_max_field = { editor.selected.z_max ~= nil }, { editor.selected.z_max or 0 };
                end
                imgui.InputText('Area name', editor.name_field, 257);
                imgui.Checkbox('Announce this area', editor.enabled_field);
                if imgui.Button('Apply name / detection') then editor:configure(editor.name_field[1], editor.enabled_field[1]); end
                if imgui.Checkbox('Exact Boundary (No Approach)', editor.exact_field) then editor:set_exact(editor.exact_field[1]); end
                -- Heights are the Z shown above as the live position; an unticked side is left open.
                for _, side in ipairs(height_sides) do
                    imgui.Checkbox(side.label, editor[side.on]);
                    imgui.SameLine();
                    imgui.PushItemWidth(90);
                    imgui.InputFloat('##zone.' .. side.field, editor[side.field], 0, 0, '%.2f');
                    imgui.PopItemWidth();
                    if state.position then
                        imgui.SameLine();
                        if imgui.Button('My Height##zone.' .. side.field) then
                            editor[side.on][1], editor[side.field][1] = true, state.position.z;
                        end
                    end
                end
                if imgui.Button('Apply Height Limits') then
                    editor:limit(editor.z_min_on[1] and editor.z_min_field[1] or nil, editor.z_max_on[1] and editor.z_max_field[1] or nil);
                end
                if editor.selected.z_min or editor.selected.z_max then
                    imgui.Text(('Announced only between heights %s and %s.'):format(
                        editor.selected.z_min and ('%.2f'):format(editor.selected.z_min) or 'any',
                        editor.selected.z_max and ('%.2f'):format(editor.selected.z_max) or 'any'));
                end
                if editor.catalog then
                    editor.add_name = editor.add_name or { 'New area' };
                    imgui.InputText('New area name', editor.add_name, 257);
                    if imgui.Button('Add Area') then editor:add(definition.key, editor.add_name[1]); end
                end
                if imgui.Button('Undo') then editor:undo(); end
                imgui.SameLine();
                if imgui.Button('Restore Default') then editor:restore(); end
                if imgui.Button('Insert vertex after selected') then editor:vertices(true); end
                imgui.SameLine();
                if imgui.Button('Remove selected vertex') then editor:vertices(false); end
                imgui.Text(('Selected vertex: %d / %d (click a handle to select it)'):format(editor.vertex or 1, #editor.selected.polygon));
                imgui.Text(editor.selected.provenance or 'Manual feature boundary');
                if editor.selected.enabled == false then imgui.Text('EDITOR-ONLY DRAFT: rename/localize it, then enable Announce this area and Apply.'); end
                imgui.Text('Drag yellow feature vertices; approach buffer is separate (/zone approach 0 for exact polygon).');
            end
            if imgui.Button('Save Boundaries') then editor:save(); end
            imgui.Text(editor:dirty() and 'UNSAVED boundary/name/detection changes' or 'Boundaries saved / unchanged');
            if editor.status ~= '' then imgui.Text(editor.status); end
        end
        if definition then
            if outlined_map ~= definition.key then
                outlines, outlined_map, reset_scroll, center_vertex = {}, definition.key, true, nil;
            end
            local previous_zoom = zoom[1];
            imgui.SliderFloat('Map zoom', zoom, 1.0, 6.0, '%.1fx');
            if not geometry.finite(zoom[1]) then zoom[1] = 1; end
            zoom[1] = math.max(1, math.min(6, zoom[1]));
            imgui.SameLine();
            if imgui.Button('Reset view') then zoom[1], reset_scroll = 1, true; end
            if editor and editor.selected then
                if imgui.Button('Center selected vertex') then
                    local point = editor.selected.polygon[editor.vertex or 1] or editor.selected.polygon[1];
                    center_vertex = { point[1], point[2] };
                end
            end
            if zoom[1] ~= previous_zoom and editor then editor:cancel(); end
            imgui.Text('Zoom 1x-6x; use map scrollbars / mouse wheel to reach other vertices.');
            local scale, canvas_size = zoom[1], SIZE * zoom[1];
            local shown = imgui.BeginChild('##zone_zoom_canvas', { SIZE + 20, SIZE + 20 }, 0,
                rawget(_G, 'ImGuiWindowFlags_HorizontalScrollbar') or 2048); -- ImGui's stable 1 << 11 flag.
            if shown ~= false then
            if reset_scroll then imgui.SetScrollX(0); imgui.SetScrollY(0); reset_scroll = false; end
            if center_vertex then
                imgui.SetScrollX(math.max(0, center_vertex[1] * scale - SIZE / 2));
                imgui.SetScrollY(math.max(0, center_vertex[2] * scale - SIZE / 2));
                center_vertex = nil;
            end
            -- Cursor screen position already incorporates child scrolling. All input/output
            -- uses the same origin and scale; stored geometry stays in 512-reference space.
            local ox, oy = imgui.GetCursorScreenPos();
            local function screen(x, y) return { ox + x * scale, oy + y * scale }; end
            local origin, draw = { ox, oy }, imgui.GetWindowDrawList();
            local wx, wy = imgui.GetWindowPos();
            local ww, wh = imgui.GetWindowSize();
            -- Conservative child-window bounds; ImGui still applies its exact clip rect.
            local left, top, right, bottom = wx - 8, wy - 8, wx + ww + 8, wy + wh + 8;
            local palette = {
                white = color(1, 1, 1), background = color(.12, .12, .12), black = color(0, 0, 0),
                gray = color(.7, .7, .7), selected = color(.2, 1, .2), disabled = color(.65, .45, .8),
                normal = color(1, .65, .1), vertex = color(1, 1, .2), player = color(0, 1, 1), entrance = color(.35, .6, 1),
            };
            local function draw_line(a, b, tint, width)
                local ax, ay, bx, by = ox + a[1] * scale, oy + a[2] * scale, ox + b[1] * scale, oy + b[2] * scale;
                if math.max(ax, bx) >= left and math.min(ax, bx) <= right
                    and math.max(ay, by) >= top and math.min(ay, by) <= bottom then
                    draw:AddLine({ ax, ay }, { bx, by }, tint, width);
                end
            end
            if editor and editor.edit_mode[1] then
                imgui.InvisibleButton('##zone_boundary_canvas', { canvas_size, canvas_size });
                local mx, my = imgui.GetMousePos();
                if imgui.IsItemHovered() and imgui.IsMouseClicked(0) and editor.selected then
                    local nearest, distance = nil, 100;
                    for i, point in ipairs(editor.selected.polygon) do
                        local dx, dy = mx - ox - point[1] * scale, my - oy - point[2] * scale;
                        if dx * dx + dy * dy <= distance then nearest, distance = i, dx * dx + dy * dy; end
                    end
                    if nearest and editor:begin(nearest) then
                        local point = editor.selected.polygon[nearest];
                        editor.dragging.offset_x, editor.dragging.offset_y = (mx - ox) / scale - point[1], (my - oy) / scale - point[2];
                    end
                end
                if editor.dragging then
                    if imgui.IsMouseDown(0) then editor:move((mx - ox) / scale - (editor.dragging.offset_x or 0), (my - oy) / scale - (editor.dragging.offset_y or 0));
                    else editor:finish(); end
                end
            else imgui.Dummy({ canvas_size, canvas_size }); end
            local handle = texture(definition.dat);
            if handle then draw:AddImage(handle, origin, { ox + canvas_size, oy + canvas_size }, { 0, 0 }, { 1, 1 }, palette.white);
            else draw:AddRectFilled(origin, { ox + canvas_size, oy + canvas_size }, palette.background); end
            for _, area in ipairs(definition.areas) do
                local bounds = geometry.bounds(area.polygon);
                if ox + (bounds[3] + radius) * scale >= left and ox + (bounds[1] - radius) * scale <= right
                    and oy + (bounds[4] + radius) * scale >= top and oy + (bounds[2] - radius) * scale <= bottom then
                local selected = live and state.area and state.area.id == area.id;
                local radius = area.exact and 0 or radius; -- A building has no approach outline.
                local tint = selected and palette.selected or (area.enabled == false and palette.disabled or palette.normal);
                local previous = area.polygon[#area.polygon];
                for _, point in ipairs(area.polygon) do
                    draw_line(previous, point, radius > 0 and palette.gray or tint, 1);
                    previous = point;
                end
                local cached = outlines[area];
                if not cached or cached.radius ~= radius or cached.polygon ~= area.polygon then
                    cached = { radius = radius, polygon = area.polygon, lines = geometry.approach_outline(area.polygon, radius) }; outlines[area] = cached;
                end
                for _, segment in ipairs(cached.lines) do
                    -- Only visible segments allocate vectors/cross the Lua/ImGui boundary.
                    draw_line(segment[1], segment[2], tint, 2);
                end
                end -- Feature/approach envelope intersects the viewport.
            end
            -- Dungeon and town entrances: not edited here, drawn so they can be seen against the map's own areas.
            local wanted = state.entrances or tracking.ENTRANCE;
            local entrances = entry and tracking.entrance_areas(definition.zone_id, entry, wanted);
            for _, area in ipairs(entrances or {}) do
                local selected = live and state.area and state.area.id == area.id;
                local previous = area.polygon[#area.polygon];
                for _, point in ipairs(area.polygon) do
                    draw_line(previous, point, selected and palette.selected or palette.entrance, 2);
                    previous = point;
                end
            end
            if editor and editor.edit_mode[1] and editor.selected then
                for i, point in ipairs(editor.selected.polygon) do
                    local position = screen(point[1], point[2]);
                    draw:AddCircleFilled(position, 6, palette.black, 16); draw:AddCircleFilled(position, 4, palette.vertex, 16);
                    draw:AddText({ position[1] + 7, position[2] - 7 }, palette.vertex, tostring(i));
                end
            end
            if live and state.map_x and state.map_x >= 0 and state.map_x <= SIZE and state.map_y >= 0 and state.map_y <= SIZE then
                local point = screen(state.map_x, state.map_y);
                draw:AddCircleFilled(point, 5, palette.black, 16); draw:AddCircleFilled(point, 3, palette.player, 16);
            end
            if not handle then imgui.Text('Map preview unavailable; showing polygons only.'); end
            elseif editor then editor:cancel(); end -- EndChild is required even when clipped.
            imgui.EndChild();
            imgui.Text('Yellow: vertices | Cyan: live player | Purple: disabled draft | Orange/green: approach | Blue: entrance');
        end
        imgui.Text('/zone sample prints live coordinates; /zone map closes this window.');
    elseif editor then editor:cancel(); end
    state.editing = editor and editor.dragging ~= nil and browser:is_live(state) or false;
    imgui.End();
    winxi_style.Pop();
end
return M;
