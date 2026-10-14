-- The game's own row of status icons, switched off and on again. Three places in the game's code are
-- changed so that it draws none; what was there is kept, and put back when the addon unloads. The
-- places are the ones the statustimers addon (heals) found.
local native = {};

local places = {
    { find = '75??8B4E0851B9', write = 0x9090 },
    { find = '7D??33C05EC20400C6', write = 0x9090 },
    { find = '85C00F??????????6A0232DBE8', write = 0xC031 },
};

local hidden = false;

-- Hides the game's status icons, or shows them again. Returns whether they are now as asked: false
-- where the places cannot be found, or something else has changed them already.
function native.Set(hide)
    hide = hide and true or false;
    if hide == hidden then
        return true;
    end

    if not hide then
        for _, place in ipairs(places) do
            ashita.memory.write_uint16(place.pointer, place.was);
        end
        hidden = false;
        return true;
    end

    for _, place in ipairs(places) do
        place.pointer = ashita.memory.find('FFXiMain.dll', 0, place.find, 0, 0);
        if place.pointer == nil or place.pointer == 0 then
            return false;
        end
        place.was = ashita.memory.read_uint16(place.pointer);
        if place.was == place.write then
            return false;
        end
    end
    for _, place in ipairs(places) do
        ashita.memory.write_uint16(place.pointer, place.write);
    end
    hidden = true;
    return true;
end

function native.IsHidden()
    return hidden;
end

return native;
