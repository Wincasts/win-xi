-- Opt-in native rendering. Lua passes no draw-list/texture pointers: the plugin synchronously reads
-- the CURRENT window through Ashita's C++ ImGui API, retains a copy, and consumes its GPU commands.
local ffi = require('ffi')
local bit = require('bit')
ffi.cdef[[
    typedef struct { float Left, Top, Right, Bottom; uint32_t Frame; } partyhook_rect_t;
    typedef struct {
        char Magic[16];
        uint32_t Version, Size, Hooked, SupportedMask, Frame;
        uint32_t DrawnFrame[6];
        uint32_t Submit;
        uint32_t CapturedVertices, BlockedCalls, Replays, Failures;
        uint32_t TargetCursorCalls;
        uint32_t GeometryReady;
        partyhook_rect_t Rects[4];
    } partyhook_shared_t;
    typedef int32_t (__cdecl *partyhook_submit_t)(int32_t index, int32_t capture);
]]
local hook = {}
local block, submit, active = nil, nil, 0
local moduleBase = nil
local plugin = 'uihook'
local looked = -1
local owned = false
local reasonParty, reasonTarget
local reason = 'Load /load uihook, then /pt native on. Unload hideparty first.'

local function Find()
    local manager = AshitaCore:GetPluginManager()
    local selected = manager:IsLoaded('uihook') and 'uihook' or 'partyhook'
    if plugin ~= selected then
        block, submit, moduleBase, looked = nil, nil, nil, -1
        plugin = selected
    end
    if not manager:IsLoaded(plugin) then
        block, submit, moduleBase = nil, nil, nil
        looked = -1
        reason = 'uihook is not loaded (/load uihook; legacy /load partyhook is also supported).'
        return nil
    end
    local base = ashita.memory.get_base(plugin .. '.dll')
    if moduleBase ~= base then
        block, submit, moduleBase = nil, nil, base
        looked = -1
    end
    if not base or base == 0 then
        reason = plugin .. ' DLL is not ready.'
        return nil
    end
    if block then return block end
    if os.clock() - looked < 1 then return nil end
    looked = os.clock()
    local address = ashita.memory.find(plugin .. '.dll', 0, '5041525459484F4F4B00000000000000', 0, 0)
    if not address or address == 0 then reason = plugin .. ' party shared block not found.'; return nil end
    local found = ffi.cast('partyhook_shared_t*', address)
    if found.Version ~= 3 or found.Size ~= ffi.sizeof('partyhook_shared_t') or found.Submit == 0 then
        reason = plugin .. ' party ABI mismatch: install the matching plugin.'
        return nil
    end
    block = found
    reasonParty,reasonTarget=nil,nil
    submit = ffi.cast('partyhook_submit_t', found.Submit)
    return block
end

function hook.Stop()
    if reasonParty~=nil or reasonTarget~=nil then reason='Native replacement inactive.' end
    -- Always check loaded state before touching a cached block or calling code in the DLL.
    if owned and block then
        local found = Find()
        if found and submit then submit(-1, 0) end
    end
    active,owned=0,false
    reasonParty,reasonTarget=nil,nil
end

function hook.Disable(target)
    if block and Find() and submit then
        for i = target and 3 or 0, target and 5 or 2 do submit(i, -1) end
    end
    active = bit.band(active, target and 7 or 8)
    reasonParty,reasonTarget=nil,nil
    reason=('Native replacement: party %s; target %s.'):format(
        bit.band(active,7)~=0 and 'active' or 'off',
        bit.band(active,8)~=0 and 'active (native arrows preserved)' or 'off')
end

function hook.Begin(party, target)
    active = 0
    if not party and not target then hook.Stop(); return false end
    local found = Find()
    if not found then return false end
    if found.Hooked == 0 then
        hook.Stop()
        reason = plugin .. ' did not recognise this client; using ordinary Party windows.'
        return false
    end
    local partyReady = party and bit.band(found.SupportedMask, 7) == 7
    local targetReady = target and bit.band(found.SupportedMask, 8) ~= 0
    owned=true -- Stop must also release a frame that fails partway through renewal.
    for i = 0, 5 do
        local wanted = (i < 3 and partyReady) or (i >= 3 and targetReady)
        if submit(i, wanted and 0 or -1) == 0 then
            hook.Stop(); reason = plugin .. ' rejected the frame.'; return false
        end
    end
    active = (partyReady and 7 or 0) + (targetReady and 8 or 0)
    local p=partyReady and 1 or (party and 2 or 0)
    local t=targetReady and 1 or (target and 2 or 0)
    if reasonParty~=p or reasonTarget~=t then
        reasonParty,reasonTarget=p,t
        reason = ('Experimental native rendering: party %s; target %s.'):format(
            partyReady and 'active' or (party and 'unsupported' or 'off'),
            targetReady and 'active (native arrows preserved)' or (target and 'unsupported (target/cursor signatures not found)' or 'off'))
    end
    return active ~= 0
end

local indexes = { ['xiframes.us.1'] = 0, ['xiframes.us.2'] = 1, ['xiframes.us.3'] = 2,
    ['xiframes.tgt.main'] = 3, ['xiframes.tgt.sub'] = 4, ['xiframes.tgt.tot'] = 5 }
function hook.Uses(window)
    local index = indexes[window.name]
    return index ~= nil and bit.band(active, index < 3 and bit.lshift(1, index) or 8) ~= 0
end
function hook.Capture(window)
    return hook.Uses(window) and submit(indexes[window.name], 1) ~= 0 or false
end

local rectIndexes = { ['xiframes.us.1']=0, ['xiframes.us.2']=1, ['xiframes.us.3']=2, ['xiframes.tgt.main']=3 }
local rects = { {}, {}, {}, {} }
function hook.Rect(window)
    local index=rectIndexes[window.name]
    if index==nil or not hook.Uses(window) then return nil end
    local found=Find()
    if not found or found.GeometryReady==0 then return nil end
    local r=found.Rects[index]
    if r.Frame==0 or (tonumber(found.Frame)-tonumber(r.Frame))%4294967296>2 or r.Right<=r.Left or r.Bottom<=r.Top then return nil end
    local out=rects[index+1]
    out[1],out[2],out[3],out[4]=tonumber(r.Left),tonumber(r.Top),tonumber(r.Right),tonumber(r.Bottom)
    return out -- normalized to the native viewport; scale by ImGui's current display size
end

function hook.Status()
    local found = Find()
    if found and found.Hooked == 0 then return plugin .. ' did not recognise this client; native lists unchanged.' end
    -- Keep user-facing status quiet; cumulative counters remain internal to the ABI.
    return reason
end
return hook
