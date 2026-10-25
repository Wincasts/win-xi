-- Actual FFI quad pipeline; no native device or GPU objects.
local ffi,bit=require('ffi'),require('bit')
local custom,casts,plates=require('custom'),require('castbar'),require('winxi.nameplates')
local imgui=require('imgui')
local packets=dofile('tests/fixtures/parse_packets.lua')
ffi.cdef('void* mmap(void*, size_t, int, int, int, long); int munmap(void*, size_t);')
local bytes=ffi.sizeof('namehook_draw_t')
local low=ffi.C.mmap(nil,bytes+16,3,0x62,-1,0);assert(low~=ffi.cast('void*',-1))
local draw=ffi.cast('namehook_draw_t*',low);draw.QuadsMax=16384
local guard=ffi.cast('uint8_t*',low)+bytes;ffi.fill(guard,16,0xA5)
local hook=ffi.new('namehook_t')
hook.Hooked,hook.Draw=1,tonumber(ffi.cast('uintptr_t',low))
hook.Width,hook.Height,hook.TargetWidth,hook.TargetHeight=1920,1080,1920,1080
hook.Count=1
local name=hook.Names[0]
name.EntityIndex,name.ServerId,name.Category=1,1001,plates.Category.Player
name.Scale,name.NameColor,name.Flags=1,0x80808080,bit.bor(plates.Flag.Wanted,plates.Flag.OnScreen)
ffi.copy(name.Name,'Player');ffi.copy(name.Text,'Player')
local options=custom.Defaults({})
options.nameFormat[1],options.monsterFormat[1]='[name]','[name]'
options.showStars[1],options.showCheckDetails[1]=false,false
options.showStatuses={false};options.npcFormat[1]='[name]'
local glyph={X0=0,Y0=0,X1=8,Y1=12,U0=0,V0=0,U1=1,V1=1,AdvanceX=8,Visible=1}
local font={ContainerAtlas={TexData={UniqueID=2,Status=0,Width=512,Height=256},TexUvWhitePixel={x=.125,y=.25}}}
imgui.GetFont=function() return font end
imgui.GetFontBaked=function() return {FindGlyph=function() return glyph end} end
imgui.PushFont,imgui.PopFont=function() end,function() end
imgui.GetIO=function() return {DisplaySize={x=1920,y=1080}} end
imgui.GetFontTexUvWhitePixel=function() return .125,.25 end
local hp=50
local memory=AshitaCore:GetMemoryManager()
memory.GetEntity=function() return {GetServerId=function(_,index) return 1000+index end,GetHPPercent=function() return hp end} end
AshitaCore.GetMemoryManager=function() return memory end
AshitaCore.GetResourceManager=function() return {GetSpellById=function() return {Name={'Fire'},CastTime=16} end} end
package.loaded['winxi.spells']={Get=function() return {Data={castTime=4000}} end}
custom.SetSheets(0,0)
local clock,now=os.clock,100;os.clock=function() return now end
local statusFoot
require('statuses').Begin=function() return true end
require('statuses').Write=function(_,left,right,clear,under) statusFoot=under end
local function render(capacity)
    draw.QuadsMax=capacity or 16384;hook.Frame=hook.Frame+1
    assert(custom.Frame(options,hook)==nil)
    for i=0,15 do assert(guard[i]==0xA5,'write beyond the FFI draw buffer') end
    assert(draw.QuadCount<=draw.QuadsMax and draw.Entities[1].Count<=256)
    local bars={}
    for i=0,draw.QuadCount-1 do
        local q=draw.Quads[i]
        assert(q.X0==q.X0 and q.Y0==q.Y0 and (q.Texture==0 or q.Texture==4))
        if q.Color==0xFF101010 then bars[#bars+1]={x=q.X0,y=q.Y0,w=q.X1-q.X0,h=q.Y1-q.Y0,at=i} end
    end
    return bars
end
local baseline=render();assert(#baseline==0)
options.showHealthBar[1]=true
local hpOnly=render();assert(#hpOnly==1)
local original={x=hpOnly[1].x,y=hpOnly[1].y,w=hpOnly[1].w,h=hpOnly[1].h}
options.showHealthBar[1]=false;options.showCastBar[1]=true
local raw=packets.Packet(1001,8,24931,{{id=2001,results={{value=144,message=327}}}},1)
-- Exercise Name's registered packet callback, not just the tracker directly.
local saved=H.options()
saved.showCastBar[1]=true;saved.showStatuses[1]=false
H.packetData(0x028,raw)
local only=render();assert(#only==1)
assert(only[1].x==original.x and only[1].y==original.y and only[1].w==original.w and only[1].h==original.h,
    'cast-only starts at exactly the original HP bar position with shared dimensions')
local castFill
now=102
local half=render()
castFill=draw.Quads[half[1].at+2]
assert(castFill.Color==draw.Quads[draw.Entities[1].First].Color,'cast fill inherits the resolved name tint')
assert(castFill and math.abs((castFill.X1-castFill.X0)/(half[1].w-2)-.5)<.001,'cast fills forward with elapsed time')
local textBottom=half[1].y+half[1].h
local lines={}
for i=half[1].at+3,draw.QuadCount-1 do
    local q=draw.Quads[i]
    assert(q.Y0>textBottom,'action name and timer belong below the cast bar')
    lines[q.Y0]=true
end
local lineCount=0;for _ in pairs(lines) do lineCount=lineCount+1 end
assert(lineCount==2 and statusFoot>textBottom,'separate action/timer rows and status layout below them')
options.showHealthBar[1]=true
local both=render();assert(#both==2 and both[1].y==original.y and both[2].y>both[1].y+both[1].h)
assert(both[1].x==both[2].x and both[1].w==both[2].w and both[1].h==both[2].h,'rows must have matching sizes and origins')
options.healthBarCategories[1]=plates.Category.Monster
local filtered=render();assert(#filtered==1 and filtered[1].y==original.y,'HP entity filters do not suppress casts')
options.healthBarCategories[1]=plates.Category.All
options.healthBarsCombatOnly[1]=true
assert(#render()==1,'HP combat-only filter does not suppress an out-of-combat cast')
options.healthBarsCombatOnly[1]=false
hp=100
local full=render();assert(#full==2 and full[2].y==both[2].y,'full HP stays above an active cast without shifting it')
options.healthBarWidth[1],options.healthBarHeight[1]=100,10
local resized=render();assert(resized[1].w==100 and resized[2].w==100 and resized[1].h==10 and resized[2].h==10)
-- Below-name status anchor includes the actual action/timer glyphs.
local maxText=0
for i=resized[2].at+3,draw.QuadCount-1 do maxText=math.max(maxText,draw.Quads[i].Y1) end
assert(statusFoot>=maxText)
-- Sustained crowd mode must not simplify an actively casting plate away.
options.crowdDeclutter[1],options.crowdThreshold[1],options.crowdHold[1]=true,4,250
hook.Count=4
for i=0,3 do
    local n=hook.Names[i]
    n.EntityIndex,n.ServerId,n.Category=i+1,1001+i,plates.Category.Player
    n.Scale,n.NameColor,n.Flags=1,0x80808080,bit.bor(plates.Flag.Wanted,plates.Flag.OnScreen)
    n.ScreenX,n.ScreenY=100+i*50,100
    ffi.copy(n.Name,'Player');ffi.copy(n.Text,'Player')
end
render();now=now+.3
assert(#render()==2,'active casters keep HP and cast rows in crowd mode')
options.crowdDeclutter[1]=false;hook.Count=1
-- Scale each caption independently; geometry must not change with text size.
options.castNameScale[1],options.castTimerScale[1]=150,50
local scaled=render()
local firstCaption=draw.Quads[scaled[2].at+3]
local lastCaption=draw.Quads[draw.QuadCount-1]
assert(firstCaption.Y1-firstCaption.Y0==18 and lastCaption.Y1-lastCaption.Y0==6)
assert(scaled[2].w==100 and scaled[2].h==10 and statusFoot>=lastCaption.Y1)
options.castNameScale[1],options.castTimerScale[1]=75,75
-- Resolve explicit name-token colours rather than spell/WS-specific colours.
options.nameFormat[1]='[name:#FF8000]'
local tinted=render();assert(draw.Quads[tinted[2].at+2].Color==0xFFFF8000)
options.nameFormat[1]='[name]'
-- Auto-width measures only the visible name/letters, not surrounding details.
options.castBarAutoWidth[1]=true;options.healthBarWidth[1]=12
local automatic=render();assert(automatic[2].w==48 and automatic[1].w==automatic[2].w)
options.nameFormat[1]='Prefix [name] suffixlong'
local decorated=render();assert(decorated[2].w==48 and decorated[2].x~=automatic[2].x)
options.nameFormat[1]='[name]'
name.Category=plates.Category.Monster
local levels=require('levels');local letter=levels.Letter;levels.Letter=function() return 'A' end
options.monsterFormat[1]='[name] [letters]'
local withLetter=render();assert(withLetter[2].w>48 and withLetter[1].w==withLetter[2].w,'visible letter badges count as name width')
options.monsterFormat[1]='[letters] [name]'
local beforeLetter=render();assert(beforeLetter[2].w==withLetter[2].w,'letter order must not change total width')
levels.Letter=letter;name.Category=plates.Category.Player;options.monsterFormat[1]='[name]'
options.healthBarWidth[1]=100
assert(render()[2].w==100,'saved width is the minimum for a short name')
options.castBarAutoWidth[1]=false
-- Cast text: white by default, the name's colour, a custom colour; name and timer each optional.
options.showHealthBar[1]=false
local function captions()
    local bars=render();local list={}
    for i=bars[1].at+3,draw.QuadCount-1 do list[#list+1]=draw.Quads[i] end
    return list
end
local function rows(list) local seen,n={},0;for _,q in ipairs(list) do if not seen[q.Y0] then seen[q.Y0]=true;n=n+1 end end;return n end
local both=captions();assert(#both>0 and rows(both)==2)
for _,q in ipairs(both) do assert(q.Color==0xFFFFFFFF,'cast text is white by default') end
options.nameFormat[1]='[name:#FF8000]';options.castTextColour[1]='name'
for _,q in ipairs(captions()) do assert(q.Color==0xFFFF8000,'cast text in the name colour') end
options.nameFormat[1]='[name]';options.castTextColour[1]='custom';options.castTextColor={0,1,0,1}
for _,q in ipairs(captions()) do assert(q.Color==0xFF00FF00,'cast text in the custom colour') end
options.castTextColour[1]='white'
options.castShowTimer[1]=false
local nameOnly=captions();assert(rows(nameOnly)==1 and #nameOnly<#both,'timer hidden')
options.castShowTimer[1],options.castShowName[1]=true,false
local timerOnly=captions();assert(rows(timerOnly)==1 and #timerOnly<#both,'action name hidden')
options.castShowTimer[1]=false
assert(#captions()==0,'no cast text at all');
options.castShowName[1],options.castShowTimer[1]=true,true
-- Cast text in a font of its own: drawn from imgui's texture as it is (4), its letters asked of that font
local pushed,push,addFont={},imgui.PushFont,imgui.AddFontFromFileTTF
imgui.PushFont=function(f) pushed[#pushed+1]=f==nil and 'usual' or f end
local castFace={}
imgui.AddFontFromFileTTF=function(path) if path:find('georgia.ttf',1,true) then return castFace end end
for _,q in ipairs(captions()) do assert(q.Texture==0,'the names\' font as before') end
local function asked(face) for _,f in ipairs(pushed) do if f==face then return true end end return false end
options.castFont[1]='georgia.ttf';pushed={}
local own=captions();assert(#own==#both)
for _,q in ipairs(own) do assert(q.Texture==4,'a font of its own from imgui\'s texture') end
assert(asked(castFace),'its letters asked of the chosen font')
options.castFont[1]=custom.CastDefaultFont;pushed={}
for _,q in ipairs(captions()) do assert(q.Texture==4) end
assert(asked('usual'),'Default: the usual font')
options.castFont[1]='missing.ttf'
for _,q in ipairs(captions()) do assert(q.Texture==0,'a font that will not load: the names\' own') end
options.showCastBar[1]=false;pushed={};render();options.showCastBar[1]=true
options.castFont[1]='georgia.ttf';options.showCastBar[1]=false;pushed={};render()
assert(not asked(castFace),'not asked for while cast bars are off')
options.showCastBar[1]=true;options.castFont[1]=''
H.packetData(0x028,raw) -- turning cast bars off forgot the cast
imgui.PushFont,imgui.AddFontFromFileTTF=push,addFont
-- A textured cast bar: winxi's art, from the sheet shared with the special signs (6)
local barArt,image=require('bar_art'),require('gdi.image')
local load,upload,free=barArt.LoadImage,barArt.Upload,barArt.Free
barArt.LoadImage=function(path)
    if path:find('special',1,true) then return image.new(256,128) end
    return image.new(path:find('front',1,true) and 226 or path:find('fill',1,true) and 204 or 220,28)
end
barArt.Upload=function() return {},0x5000 end;barArt.Free=function() end
options.castBarTexture[1]='glass'
now=now+2 -- half way, so that there is a fill
draw.QuadsMax=16384;hook.Frame=hook.Frame+1;assert(custom.Frame(options,hook)==nil)
local art,plain,captionsAfter=0,0,0
for i=0,draw.QuadCount-1 do
    local q=draw.Quads[i]
    if q.Texture==6 then art=art+1 elseif q.Color==0xFF101010 then plain=plain+1 end
end
assert(art==7 and plain==0 and draw.Textures[6]==0x5000,'the cast bar in the art, the sheet published')
options.castBarTexture[1]='plain'
assert(#render()==1 and draw.Textures[6]==0,'plain again, the sheet let go')
barArt.LoadImage,barArt.Upload,barArt.Free=load,upload,free
options.showHealthBar[1]=true
-- Font overshoots/descenders must not push cast text into its bar or statuses.
glyph.Y0,glyph.Y1=-4,20;font.ContainerAtlas.TexData.UniqueID=3
local overshoot=render()
local endOfBar=overshoot[2].y+overshoot[2].h
for i=overshoot[2].at+3,draw.QuadCount-1 do
    assert(draw.Quads[i].Y0>endOfBar and draw.Quads[i].Y1<=statusFoot)
end
for _,capacity in ipairs({1,6,10,20,16384}) do render(capacity) end
casts.HandlePacket({id=0x028,data=packets.Packet(1001,4,144,{},2)},options)
assert(#render()==0,'completed spell removes cast, and ordinary full HP is hidden again')
casts.Preview[1]=true;casts.PreviewVisible(now)
assert(#render()==2,'idle preview uses the real HP/cast stacking pipeline')
-- Weaponskills and TP moves are text alone by default; spells keep their bar.
options.castBarWeaponskills[1]=true
now=now+4.5;casts.PreviewVisible(now)
local skillOnly=render();assert(#skillOnly==1,'a TP move draws no cast bar, only the HP row')
local skillText=0
for i=skillOnly[1].at+3,draw.QuadCount-1 do
    assert(draw.Quads[i].Y0>skillOnly[1].y+skillOnly[1].h);skillText=skillText+1
end
assert(skillText>0,'a TP move still writes its name and timer')
options.castBarSkillTextOnly[1]=false
assert(#render()==2,'a TP move has its bar with Text Only for Weaponskills off')
options.castBarSkillTextOnly[1],options.castBarWeaponskills[1]=true,false
now=now+.3;assert(#render()==0,'closed preview control expires without a fake action record')
options.showCastBar[1]=false;hp=50
assert(#render()==1,'disabled cast bars preserve the HP-only pipeline')
glyph.Y0,glyph.Y1=0,12;font.ContainerAtlas.TexData.UniqueID=4
local plainWidth=render()[1].w
options.castBarAutoWidth[1]=true;options.healthBarWidth[1]=12
local fitted=render();assert(#fitted==1 and fitted[1].w==48,'Fit to Name widens a health bar with no cast')
options.healthBarWidth[1]=100
assert(render()[1].w==100,'the saved width still the least')
options.castBarAutoWidth[1]=false;assert(render()[1].w==plainWidth)
custom.Deactivate();os.clock=clock
ffi.C.munmap(low,bytes+16)
H.print('Cast rendering: shared origin/dimensions, HP above cast including full HP, progress, labels/timer below, status clearance, packet hookup and bounded writes passed',true)
