-- winxi.game: what an addon asks of the game itself, read from its memory.
--
--   game.MenuName()            the name of the game menu on top, or ''
--   game.IsChatExpanded()      the chat log is opened right out
--   game.IsMapOpen()           the map (or another full-screen list of its kind) is open
--   game.IsEventHappening()    a cutscene or an NPC's dialogue is running
--   game.IsInterfaceHidden()   the player has hidden the game's own interface
--   game.IsLoading()           there is no player yet: zoning, or not logged in
--   game.HasBagAccess(bag)     the player can use the bag with that number
--
-- And the usual rules for when an addon's windows should get out of the way:
--
--   game.CompleteHide(settings)    gives a settings table each rule it lacks; returns it
--   game.IsHidden(settings)        whether any rule that is switched on applies now
--
-- The rules are UnderMap, UnderChat, WhileLoading, DuringEvent and WithInterface, each true or false.
-- winxi.widgets.Hide draws the controls for them.
--
-- The places in memory are found by searching the game's code, which is slow: each is searched for
-- once, the first time it is wanted.
local bit = require('bit');

local game = {};

local found = {};

-- Where a pattern is in the game's code, searched for the first time and remembered. 0 if nowhere.
local function Find(key, pattern, offset)
    local at = found[key];
    if at == nil then
        at = ashita.memory.find('FFXiMain.dll', 0, pattern, offset, 0);
        found[key] = at;
    end
    return at;
end

function game.MenuName()
    local base = Find('menu', '8B480C85C974??8B510885D274??3B05', 16);
    if base == 0 then
        return '';
    end

    local pointer = ashita.memory.read_uint32(base);
    if pointer == 0 then
        return '';
    end
    local value = ashita.memory.read_uint32(pointer);
    if value == 0 then
        return '';
    end
    local header = ashita.memory.read_uint32(value + 4);
    if header == 0 then
        return '';
    end

    local name = ashita.memory.read_string(header + 0x46, 16);
    return (string.gsub(name, '\x00', ''));
end

-- chat expanded signature courtesy of Syllendel
function game.IsChatExpanded()
    local base = Find('chat', '83EC??B9????????E8????????0FBF4C24??84C0', 0x04);
    if base == 0 then
        return false;
    end

    local pointer = ashita.memory.read_uint32(base);
    if pointer == 0 then
        return false;
    end
    return ashita.memory.read_uint8(pointer + 0xF1) > 2;
end

function game.IsMapOpen()
    local name = game.MenuName();
    if name == '' then
        return false;
    end
    return name:find('menu%s+map') ~= nil
        or name:find('menu%s+scanlist') ~= nil
        or name:find('menu%s+cnqframe') ~= nil;
end

-- event system signature courtesy of Velyn
function game.IsEventHappening()
    local base = Find('event', 'A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3', 0);
    if base == 0 then
        return false;
    end

    local pointer = ashita.memory.read_uint32(base + 1);
    if pointer == 0 then
        return false;
    end
    return ashita.memory.read_uint8(pointer) == 1;
end

-- interface hidden signature courtesy of Velyn
function game.IsInterfaceHidden()
    local base = Find('interface', '8B4424046A016A0050B9????????E8????????F6D81BC040C3', 0);
    if base == 0 then
        return false;
    end

    local pointer = ashita.memory.read_uint32(base + 10);
    if pointer == 0 then
        return false;
    end
    return ashita.memory.read_uint8(pointer + 0xB4) == 1;
end

function game.IsLoading()
    return GetPlayerEntity() == nil;
end

-- Whether the player can use a bag, by the game's number for it. Code provided by atom0s.
-- The inventory always; wardrobes 3 to 8 (11 to 16) by the flags the game keeps for them; the bags up
-- to wardrobe 2 by whether they have any room at all; nothing else.
function game.HasBagAccess(index)
    local inventory = AshitaCore:GetMemoryManager():GetInventory();
    local base = Find('bags', 'A1????????8B88B4000000C1E907F6C101E9', 0);
    if base == 0 or inventory == nil then
        return false;
    end

    if index == 0 then
        return true;
    end

    if index >= 11 and index <= 16 then
        local pointer = ashita.memory.read_uint32(base + 1);
        if pointer == 0 then
            return false;
        end
        local flags = ashita.memory.read_uint32(pointer);
        if flags == 0 then
            return false;
        end

        -- wardrobe 3 is the third bit, and so on up
        local value = ashita.memory.read_uint8(flags + 0xB4);
        return bit.band(bit.rshift(value, index - 9), 0x01) ~= 0;
    end

    if index >= 1 and index <= 10 then
        return inventory:GetContainerCountMax(index) > 0;
    end
    return false;
end

-- The rules for hiding an addon's windows, each on unless the addon's settings say otherwise
game.HideDefaults = {
    UnderMap = true,
    UnderChat = true,
    WhileLoading = true,
    DuringEvent = true,
    WithInterface = true,
};

function game.CompleteHide(settings)
    for key, value in pairs(game.HideDefaults) do
        if settings[key] == nil then
            settings[key] = value;
        end
    end
    return settings;
end

function game.IsHidden(settings)
    return (settings.WhileLoading and game.IsLoading())
        or (settings.UnderChat and game.IsChatExpanded())
        or (settings.UnderMap and game.IsMapOpen())
        or (settings.DuringEvent and game.IsEventHappening())
        or (settings.WithInterface and game.IsInterfaceHidden())
        or false;
end

return game;
