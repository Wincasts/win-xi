-- winxi.gamedata: what is known of the game that the client does not say, made from the server's own
-- data by tools/build_winxi_data.py and kept in libs\winxi\data, one folder to each set.
--
--     gamedata.Read(set, key)   data\<set>\<key>.lua, the table it returns, or nil where there is none
--                               or it cannot be read
--     gamedata.Manifest()       data\manifest.lua: where the data was made from (Source: Repository,
--                               Branch, Commit, Built) and each set's file count (Sets), or {}
--     gamedata.Root(path)       the folder data is read from, ending in a separator; a path given
--                               reads from there instead (nil goes back to libs\winxi\data)
--
-- The sets are winxi.mobs': mobs (an area's monsters, as mobdb has them) and placeholders (the
-- monsters each of an area's notorious monsters is drawn by lot from). Nothing is kept here: a set's
-- own module keeps what it reads, for as long as it wants it.
local gamedata = {};

local root = nil;

function gamedata.Root(path)
    if (path ~= nil) then
        root = path;
    end
    root = root or ('%s\\addons\\libs\\winxi\\data\\'):format(AshitaCore:GetInstallPath());
    return root;
end

-- A file's table, read with nothing of the addon's to reach: data, never code that does things
local function Load(path)
    local chunk = loadfile(path);
    if (chunk == nil) then
        return nil;
    end
    setfenv(chunk, {});
    local ok, result = pcall(chunk);
    return ok and type(result) == 'table' and result or nil;
end

function gamedata.Read(set, key)
    if (type(set) ~= 'string' or not set:match('^[%w_]+$') or key == nil or not tostring(key):match('^[%w_]+$')) then
        return nil;
    end
    return Load(('%s%s/%s.lua'):format(gamedata.Root(), set, tostring(key))); -- Windows takes / as well as \
end

local manifest = nil;
function gamedata.Manifest()
    manifest = manifest or Load(gamedata.Root() .. 'manifest.lua') or {};
    return manifest;
end

return gamedata;
