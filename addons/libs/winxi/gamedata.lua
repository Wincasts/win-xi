-- winxi.gamedata: what is known of the game that the client does not say, made from a server's own
-- data by tools/build_winxi_data.py and kept in libs\winxi\data: a folder for each server the data was
-- made for (data\phoenix), a folder in it for each set. What is not a server's (the client's
-- auto-translate dictionary, the addons' tooltips) is in data itself.
--
--     gamedata.Read(set, key)   the set's <key>.lua, the table it returns, or nil where there is none or
--                               it cannot be read: from the chosen server's folder, or failing that
--                               data's own (the sets that are no server's, and data laid out as it was
--                               before there were servers)
--     gamedata.Manifest()       the chosen server's manifest.lua: Source (Name, Key, Repository, Branch,
--                               Commit, Built) and each set's file count (Sets), or {}
--     gamedata.Datasets()       the servers there is data for: { { Key, Name }, ... } (data\datasets.lua)
--     gamedata.Dataset()        the chosen server's key: the one chosen in winxisettings (kept in
--                               config\addons\winxi\dataset.lua, for every addon), or the first there is
--     gamedata.UseDataset(key)  choose a server's data, for every addon: kept, and each addon's readers
--                               told within a few seconds
--     gamedata.OnChange(fn)     fn() is called when the choice changes, for a reader to forget what it has
--     gamedata.Lookup(set, key) a table that reads as the set's key (index) does, read when first looked
--                               in and again after the choice changes
--     gamedata.Root(path)       the data folder, ending in a separator; a path given reads from there
--                               instead (nil goes back to libs\winxi\data)
--
-- Sets include mobs/placeholders, items, quests, spells/abilities/weaponskills/traits, jobs/skills/
-- elements, statuses and rules. Nothing is kept here but the choice: a set's own module keeps what it
-- reads, for as long as it wants it, and forgets it when told the choice changed.
local gamedata = {};

local root = nil;
local chosen = nil;      -- the server's key in use, or false for none
local chosenAt = nil;    -- os.clock() when the choice was last read from its file
local LOOK_AGAIN = 5;    -- seconds between reading the choice again, for a change made in another addon
local listeners = {};
local datasets = nil;

local function Load(path)
    local chunk = loadfile(path);
    if (chunk == nil) then
        return nil;
    end
    setfenv(chunk, {});
    local ok, result = pcall(chunk);
    return ok and type(result) == 'table' and result or nil;
end

-- An addon released with its own winxi (addons\<addon>\winxi) carries its own data beside it: that
-- folder, or nil for the shared winxi in addons\libs
local function OwnData()
    local info = debug.getinfo(1, 'S');
    local file = info and info.source and info.source:match('^@(.*)$') or nil;
    if (file == nil) then
        return nil;
    end
    local folder = file:match('^(.*[/\\])gamedata%.lua$');
    if (folder == nil or folder:lower():match('[/\\]libs[/\\]winxi[/\\]$') or not folder:lower():match('[/\\]winxi[/\\]$')) then
        return nil;
    end
    return folder .. 'data\\';
end

local Changed;

function gamedata.Root(path)
    if (path ~= nil) then
        local before = root;
        root, chosen, chosenAt, datasets = path, nil, nil, nil;
        if (before ~= path and Changed ~= nil) then
            Changed(); -- what was read is another folder's: the readers read again
        end
    end
    -- away from Ashita (a check run on its own) there is no install, and so no data: nothing is read
    if (root == nil and AshitaCore == nil) then
        return '';
    end
    root = root or OwnData() or ('%s\\addons\\libs\\winxi\\data\\'):format(AshitaCore:GetInstallPath());
    return root;
end

-- Where the choice is kept: winxi's shared config, beside the theme; nil away from Ashita
local function ChoicePath()
    local ok, install = pcall(function () return AshitaCore:GetInstallPath(); end);
    if (not ok or type(install) ~= 'string') then
        return nil;
    end
    return ('%sconfig\\addons\\winxi\\dataset.lua'):format(install);
end

function gamedata.Datasets()
    if (datasets == nil) then
        local base = gamedata.Root();
        local found = base ~= '' and Load(base .. 'datasets.lua') or nil;
        datasets = type(found) == 'table' and found or {};
    end
    return datasets;
end

local function Known(key)
    for _, dataset in ipairs(gamedata.Datasets()) do
        if (dataset.Key == key) then return true; end
    end
    return false;
end

local manifest = nil;
function Changed()
    manifest = nil;
    for _, fn in ipairs(listeners) do
        pcall(fn);
    end
end

function gamedata.Dataset()
    local now = os.clock();
    if (chosenAt == nil or now - chosenAt >= LOOK_AGAIN) then
        chosenAt = now;
        local path = ChoicePath();
        local saved = path and Load(path) or nil;
        local key = saved and saved.Key or nil;
        if (key == nil or not Known(key)) then
            key = gamedata.Datasets()[1] and gamedata.Datasets()[1].Key or false;
        end
        if (chosen ~= nil and key ~= chosen) then
            chosen = key;
            Changed();
        end
        chosen = key;
    end
    return chosen or nil;
end

function gamedata.UseDataset(key)
    if (not Known(key)) then
        return false;
    end
    local path = ChoicePath();
    if (path ~= nil) then
        local directory = path:match('^(.*\\)');
        for position = 1, #directory do
            if (directory:sub(position, position) == '\\') then
                ashita.fs.create_directory(directory:sub(1, position));
            end
        end
        local file = io.open(path, 'w');
        if (file == nil) then
            return false;
        end
        file:write('-- The server whose data every winxi addon reads. Written by winxi: choose it in winxisettings.\n');
        file:write(('return { Key = %q };\n'):format(key));
        file:close();
    end
    local before = chosen;
    chosen, chosenAt = key, os.clock();
    if (before ~= key) then
        Changed();
    end
    return true;
end

function gamedata.OnChange(fn)
    listeners[#listeners + 1] = fn;
end

function gamedata.Read(set, key)
    if (type(set) ~= 'string' or not set:match('^[%w_]+$') or key == nil or not tostring(key):match('^[%w_]+$')) then
        return nil;
    end
    local base = gamedata.Root();
    if (base == '') then
        return nil;
    end
    local dataset = gamedata.Dataset();
    local found = dataset and Load(('%s%s/%s/%s.lua'):format(base, dataset, set, tostring(key))) or nil; -- Windows takes / as well as \
    return found or Load(('%s%s/%s.lua'):format(base, set, tostring(key)));
end

-- A table that reads as the set's key (index by default) does, read the first time it is looked in and
-- again after another server's data is chosen: for an addon that looks things up by zone and the like
function gamedata.Lookup(set, key)
    local data = nil;
    gamedata.OnChange(function () data = nil; end);
    return setmetatable({}, { __index = function (_, k)
        data = data or gamedata.Read(set, key or 'index') or {};
        return data[k];
    end });
end

function gamedata.Manifest()
    if (manifest == nil) then
        local base, dataset = gamedata.Root(), gamedata.Dataset();
        manifest = (dataset and Load(('%s%s/manifest.lua'):format(base, dataset))) or Load(base .. 'manifest.lua') or {};
    end
    return manifest;
end

return gamedata;
