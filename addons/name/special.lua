-- The sheet of Name's own signs, assets/special.png (assets/make_special_sheet.py): the tracked
-- notorious monster's, a vendor's coin and the party and alliance roles, four to a row. The plugin's
-- eight textures are all taken, so they share its number 6 (letter_badges has 5, statuses 7).
--
--   special.UV(sign)    the sign's place on the sheet: u0, v0, u1, v1
local special = {
    Slot = 6,
    Sheet = 'special.png',
    Hunt = 0, Vendor = 1,
    AllianceLeader = 2, PartyLeader = 3, AlliancePartyLeader = 4, AllianceMember = 5, PartyMember = 6,
};

local ACROSS, DOWN = 4, 2;

function special.UV(sign)
    local u, v = (sign % ACROSS) / ACROSS, math.floor(sign / ACROSS) / DOWN;
    return u, v, u + 1 / ACROSS, v + 1 / DOWN;
end

return special;
