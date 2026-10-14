-- Bounded, read-only hypotheses about the focused native menu. Only the name chain is known:
-- slot -> holder -> node -> (+4) header -> (+46) name. All rectangle offsets are UNVERIFIED.
-- Memory is injected so the parser can be tested without dereferencing the game.
local ffi = require('ffi');
local M = {};
local scratch = ffi.new('float[1]');
local function u32(bytes, offset)
    if not bytes or offset + 4 > #bytes then return nil; end
    local a,b,c,d = bytes:byte(offset + 1, offset + 4);
    return a + b*256 + c*65536 + d*16777216;
end
local function scalar(bytes, offset, kind)
    if kind == 'i16' then
        local a,b = bytes:byte(offset + 1, offset + 2);
        local n = a + b*256; return n >= 32768 and n - 65536 or n;
    end
    local n = u32(bytes, offset);
    if kind == 'f32' then
        ffi.cast('uint32_t*', scratch)[0] = n;
        return tonumber(scratch[0]);
    end
    return n >= 2147483648 and n - 4294967296 or n;
end
local function pointer(memory, address)
    local bytes = memory.read(address, 4);
    local n = u32(bytes, 0);
    return n and n >= 0x10000 and n < 0xFFFFFF00 and n % 4 == 0 and n or nil;
end
function M.resolve(memory, slot)
    local holder = pointer(memory, slot);
    local node = holder and pointer(memory, holder);
    local header = node and pointer(memory, node + 4);
    local bytes = header and memory.read(header + 0x46, 16);
    if not bytes or not bytes:match('^menu%s+') then return nil, 'no readable focused menu'; end
    return { slot=slot, holder=holder, node=node, header=header, name=bytes:gsub('%z', '') };
end
function M.rectangle(bytes, offset, kind, layout, width, height)
    local step = kind == 'i16' and 2 or 4;
    if not bytes or offset < 0 or offset + step*4 > #bytes then return nil; end
    local v = {};
    for i=1,4 do
        local n = scalar(bytes, offset + (i-1)*step, kind);
        if n ~= n or math.abs(n) > math.max(width, height)*2 then return nil; end
        v[i] = n;
    end
    if layout == 'xywh' then v[3],v[4] = v[1]+v[3],v[2]+v[4]; end
    local w,h = v[3]-v[1],v[4]-v[2];
    if w < 12 or h < 12 or math.max(w,h) < 32 or w > width*2 or h > height*2
        or v[1] < -width or v[2] < -height or v[3] <= 0 or v[4] <= 0
        or v[1] >= width or v[2] >= height then return nil; end
    return v;
end
local function address(memory, menu, source)
    local base = menu[source.root];
    if source.via then return pointer(memory, base + source.via); end
    return base;
end
function M.scan(memory, menu, width, height)
    local sources, candidates, seen = {}, {}, {};
    local function add(root, via)
        if #sources >= 12 then return; end
        local source = { root=root, via=via };
        local at = address(memory, menu, source);
        if not at or seen[at] then return; end
        local bytes = memory.read(at, 256);
        if not bytes then return; end
        seen[at] = true;
        source.address, source.bytes = at, bytes;
        source.label = root .. (via and ('->+%02X'):format(via) or '');
        sources[#sources+1] = source;
    end
    add('node'); add('header');
    -- One hop only; no walking arbitrary linked lists or guessing which entries are visible.
    for offset=8,0x3C,4 do
        add('node', offset); add('header', offset);
    end
    for _, source in ipairs(sources) do
        for _, kind in ipairs({ 'i16', 'i32', 'f32' }) do
            local step = kind == 'i16' and 2 or 4;
            for offset=0,256-step*4,step do
                for _, layout in ipairs({ 'ltrb', 'xywh' }) do
                    local rect = M.rectangle(source.bytes, offset, kind, layout, width, height);
                    if rect then candidates[#candidates+1] = {
                        source=source, offset=offset, kind=kind, layout=layout, rect=rect,
                        label=('%s +%02X %s %s'):format(source.label, offset, kind, layout),
                    }; end
                end
            end
        end
    end
    return candidates, sources;
end
function M.live(memory, menu, candidate, width, height)
    local at = address(memory, menu, candidate.source);
    -- Never silently retarget a hypothesis after a child object is replaced.
    if at ~= candidate.source.address then return nil; end
    local step = candidate.kind == 'i16' and 2 or 4;
    local bytes = memory.read(at + candidate.offset, step*4);
    return M.rectangle(bytes, 0, candidate.kind, candidate.layout, width, height);
end
return M;
