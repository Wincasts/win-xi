-- Every line given to the game's chat log, read through uihook (independent text ABI 1, magic UIHOOK-TEXT): each as
-- the game was given it and as it will keep it after every plugin and addon loaded before uihook, with its modes and
-- flags. An addon whose own text_in handler runs before a formatter's (loaded before SimpleLog, say) takes each line
-- from here instead, so the load order no longer matters to it. Nothing is written to the game.
--
--   local tap = require('winxi.nativetext').new()
--   tap.Ready()         -- true while uihook keeps the lines (0.8 or newer, loaded)
--   tap.Drain()         -- the lines recorded since the last Drain (none the first time: it starts at the newest),
--                       --   oldest first, each { serial, mode, finalMode, original, text, injected, blocked, indent,
--                       --   modified, cut }: text the bytes the game will keep; nil while uihook does not keep them
--   tap.Status()
local ffi=require('ffi')
ffi.cdef[[typedef struct {
    uint32_t Serial,Mode,FinalMode,Flags,OriginalLength,FinalLength;
    char Original[4096]; char Final[4096];
} uihook_text_event_t;
typedef struct {
    char Magic[16]; uint32_t Version,Size,Frame,Serial;
    uihook_text_event_t Events[64];
} uihook_text_t;]]
local EVENTS,LINE=64,4096
local INJECTED,BLOCKED,INDENT,MODIFIED,CUT=1,2,4,8,16
local M={}
function M.new()
    local block,base,looked=nil,nil,-1
    local reason='Load uihook 0.8 or newer to read each chat line after every addon.'
    local function Find()
        if not AshitaCore:GetPluginManager():IsLoaded('uihook') then
            block,base,looked=nil,nil,-1; reason='Load uihook 0.8 or newer to read each chat line after every addon.'; return nil
        end
        local current=ashita.memory.get_base('uihook.dll')
        if current~=base then block,base,looked=nil,current,-1 end
        if not current or current==0 then reason='uihook DLL is not ready.'; return nil end
        if not block then
            if os.clock()-looked<1 then return nil end
            looked=os.clock()
            local at=ashita.memory.find('uihook.dll',0,'5549484F4F4B2D544558540000000000',0,0)
            if not at or at==0 then reason='Update uihook to 0.8 or newer: chat lines are read as they reach chatbox.'; return nil end
            local found=ffi.cast('uihook_text_t*',at)
            if found.Version~=1 or found.Size~=ffi.sizeof('uihook_text_t') then
                reason='uihook text ABI mismatch; install the matching DLL.'; return nil
            end
            block=found
        end
        return block
    end
    local hook={}
    local last=nil -- the serial last read; nil until the block is first seen, then the newest at that moment
    function hook.Ready() return Find()~=nil end
    function hook.Drain()
        local b=Find()
        if not b then last=nil; return nil end
        local newest=tonumber(b.Serial)
        if last==nil or last>newest then last=newest; reason='Reading each chat line after every addon.'; return {} end
        if newest-last>EVENTS then last=newest-EVENTS end -- further behind than the ring holds: the oldest lost
        local list,read={},last
        for serial=last+1,newest do
            local e=b.Events[(serial-1)%EVENTS]
            if tonumber(e.Serial)~=serial then break end -- not whole yet: read next time
            local flags=tonumber(e.Flags)
            local originalLength,finalLength=math.min(tonumber(e.OriginalLength),LINE),math.min(tonumber(e.FinalLength),LINE)
            list[#list+1]={serial=serial,mode=tonumber(e.Mode),finalMode=tonumber(e.FinalMode),
                original=ffi.string(e.Original,originalLength),text=ffi.string(e.Final,finalLength),
                injected=bit.band(flags,INJECTED)~=0,blocked=bit.band(flags,BLOCKED)~=0,indent=bit.band(flags,INDENT)~=0,
                modified=bit.band(flags,MODIFIED)~=0,cut=bit.band(flags,CUT)~=0}
            read=serial
        end
        last=read
        reason=('Reading each chat line after every addon; %d so far.'):format(newest)
        return list
    end
    function hook.Status() Find(); return reason end
    return hook
end
return M
