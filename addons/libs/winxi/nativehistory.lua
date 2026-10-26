-- The game's first log window's history, read through uihook (independent history ABI 1, magic UIHOOK-HISTORY):
-- the game's ring of 100 lines, each decoded back to the bytes the game was given (CP932 with its 1E/1F colour
-- codes). Read once for each Request, nothing written to the game. The game keeps each message as the lines it
-- wrapped it into; each line comes with its whole mode word, its serial, its flags and +38 as the game left them.
--
--   local history = require('winxi.nativehistory').new()
--   history.Request()        -- ask for a read (uihook serves it on its next frame)
--   history.Lines()          -- once served: { { text, mode, serial, flags, extra }, ... } oldest first; nil before
--   history.Status()
local ffi=require('ffi')
local abi=require('winxi.abi')
ffi.cdef[[typedef struct {
    char Magic[16]; uint32_t Version,Size,Frame,Supported,RequestFrame,Serial,ReadFrame,Count,Used;
    struct { uint32_t Offset,Length,Mode,Serial,Flags,Extra; } Lines[100];
    char Text[65536];
} uihook_history_t;]]
local M={}
function M.new()
    local block,base,looked=nil,nil,-1
    local reason='Load uihook to read the game\'s chat history.'
    local function Find()
        if not AshitaCore:GetPluginManager():IsLoaded('uihook') then
            block,base,looked=nil,nil,-1; reason='Load uihook to read the game\'s chat history.'; return nil
        end
        local current=ashita.memory.get_base('uihook.dll')
        if current~=base then block,base,looked=nil,current,-1 end
        if not current or current==0 then reason='uihook DLL is not ready.'; return nil end
        if not block then
            if os.clock()-looked<1 then return nil end
            looked=os.clock()
            local at=ashita.memory.find('uihook.dll',0,'5549484F4F4B2D484953544F52590000',0,0)
            if not at or at==0 then reason='Update uihook: the game\'s chat history cannot be read.'; return nil end
            local found=ffi.cast('uihook_history_t*',at)
            if not abi.Accepts(found,'uihook_history_t',1) then
                reason='uihook history ABI mismatch; install the matching DLL.'; return nil
            end
            block=found
        end
        if block.Supported==0 then reason='uihook did not recognise the game\'s chat windows.'; return nil end
        return block
    end
    local hook={}
    local asked=nil -- the serial before the request, while it is waiting
    function hook.Request()
        local b=Find(); if not b then return false end
        asked=tonumber(b.Serial)
        b.RequestFrame=b.Frame~=0 and b.Frame or 1
        reason='Reading the game\'s chat history.'
        return true
    end
    function hook.Lines()
        if asked==nil then return nil end
        local b=Find(); if not b then return nil end
        if tonumber(b.Serial)==asked then return nil end
        asked=nil
        local list,count,used={},math.min(tonumber(b.Count),100),tonumber(b.Used)
        for i=0,count-1 do
            local l=b.Lines[i]
            local offset,length=tonumber(l.Offset),tonumber(l.Length)
            local text=''
            if length>0 and offset+length<=math.min(used,65536) then text=ffi.string(b.Text+offset,length) end
            list[#list+1]={text=text,mode=tonumber(l.Mode),serial=tonumber(l.Serial),flags=tonumber(l.Flags),extra=tonumber(l.Extra)}
        end
        reason=('Read %d lines of the game\'s chat history.'):format(#list)
        return list
    end
    function hook.Status() Find(); return reason end
    return hook
end
return M
