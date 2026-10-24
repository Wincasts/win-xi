-- zone's cost a frame, offline: Lua time, Lua memory allocated and imgui calls for each kind of frame
-- the addon draws (nothing up, the location line, a banner in each style). Not the game's frame time:
-- imgui and the game are stand-ins here, so only the addon's own Lua work is measured.
--
--   luajit tests/harness.lua zone tests/zoneinfo_fixture.lua tools/benchmark_zone_frames.lua
local ffi = require('ffi');
ffi.cdef('typedef struct { long tv_sec; long tv_nsec; } bench_timespec; int clock_gettime(int, bench_timespec *);');
local ts = ffi.new('bench_timespec');
local function now_us() ffi.C.clock_gettime(1, ts); return tonumber(ts.tv_sec) * 1e6 + tonumber(ts.tv_nsec) / 1e3; end

-- The harness's imgui makes a new function each time one is asked for, which would be counted as the
-- addon's; keep each once made, as the game's are.
local imgui = require('imgui');
local function keep(t)
    local mt = getmetatable(t);
    local index = mt.__index;
    mt.__index = function(self, k) local f = index(self, k); rawset(self, k, f); return f; end;
end
keep(imgui);
keep(imgui.GetBackgroundDrawList());

-- A Japanese font, for the Kanji Watermark to draw its watermark.
imgui.AddFontFromFileTTF = function(path) return { path = path }; end;
local p = require('presentation');
local d = p.app.options.display;
package.loaded['ffxi.time'] = { get_game_time_raw = function() return 0; end, get_game_weekday = function() return 0; end,
    get_game_hours = function() return 14; end, get_game_minutes = function() return 20; end };

local function total_calls()
    local n = 0;
    for _, count in pairs(H.calls) do n = n + count; end
    return n;
end

local FRAMES = 2000;
local results = {};
-- run: how the frames go by, H.frames unless given
local function measure(label, setup, run)
    run = run or H.frames;
    if setup then setup(); end
    run(200); -- warm: caches filled, traces compiled
    collectgarbage('collect');
    collectgarbage('stop');
    local before, calls, t = collectgarbage('count'), total_calls(), now_us();
    run(FRAMES);
    local elapsed = now_us() - t;
    local allocated = (collectgarbage('count') - before) * 1024;
    calls = total_calls() - calls;
    collectgarbage('restart');
    results[#results + 1] = { label, elapsed / FRAMES, allocated / FRAMES, calls / FRAMES };
end

-- Nothing up: the popups on, standing still, after any popup has gone (each lasts 6 s, 200 frames).
measure('idle: nothing up', function() d.locationEnabled[1] = false; H.frames(400); end);
measure('location line', function() d.locationEnabled[1] = true; end);
d.locationEnabled[1] = false;

-- A banner kept up for the whole measurement: a long hold, shown again before each.
d.hold[1], d.fadeIn[1], d.fadeOut[1] = 60, .2, 1;
local function banner(style)
    return function()
        d.zoneStyle = style;
        H.command('/zone test');
        H.frames(40); -- past the entrance
    end;
end

measure('banner: Classic Text', banner('classic'));
measure('banner: Title Card', banner('titlecard'));
measure('banner: Pennant', banner('pennant'));
measure('banner: Kanji Watermark', banner('kanji'));
measure('banner: Letter Reveal', banner('reveal'));
measure('banner: Classic Window', banner('window'));
measure('banner: Elemental Weather', banner('element'));
measure('banner: Kind Frames (open country)', banner('kind'));
measure('banner: Nation Seal', banner('seal'));
measure('banner: Atlas Cartouche (no map)', banner('atlas'));
measure('banner: Edge Toast', banner('toast'));
-- The harness's zone is West Ronfaure (100, open country): Southern San d'Oria (230) a city, Davoi (149) a dungeon.
local game = H.zoneinfo_game;
measure('banner: Kind Frames (city)', function() game.zone = 230; H.frames(1); banner('kind')(); end);
measure('banner: Kind Frames (dungeon)', function() game.zone = 149; H.frames(1); banner('kind')(); end);
game.zone = 100; H.frames(1);
-- The entrance: shown again every 50 frames (1.5 s), so every frame is in its first second and a half.
local function entrances(count)
    for i = 1, count do
        if i % 50 == 1 then H.command('/zone test'); end
        H.frames(1);
    end
end
measure('banner: Title Card entrance', function() d.zoneStyle = 'titlecard'; end, entrances);
measure('banner: Pennant entrance', function() d.zoneStyle = 'pennant'; end, entrances);
measure('banner: Kanji Watermark entrance', function() d.zoneStyle = 'kanji'; end, entrances);
measure('banner: Letter Reveal entrance', function() d.zoneStyle = 'reveal'; end, entrances);
measure('banner: Classic Window entrance', function() d.zoneStyle = 'window'; end, entrances);
measure('banner: Elemental Weather entrance', function() d.zoneStyle = 'element'; end, entrances);
measure('banner: Kind Frames entrance', function() d.zoneStyle = 'kind'; end, entrances);
measure('banner: Nation Seal entrance', function() d.zoneStyle = 'seal'; end, entrances);
measure('banner: Edge Toast entrance', function() d.zoneStyle = 'toast'; end, entrances);
d.locationEnabled[1], d.locationStyle = true, 'breadcrumb';
measure('location line: Breadcrumb', function() d.zoneStyle = 'classic'; end);
d.locationEnabled[1], d.locationStyle = false, 'plain';

-- What each style asks of imgui in a settled frame, by name: BENCH_CALLS=1 to see it.
if os.getenv('BENCH_CALLS') then
    for _, style in ipairs(require('banner_styles').ids) do
        banner(style)();
        local before = {};
        for k, v in pairs(H.calls) do before[k] = v; end
        H.frames(1);
        local parts = {};
        for k, v in pairs(H.calls) do if v ~= (before[k] or 0) then parts[#parts + 1] = ('%s %d'):format(k, v - (before[k] or 0)); end end
        table.sort(parts);
        H.print(style .. ': ' .. table.concat(parts, ', '));
    end
end

H.print(('%-44s %10s %12s %12s'):format('frame', 'us/frame', 'bytes/frame', 'calls/frame'));
for _, r in ipairs(results) do
    H.print(('%-44s %10.2f %12.0f %12.1f'):format(r[1], r[2], r[3], r[4]));
end
