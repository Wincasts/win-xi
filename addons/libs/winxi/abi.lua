-- winxi.abi: whether a plugin's block can be read, as plugins/ABI.md promises until 2.0. A block's 1.0 layout
-- never changes: a newer plugin only adds fields after it, and says so in Size. So a block is read when its
-- Version is the one the addon was written for and it is at least as large as the addon's copy of it; what
-- comes after is the newer plugin's own. An addon newer than the plugin asks Has before reading a field the
-- plugin's 1.0 layout did not have.
--
--   abi.Accepts(block, ctype, version)  the block is this one, or a newer plugin's growth of it
--   abi.Has(block, ctype, field)        the block's own Size reaches the field: the plugin is new enough for it
--
-- block is the cdata pointer cast from the plugin's memory; ctype the addon's ffi type for it.
local ffi = require('ffi');

local abi = {};

local sizes = {}; -- ctype -> ffi.sizeof, worked out once

local function SizeOf(ctype)
    local size = sizes[ctype];
    if (size == nil) then
        size = ffi.sizeof(ctype);
        sizes[ctype] = size;
    end
    return size;
end

function abi.Accepts(block, ctype, version)
    return block ~= nil and block.Version == version and block.Size >= SizeOf(ctype);
end

function abi.Has(block, ctype, field)
    if (block == nil) then return false; end
    local ok, at = pcall(ffi.offsetof, ctype, field);
    return ok and at ~= nil and at < block.Size;
end

return abi;
