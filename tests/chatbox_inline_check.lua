package.path = 'addons/chatbox/?.lua;' .. package.path
local model, rich = require('log'), require('richtext')
local palette = require('palette')
local measure = function(text) return #text end
local source = model.New()
local spans = {{first=1,last=11,bank=31,slot=2},{first=18,last=22,bank=30,slot=5}}
model.Add(source, 'Alice casts Fire\nCrab burns.', 50, 1, 50, spans)
local rows = model.Tail(source, 6, 'font', 12, measure, 20)
for _, row in ipairs(rows) do
    for _, s in ipairs(row.spans or {}) do
        assert(s.first >= 1 and s.last <= #row.text, 'wrapping clips spans to visible row bytes')
    end
end
assert(rows[2].text == 'casts' and rows[2].spans[1].last == 5, 'colour persists over wrapping / dropped whitespace')
assert(rows[4].text == 'Crab' and rows[4].spans[1].first == 1 and rows[4].spans[1].last == 4,
    'source paragraph breaks preserve and rebase spans without a combat formatter')
local npc = model.New()
model.Add(npc, 'Bob: Hello', 150, 1, 150, {{first=6,last=10,bank=31,slot=2}})
assert(npc.messages[1].text == 'Bob [NPC]: Hello')
local tag = npc.messages[1].spans[1]
assert(tag.first == 6 and tag.last == 8 and tag.bank == 31 and tag.slot == 50, 'only NPC letters receive yellow')
assert(npc.messages[1].spans[2].first == 12, 'NPC marker insertion shifts later spans')
model.Add(npc,'Bob: Hello',150,3,150,{{first=1,last=10,bank=31,slot=2}})
local spans = npc.messages[2].spans
assert(#spans == 3 and spans[1].last == 5 and spans[2].first == 6 and spans[2].last == 8
    and spans[3].first == 9 and spans[3].last == 16 and spans[3].slot == 2,
    'yellow tag splits a spanning source colour without recolouring brackets or dialogue')
local wrapped = model.Tail(npc,8,'font',12,function(s) return #s end,20)
local foundYellow = false
for _, row in ipairs(wrapped) do
    for _, span in ipairs(row.spans or {}) do
        if span.slot == 50 then
            assert(row.text:sub(span.first,span.last):match('^[NPC]+$'),'wrapped yellow span contains only tag letters')
            foundYellow = true
        end
    end
end
assert(foundYellow, 'NPC tag colour survives wrapping')
local hits = model.New()
local text = 'Alice hits Crab for 123 points of damage.'
model.Add(hits,text,20,1,20,{{first=1,last=5,bank=31,slot=2}})
model.Add(hits,text,20,1.1,20,{{first=1,last=5,bank=31,slot=2}})
assert(#hits.messages == 2 and hits.messages[1].text == text and hits.messages[2].text == text,
    'source combat messages are never compacted, grouped or stamped')
assert(palette.Color(30,1) == nil and palette.Color(31,1) == nil, 'both reset codes use line default')
assert(palette.Color(30,2)[1] ~= palette.Color(31,2)[1], 'palette banks remain distinct')
assert(palette.Color(99,2) == nil and palette.Color(31,0) == nil)
assert(palette.Mode(1)[1] == 1 and palette.Mode(1)[2] == 1 and palette.Mode(1)[3] == 1, 'Say is white, not inline reset')
assert(palette.Mode(9) == palette.Mode(1), 'incoming Say is white too')
for _, mode in ipairs({2,3,4,5,6,7,10,11,12,13,14,15,205,211,212,213,214,217,50,123}) do
    assert(palette.Mode(mode) == palette.Color(31,mode), 'mode uses the native second-palette slot: '..mode)
end
assert(palette.Mode(nil) == nil and palette.Mode(-1) == nil and palette.Mode(256) == nil
    and palette.Mode(1.5) == nil and palette.Mode('tell') == nil, 'invalid modes allow the window/theme fallback')
local drawn = {}
package.loaded.imgui = {
    CalcTextSize=measure, GetFontSize=function() return 12 end,
    GetColorU32=function(c) return c end,
}
local render = require('render')
local list = {AddText=function(_, pos, color, text) drawn[#drawn+1]={x=pos[1],color=color,text=text} end}
render.Rich(list, {10,20}, 'base', 'ABCDEF', {{first=2,last=4,bank=31,slot=2}})
assert(#drawn == 3 and drawn[1].text == 'A' and drawn[2].text == 'BCD' and drawn[3].text == 'EF')
assert(drawn[1].color == 'base' and drawn[2].color == palette.Color(31,2) and drawn[3].color == 'base')
assert(drawn[2].x == 11 and drawn[3].x == 14, 'span advances use the same measurement as wrapping')
print('Chatbox inline: palette banks/reset, source preservation, wrap, paragraphs, NPC labels and drawing passed')
