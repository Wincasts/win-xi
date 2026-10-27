-- Every status effect the server has, by number: Name, Symbol, Flags (erasable, waltzable, ...),
-- Element, Overwrite, WearOff (the message that says it wore off). From the server's data (tools/build_action_data.py).
--
--     statuses.Harmful(id)    whether the status does its bearer harm: one place for every addon that
--                             tells debuffs from buffs (party's order, sct's colours, simplelog's lines)
--
-- The server says what Erase or a waltz removes (the erasable and waltzable flags); what cannot be
-- cancelled and still does harm it does not say, so those are named here (sleep, petrification,
-- charm, doom, the songs on enemies, the dazes, the Geo downs and the like), and kept to the statuses
-- the server has. Where winxi's data is not installed (an addon released with its own winxi), the
-- statuses taken as harmful are the whole list as it was before the server's flags were read.
local statuses = require('winxi.catalog').New('statuses');

-- harmful, though neither erasable nor waltzable
local CANNOT_CANCEL = {
    0, 1, 2, 7, 14, 15, 16, 17, 18, 19, 20, 22, 23, 28, 29, 168, 177, 186, 193, 217, 223, 259, 260, 261,
    262, 263, 264, 309, 378, 379, 380, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398,
    399, 400, 448, 449, 450, 451, 452, 473, 540, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567,
    572, 576, 630, 631, 802,
};
-- and, without the server's flags, those it flags erasable or waltzable
local FLAGGED_WITHOUT_DATA = {
    3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 21, 30, 31, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138,
    139, 140, 141, 142, 144, 145, 146, 147, 148, 149, 156, 167, 174, 175, 189, 192, 194, 291, 298, 404,
    536, 571,
};

local harmful = nil;

function statuses.Harmful(id)
    if (harmful == nil) then
        harmful = {};
        local ids = statuses.Ids();
        if (#ids == 0) then
            for _, list in ipairs({ CANNOT_CANCEL, FLAGGED_WITHOUT_DATA }) do
                for _, number in ipairs(list) do harmful[number] = true; end
            end
        else
            local named = {};
            for _, number in ipairs(CANNOT_CANCEL) do named[number] = true; end
            for _, number in ipairs(ids) do
                local record = statuses.Get(number);
                for _, flag in ipairs(record and record.Flags or {}) do
                    if (flag == 'erasable' or flag == 'waltzable') then harmful[number] = true; end
                end
                if (record ~= nil and named[number]) then harmful[number] = true; end
            end
        end
    end
    return harmful[id] == true;
end

local clear = statuses.Clear;
function statuses.Clear()
    harmful = nil;
    clear();
end

return statuses;
