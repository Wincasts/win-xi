-- What name has been doing, kept for testers to send in: why the names it draws stopped, if they
-- did, and a short history of what happened around it. Off unless turned on, with /name diag:
-- while off, nothing is kept, said or written but what diag.Write is asked for.
--
--   diag.Enabled(), diag.Enable(on)
--   diag.Frame(reason, detail)  each frame: nil while the names are drawn, or why they were not, a
--                             key of diag.Reasons; detail, if any, what was said of it (imgui's
--                             answers for the font texture), kept as the latest of the pause
--   diag.Error(message)       a Lua error in the frame, with its traceback; the same one is kept once,
--                             with a count
--   diag.Note(text, ...)      a line for the history, formatted as string.format would
--   diag.Status()             a sentence for the settings: drawing, or paused and why
--   diag.Write(why)           writes a log file, and returns its path or nil and why not
--   diag.LastPath()           the last file written, or nil
--
-- The plugin draws the game's names again when a claim is not made for HOOK_CLAIM_FRAMES (30)
-- frames. A pause shorter than that is not seen and is only counted; a longer one is put in the
-- history, said once in the chat log, and written to a file of its own, once a session for each reason.
-- Logs go to config\addons\name\logs.
local bit = require('bit');
local ffi = require('ffi');
local imgui = require('imgui');
local fonts = require('winxi.fonts');
local nameplates = require('winxi.nameplates');

local diag = {};

diag.Reasons = {
    unloaded = 'the namehook plugin is not loaded',
    old      = 'the namehook plugin has no block this addon can read',
    mismatch = 'the namehook plugin and this addon are of different versions',
    unhooked = 'the namehook plugin did not recognise this client\'s name drawing',
    texture  = 'imgui\'s font texture was not ready, or could not be read',
    draw     = 'the namehook plugin had no drawing buffer',
    error    = 'a Lua error in the frame',
    off      = 'Custom Nameplates is off, in General',
};

local SEEN_AFTER = 30;    -- frames: the plugin's HOOK_CLAIM_FRAMES, after which the game's names are back
local HISTORY    = 300;   -- lines kept

local history = {};
local historyStart = 1;   -- the oldest line, once the history has wrapped
local frame = 0;
local loadedAt = os.clock();

local reason = nil;       -- why the names are not drawn, or nil while they are
local detail = nil;       -- what was said of it, the latest
local since = 0;          -- the frame that started
local sinceClock = 0;
local seen = false;       -- whether this pause has lasted long enough to be seen
local counts = {};        -- reason -> { blips = pauses too short to be seen, seen = longer ones, frames = all their frames }
local told = {};          -- reason -> true once said in the chat log and written this session
local errors = {};        -- message -> { count, traceback, first, last }
local errorOrder = {};
local lastPath = nil;
local zone = nil;
local enabled = false;

local function stamp()
    return ('%s %8.2f f%d'):format(os.date('%H:%M:%S'), os.clock() - loadedAt, frame);
end

function diag.Enabled()
    return enabled;
end

-- Notes the change while on, so the history says when it began and ended
function diag.Enable(on)
    on = on and true or false;
    if (on == enabled) then
        return;
    end
    if (on) then
        enabled = true;
        reason, detail, seen = nil, nil, false; -- what was not watched is not counted
        diag.Note('Diagnostics on, name %s', addon.version);
    else
        diag.Note('Diagnostics off');
        enabled = false;
    end
end

function diag.Note(text, ...)
    if (not enabled) then
        return;
    end
    local line = stamp() .. '  ' .. ((select('#', ...) > 0) and text:format(...) or text);
    if (#history < HISTORY) then
        history[#history + 1] = line;
    else
        history[historyStart] = line;
        historyStart = historyStart % HISTORY + 1;
    end
end

-- The reason, in words, with what was said of it
local function Describe()
    local words = diag.Reasons[reason] or tostring(reason);
    if (detail ~= nil) then
        return ('%s (%s)'):format(words, detail);
    end
    return words;
end

local function count(key)
    local known = counts[key];
    if (known == nil) then
        known = { blips = 0, seen = 0, frames = 0 };
        counts[key] = known;
    end
    return known;
end

local function finish()
    local known = count(reason);
    local frames = frame - since;
    known.frames = known.frames + frames;
    if (seen) then
        diag.Note('Custom names back after %d frames (%.1fs); they had stopped: %s', frames, os.clock() - sinceClock, Describe());
    else
        known.blips = known.blips + 1;
    end
end

function diag.Frame(now, said)
    if (not enabled) then
        return;
    end
    frame = frame + 1;
    if (now == reason) then
        if (said ~= nil) then detail = said; end
        if (reason ~= nil and not seen and frame - since >= SEEN_AFTER) then
            seen = true;
            count(reason).seen = count(reason).seen + 1;
            diag.Note('Custom names stopped, the game draws its own: %s', Describe());
            -- one the player chose is not worth a word or a file
            if (reason ~= 'unloaded' and reason ~= 'off' and not told[reason]) then
                told[reason] = true;
                local path = diag.Write('custom names stopped: ' .. reason .. (detail ~= nil and (' (' .. detail .. ')') or ''));
                print(('\30\81[%s]\30\01 Custom names stopped: %s.%s'):format(addon.name, Describe(),
                    path and (' A log for the developers was written to ' .. path) or ''));
            end
        end
        return;
    end

    if (reason ~= nil) then
        finish();
    end
    reason, detail, since, sinceClock, seen = now, said, frame, os.clock(), false;
end

function diag.Error(message, traceback)
    if (not enabled) then
        return;
    end
    message = tostring(message);
    local known = errors[message];
    if (known == nil) then
        known = { count = 0, traceback = traceback, first = stamp() };
        errors[message] = known;
        errorOrder[#errorOrder + 1] = message;
        diag.Note('Lua error: %s', message);
    end
    known.count = known.count + 1;
    known.last = stamp();
end

function diag.Status()
    if (reason == nil) then
        return 'Drawing';
    end
    return ('%s for %.1fs: %s'):format(seen and 'Stopped' or 'Pausing', os.clock() - sinceClock, Describe());
end

function diag.LastPath()
    return lastPath;
end

-- the area entered, from the packet that says so
ashita.events.register('packet_in', 'name_diag_packet', function (e)
    if (e.id == 0x00A) then
        zone = struct.unpack('H', e.data, 0x30 + 1);
        diag.Note('Zone in: %d', zone);
    end
end);

-- What is known now, a line each; nothing here may stop the rest being written
local function try(lines, label, read)
    local ok, value = pcall(read);
    lines[#lines + 1] = ('%-22s %s'):format(label, ok and tostring(value) or ('(unreadable: ' .. tostring(value) .. ')'));
end

local function snapshot(lines)
    local party = function () return AshitaCore:GetMemoryManager():GetParty(); end;
    try(lines, 'Character', function () return party():GetMemberName(0); end);
    try(lines, 'Zone', function ()
        local id = party():GetMemberZone(0);
        return ('%d %s (last zone-in packet: %s)'):format(id, AshitaCore:GetResourceManager():GetString('zones.names', id) or '?', tostring(zone));
    end);
    try(lines, 'Plugin loaded', function () return AshitaCore:GetPluginManager():IsLoaded(nameplates.Plugin); end);

    local ok, hook, why = pcall(nameplates.Hook);
    if (not ok) then
        hook, why = nil, hook;
    end
    lines[#lines + 1] = ('%-22s %s'):format('Plugin block', hook ~= nil and 'found' or ('none: ' .. tostring(why)));
    if (hook ~= nil) then
        try(lines, 'Hooked', function () return hook.Hooked; end);
        try(lines, 'Frame / ClaimFrame', function ()
            return ('%d / %d (%d frames since the claim; it lapses after %d)'):format(hook.Frame, hook.ClaimFrame,
                bit.band(hook.Frame - hook.ClaimFrame, 0xFFFFFFFF), SEEN_AFTER);
        end);
        try(lines, 'Claimed', function () return ('0x%02X'):format(hook.Claimed); end);
        try(lines, 'Hidden / Options', function () return ('0x%02X / 0x%X'):format(hook.Hidden, hook.Options); end);
        try(lines, 'Names last frame', function () return hook.Count; end);
        try(lines, 'Window', function () return ('%.0f x %.0f'):format(hook.Width, hook.Height); end);
        try(lines, 'Game picture', function () return ('%.0f x %.0f'):format(hook.TargetWidth, hook.TargetHeight); end);
        try(lines, 'Drawing buffer', function ()
            if (hook.Draw == 0) then return 'none'; end
            local draw = ffi.cast('namehook_draw_t*', hook.Draw);
            return ('frame %d, %d quads of %d'):format(draw.Frame, draw.QuadCount, draw.QuadsMax);
        end);
        -- the texture the plugin read for the font's mark, as it last drew the names: 0 for none
        try(lines, 'Font texture drawn', function () return '0x' .. bit.tohex(hook.FontTexture); end);
        try(lines, 'Names', function ()
            local shown, custom, game = 0, 0, 0;
            for _, name in nameplates.Each() do
                if (nameplates.Has(name, nameplates.Flag.Wanted)) then shown = shown + 1; end
                if (nameplates.Has(name, nameplates.Flag.Custom)) then custom = custom + 1; end
                if (nameplates.Has(name, nameplates.Flag.Drawn)) then game = game + 1; end
            end
            return ('%d wanted, %d drawn by name, %d drawn by the game'):format(shown, custom, game);
        end);
    end

    try(lines, 'Display', function ()
        local size = imgui.GetIO().DisplaySize;
        return ('%.0f x %.0f'):format(size.x, size.y);
    end);
    try(lines, 'Font texture', function ()
        local texture, said = fonts.Texture();
        return texture ~= nil and ('ready (unique id %s): the plugin is given its mark'):format(tostring(said)) or said;
    end);
    try(lines, 'Font texture data', fonts.TextureDetail);
end

local function optionLines(lines, options)
    local keys = {};
    for key, value in pairs(options or {}) do
        if (type(value) ~= 'table' or (#value == 1 and type(value[1]) ~= 'table')) then
            keys[#keys + 1] = key;
        end
    end
    table.sort(keys);
    for _, key in ipairs(keys) do
        local value = options[key];
        if (type(value) == 'table') then value = value[1]; end
        lines[#lines + 1] = ('%-22s %s'):format(key, tostring(value));
    end
end

diag.Options = nil; -- set by name: the settings, to be written with the rest

local function makeFolder(path)
    for at = 1, #path do
        if (path:byte(at) == 92) then -- each folder on the way
            ashita.fs.create_directory(path:sub(1, at));
        end
    end
end

function diag.Write(why)
    -- the install path has a backslash at its end, or may not
    local install = tostring(AshitaCore:GetInstallPath()):gsub('[\\/]$', '');
    local folder = ('%s\\config\\addons\\%s\\logs\\'):format(install, addon.name);
    local path = folder .. ('name-%s.txt'):format(os.date('%Y%m%d-%H%M%S'));

    local lines = {
        ('name %s diagnostic log'):format(addon.version),
        ('Written %s, %.0fs after loading, frame %d: %s'):format(os.date('%Y-%m-%d %H:%M:%S'), os.clock() - loadedAt, frame, why or 'asked for'),
        ('Custom names: %s'):format(diag.Status()),
        ('Diagnostics: %s'):format(enabled and 'on' or 'off: only what is here now, no history'),
        '',
        '== Now',
    };
    snapshot(lines);

    lines[#lines + 1] = '';
    lines[#lines + 1] = '== Pauses since loading (short ones are not seen: the game\'s names come back after 30 frames)';
    local any = false;
    for key, known in pairs(counts) do
        any = true;
        lines[#lines + 1] = ('%-10s %d short, %d seen, %d frames in all'):format(key, known.blips, known.seen, known.frames);
    end
    if (not any) then lines[#lines + 1] = 'none'; end

    lines[#lines + 1] = '';
    lines[#lines + 1] = '== Lua errors';
    if (#errorOrder == 0) then lines[#lines + 1] = 'none'; end
    for _, message in ipairs(errorOrder) do
        local known = errors[message];
        lines[#lines + 1] = ('%d times, first %s, last %s'):format(known.count, known.first, known.last);
        lines[#lines + 1] = known.traceback or message;
    end

    lines[#lines + 1] = '';
    lines[#lines + 1] = '== History (time, seconds since loading, frame)';
    for i = 0, #history - 1 do
        lines[#lines + 1] = history[(historyStart - 1 + i) % #history + 1];
    end

    lines[#lines + 1] = '';
    lines[#lines + 1] = '== Settings';
    optionLines(lines, diag.Options);

    local ok, result = pcall(function ()
        makeFolder(folder);
        local file, problem = io.open(path, 'w');
        if (file == nil) then error(problem); end
        file:write(table.concat(lines, '\n'), '\n');
        file:close();
    end);
    if (not ok) then
        diag.Note('Log not written: %s', tostring(result));
        return nil, tostring(result);
    end
    lastPath = path;
    diag.Note('Log written: %s', path);
    return path;
end

return diag;
