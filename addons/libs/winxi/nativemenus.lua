-- Publish the captured info panel's pixel bounds. Native layout (not GPU/mouse translation)
-- moves only the verified action-menu family. Independent of the read-only chat ABI.
local ffi=require('ffi')
ffi.cdef[[typedef struct {
    char Magic[16]; uint32_t Version,Size,Frame,Supported,RequestFrame,HostSlot;
    float Panel[4]; uint32_t MenuFrame,Applied,Restored; char LastName[16];
    uint32_t LogRequestFrame; float LogPlace[2]; uint32_t LogFrame,LogApplied,LogRestored;
} uihook_menus_t;]]
local M={}
function M.new()
    local block,base,owned,looked=nil,nil,false,-1
    local reason='Update uihook for native menu anchoring.'
    local function Find()
        if not AshitaCore:GetPluginManager():IsLoaded('uihook') then
            block,base,owned,looked=nil,nil,false,-1; reason='Load uihook for native menu anchoring.'; return nil
        end
        local current=ashita.memory.get_base('uihook.dll')
        if current~=base then block,base,owned,looked=nil,current,false,-1 end
        if not current or current==0 then reason='uihook DLL is not ready.'; return nil end
        if not block then
            if os.clock()-looked<1 then return nil end
            looked=os.clock()
            local at=ashita.memory.find('uihook.dll',0,'5549484F4F4B2D4D454E55530000000000',0,0)
            if not at or at==0 then reason='Update uihook: native menu anchoring is unavailable.'; return nil end
            local found=ffi.cast('uihook_menus_t*',at)
            if found.Version~=1 or found.Size~=ffi.sizeof('uihook_menus_t') then
                reason='uihook menu ABI mismatch; install the matching DLL.'; return nil
            end
            block=found
        end
        if block.Supported==0 then reason='uihook did not recognise native action-menu layout; menus unchanged.'; return nil end
        return block
    end
    local hook={}
    function hook.Set(rect,slot)
        if type(rect)~='table' or (slot~=0 and slot~=1) then return false end
        for _,key in ipairs({'left','top','width','height'}) do
            local v=rect[key]
            if type(v)~='number' or v~=v or math.abs(v)==math.huge then return false end
        end
        if rect.left<0 or rect.top<0 or rect.width<=0 or rect.height<=0 then return false end
        local b=Find(); if not b then return false end
        local values={rect.left,rect.top,rect.left+rect.width,rect.top+rect.height}
        for i=1,4 do b.Panel[i-1]=values[i] end
        b.HostSlot=slot
        b.RequestFrame=b.Frame -- commit only after all bounds; must be renewed with a successful capture
        owned=true; reason='Native action menus anchor above the info panel.'
        return true
    end
    function hook.Stop()
        if not owned then return end
        local b=Find(); if b then b.RequestFrame=0 end
        owned=false
    end
    -- The expanded chat log placed by its bottom-left (display pixels), renewed each frame; it goes back to the
    -- game's place two frames after the last. Its size, rows and hit-tests are the game's, moved with it.
    local logOwned=false
    function hook.PlaceLog(left,bottom)
        if type(left)~='number' or type(bottom)~='number' or left~=left or bottom~=bottom
            or math.abs(left)==math.huge or math.abs(bottom)==math.huge or left<0 or bottom<=0 then return false end
        local b=Find(); if not b then return false end
        b.LogPlace[0],b.LogPlace[1]=left,bottom
        b.LogRequestFrame=b.Frame -- after the place, as Set's commit
        logOwned=true
        return true
    end
    function hook.StopLog()
        if not logOwned then return end
        local b=Find(); if b then b.LogRequestFrame=0 end
        logOwned=false
    end
    function hook.Status() if Find() and not owned then return 'Native menu anchoring ready.' end return reason end
    return hook
end
return M
