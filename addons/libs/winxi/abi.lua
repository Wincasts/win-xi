-- winxi.abi: whether a plugin's block can be read, as plugins/ABI.md promises until 2.0. A block's 1.0 layout
-- never changes: a newer plugin only adds fields after it, and says so in Size. So a block is read when its
-- Version is the one the addon was written for and it is at least as large as the addon's copy of it; what
-- comes after is the newer plugin's own. An addon newer than the plugin asks Has before reading a field the
-- plugin's 1.0 layout did not have.
--
--   abi.Accepts(block, ctype, version[, since])
--                                       the block is this one, or a newer plugin's growth of it. since names the
--                                       first field of the addon's copy it can do without (one a plugin added
--                                       after 1.0): the block need only reach that far, so an older plugin is
--                                       still read, and Has says whether each later field is there
--   abi.Has(block, ctype, field)        the block's own Size reaches the field: the plugin is new enough for it
--
-- block is the cdata pointer cast from the plugin's memory; ctype the addon's ffi type for it.
local ffi = require('ffi');

local abi = {};

local sizes = {}; -- ctype .. since -> the size a block must reach, worked out once

local function Needed(ctype, since)
    local key = since and (ctype .. '.' .. since) or ctype;
    local size = sizes[key];
    if (size == nil) then
        size = since and ffi.offsetof(ctype, since) or ffi.sizeof(ctype);
        sizes[key] = size;
    end
    return size;
end

function abi.Accepts(block, ctype, version, since)
    return block ~= nil and block.Version == version and block.Size >= Needed(ctype, since);
end

function abi.Has(block, ctype, field)
    if (block == nil) then return false; end
    local ok, at = pcall(ffi.offsetof, ctype, field);
    return ok and at ~= nil and at < block.Size;
end

return abi;
