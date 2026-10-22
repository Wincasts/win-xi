addon.name    = 'zone';
addon.author  = 'win';
addon.version = '2.6.3';
addon.desc    = 'Zone, region, sub-zone and weather banners, a location line, and an all-map experimental boundary editor.';

require('common');

local chat    = require('chat');
local regions = require('data.regions');
local rz      = require('data.regionZones');
local region_flags = require('data.region_flags');
local zone_names_ja = require('data.zone_names_ja');
local map_position = require('map_position');
local debug_view   = require('debug_view');
local presentation = require('presentation');
local tracking     = require('area_tracking').new(map_position.new(ashita.memory));
local catalog      = require('map_catalog');
local editor       = require('boundary_editor').new(catalog, addon.path .. 'data/boundary_overrides.txt');
editor.reader = tracking.reader;
local editor_revision = 0;
local next_render_error = 0;

local ZONE_IN_PACKET = 0x00A;
-- The weather in memory can still be the last zone's just after zoning: a change this soon after
-- is taken as the banner catching up, not as the weather turning.
local WEATHER_SETTLE = 10.0;

local state = {
    last_zone = nil,
    weather_ptr = 0,
    visible_until = 0,
    started_at = nil,
    next_sample = 0,
    title = '',
    zone_title = '',
    banner_is_area = false,
    region = '',
    weather = '',
    weather_id = nil,
    weather_quiet_until = 0,
    weather_pending = false,
    next_weather = 0,
    banner_is_weather = false,
    flag = nil,
    zone_ja = nil,
    region_ja = nil,
    style_override = nil,
};

local weather_fallback = {
    [0] = 'Clear',
    [1] = 'Sunshine',
    [2] = 'Clouds',
    [3] = 'Fog',
    [4] = 'Fire',
    [5] = 'Fire x2',
    [6] = 'Water',
    [7] = 'Water x2',
    [8] = 'Earth',
    [9] = 'Earth x2',
    [10] = 'Wind',
    [11] = 'Wind x2',
    [12] = 'Ice',
    [13] = 'Ice x2',
    [14] = 'Thunder',
    [15] = 'Thunder x2',
    [16] = 'Light',
    [17] = 'Light x2',
    [18] = 'Dark',
    [19] = 'Dark x2',
};

local zone_to_region = {};
local region_names = {};
local region_names_ja = {};

local function build_region_lookup()
    for _, r in ipairs(regions) do
        region_names[r.id] = r.en;
        region_names_ja[r.id] = r.ja;
    end

    for region_id, zones in pairs(rz.map) do
        for _, zone_id in ipairs(zones) do
            zone_to_region[zone_id] = region_id;
        end
    end
end

-- Read every frame: made once, so no function is made each time.
local function read_zone()
    return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
end

local function get_zone_id()
    local ok, zone = pcall(read_zone);

    if (ok and zone ~= nil and zone > 0) then
        return zone;
    end

    return 0;
end

local function get_zone_name(zone)
    if (zone == nil or zone <= 0) then
        return 'Unknown Zone';
    end

    local ok, name = pcall(function()
        return AshitaCore:GetResourceManager():GetString('zones.names', zone);
    end);

    if (ok and name ~= nil and name ~= '') then
        return name;
    end

    return ('Zone %d'):format(zone);
end

local function get_region_name(zone)
    local region_id = zone_to_region[zone or 0];
    return region_id ~= nil and (region_names[region_id] or ('Region %d'):format(region_id)) or 'Unknown Region';
end

local function get_weather_id()
    if (state.weather_ptr == 0) then
        return nil;
    end

    local ok, ptr = pcall(function()
        return ashita.memory.read_uint32(state.weather_ptr + 0x02);
    end);

    if (not ok or ptr == nil or ptr == 0) then
        return nil;
    end

    ok, ptr = pcall(function()
        return ashita.memory.read_uint8(ptr + 0);
    end);

    return ok and ptr or nil;
end

local function get_weather_name()
    local id = get_weather_id();
    if (id == nil) then
        return 'Unknown';
    end

    local ok, name = pcall(function()
        return AshitaCore:GetResourceManager():GetString('weather', id);
    end);

    if (ok and name ~= nil and name ~= '') then
        return name;
    end

    return weather_fallback[id] or ('Weather %d'):format(id);
end

-- The flag of the nation a zone's region belongs to, if it is one's own: see data/region_flags.lua.
local function get_flag(zone)
    return region_flags[zone_to_region[zone or 0] or -1];
end

-- The zone's and its region's names in the Japanese client, for the Kanji Watermark, and no
-- /zone test style carried over: set for every banner.
local function set_banner_names(zone)
    state.zone_ja = zone_names_ja[zone or 0];
    state.region_ja = region_names_ja[zone_to_region[zone or 0] or -1];
    state.style_override = nil;
end

local function show_zone(zone)
    state.last_zone = zone;
    state.title = get_zone_name(zone);
    state.zone_title = state.title;
    state.banner_is_area, state.banner_is_weather, state.area_preview = false, false, false;
    state.region = get_region_name(zone);
    state.weather_id, state.weather = get_weather_id(), get_weather_name();
    state.weather_pending, state.weather_quiet_until = false, os.clock() + WEATHER_SETTLE;
    state.flag = get_flag(zone);
    set_banner_names(zone);
    presentation.start(state, os.clock());
    tracking.announce_after = state.visible_until;
    if (presentation.chat_enabled()) then
        print(chat.header(addon.name):append(chat.message(('%s - %s - %s'):format(state.region, state.title, state.weather))));
    end
end

-- The map chosen for live detection is kept for each zone, in the character's settings.
local function apply_live_map(zone)
    local key = presentation.display().liveMaps['z' .. tostring(zone)];
    local map = key and catalog.maps[key];
    tracking.reader.live_map = map and map.zone_id == zone and key or nil;
end

local function save_live_map(zone)
    if (zone == nil or zone <= 0) then return; end
    local map = tracking.reader.live_map and catalog.maps[tracking.reader.live_map];
    presentation.display().liveMaps['z' .. tostring(zone)] = map and map.zone_id == zone and map.key or nil;
    presentation.save();
end

-- The approach distance is a setting: the slider, the command and another character's settings all
-- arrive here, and membership starts afresh with the new distance.
local function sync_approach()
    local distance = presentation.display().approachYalms[1];
    if (tracking.state.approach_yalms == distance) then return; end
    tracking.state.approach_yalms = distance;
    local quiet_until = tracking.quiet_until;
    tracking:reset(os.clock());
    tracking.quiet_until = math.max(tracking.quiet_until, quiet_until);
    state.next_sample = 0;
    if (state.banner_is_area) then state.visible_until = 0; end
end

local function check_zone_changed(force)
    local zone = get_zone_id();
    if (zone <= 0) then
        if (state.last_zone ~= nil) then
            state.last_zone, state.visible_until = nil, 0;
            tracking:set_zone(0, os.clock());
        end
        return;
    end

    if (zone ~= state.last_zone) then
        tracking:set_zone(zone, os.clock());
        apply_live_map(zone);
        state.next_sample = 0;
        show_zone(zone);
    elseif (force) then
        show_zone(zone);
    end
end

presentation.on_preview = function() check_zone_changed(true); end;
presentation.on_settings = function()
    state.visible_until, state.started_at, state.banner_timing, state.line_timing = 0, nil, nil, nil; -- Never show a previous character's banner.
    apply_live_map(get_zone_id());
end;

local function message(text, is_error)
    print(chat.header(addon.name):append(is_error and chat.error(text) or chat.message(text)));
end

local function show_area(area)
    state.title = area.name;
    state.zone_title = get_zone_name(state.last_zone);
    state.banner_is_area, state.banner_is_weather, state.area_preview = true, false, false;
    state.region, state.weather = get_region_name(state.last_zone), get_weather_name();
    state.flag = get_flag(state.last_zone);
    set_banner_names(state.last_zone);
    presentation.start(state, os.clock());
    if (presentation.chat_enabled()) then
        message(('Sub-zone: %s - %s - %s - %s'):format(state.title, state.zone_title, state.region, state.weather));
    end
end

presentation.on_area_preview = function()
    state.last_zone = get_zone_id();
    show_area(tracking.state.area or { name = 'Example Sub-zone' });
    state.area_preview = true;
end;

local function show_weather()
    state.title = 'Weather: ' .. state.weather;
    state.zone_title = get_zone_name(state.last_zone);
    state.banner_is_area, state.banner_is_weather, state.area_preview = false, true, false;
    state.region = get_region_name(state.last_zone);
    state.flag = get_flag(state.last_zone);
    set_banner_names(state.last_zone);
    presentation.start(state, os.clock());
    if (presentation.chat_enabled()) then
        message(('Weather: %s - %s'):format(state.weather, state.zone_title));
    end
end

presentation.on_weather_preview = function()
    state.last_zone = get_zone_id();
    state.weather = get_weather_name();
    show_weather();
end;

-- Once a second: a change of weather inside a zone is shown in the banner that is up, and gets a
-- popup of its own once that banner has gone.
local function poll_weather(now)
    if (now < state.next_weather) then return; end
    state.next_weather = now + 1.0;
    if (state.last_zone == nil) then return; end
    local id = get_weather_id();
    if (id ~= nil and id ~= state.weather_id) then
        local seeded = state.weather_id ~= nil;
        state.weather_id, state.weather = id, get_weather_name();
        if (state.banner_is_weather) then state.title = 'Weather: ' .. state.weather; end
        -- The first reading, and one just after zoning, only bring the banner up to date.
        state.weather_pending = seeded and now >= state.weather_quiet_until;
    end
    if (not state.weather_pending) then return; end
    if (not presentation.weather_enabled()) then state.weather_pending = false; return; end
    if (state.started_at ~= nil and state.visible_until > now) then return; end
    state.weather_pending = false;
    show_weather();
end

local function poll_areas(force)
    local now = os.clock();
    if (not force and now < state.next_sample) then return; end
    state.next_sample = now + 0.25;
    local area_popups = (not force and presentation.area_enabled());
    -- The location line names the sub-zone, so it samples as the debug window does: without announcing.
    local location = (not force and presentation.location_enabled());
    if (not force and not area_popups and not location and not tracking.state.debug) then return; end
    local was_debug, was_enabled = tracking.state.debug, tracking.state.enabled;
    if (force or location) then tracking.state.debug = true; end
    if (area_popups) then tracking.state.enabled = true; end
    local position = map_position.player_position();
    local area = tracking:sample(state.last_zone or 0, position, now);
    tracking.state.debug, tracking.state.enabled = was_debug, was_enabled;
    if (area) then show_area(area); end
    if (state.banner_is_area and not state.area_preview and not tracking.state.area) then state.visible_until = 0; end
end

-- 'Zone - Sub-zone' for the location line, made again only when either changes.
local location = { zone = nil, area = nil, words = '' };
local function location_words()
    local zone, area = state.last_zone, tracking.state.area and tracking.state.area.name or nil;
    if (zone == nil or zone <= 0) then return nil; end
    if (location.zone ~= zone or location.area ~= area) then
        location.zone, location.area = zone, area;
        location.words = area and ('%s - %s'):format(get_zone_name(zone), area) or get_zone_name(zone);
    end
    return location.words;
end

local function sample_report()
    check_zone_changed(false);
    poll_areas(true);
    local s = tracking.state;
    message(('Sample zone=%d | map=%s | approach=%.0f yalms | %s'):format(s.zone, s.map_key or 'unresolved', s.approach_yalms, s.error or 'experimental alignment'));
    if (s.position) then
        message(('World X=%.3f Y=%.3f Z(height)=%.3f'):format(s.position.x, s.position.y, s.position.z));
    end
    if (s.entry and s.map_x) then
        message(('Map floor=%d scale=%.3f offset=(%.3f, %.3f) pixel512=(%.3f, %.3f)'):format(
            s.entry.floor_id, s.entry.scale, s.entry.offset_x, s.entry.offset_y, s.map_x, s.map_y));
        message(('Candidate=%s | stable=%s | %s'):format(s.raw_area and s.raw_area.name or 'unlabelled',
            s.area and s.area.name or 'unlabelled', s.entry.source));
    end
end

ashita.events.register('load', 'zone_load', function()
    local loaded, err = editor:load();
    if (not loaded) then message('Boundary overrides not loaded: ' .. tostring(err), true); end
    editor_revision = editor.revision;
    build_region_lookup();

    state.weather_ptr = ashita.memory.find('FFXiMain.dll', 0, '66A1????????663D????72', 0, 0);
    if (state.weather_ptr == 0) then
        print(chat.header(addon.name):append(chat.error('Weather signature scan failed; weather will show as Unknown.')));
    end

    -- Seed the current zone without popping the banner on addon load.
    state.last_zone = get_zone_id();
    tracking:set_zone(state.last_zone, os.clock(), 0);
    tracking.state.approach_yalms = presentation.display().approachYalms[1];
    apply_live_map(state.last_zone);
    message('Use /zone for sub-zone popups and display settings, or /zone debug on to check alignment.');
end);

ashita.events.register('packet_in', 'zone_packet_in', function(e)
    if (e.id == ZONE_IN_PACKET) then
        -- Do not classify stale coordinates during zone-in, including same-zone reloads.
        -- The frame poll remains responsible for reading the updated zone ID and its banner.
        tracking:set_zone(state.last_zone or 0, os.clock(), 1.25);
        state.visible_until, state.next_sample = 0, 0;
        state.weather_pending, state.weather_quiet_until = false, os.clock() + WEATHER_SETTLE;
    end
end);

-- The banner and the location line, drawn each frame inside xpcall: made once.
local function draw_banners()
    presentation.draw(state, tracking.state, os.clock());
    presentation.draw_location(location_words());
end

ashita.events.register('d3d_present', 'zone_present', function()
    presentation.begin_frame();
    check_zone_changed(false);
    sync_approach();
    poll_weather(os.clock());
    poll_areas(false);
    debug_view.draw(tracking.state, editor);
    local edited = editor.revision ~= editor_revision;
    editor_revision = editor.revision;
    local live_key = tracking.state.map_key or (catalog[state.last_zone] and catalog[state.last_zone].key);
    if (editor.live_map_changed or (edited and editor.changed_map == live_key)) then
        if (editor.live_map_changed) then save_live_map(state.last_zone); end
        editor.live_map_changed = false;
        local quiet_until = tracking.quiet_until;
        tracking:reset(os.clock());
        tracking.quiet_until = math.max(quiet_until, tracking.quiet_until);
        state.next_sample = 0;
        if (state.banner_is_area) then state.visible_until = 0; end
    end

    local ok, err = xpcall(draw_banners, debug.traceback);
    if (not ok and os.clock() >= next_render_error) then
        next_render_error = os.clock() + 10;
        message('Banner render failed: ' .. tostring(err), true);
    end
end);

ashita.events.register('command', 'zone_command', function(e)
    local args = e.command:args();
    if (#args == 0 or args[1]:lower() ~= '/zone') then return; end
    e.blocked = true;
    local command = args[2] and args[2]:lower() or '';
    if (command == '') then
        presentation.toggle_config();
    elseif (command == 'test') then
        local style = args[3] and args[3]:lower();
        if (style and not presentation.valid_style(style)) then
            message('Usage: /zone test [classic|titlecard|pennant|kanji]', true);
            return;
        end
        check_zone_changed(true);
        state.style_override = style;
    elseif (command == 'reload' or command == 'rl') then
        if (presentation.reload()) then
            message('Display settings reloaded.'); check_zone_changed(true);
        else message('Settings reload is unavailable in this environment.', true); end
    elseif (command == 'poc' or command == 'debug') then
        local field = command == 'poc' and 'enabled' or 'debug';
        local mode = args[3] and args[3]:lower();
        if (mode and mode ~= 'on' and mode ~= 'off') then
            message(('Usage: /zone %s [on|off]'):format(command), true);
            return;
        end
        tracking.state[field] = mode == 'on' or (not mode and not tracking.state[field]);
        if (command == 'poc' or not tracking.state.enabled) then tracking:reset(os.clock()); end
        tracking.announce_after = math.max(os.clock(), state.visible_until);
        state.next_sample = 0;
        if (not tracking.state.enabled and state.banner_is_area) then state.visible_until = 0; end
        message(('%s: %s (unverified map alignment/boundaries).'):format(command, tracking.state[field] and 'ON' or 'OFF'));
    elseif (command == 'approach') then
        local distance = tonumber(args[3]);
        if (not distance or distance ~= distance or distance < 0 or distance > 100) then
            message('Usage: /zone approach <0..100 yalms> (default 30; 0 restores feature-only detection).', true);
            return;
        end
        presentation.display().approachYalms[1] = distance;
        sync_approach();
        presentation.save();
        message(('Approach buffer: %.0f yalms around each feature (saved).'):format(distance));
    elseif (command == 'sample' or command == 'status') then
        sample_report();
    elseif (command == 'livemap') then
        local key = args[3];
        if (key == 'auto') then
            tracking.reader.live_map = nil;
        elseif (key and catalog.maps[key] and catalog.maps[key].zone_id == get_zone_id()) then
            tracking.reader.live_map = key;
        else
            message('Use the debug window live-map button, or /zone livemap auto. A live override must belong to the current zone.', true);
            return;
        end
        save_live_map(get_zone_id());
        tracking:reset(os.clock());
        state.next_sample = 0;
        message('Live map selection updated and saved for this zone; browsing remains independent.');
    elseif (command == 'transform') then
        local zone = get_zone_id();
        local forced = tracking.reader.live_map and catalog.maps[tracking.reader.live_map];
        local map_key = forced and forced.zone_id == zone and forced.key or nil;
        map_key = map_key or (tracking.state.zone == zone and tracking.state.map_key) or (catalog[zone] and catalog[zone].key);
        if (args[3] == 'reset') then
            tracking.reader.overrides[map_key or ''] = nil;
            tracking.reader:refresh();
            tracking:reset(os.clock());
            state.next_sample = 0;
            message('Transform override cleared; retrying the client map table.');
        else
            local scale, ox, oy = tonumber(args[3]), tonumber(args[4]), tonumber(args[5]);
            if (not tracking.reader:set_override(zone, scale, ox, oy, map_key)) then
                message('Usage in a mapped zone: /zone transform <scale> <offset_x> <offset_y> (or transform reset).', true);
                return;
            end
            tracking:reset(os.clock());
            state.next_sample = 0;
            message('Session-only manual transform set; verify alignment at several separated landmarks.');
        end
    else
        message('/zone [test [style]|reload] | poc [on|off] | debug [on|off] | approach <0..100 yalms> | sample | livemap auto | transform <scale> <offset_x> <offset_y> | transform reset');
    end
end);

ashita.events.register('unload', 'zone_unload', function()
    presentation.shutdown();
    editor:cancel();
    if (editor:dirty()) then message('Unsaved boundary edits discarded. Use Save Boundaries in the debug window to persist them.'); end
    debug_view.clear();
end);
