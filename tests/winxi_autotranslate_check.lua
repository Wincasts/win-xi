package.path = 'addons/libs/?.lua;' .. package.path
require('winxi.gamedata').Root('addons/libs/winxi/data/')
local auto = require('winxi.autotranslate')
local function check(label, ok) assert(ok, label) end
check('installed client provenance', auto.Index().Source.Type == 'installed-client' and #auto.Index().Source.Files.en.SHA256 == 64)
check('all dictionary entries', #auto.Ids() == auto.Index().Count and #auto.Ids() > 2500)
check('42 categories', auto.Categories()[1].Names.en == 'Greetings' and auto.Categories()[42])
local hello = auto.Search('hello', 'en', 1, 1)[1]
check('literal English search', hello and hello.Text.en == 'Hello!')
check('Japanese display text', auto.Text(hello.Id, 'ja') == 'こんにちは。')
check('known Hello token bytes', auto.Token(hello.Id, 'en') == string.char(0xFD, 2, 2, 1, 11, 0xFD))
for _, id in ipairs(auto.Ids()) do
    local record = auto.Get(id)
    for locale, text in pairs(record.Text) do
        local token = auto.Token(id, locale)
        local decoded = auto.Decode(token)
        check('phrase roundtrip', decoded and decoded.Kind == 'phrase' and decoded.Id == id and auto.Text(id, locale) == text)
        check('raw ID preserved', record.RawIds[locale] == token:byte(2) + token:byte(3) * 256 + token:byte(4) * 65536 + token:byte(5) * 16777216)
        check('no NUL token bytes', not token:find('\0', 1, true))
    end
end
for id = 1, 65535 do
    for _, variant in ipairs({ { 'item', auto.ItemToken }, { 'keyitem', auto.KeyItemToken } }) do
        local token = variant[2](id, 'en')
        local decoded = auto.Decode(token)
        check('all item/key-item IDs roundtrip', decoded and decoded.Id == id and decoded.Kind == variant[1] and decoded.LanguageByte == 2)
        check('escaped zero bytes', not token:find('\0', 1, true))
    end
end
check('item high-byte escape', auto.ItemToken(1):byte(2) == 9 and auto.ItemToken(1):byte(4) == 255)
check('item low-byte escape', auto.ItemToken(256):byte(2) == 10 and auto.ItemToken(256):byte(5) == 255)
check('bad locale', not auto.Token(hello.Id, 'missing') and #auto.Search('', 'missing') == 0)
check('bad input', not auto.Decode('Hello!') and not auto.Decode(nil) and not auto.ItemToken(0) and not auto.ItemToken(65536) and not auto.ItemToken('1'))
check('category is not a sendable phrase', not auto.Token(256))
check('literal search', #auto.Search('', 'en', nil, 0) == 0 and (function()
    local found = auto.Search('[s]', 'en')
    for _, record in ipairs(found) do if not record.Text.en:find('[S]', 1, true) then return false end end
    return #found > 0
end)())
-- The client's name references (@A area, @C spell, @J job, @Y ability) come resolved, the reference kept
local function named(text, category)
    for _, record in ipairs(auto.Search(text, 'en', category)) do
        if record.Text.en == text then return record end
    end
end
local dem = named('Teleport-Dem', 27)
check('spell reference', dem and dem.References.en == '@C7B' and dem.Text.ja == 'テレポデム')
local mines = named('Bastok Mines', 20)
check('area reference', mines and mines.References.en == '@AEA' and mines.Text.ja == 'バストゥーク鉱山区')
check('ability reference', named('Provoke', 31) and named('Savage Blade', 33) and named('Store TP', 32) and named('Thief', 16))
local references, blank = 0, 0
for _, id in ipairs(auto.Ids()) do
    local record = auto.Get(id)
    for _, text in pairs(record.Text) do check('no unresolved reference', not text:find('^@[ACJY]%x')) end
    if record.References then references = references + 1 end
    if not record.Text.en:find('%S') then blank = blank + 1 end
end
check('every reference resolved', references == 1283)
check('blank slots kept but never found', blank > 0 and (function()
    for _, record in ipairs(auto.Search('', 'en', 7)) do if not record.Text.en:find('%S') then return false end end
    return true
end)())
local requested
AshitaCore = { GetChatManager = function() return { ParseAutoTranslate = function(_, token, brackets) requested = token; return brackets and 'expanded' or 'plain' end } end }
check('game expansion bridge', auto.Expand(auto.Token(hello.Id), true) == 'expanded' and requested == auto.Token(hello.Id))
check('bad expansion blocked', not auto.Expand('Hello!'))
auto.Clear()
check('reload', auto.Get(hello.Id).Text.en == 'Hello!')
print('winxi.autotranslate: all phrases/locales, known token bytes, exhaustive item/key-item ID roundtrips, zero-byte escapes and game expansion', true)
