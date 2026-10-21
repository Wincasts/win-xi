-- Layouts: every addon's settings, kept for each screen resolution, so that each resolution has its
-- own place and size for everything.
--
-- A layout is a copy of each addon's settings file for every character (config\addons\<addon>\
-- <name>_<server>\settings.lua) and the shared Winxi Theme (config\addons\winxi\theme.lua), kept in
-- config\addons\winxi\layouts\<width>x<height>\. Only settings.lua: an addon's other files (tCrossBar's
-- bindings, simplelog's filters) are the same at every resolution.
--
-- Each addon runs on its own and writes its settings back as it is unloaded or a character logs out, so
-- a layout is put in place only while no character is logged in: at the title screen or character
-- select, before any addon has read a character's settings. While logged in one is kept to be put in
-- place the next time the game starts (Pending).
--
-- With Automatic on, starting the game at another resolution than last time keeps the settings as they
-- were under the resolution they were used at, then puts in place the layout kept for the new one, if
-- there is one (none, and the settings stay as they are, to be moved for it). Call layouts.Start each
-- frame; it does this once, when the screen's size is known.
local layouts = {};

local imgui = require('imgui');

local function Root()
    return string.format('%sconfig\\addons\\', AshitaCore:GetInstallPath());
end

local function Folder()
    return Root() .. 'winxi\\layouts\\';
end

local function StatePath()
    return Folder() .. 'state.lua';
end

-- Makes every folder of a path ending in a backslash
local function MakeFolders(path)
    for position = 1, #path do
        if path:sub(position, position) == '\\' then
            ashita.fs.create_directory(path:sub(1, position));
        end
    end
end

-- The folders within a folder: a name with no extension is a folder
local function Folders(path)
    local found = {};
    local ok, entries = pcall(ashita.fs.get_directory, path);
    for _, entry in ipairs(ok and type(entries) == 'table' and entries or {}) do
        entry = tostring(entry);
        if not entry:find('%.%w+$') and ashita.fs.exists(path .. entry .. '\\') then
            found[#found + 1] = entry;
        end
    end
    table.sort(found);
    return found;
end

local function Copy(from, to)
    local source = io.open(from, 'rb');
    if not source then
        return false;
    end
    local content = source:read('*a');
    source:close();

    local target = io.open(to, 'wb');
    if not target then
        return false;
    end
    target:write(content);
    target:close();
    return true;
end

-- Kept between starts: { Last = the resolution the settings were last used at, Automatic, Pending }
local state = { Automatic = true };

local function LoadState()
    local chunk = loadfile(StatePath());
    local ok, saved = pcall(chunk or error);
    if ok and type(saved) == 'table' then
        state.Last = type(saved.Last) == 'string' and saved.Last or nil;
        state.Pending = type(saved.Pending) == 'string' and saved.Pending or nil;
        state.Automatic = saved.Automatic ~= false;
    end
end

local function SaveState()
    MakeFolders(Folder());
    local file = io.open(StatePath(), 'w');
    if not file then
        return false;
    end
    file:write('-- Which layout is in use, for winxi\'s layouts. Written by winxi: change it in game.\n');
    file:write('return {\n');
    if state.Last then file:write(string.format('    Last = %q,\n', state.Last)); end
    if state.Pending then file:write(string.format('    Pending = %q,\n', state.Pending)); end
    file:write(string.format('    Automatic = %s,\n', tostring(state.Automatic)));
    file:write('};\n');
    file:close();
    return true;
end

LoadState();

-- Whether a character is logged in, as the settings library sees it: from the start if one already is,
-- then by entering a zone and logging out
local loggedIn = false;
do
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    loggedIn = player ~= nil and player:GetLoginStatus() == 2;
end

ashita.events.register('packet_in', 'winxi_layouts_packet_in', function(e)
    if e.id == 0x000A then
        loggedIn = true;
    elseif e.id == 0x000B and e.data:byte(0x04 + 0x01) == 1 then
        loggedIn = false;
    end
end);

function layouts.IsLoggedIn()
    return loggedIn;
end

-- The screen's size as a layout's name, '1920x1080', or nil before it is known
function layouts.Resolution()
    local io = imgui.GetIO();
    local size = io and io.DisplaySize;
    if size == nil or size.x == nil or size.x < 1 or size.y < 1 then
        return nil;
    end
    return string.format('%dx%d', math.floor(size.x + 0.5), math.floor(size.y + 0.5));
end

function layouts.Last() return state.Last; end
function layouts.Pending() return state.Pending; end
function layouts.IsAutomatic() return state.Automatic; end

function layouts.SetAutomatic(on)
    state.Automatic = on and true or false;
    SaveState();
end

-- The layouts kept, by name
function layouts.List()
    local found = {};
    for _, name in ipairs(Folders(Folder())) do
        if name:find('^%d+x%d+$') then
            found[#found + 1] = name;
        end
    end
    return found;
end

function layouts.Exists(name)
    return name ~= nil and ashita.fs.exists(Folder() .. name .. '\\');
end

-- Keeps every addon's settings as they are on disk, and the shared theme, as the named layout. Returns
-- how many files were kept.
function layouts.Save(name)
    local kept = 0;
    local target = Folder() .. name .. '\\';
    MakeFolders(target);

    for _, addonName in ipairs(Folders(Root())) do
        if addonName ~= 'winxi' then
            for _, character in ipairs(Folders(Root() .. addonName .. '\\')) do
                local from = string.format('%s%s\\%s\\settings.lua', Root(), addonName, character);
                if character:find('_%d+$') and ashita.fs.exists(from) then
                    local folder = string.format('%s%s\\%s\\', target, addonName, character);
                    MakeFolders(folder);
                    if Copy(from, folder .. 'settings.lua') then
                        kept = kept + 1;
                    end
                end
            end
        end
    end

    local theme = Root() .. 'winxi\\theme.lua';
    if ashita.fs.exists(theme) and Copy(theme, target .. 'theme.lua') then
        kept = kept + 1;
    end
    return kept;
end

-- Puts the named layout's files in place of every addon's settings and the shared theme, and has every
-- addon using winxi load the theme again. Only while no character is logged in; returns how many files
-- were put in place, or nil if it cannot be now.
function layouts.Apply(name)
    if loggedIn or not layouts.Exists(name) then
        return nil;
    end

    local placed = 0;
    local source = Folder() .. name .. '\\';
    for _, addonName in ipairs(Folders(source)) do
        for _, character in ipairs(Folders(source .. addonName .. '\\')) do
            local from = string.format('%s%s\\%s\\settings.lua', source, addonName, character);
            if ashita.fs.exists(from) then
                local folder = string.format('%s%s\\%s\\', Root(), addonName, character);
                MakeFolders(folder);
                if Copy(from, folder .. 'settings.lua') then
                    placed = placed + 1;
                end
            end
        end
    end

    if ashita.fs.exists(source .. 'theme.lua') and Copy(source .. 'theme.lua', Root() .. 'winxi\\theme.lua') then
        placed = placed + 1;
        local theme = require('winxi.theme');
        theme.Load();
        theme.Save(); -- written as loaded, which tells every other addon to load it
    end
    return placed;
end

-- Puts the named layout in place now if no character is logged in, or the next time the game starts.
-- Returns 'now' or 'next start'.
function layouts.Use(name)
    if layouts.Apply(name) ~= nil then
        state.Last, state.Pending = layouts.Resolution() or name, nil;
        SaveState();
        return 'now';
    end
    state.Pending = name;
    SaveState();
    return 'next start';
end

function layouts.CancelPending()
    state.Pending = nil;
    SaveState();
end

-- An empty folder: Ashita's own, as os.remove does not remove one on Windows
local function RemoveFolder(path)
    local remove = ashita.fs.remove_directory or ashita.fs.remove_dir;
    if remove then
        pcall(remove, path);
    else
        os.remove(path);
    end
end

-- Removes a kept layout
function layouts.Delete(name)
    local source = Folder() .. name .. '\\';
    for _, addonName in ipairs(Folders(source)) do
        for _, character in ipairs(Folders(source .. addonName .. '\\')) do
            os.remove(string.format('%s%s\\%s\\settings.lua', source, addonName, character));
            RemoveFolder(string.format('%s%s\\%s', source, addonName, character));
        end
        RemoveFolder(source .. addonName);
    end
    os.remove(source .. 'theme.lua');
    RemoveFolder(Folder() .. name);
    if state.Pending == name then
        state.Pending = nil;
        SaveState();
    end
end

-- Once the screen's size is known: put in place a layout chosen while logged in, or, with Automatic on
-- and the resolution changed, keep the settings under the one they were used at and put in place the
-- new one's. Returns what was done, for the chat log, or nil.
local started = false;

function layouts.Start()
    if started then
        return nil;
    end
    local resolution = layouts.Resolution();
    if resolution == nil then
        return nil;
    end
    started = true;

    -- Logged in already (loaded partway through play): the settings are in use, nothing is put in place
    if loggedIn then
        if state.Last == nil then
            state.Last = resolution;
            SaveState();
        end
        return nil;
    end

    local said = nil;
    local changed = state.Last ~= nil and state.Last ~= resolution;
    if changed and state.Automatic then
        layouts.Save(state.Last);
        said = string.format('Kept the layout for %s.', state.Last);
    end

    local wanted = state.Pending or ((changed and state.Automatic) and resolution or nil);
    if wanted ~= nil and layouts.Exists(wanted) and layouts.Apply(wanted) ~= nil then
        said = (said and said .. ' ' or '') .. string.format('Using the layout for %s.', wanted);
    end

    state.Last, state.Pending = resolution, nil;
    SaveState();
    return said;
end

return layouts;
