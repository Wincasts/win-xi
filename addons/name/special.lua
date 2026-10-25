-- The sheet of Name's own signs, assets/special.png (assets/make_special_sheet.py): the tracked
-- notorious monster's, a vendor's coin and the party and alliance roles, four to a row. The plugin's
-- eight textures are all taken, so they share its number 6 (letter_badges has 5, statuses 7).
--
--   special.UV(sign)    the sign's place on the sheet: u0, v0, u1, v1
--   special.SetRegion(region)  where the sheet is in the texture of number 6: nil, all of it; or the
--                       { u0, v0, u1, v1 } of it in the sheet bar_art makes, with textured bars in it
local special = {
    Slot = 6,
    Sheet = 'special.png',
    Hunt = 0, Vendor = 1,
    AllianceLeader = 2, PartyLeader = 3, AlliancePartyLeader = 4, AllianceMember = 5, PartyMember = 6,
};

local ACROSS, DOWN = 4, 2;
local region = nil;

function special.SetRegion(found)
    region = found;
end

function special.UV(sign)
    local u, v = (sign % ACROSS) / ACROSS, math.floor(sign / ACROSS) / DOWN;
    local u1, v1 = u + 1 / ACROSS, v + 1 / DOWN;
    if region == nil then return u, v, u1, v1; end
    local w, h = region.u1 - region.u0, region.v1 - region.v0;
    return region.u0 + u * w, region.v0 + v * h, region.u0 + u1 * w, region.v0 + v1 * h;
end

return special;
