-- Brackets must not depend on glyph coverage of the selected font.
local drawn, lines = {}, {}
package.loaded.imgui = {
    GetFontSize=function() return 20 end,
    CalcTextSize=function(text) assert(not text:find('❮',1,true) and not text:find('❯',1,true)); return #text*10,20 end,
    GetColorU32=function(color) return color end,
}
local render=dofile('addons/chatbox/render.lua')
local list={
    AddText=function(_,pos,color,text) drawn[#drawn+1]={pos=pos,text=text} end,
    AddLine=function(_,a,b,color,thickness) lines[#lines+1]={a=a,b=b,color=color} end,
}
assert(render.Measure('a❮word❯b')==86, 'text width includes geometric brackets')
render.Text(list,{10,20},0,'a❮word❯b')
assert(#lines==4 and #drawn==3 and drawn[2].text=='word' and drawn[2].pos[1]==33)
assert(drawn[3].pos[1]==86, 'drawing uses the same advances as wrapping and caret measurement')
assert(lines[1].color[2]==1 and lines[3].color[1]==1, 'opening green, closing red')
assert(render.Measure('❮')==13 and render.Measure('❮word')==53, 'partial input prefixes measure consistently')
render.Text(list,{0,0},0,'❮❯')
assert(#lines==8 and #drawn==3, 'adjacent icons never go through font rendering')
print('Chatbox render: font-independent coloured brackets, wrapping and caret advances passed')
