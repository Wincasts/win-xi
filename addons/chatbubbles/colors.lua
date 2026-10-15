-- Read FFXI's live log-mode -> palette-slot -> color tables. No game writes or
-- native function calls. Signatures identify the two read-only lookup routines;
-- their embedded operands locate the ASLR-relocated tables, not fixed addresses.
local M = {};
M.ModeSignature = 'A1????????33C96685C07418668B542404663BC27411668B048D????????416685C075ED';
M.PaletteSignature = 'A0????????33C984C0741A0FBF54240425FF0000003BC274128A04CD????????4184C075EBB880808080C38B04CD????????C3';
local modeAddress, paletteAddress;
local lookedAt, refreshedAt = -math.huge, -math.huge;
local logSlots, palette = {}, {};
local problem;

-- Player packet modes are NOT text-log mode IDs. Incoming/outgoing share colors
-- today, but keep the direction-specific modes so client mappings remain authoritative.
local incoming = { [0]=9, [1]=10, [3]=12, [4]=13, [5]=14, [8]=15,
    [13]=9, [14]=10, [15]=13, [16]=14, [26]=11, [27]=214, [28]=214,
    [33]=212, [34]=220, [35]=222 };
local outgoing = { [0]=1, [1]=2, [3]=4, [4]=5, [5]=6, [8]=7,
    [26]=3, [27]=213, [33]=211, [34]=220, [35]=222 };
local function u32(bytes, at)
    local a, b, c, d = bytes:byte(at, at + 3);
    return a + b * 256 + c * 65536 + d * 16777216;
end
function M.Problem() return problem; end
function M.Reset()
    modeAddress, paletteAddress = nil, nil;
    lookedAt, refreshedAt = -math.huge, -math.huge;
    logSlots, palette, problem = {}, {}, nil;
end
local function refresh(now)
    local safe = require('winxi.safe_memory');
    if (not modeAddress or not paletteAddress) then
        if (now - lookedAt < 1) then return false; end
        lookedAt = now;
        local mode = ashita.memory.find('FFXiMain.dll', 0, M.ModeSignature, 0, 0);
        local colors = ashita.memory.find('FFXiMain.dll', 0, M.PaletteSignature, 0, 0);
        if (not mode or mode == 0 or not colors or colors == 0) then
            problem = 'Client chat-color signatures unavailable; using manual text color.';
            return false;
        end
        local modeCode = safe.read(mode, 36);
        local colorCode = safe.read(colors, 51);
        -- Cross-check repeated table operands, not just the first signature hit.
        if (not modeCode or not colorCode
                or u32(modeCode, 27) ~= u32(modeCode, 2) + 4
                or u32(colorCode, 29) ~= u32(colorCode, 2) + 8
                or u32(colorCode, 47) ~= u32(colorCode, 2) + 4) then
            problem = 'Client chat-color lookup validation failed; using manual text color.';
            return false;
        end
        modeAddress, paletteAddress = u32(modeCode, 2), u32(colorCode, 2);
    end
    if (now - refreshedAt < 0.25) then return problem == nil; end
    refreshedAt = now;
    local modeBytes = safe.read(modeAddress, 1024);
    local colorBytes = safe.read(paletteAddress, 1024);
    if (not modeBytes or not colorBytes) then
        problem = 'Client chat-color tables are not readable; using manual text color.';
        logSlots, palette = {}, {};
        return false;
    end
    local slots, colors, modeEnd, colorEnd = {}, {}, false, false;
    for at = 1, #modeBytes - 3, 4 do
        local mode = modeBytes:byte(at) + modeBytes:byte(at + 1) * 256;
        if (mode == 0) then modeEnd = true; break; end
        if (slots[mode] == nil) then slots[mode] = modeBytes:byte(at + 2); end
    end
    for at = 1, #colorBytes - 7, 8 do
        local slot = colorBytes:byte(at);
        if (slot == 0) then colorEnd = true; break; end
        -- FFXI returns the first entry when a palette slot occurs more than once.
        if (colors[slot] == nil) then colors[slot] = u32(colorBytes, at + 4); end
    end
    if (not modeEnd or not colorEnd or not slots[9] or colors[slots[9]] == nil) then
        problem = 'Client chat-color table layout is unexpected; using manual text color.';
        logSlots, palette = {}, {};
        return false;
    end
    logSlots, palette, problem = slots, colors, nil;
    return true;
end
function M.Get(logMode, alpha)
    if (not refresh(os.clock())) then return nil; end
    local raw = palette[logSlots[logMode]];
    if (raw == nil) then return nil; end
    -- Native FFXI colors use 0x80 as full intensity. Our quads use conventional
    -- 0xFF intensity. Native alpha belongs to the log; bubble opacity is separate.
    local function part(shift) return math.min(255, math.floor(raw / 2 ^ shift) % 256 * 2); end
    local a = math.floor(math.max(0, math.min(1, alpha or 1)) * 255 + 0.5);
    return a * 0x1000000 + part(16) * 0x10000 + part(8) * 0x100 + part(0);
end
function M.ForMessage(message, appearance)
    local setting = appearance and appearance.gameTextColors;
    if (not setting or not setting[1] or message.synthetic or message.mode == nil) then return nil; end
    local logMode = message.npc and message.mode or (message.outgoing and outgoing or incoming)[message.mode];
    if (not logMode) then return nil; end
    return M.Get(logMode, appearance.text[4]);
end
return M;
