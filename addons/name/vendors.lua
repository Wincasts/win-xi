-- The coin of [vendor] beside a vendor's name: which NPCs sell, by vendor_list.lua (tools/build_name_vendors.py),
-- the names of the NPCs whose scripts open a shop, for each area.
--
--   vendors.Begin(wanted)     each frame: whether any name here can have the coin; wanted, whether a
--                             format has [vendor]
--   vendors.Of(written, name) whether this one is a vendor; written is custom's parse of it, which
--                             keeps the answer while the character and the area are the same
local ffi = require('ffi');
local list = require('vendor_list');

local vendors = {};

local here = nil; -- the area's vendors while the coin is wanted, or nothing

function vendors.Begin(wanted)
    here = nil;
    if (not wanted) then
        return false;
    end
    local memory = AshitaCore:GetMemoryManager();
    local party = memory ~= nil and memory:GetParty() or nil;
    if (party == nil or party.GetMemberZone == nil) then
        return false;
    end
    here = list[party:GetMemberZone(0)];
    return here ~= nil;
end

function vendors.Of(written, name)
    if (here == nil) then
        return false;
    end
    if (written.vendorOf ~= name.ServerId or written.vendorIn ~= here) then
        written.vendorOf, written.vendorIn = name.ServerId, here;
        written.vendor = here[ffi.string(name.Name)] == true;
    end
    return written.vendor;
end

return vendors;
