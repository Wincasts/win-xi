addon.name    = 'perf';
addon.author  = 'win';
addon.version = '0.2';
addon.desc    = 'What each addon costs a frame: the time its event handlers take, live, with a mark to compare a change of settings against.';

local winxiNeeded = 65; -- winxi.widgets' described rows
do
    local ok, found = pcall(require, 'winxi.version');
    local number = ok and type(found) == 'table' and found.Number or 0;
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
        print('[perf] ' .. text);
        error(text, 0);
    end
end

require('common');
local imgui = require('imgui');
local shell = require('winxi.shell');
local widgets = require('winxi.widgets');
local tooltip = require('winxi.tooltip');
local perf = require('winxi.perf');

local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    sampleWindow = T{ 2 },      -- seconds between readings
    showIdle = T{ false },      -- addons that cost nothing in the window, and ones not heard from
    showPackets = T{ true },    -- the packet columns
    locked = T{ false },
};

local app;
local IDLE_AFTER = 3;           -- seconds without a handler call before an addon counts as idle

---------------------------------------------------------------------------------------------------
-- Readings
---------------------------------------------------------------------------------------------------

local last = {};                -- by name: the row as it was at the last reading
local lastAt, frames = nil, 0;  -- when the last reading was taken, and the frames since
local frameAt, frameSum, frameCount = nil, 0, 0;   -- present-to-present time, summed over the window
local readings = {};            -- by name: { present, max, packetsMs, packetsPerSecond, other, total, touched }
local order = {};               -- the names, costliest first
local frame = { ms = 0, fps = 0, addons = 0 };   -- the window's frame time, rate and all addons' share of it
local mark, markLabel = nil, nil;   -- the readings kept to compare against, and what they were called

local function Delta(now, before)
    if not before or now < before then return now; end   -- the addon loaded again: its sums started over
    return now - before;
end

local function Read(now)
    local seconds = lastAt and (now - lastAt) or 0;
    if frames == 0 or seconds <= 0 then return; end
    local fresh, names = {}, {};
    for _, row in ipairs(perf.Rows()) do
        local before = last[row.name];
        if before and before.generation ~= row.generation then before = nil; end
        local us, calls, maxus = {}, {}, 0;
        for slot = 1, 7 do
            local event = row.events[slot];
            us[slot] = Delta(event.us, before and before.events[slot].us);
            calls[slot] = Delta(event.calls, before and before.events[slot].calls);
            if event.maxus > maxus then maxus = event.maxus; end
        end
        local present = us[1] / 1000 / frames;
        local packetsMs = (us[2] + us[3]) / 1000 / frames;
        local other = (us[4] + us[5] + us[6] + us[7]) / 1000 / frames;
        fresh[row.name] = {
            present = present, max = maxus / 1000, packetsMs = packetsMs, packetsPerSecond = (calls[2] + calls[3]) / seconds,
            other = other, total = present + packetsMs + other, touched = row.touched,
        };
        names[#names + 1] = row.name;
        last[row.name] = row;
    end
    table.sort(names, function(a, b)
        if fresh[a].total ~= fresh[b].total then return fresh[a].total > fresh[b].total; end
        return a < b;
    end);
    readings, order = fresh, names;
    frame.ms = frameCount > 0 and frameSum / frameCount or 0;
    frame.fps = frame.ms > 0 and 1000 / frame.ms or 0;
    local sum = 0;
    for _, name in ipairs(names) do sum = sum + fresh[name].total; end
    frame.addons = sum;
    frameSum, frameCount = 0, 0;
end

local function Frame()
    local now = perf.Seconds();
    frames = frames + 1;
    if frameAt then frameSum, frameCount = frameSum + (now - frameAt) * 1000, frameCount + 1; end
    frameAt = now;
    if not lastAt then lastAt = now; frames = 0; return; end
    if now - lastAt >= app.options.sampleWindow[1] then
        Read(now);
        lastAt, frames = now, 0;
    end
end

---------------------------------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------------------------------

local function Ms(value) return ('%.2f'):format(value); end

local function Draw(options)
    local now = perf.Seconds();
    imgui.Text(('Frame %s ms (%d fps)   Addons %s ms, %d%% of it'):format(Ms(frame.ms), math.floor(frame.fps + 0.5), Ms(frame.addons),
        frame.ms > 0 and math.floor(frame.addons / frame.ms * 100 + 0.5) or 0));
    tooltip.Hover('Over the last Sample Window: how long a frame took from one present to the next, and how much of it the addons\' handlers took between them. CPU time in the handlers only; what they draw is drawn by Ashita afterwards, and the GPU\'s time is not counted.');
    if mark then
        imgui.Text(('Compared with %s'):format(markLabel));
        tooltip.Hover('The numbers kept by /perf mark. Was is each addon then; Change is now against then.');
    end
    local columns = 5 + (options.showPackets[1] and 2 or 0) + (mark and 2 or 0);
    if not imgui.BeginTable('perf.addons', columns, bit.bor(ImGuiTableFlags_SizingFixedFit, ImGuiTableFlags_RowBg)) then return; end
    imgui.TableSetupColumn('Addon', ImGuiTableColumnFlags_WidthFixed);
    imgui.TableSetupColumn('Present', ImGuiTableColumnFlags_WidthFixed);
    imgui.TableSetupColumn('Longest', ImGuiTableColumnFlags_WidthFixed);
    if options.showPackets[1] then
        imgui.TableSetupColumn('Packets', ImGuiTableColumnFlags_WidthFixed);
        imgui.TableSetupColumn('Packets/s', ImGuiTableColumnFlags_WidthFixed);
    end
    imgui.TableSetupColumn('Other', ImGuiTableColumnFlags_WidthFixed);
    imgui.TableSetupColumn('Total', ImGuiTableColumnFlags_WidthFixed);
    if mark then
        imgui.TableSetupColumn('Was', ImGuiTableColumnFlags_WidthFixed);
        imgui.TableSetupColumn('Change', ImGuiTableColumnFlags_WidthFixed);
    end
    imgui.TableHeadersRow();
    local shown = 0;
    for _, name in ipairs(order) do
        local reading = readings[name];
        local idle = reading.total == 0 or (now - reading.touched) > IDLE_AFTER;
        if not idle or options.showIdle[1] then
            shown = shown + 1;
            imgui.TableNextRow();
            imgui.TableNextColumn(); imgui.Text(name);
            imgui.TableNextColumn(); imgui.Text(Ms(reading.present));
            imgui.TableNextColumn(); imgui.Text(Ms(reading.max));
            if options.showPackets[1] then
                imgui.TableNextColumn(); imgui.Text(Ms(reading.packetsMs));
                imgui.TableNextColumn(); imgui.Text(('%d'):format(reading.packetsPerSecond + 0.5));
            end
            imgui.TableNextColumn(); imgui.Text(Ms(reading.other));
            imgui.TableNextColumn(); imgui.Text(Ms(reading.total));
            if mark then
                local was = mark[name];
                imgui.TableNextColumn(); imgui.Text(was and Ms(was.total) or '-');
                imgui.TableNextColumn(); imgui.Text(was and ('%+.2f'):format(reading.total - was.total) or '-');
            end
        end
    end
    imgui.EndTable();
    if shown == 0 then imgui.Text('Nothing yet: the first reading comes after the Sample Window.'); end
end

---------------------------------------------------------------------------------------------------
-- Settings and commands
---------------------------------------------------------------------------------------------------

local function Save() app:Save(); end

local lockSpec = { onChanged = Save };

local function DrawSettings(options)
    if widgets.Header('Window', true) then
        widgets.Check('Visible', 'Shows the table of readings. /perf switches it too.', options.isVisible, '##perf.visible');
        widgets.Lock(options.locked, '##perf.locked', lockSpec);
        if widgets.Numbers('Position', 'Where the window\'s corner is on the screen.', options.pos, '##perf.position') then
            imgui.SetWindowPos('perf.window', options.pos);
            Save();
        end
    end
    if widgets.Header('Readings') then
        local _, done = widgets.Slider('Sample Window', 'How many seconds each reading covers. Longer is steadier, shorter follows a change sooner.',
            options.sampleWindow, 1, 10, '##perf.sampleWindow', widgets.Seconds);
        if done then Save(); end
        if widgets.Check('Show Idle Addons', 'Lists addons that cost nothing, or have done nothing for three seconds.', options.showIdle, '##perf.showIdle') then Save(); end
        if widgets.Check('Show Packet Columns', 'Adds the time spent on packets a frame, and how many packets a second.', options.showPackets, '##perf.showPackets') then Save(); end
    end
    if next(readings) == nil then
        widgets.Status('Nothing read yet. The first reading comes after the Sample Window.');
    elseif mark then
        widgets.Status(('%d addons read, compared with %s.'):format(#order, markLabel));
    else
        widgets.Status(('%d addons read.'):format(#order));
    end
end

local function Mark(options, args)
    local words = {};
    for i = 3, #args do words[#words + 1] = args[i]; end
    local label = table.concat(words, ' ');
    if label:lower() == 'clear' then
        mark, markLabel = nil, nil;
        print('[perf] The mark is forgotten.');
        return;
    end
    if next(readings) == nil then print('[perf] Nothing to mark yet: the first reading comes after the Sample Window.'); return; end
    mark = {};
    for name, reading in pairs(readings) do mark[name] = { total = reading.total }; end
    markLabel = label ~= '' and label or os.date('%H:%M:%S');
    print(('[perf] Marked as %s: change a setting and the Change column says what it costs.'):format(markLabel));
end

local function Reset()
    perf.ResetMax();
    print('[perf] The longest calls start over.');
end

app = shell.New({
    defaults = defaults,
    window = 'perf.window',
    title = 'Perf',
    configTitle = 'Perf Settings',
    command = '/perf',
    help = '/perf shows or hides the window; /perf mark [name] keeps this moment\'s numbers to compare against, /perf mark clear forgets them; /perf reset starts the longest calls over; /perf config opens the settings.',
    drawSettings = DrawSettings,
    commands = { mark = Mark, reset = Reset },
});

ashita.events.register('d3d_present', 'perf_present', function()
    Frame();
    if not app:BeginFrame() then return end
    app:Window(app.options.isVisible, Draw, { locked = app.options.locked[1] or nil, clickThrough = app.options.locked[1] or nil });
end);
