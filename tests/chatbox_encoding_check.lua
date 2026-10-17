-- Exercise the decoder's Windows conversion contract without loading kernel32 on Linux.
package.path = 'addons/chatbox/?.lua;' .. package.path
local cleaned, fail, parsed = nil, false, false
local decoded = { ['\n']='\n', ['hello world']='hello world', [' hello world ']=' hello world ', ['\130\160']='あ',
    ['\129\239\39']="○'", ['Hill Lizard']='Hill Lizard', ['Hill?Lizard']='Hill?Lizard',
    ['\130\160 \130\160']='あ あ',
    ['The Stalking Sapling hits Win for 190 points of damage.']='The Stalking Sapling hits Win for 190 points of damage.',
    ['[02:13:24] The Stalking Sapling hits Win for 190 points of damage.']='[02:13:24] The Stalking Sapling hits Win for 190 points of damage.' }
local kernel = {}
function kernel.MultiByteToWideChar(cp, flags, text, count, out, capacity)
    assert(cp==932 and flags==0 and count==#text and parsed)
    cleaned=text
    if fail then return 0 end
    if out then assert(capacity==#text); out.text=text end
    return #text
end
function kernel.WideCharToMultiByte(cp, flags, wide, count, out, capacity, default, used)
    assert(cp==65001 and flags==0 and count==#wide.text and default==nil and used==nil)
    local text=assert(decoded[wide.text] or (not wide.text:find('[\128-\255]') and wide.text), 'unexpected cleaned input')
    if out then assert(capacity==#text); out.text=text end
    return #text
end
package.loaded.ffi = {
    cdef=function() end,
    load=function(name) assert(name=='kernel32'); return kernel end,
    new=function() return {} end,
    string=function(output,size) assert(size==#output.text); return output.text end,
}
AshitaCore={GetChatManager=function() return {ParseAutoTranslate=function(_,raw,expand)
    assert(expand); parsed=true
    if raw=='' then return nil end -- the game's answer to nothing is not relied on
    return raw:gsub('<AT>', 'world'):gsub('<PHRASE>', '\239\39hello world\239\40')
end} end}
local encoding = require('encoding')
assert(encoding.Decode('\30\81hello <AT>\31\1')=='hello world' and cleaned=='hello world')
assert(encoding.Decode(' hello world ', true)==' hello world ', 'input preserves leading/trailing spaces')
assert(encoding.Decode(' hello world ')=='hello world', 'log still trims whitespace')
assert(encoding.Decode('\130\160')=='あ', 'CP932 bytes passed intact, UTF-8 output returned')
assert(encoding.Decode('\7')=='', 'paragraph-only messages trim to empty')
do local empty, expandedEmpty, emptySpans = encoding.Decode('', true)
    assert(empty=='' and expandedEmpty=='' and type(emptySpans)=='table' and #emptySpans==0, 'an empty line decodes to an empty line without the game: the input bar stays with its caret at the start') end
local phrase, expanded=encoding.Decode('<PHRASE>')
assert(phrase=='❮hello world❯', 'expanded phrase uses auto-translate brackets')
assert(expanded=='\239\39hello world\239\40', 'diagnostic exposes the actual expanded bytes before cleaning')
assert(encoding.Decode('\239\39\130\160\239\40')=='❮あ❯', 'icons bypass CP932 while Japanese is transcoded')
assert(encoding.Decode('\127\102hello world\127\102')=='❮hello world❯', 'input preview brackets')
assert(encoding.Decode('\127\105hello world\127\100')=='❮hello world❯', 'committed input brackets')
assert(encoding.Decode('\127\105hello world', true)=='❮hello world', 'caret prefix retains opening bracket')
assert(encoding.Decode('\127\102hello world\127\102\127\255')=='❮hello world❯', 'display controls do not leak')
assert(encoding.Decode('\129\239\39')=="○'", 'SJIS trail EF must not be mistaken for an icon lead')
assert(encoding.Decode('Hill\129\64Lizard')=='Hill Lizard' and cleaned=='Hill Lizard', 'enemy-name spaces are normalised before Windows conversion')
assert(encoding.Decode('Hill\129\64Lizard', true)=='Hill Lizard', 'input uses the same space normalisation')
assert(encoding.Decode('Hill?Lizard')=='Hill?Lizard', 'literal question marks are not replaced')
assert(encoding.Decode('\130\160\129\64\130\160')=='あ あ', 'Japanese characters remain intact around a normalised space')
-- Separator and palette bytes transcribed from Screenshot_20261017_021446.png.
local original='The \31\69Stalking\129\63Sapling\30\1 hits \31\207Win\30\1 for 190 points of damage.'
local expected='The Stalking Sapling hits Win for 190 points of damage.'
assert(encoding.Decode(original)==expected and cleaned==expected, 'live 81 3F enemy-name separator does not leak a question mark')
local modified='\30\81[02:13:24]\30\1 ' .. original
assert(encoding.Decode(modified)=='[02:13:24] ' .. expected, 'timestamped modified capture uses the same separator fix')
assert(encoding.Decode('Hill\129\63Lizard',true)=='Hill Lizard', 'input uses the game-specific separator fix too')
assert(encoding.Decode('\130\160\129\63\130\160')=='あ あ', 'game separator normalises without damaging surrounding Japanese')
local rich = require('richtext')
local text, _, spans = encoding.Decode('  \31\2\130\160\30\1 plain \30\5pink\31\1  ', false, true)
assert(text == 'あ plain pink' and #spans == 2)
assert(spans[1].first == 1 and spans[1].last == 3 and spans[1].bank == 31 and spans[1].slot == 2,
    'palette ranges use UTF-8 offsets after CP932 conversion and whitespace trimming')
assert(text:sub(spans[2].first, spans[2].last) == 'pink' and spans[2].bank == 30,
    'both palette banks survive and reset restores uncoloured text')
local _, _, spaces = encoding.Decode('\30\2 hello world ', true, true)
assert(spaces[1].first == 1 and spaces[1].last == 13, 'input-space preservation does not shift colour spans')
assert(encoding.Decode('first\7second\r\nthird') == 'first\nsecond\nthird', 'NPC bells and CRLF are paragraph breaks')
assert(encoding.Decode('\239\31\239\32\239\38') == '[fire][ice][dark]', 'elemental game glyphs do not leak as CP932 junk')
assert(encoding.Decode('ok\127\49\1!\30', false, true) == 'ok!', 'prompt controls and truncated escapes are safe')
local _, _, newlineSlot = encoding.Decode('\31\10hello world', false, true)
assert(newlineSlot[1].slot == 10, 'a palette operand is not a paragraph break')
fail=true; assert(encoding.Decode('bad')==nil, 'failed Windows conversion is rejected')
print('Chatbox encoding: auto-translate before control removal, CP932/UTF-8 conversion contract and failure passed')
