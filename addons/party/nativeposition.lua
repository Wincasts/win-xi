-- Default HUD anchoring is independent of automatic edge layout and never edits saved positions/links.
local placement = {}
local available=false -- parked for the testing build; settings cannot reactivate native anchoring
function placement.GroupRequested(saved,key)
    if key=='party1' or key=='party2' or key=='party3' then return saved.nativeParty[1] and saved.party.enabled[1] end
    if key=='main' or key=='sub' or key=='tot' then return saved.nativeTarget[1] and saved.target.enabled[1] end
    return false
end
function placement.Enabled(saved,key)
    if not available or not saved.nativePositioning[1] or not placement.GroupRequested(saved,key) then return false end
    if key=='party2' then return saved.nativeAlliance2[1] end
    if key=='party3' then return saved.nativeAlliance3[1] end
    return key=='party1' or key=='main' -- sub/ToT have no independent stock HUD rectangle
end
function placement.ManualOverride(saved,key)
    return available and saved.nativePositioning[1] and placement.GroupRequested(saved,key)
        and ((key=='party2' and not saved.nativeAlliance2[1]) or (key=='party3' and not saved.nativeAlliance3[1]))
end
local function finite(x) return type(x)=='number' and x==x and x>-math.huge and x<math.huge end
function placement.Place(key,rect,displayWidth,displayHeight,width,height,followBehavior)
    if not rect or not finite(displayWidth) or not finite(displayHeight) or displayWidth<=0 or displayHeight<=0
        or not finite(width) or not finite(height) or width<0 or height<0 then return nil end
    for i=1,4 do if not finite(rect[i]) then return nil end end
    if rect[3]<=rect[1] or rect[4]<=rect[2] then return nil end
    local left=rect[3]*displayWidth-width
    -- Main party grows upward from the stock bottom/right; alliances stay at their own top/right.
    local top=(key=='party2' or key=='party3') and rect[2]*displayHeight or rect[4]*displayHeight-height
    if not followBehavior then
        left=math.max(0,math.min(math.max(0,displayWidth-width),left))
        top=math.max(0,math.min(math.max(0,displayHeight-height),top))
    end
    return left,top
end
return placement
