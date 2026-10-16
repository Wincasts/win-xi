-- The game's own status icons, switched off and on again. Places in the game's code are changed so
-- that it draws none; what was there is kept, and put back when the addon unloads. The places are the
-- ones the statustimers addon (heals) found.
--
-- The first two are the row of icons itself, which the buffhook plugin draws the anchored bar in
-- place of, and which must be left alone for it to: so the row and the rest are switched apart.
--
--   native.Set(row, other)   hides the row, the rest, both or neither. Returns whether they are now as
--                            asked: false where a place cannot be found, or something else has changed
--                            it already.
local native = {};

local places = {
    { find = '75??8B4E0851B9', write = 0x9090, row = true },
    { find = '7D??33C05EC20400C6', write = 0x9090, row = true },
    { find = '85C00F??????????6A0232DBE8', write = 0xC031, row = false },
};

local function Show(place)
    if place.hidden then
        ashita.memory.write_uint16(place.pointer, place.was);
        place.hidden = false;
    end
end

local function Hide(place)
    if place.hidden then
        return true;
    end
    place.pointer = ashita.memory.find('FFXiMain.dll', 0, place.find, 0, 0);
    if place.pointer == nil or place.pointer == 0 then
        return false;
    end
    place.was = ashita.memory.read_uint16(place.pointer);
    if place.was == place.write then
        return false;
    end
    ashita.memory.write_uint16(place.pointer, place.write);
    place.hidden = true;
    return true;
end

function native.Set(row, other)
    local ok = true;
    for _, place in ipairs(places) do
        local hide;
        if place.row then hide = row else hide = other end
        if hide then
            ok = Hide(place) and ok;
        else
            Show(place);
        end
    end
    return ok;
end

return native;
