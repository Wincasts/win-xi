local input = dofile('addons/chatbox/input.lua')
assert(input.Prompt() == '> ', 'input prompt is just an arrow, with no mode label')
local opened, raw, display, caret = 0x11, 'hello world', 'hello world', 5
local chat = {
    IsInputOpen=function() return opened end,
    GetInputTextRaw=function() return raw end,
    GetInputTextDisplay=function() return display end,
    GetInputTextRawCaretPosition=function() return caret end,
}
local function decode(text, preserve)
    assert(preserve, 'input whitespace must never be trimmed')
    return text:gsub('\127\255',''):gsub('\130\160','あ')
end
local s=input.Snapshot(chat, decode)
assert(s.text=='hello world' and s.before=='hello')
raw,display,caret=' hello  ', ' hello  ',0
s=input.Snapshot(chat,decode); assert(s.text==' hello  ' and s.before=='')
caret=99; s=input.Snapshot(chat,decode); assert(s.before==raw,'caret clamped')
raw,display,caret='abcXYZ', 'abc\127\255PREVIEWXYZ', 1
s=input.Snapshot(chat,decode)
assert(s.before=='abc' and s.text=='abcPREVIEWXYZ','display caret wins during preview')
raw,display,caret='\130\160x', '\130\160x',2
s=input.Snapshot(chat,decode); assert(s.text=='あx' and s.before=='あ','native byte caret decoded on whole CP932 prefix')
display=''; s=input.Snapshot(chat,decode); assert(s.text=='あx','empty display falls back to raw')
chat.GetInputTextDisplay=function() error('older SDK') end
s=input.Snapshot(chat,decode); assert(s.text=='あx','missing display binding falls back')
opened=0; assert(input.Snapshot(chat,decode)==nil,'stale closed buffer never displayed')
opened=0x11; caret=0/0; assert(not pcall(input.Snapshot,chat,decode),'invalid caret fails open to native')
caret=0; raw=string.rep('x',8193); assert(not pcall(input.Snapshot,chat,decode),'buffer bounded')
raw='hello'; assert(not pcall(input.Snapshot,chat,function() return nil end),'decode failure rejected')
local layout=input.Layout(640,1920,1080,14,12,{0,1020,1920,1060})
assert(layout.matched and layout.x==0 and layout.bottom==1060 and layout.width==1920 and layout.height==40)
assert(layout.fontSize==14, 'native outer sizing keeps the requested text size')
layout=input.Layout(640,1920,1080,40,12,{0,1020,1920,1060},3,3)
assert(layout.matched and layout.fontSize==40 and layout.height==46 and layout.bottom==1060,
    'a font too big for the native bar grows the bar upward from its foot, never shrinks the text')
layout=input.Layout(640,1920,1080,14,12,nil)
assert(not layout.matched and layout.width==640 and layout.height==38 and layout.fontSize==14)
for _,rect in ipairs({ {0,0,0,30}, {0,0,500,0}, {-1,100,400,130}, {0,0,1921,30}, {0,0,640,300}, {0,0,0/0,30} }) do
    assert(not input.Layout(640,1920,1080,14,12,rect).matched, 'bad geometry falls back to WinXI sizing')
end
layout=input.Layout(640,3840,2160,14,12,{0,2040,3840,2120})
assert(layout.width==3840 and layout.height==80 and layout.fontSize==14,'native geometry preserves compact text')
print('Chatbox input: native editor snapshot, whitespace, caret, preview, CP932, closed state and failure passed')
