-- Run with tests/harness.lua party addons/party/party.lua.
H.load()
local imgui, theme = require('imgui'), require('winxi.theme')
local shadow = require('winxi.shadow')
local look = theme.Get()
local clip, rects, pushes, pops, backgrounds = nil, 0, 0, 0, 0
local list = {}
function list:PushClipRect(a, b, intersect)
    assert(not clip and intersect==false, 'replace the content clip')
    clip={a[1],a[2],b[1],b[2]}; pushes=pushes+1
    assert(clip[3]<=100 or clip[1]>=400 or clip[4]<=200 or clip[2]>=350,
        'shadow must not overpaint the existing window background/border')
end
function list:PopClipRect() assert(clip); clip=nil; pops=pops+1 end
function list:AddRectFilled(a,b,color,rounding)
    assert(clip and b[1]>a[1] and b[2]>a[2] and rounding>=2)
    rects=rects+1
end
imgui.GetWindowDrawList=function() return list end
imgui.GetBackgroundDrawList=function()
    backgrounds=backgrounds+1
    return {AddRectFilled=function() rects=rects+1 end}
end
look.ShadowEnabled,look.ShadowOpacity=true,17
for _,offset in ipairs({-8,0,2,8}) do
    for _,blur in ipairs({0,1,4,12}) do
        look.ShadowOffset,look.ShadowBlur=offset,blur
        local before=rects
        shadow.Draw(true)
        assert(not clip and pushes==pops and backgrounds==0, 'balanced clips, no global shadow')
        if offset~=0 or blur>1 then assert(rects>before, 'exterior shadow emitted') end
    end
end
local before=rects
look.ShadowEnabled=false
shadow.Draw(true)
assert(rects==before, 'disabled shadow emits nothing')
look.ShadowEnabled=true; look.ShadowOpacity=0
shadow.Draw(true)
assert(rects==before, 'zero opacity emits nothing')
look.ShadowOpacity=17; look.ShadowBlur=4
shadow.Draw()
assert(backgrounds==1 and rects==before+4, 'ordinary shadow keeps its original layers/list')
H.print('Party native shadow: exterior clips, offsets/blur, disabled/transparent, ordinary fallback passed')
