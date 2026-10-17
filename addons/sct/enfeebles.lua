-- The statuses that count as enfeebles: drawn in the enfeeble colour as they land, the rest in the
-- buff colour. The game says nothing of which is which, so the list is kept here: Windower's, as
-- simplelog has it (addons/simplelog/lib/constants.lua, enfeebling).
local ids = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28,
    29, 30, 31, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145,
    146, 147, 148, 149, 155, 156, 157, 158, 159, 167, 168, 174, 175, 177, 186, 189, 192, 193, 194, 223, 259,
    260, 261, 262, 263, 264, 298, 378, 379, 380, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397,
    398, 399, 400, 404, 448, 449, 450, 451, 452, 473, 540, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566,
    567,
};

local enfeebles = {};
for _, id in ipairs(ids) do
    enfeebles[id] = true;
end
return enfeebles;
