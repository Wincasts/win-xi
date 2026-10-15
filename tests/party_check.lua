-- party: loads, brings old settings up to date, draws its frames, marks what is waiting, answers its command
H.load()
local o = H.options()
H.print('settings by section', o.style ~= nil and o.party ~= nil and o.target ~= nil and o.pets ~= nil, '| nothing of the old layout', o.tools == nil and o.globals == nil,
    '| scale', o.style.scale[1], '| party at', o.party.pos1[1], o.party.pos1[2], '| icons beside', o.party.iconCorner)

-- new settings start as the author's own; what may be taken out again (the links, the corner the
-- party's window is held by) is given the once, and not put back when the settings are next loaded
H.print('new settings: value size', o.style.valueSize[1], '| HP offset', o.style.hpOffset[1], '| click through', o.clickThrough[1], '| fade after', o.fade.Delay,
    '| links', #o.links, '| held at', o.party.corner1 and o.party.corner1[2])
do
    local again = require('options').Defaults()
    again.version, again.links = 2, T{ }
    require('options').Complete(again)
    H.print('loaded again: links left out stay out', #again.links == 0, '| no corner put back', again.party.corner1 == nil)
end

-- a character's settings from before they were set out by section: what was set is carried over
local options = require('options')
local old = options.Complete(dofile('tests/fixtures/party_v1_settings.lua'))
H.print('old settings: scale', old.style.scale[1], 'name size', old.style.nameSize[1], 'value size', old.style.valueSize[1], 'buff size', old.style.buffSize[1],
    '| HP offset', old.style.hpOffset[1], old.style.hpOffset[2], 'TP offset', old.style.tpOffset[1], old.style.tpOffset[2])
H.print('old settings: party at', old.party.pos1[1], old.party.pos1[2], 'held at', old.party.corner1 and old.party.corner1[2], '| icon offset', old.party.iconOffset[1], old.party.iconOffset[2],
    '| target at', old.target.mainPos[1], old.target.mainPos[2], '| links', #old.links, old.links[2].child, old.links[2].side, old.links[2].parent)
H.print('old settings: fade', old.fade.Enabled, 'after', old.fade.Delay, '| party fades', old.fade.windows.party and old.fade.windows.party[1], '| hide under map', old.hide.UnderMap,
    '| shared theme', old.useSharedTheme, '| the old tables gone', old.tools == nil and old.globals == nil and old.importedFromXilite == nil)

-- a character who had the addon as xiframes: what xiframes kept is taken up the once, and not looked
-- for again once there are settings of party's own
do
    local realLoadfile, asked = loadfile, 0
    loadfile = function(p)
        if p:find('\\xiframes\\') then
            asked = asked + 1
            return function() return { version = options.Version, party = { hideWhenSolo = { true }, pos1 = { 11, 22 } } } end
        end
        return realLoadfile(p)
    end
    local carried = options.Complete(options.Defaults())
    local first = asked
    options.Complete(carried)
    loadfile = realLoadfile
    H.print('xiframes settings taken up', carried.fromXiframes == true and carried.party.hideWhenSolo[1] == true and carried.party.pos1[2] == 22,
        '| looked for once', first == 1 and asked == 1)
end

H.frames(3); H.print('loading: windows begun', H.calls.Begin or 0)

-- in game, everyone with a pet and something targeted: the memory here answers 1 to whatever it is asked
local anything
local managers = { GetParty = true, GetPlayer = true, GetEntity = true, GetTarget = true, GetRecast = true, GetCastBar = true }
anything = setmetatable({}, { __index = function(_, k) return function()
    if managers[k] then return anything end
    if k:match('Name$') then return 'Tester' end
    if k:match('Buffs') or k:match('StatusIcons') then return {} end
    if k == 'GetIsZoning' then return 0 end
    if k == 'GetLoginStatus' then return 2 end
    return 1
end end })
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return anything end }, { __index = core })
-- but the inventory is the harness's own, which has a treasure pool
rawset(anything, 'GetInventory', function() return core.GetMemoryManager():GetInventory() end)
GetEntity = function(index)
    if index == 99 then return { Name = 'Carbuncle', Distance = 16, HPPercent = 80 } end
    return { Name = 'Greater Colibri', Distance = 64, HPPercent = 75, ServerId = 7, PetTargetIndex = 99, TargetedIndex = 0 }
end
GetPlayerEntity = function() return { Name = 'Tester', HPPercent = 100, Distance = 0, ServerId = 1, TargetIndex = 1 } end
o.party.showTreasure[1] = false

local ok, problem = pcall(function() H.packet(0x00A); H.frames(4) end)
H.print('in game: frames ran', ok, ok and '' or problem, '| windows begun', H.calls.Begin or 0, '| lists given room', (H.calls.Dummy or 0) > 0,
    '| a line over the pets', (H.calls.Separator or 0) > 0)

-- The bar texture, bookends and status icons are winxi's theme's: its choices reach the renderer, and
-- an unknown texture falls back to the original. Settings that had them as the addon's own carry them
-- into the theme, and keep them no longer.
local winxiTheme = require('winxi.theme')
local look = winxiTheme.Get()
assert(look.BarTexture == 'original' and look.BookendStyle == 'texture' and look.Bookends == true and look.StatusIcons == true)
assert(o.style.barTexture == nil and o.style.bookends == nil and o.style.ffxivIcons == nil)
do
    local carried = options.Complete({ version = 2, style = { borderStyle = 'crystal', barTexture = 'satin', bookends = { false },
        bookendStyle = 'texture', ffxivIcons = { false } } })
    assert(carried.style.borderStyle == nil and carried.style.bookends == nil and carried.style.ffxivIcons == nil)
    assert(carried.theme.BorderStyle == 'crystal' and carried.theme.BarTexture == 'satin' and carried.theme.Bookends == false
        and carried.theme.BookendStyle == 'texture' and carried.theme.StatusIcons == false)
    -- only what differs from how the theme starts goes on to the shared theme
    assert(carried.carriedTheme.BorderStyle == 'crystal' and carried.carriedTheme.BookendStyle == nil and carried.carriedTheme.Bookends == false)
end
do
    local draw = require('draw')
    local originalTexture = draw.Texture
    local seen = {}
    draw.Texture = function(path) seen[path] = true; return originalTexture(path) end
    local generated = { glass = true, detailed = true, crystal = true, satin = true, runic = true, classic = true, radiant = true,
        chrome = true, flat = true, segmented = true, ember = true }
    for _, choice in ipairs({ 'glass', 'detailed', 'crystal', 'satin', 'runic', 'classic', 'radiant', 'chrome', 'flat', 'segmented', 'ember', 'unknown', 'original' }) do
        look.BarTexture = choice
        assert(options.Style(o).barTexture == choice)
        seen = {}
        H.frames(1)
        local root = generated[choice] and ('bars/' .. choice .. '/') or 'bars/'
        for _, kind in ipairs({ 'hp', 'mp' }) do
            for _, layer in ipairs({ 'back', 'fill', 'front' }) do
                assert(seen[root .. kind .. '_' .. layer .. '.png'], 'Missing texture: ' .. root .. kind .. '_' .. layer)
            end
        end
    end
    draw.Texture = originalTexture
end

-- Independent ornaments use the whole image, retain the atlas fallback, and honour the toggle.
do
    local draw = require('draw')
    local texture, image = draw.Texture, draw.Image
    local capCount, atlasCount, requested = 0, 0, nil
    local available = true
    draw.Texture = function(path)
        if path:match('^bookends/') then requested = path; return available and 123 or false end
        if path:match('_front%.png$') then return 124 end
        return texture(path)
    end
    draw.Image = function(handle, x1, y1, x2, y2, tint, u1, v1, u2, v2)
        if handle == 123 then
            assert(u1 == 0 and v1 == 0 and u2 == 1 and v2 == 1)
            capCount = capCount + 1
        elseif handle == 124 and u1 > 0 then
            atlasCount = atlasCount + 1
        end
        return image(handle, x1, y1, x2, y2, tint, u1, v1, u2, v2)
    end
    local styles = {}
    for index = 3, #require('winxi.theme').BookendStyles do
        local choice = require('winxi.theme').BookendStyles[index].key
        styles[#styles + 1] = choice
        local image = io.open(('addons/party/assets/bookends/%s.png'):format(choice), 'rb')
        assert(image, 'no bookend for ' .. choice)
        image:close()
    end
    assert(#styles == 12)
    for _, choice in ipairs(styles) do
        look.BookendStyle = choice
        capCount, requested = 0, nil
        H.frames(1)
        assert(capCount > 0 and requested == 'bookends/' .. choice .. '.png')
        look.BookendStyle, look.BorderStyle = 'match', choice
        capCount, requested = 0, nil
        H.frames(1)
        assert(capCount > 0 and requested == 'bookends/' .. choice .. '.png')
    end
    available, atlasCount, capCount = false, 0, 0
    H.frames(1)
    assert(capCount == 0 and atlasCount > 0)
    -- Bookend Opacity: the caps drawn that much less solid, and at 0 not at all
    available = true
    local packed = draw.Packed
    local alphas = {}
    draw.Packed = function(colour, alpha) alphas[#alphas + 1] = alpha return packed(colour, alpha) end
    look.BookendOpacity, capCount = 40, 0
    H.frames(1)
    local faded = false
    for _, alpha in ipairs(alphas) do if math.abs(alpha - 0.4) < 1e-9 then faded = true end end
    assert(capCount > 0 and faded, 'caps faded')
    look.BookendOpacity, capCount, atlasCount = 0, 0, 0
    H.frames(1)
    assert(capCount == 0, 'none at all: not drawn')
    look.BookendOpacity, draw.Packed = 100, packed
    available, capCount, atlasCount = true, 0, 0
    look.Bookends = false
    H.frames(1)
    assert(capCount == 0 and atlasCount == 0)
    look.Bookends = true
    look.BookendStyle, look.BorderStyle = 'texture', 'theme'
    draw.Texture, draw.Image = texture, image
end
H.print('theme styles: bar textures, bookends and carried settings', true)

-- a leader has a circle in front of their name: here everyone leads their party and the alliance, so two each
rawset(anything, 'GetMemberFlagMask', function() return 12 end)
local circles = H.calls['draw.AddCircleFilled'] or 0
ok, problem = pcall(H.frames, 5)
H.print('leaders: frames ran', ok, ok and '' or problem, '| circles drawn', (H.calls['draw.AddCircleFilled'] or 0) > circles)
rawset(anything, 'GetMemberFlagMask', nil)
-- Let the party's throttled snapshot discard the leader flags before counting invite circles.
H.frames(10)

-- an invitation: marked beside the party's window until it is answered
local function invitation(kind) return ('\0'):rep(0x0B) .. string.char(kind) .. ('\0'):rep(20) end
local realUnpack = struct.unpack
struct.unpack = function(format, data, at)
    if format == 'B' and #data > 0x0B then return data:byte(at) end
    return realUnpack(format, data, at)
end
-- the icons are circles, as leaders' marks are: no one leads now, so only an icon is one
local function drawn() local before = H.calls['draw.AddCircleFilled'] or 0; H.frames(1); return (H.calls['draw.AddCircleFilled'] or 0) > before end
H.print('no invitation: no mark', drawn() == false)
H.packetData(0x0DC, invitation(0)); H.print('a party invite: marked', drawn())
H.packetOut(0x074); H.print('answered: gone', drawn() == false)
H.packetData(0x0DC, invitation(5)); H.print('an alliance invite: marked', drawn())
H.packet(0x00A); H.print('a change of area: gone', drawn() == false)
struct.unpack = realUnpack

-- the treasure pool: an icon while there is something in it. It is looked at twice a second.
o.party.showTreasure[1] = true
H.frames(20); H.print('an empty pool: no icon', drawn() == false)
H.pool(2); H.frames(20); H.print('two items in the pool: an icon', drawn())
H.pool(0); H.frames(20); H.print('emptied: gone', drawn() == false)

-- the game's own icons, where they load: the green exclamation mark for an invitation
-- and the chest for the treasure, each the image cut for it; the circles only where an image will not load
do
    local draw = require('draw')
    local texture, image = draw.Texture, draw.Image
    local asked, images = {}, 0
    draw.Texture = function(file)
        if file:match('^notices/') then asked[file] = true; return 200 end
        return texture(file)
    end
    draw.Image = function(handle, ...) if handle == 200 then images = images + 1 end return image(handle, ...) end
    struct.unpack = function(format, data, at)
        if format == 'B' and #data > 0x0B then return data:byte(at) end
        return realUnpack(format, data, at)
    end
    H.packetData(0x0DC, invitation(0))
    H.pool(2); H.frames(20)
    local circles, rings = H.calls['draw.AddCircleFilled'] or 0, H.calls['draw.AddCircle'] or 0
    images = 0
    H.frames(1)
    -- each five times: four dark copies a pixel to each side, for its outline, then itself (and the
    -- party's window is drawn twice here, once to be measured)
    assert(asked['notices/invite.png'] and asked['notices/treasure.png'] and images >= 10 and images % 10 == 0, 'both images drawn, outlined')
    assert((H.calls['draw.AddCircleFilled'] or 0) == circles and (H.calls['draw.AddCircle'] or 0) == rings, 'and no circles or rings')
    H.packetOut(0x074); H.pool(0); H.frames(20)
    struct.unpack = realUnpack
    draw.Texture, draw.Image = texture, image
    for _, file in ipairs({ 'invite', 'treasure' }) do
        local found = io.open(('addons/party/assets/notices/%s.png'):format(file), 'rb')
        assert(found, 'no image for ' .. file)
        found:close()
    end
    H.print('notice icons: the game\'s invitation and treasure images, no circles', true)
end

-- the settings, tab by tab: drawn directly, as the harness shows only a window's first tab
local config = require('config')
local sliders = H.calls.SliderInt or 0
for _, tab in ipairs(config.Tabs) do
    ok, problem = pcall(tab.draw, o)
    H.print(tab.name, 'tab draws', ok, ok and '' or problem)
end
H.print('sliders in the tabs', (H.calls.SliderInt or 0) - sliders)

local menuGame = require('winxi.game')
local menuName, wasShowing = menuGame.MenuName, o.showConfig[1]
menuGame.MenuName = function() return 'menu    diagnostic' end
assert(H.command('/pt menu') and o.showConfig[1] == wasShowing, 'menu diagnostic does not toggle settings')
assert(H.printed[#H.printed]:find('menu    diagnostic', 1, true), 'menu diagnostic reports exact native name')
menuGame.MenuName = menuName
local before = H.calls.Begin or 0
H.print('/pt kept from the game', H.command('/pt'), '| settings showing', o.showConfig[1]); H.frames(1)
H.print('settings window drawn', (H.calls.Begin or 0) > before)
H.print('/xif closes it', H.command('/xif') and o.showConfig[1] == false, '| /ptx is left alone', H.command('/ptx') == false,
    '| old /xiframes is left alone', H.command('/xiframes') == false,
    '| /party (the game\'s party chat) is left alone', H.command('/party hello') == false)
H.unload(); H.print('unload ran; saves', H.saves() > 0)

-- Alliance Scale: the alliance's other two parties drawn at it, on top of the Scale; the player's own party not
do
    local frames = require('frames')
    local realDraw, scales = frames.Draw, {}
    frames.Draw = function(members, kind, statuses, style)
        scales[kind] = style.scale
        return realDraw(members, kind, statuses, style)
    end
    local o = H.options()
    o.style.scale[1], o.party.allianceScale[1] = 120, 150
    H.command('/xif arrange')
    H.frames(2)
    H.command('/xif arrange')
    frames.Draw = realDraw
    H.print('alliance scale: own party', scales.party, '| alliance', scales.alliance)
    assert(scales.party == 120 and scales.alliance == 180)
    o.style.scale[1], o.party.allianceScale[1] = 100, 100
end

-- Name Font and Value Font: the names in one, the values in the other, the theme's where unset
do
    local imgui = require('imgui')
    local push, pop, add = imgui.PushFont, imgui.PopFont, imgui.AddFontFromFileTTF
    local pushed, depth = {}, 0
    imgui.AddFontFromFileTTF = function(path) return { path = path } end
    imgui.PushFont = function(font) depth = depth + 1; pushed[#pushed + 1] = font and font.path or 'theme' end
    imgui.PopFont = function() depth = depth - 1 end
    local o = H.options()
    local function Fonts()
        pushed = {}
        H.command('/xif arrange')
        H.frames(1)
        H.command('/xif arrange')
        local seen = {}
        for _, font in ipairs(pushed) do seen[font:match('[^\\]+$')] = true end
        return seen
    end
    o.style.nameFont, o.style.valueFont = 'name.ttf', ''
    local seen = Fonts()
    assert(seen['name.ttf'] and seen.theme, 'names in theirs, values in the theme\'s')
    o.style.nameFont, o.style.valueFont = '', 'value.ttf'
    seen = Fonts()
    assert(seen['value.ttf'] and not seen['name.ttf'], 'values in theirs')
    o.style.valueFont = ''
    assert(depth == 0, 'a font left pushed')
    -- a path is never taken in
    local completed = options.Complete({ version = 3, style = { nameFont = 'C:\\evil\\x.ttf', valueFont = 'good.ttf' } })
    assert(completed.style.nameFont == 'trebucbi.ttf' and completed.style.valueFont == 'good.ttf')
    imgui.PushFont, imgui.PopFont, imgui.AddFontFromFileTTF = push, pop, add
    H.print('name and value fonts: each its own, the theme\'s where unset, no paths', true)
end

-- A name runs to the right end of the HP bar, and is cut short with '...' only where it would go past it
do
    local imgui = require('imgui')
    local draw = require('draw')
    local text, written = draw.Text, {}
    draw.Text = function(x, y, packed, words, ...) written[words] = true return text(x, y, packed, words, ...) end
    local function Names(perLetter)
        rawset(imgui, 'CalcTextSize', function(words) return #words * perLetter, 14 end)
        written = {}
        H.command('/xif arrange')
        H.frames(1)
        H.command('/xif arrange')
        rawset(imgui, 'CalcTextSize', nil)
        return written
    end
    -- the HP bar ends 150 across, at a scale of 100: at 10 a letter the target, "Greater Colibri" (150), fits whole
    local shown = Names(10)
    assert(shown['Greater Colibri'], 'fits: whole')
    -- at 12 a letter it does not: nine letters and '...' are 144. A name is fitted again when its size
    -- changes (here, the measure is changed under it), so the size is nudged
    local o = H.options()
    local size = o.style.nameSize[1]
    o.style.nameSize[1] = size + 1
    shown = Names(12)
    o.style.nameSize[1] = size
    assert(shown['Greater C...'] and not shown['Greater Colibri'], 'too long: cut at the bar\'s end')
    draw.Text = text
    H.print('names: whole where they fit before the HP bar\'s end, cut there where not', true)
end

-- Debuff Style: the letters under the window, or an icon beside it for each status seen to take hold,
-- drawn as the party's buffs are
do
    local tracker = require('winxi.debuffs')
    local roster = require('roster')
    local draw = require('draw')
    local texture, image = roster.StatusTexture, draw.Image
    local asked, images = {}, 0
    roster.StatusTexture = function(id, useOwn)
        if id < 100 or id == 134 then asked[#asked + 1] = id end
        return 400 + id, false
    end
    draw.Image = function(handle, ...) if handle == 404 or handle == 413 then images = images + 1 end return image(handle, ...) end
    -- Slow and Paralyze are on whatever is targeted (winxi.debuffs' own check is of how they come to be)
    local statuses = tracker.Statuses
    local later = os.time() + 60
    tracker.Statuses = function() return { [13] = { id = 13, expires = later }, [4] = { id = 4, expires = later }, [5] = { id = 5, expires = 0 } } end
    local o = H.options()
    o.target.mainDebuffs[1] = true
    local function Drawn(how)
        o.target.debuffStyle = how
        asked, images = {}, 0
        H.command('/xif arrange')
        local letters = H.calls.Text or 0
        H.frames(1)
        H.command('/xif arrange')
        return images, (H.calls.Text or 0) - letters
    end
    local lettersImages, letters = Drawn('letters')
    local icons, lettersWithIcons = Drawn('icons')
    assert(lettersImages == 0 and letters > 0, 'letters: no icons')
    -- in order of the status's number, Paralyze (4) before Slow (13); Blind, run out, not at all; and no letters
    assert(icons == 2, 'an icon for each: ' .. icons)
    assert(table.concat(asked, ',') == '4,13', table.concat(asked, ','))
    assert(lettersWithIcons < letters, 'icons: no letters')
    o.target.mainDebuffs[1], o.target.debuffStyle = false, 'letters'
    roster.StatusTexture, draw.Image, tracker.Statuses = texture, image, statuses
    H.print('debuff style: letters under the window, or icons beside it as the party\'s buffs are', true)
end

-- Frame Titles: each window's label on its top edge, in each of the theme's title styles
do
    local theme = require('winxi.theme')
    local look = theme.Get()
    local function Drawn(on, how)
        look.FrameTitles, look.TitleStyle = on, how
        theme.Touch()
        local before = {}
        for _, key in ipairs({ 'draw.AddText', 'draw.PushClipRect', 'draw.AddRect', 'draw.AddRectFilled', 'draw.PathStroke' }) do
            before[key] = H.calls[key] or 0
        end
        H.frames(1)
        local after = {}
        for key, count in pairs(before) do after[key] = (H.calls[key] or 0) - count end
        return after
    end
    local off, outline, broken, plate = Drawn(false, 'outline'), Drawn(true, 'outline'), Drawn(true, 'break'), Drawn(true, 'plate')
    -- the words, and four times over in the dark for their edge
    local words = outline['draw.AddText'] - off['draw.AddText']
    assert(words > 0 and words % 5 == 0, 'titles written: ' .. words)
    local windows = words / 5
    assert(outline['draw.PushClipRect'] - off['draw.PushClipRect'] == windows, 'each title opened up past its window')
    -- the plain border drawn by winxi, round the gap, unclipped
    assert(broken['draw.PathStroke'] - outline['draw.PathStroke'] == windows, 'border broken: ' .. broken['draw.PathStroke'] - outline['draw.PathStroke'])
    assert(broken['draw.PushClipRect'] == outline['draw.PushClipRect'], 'gap not clipped')
    assert(plate['draw.AddRectFilled'] - outline['draw.AddRectFilled'] == windows and plate['draw.AddRect'] - outline['draw.AddRect'] == windows, 'a plate under each')
    -- broken with a shadow: the same gap, a haze of three under each title, and the words dropped a pixel
    local hazed = Drawn(true, 'breakshadow')
    assert(hazed['draw.PathStroke'] == broken['draw.PathStroke'], 'the border broken as for Break In Border')
    assert(hazed['draw.AddRectFilled'] - broken['draw.AddRectFilled'] == 3 * windows, 'a haze under each')
    assert(hazed['draw.AddText'] - broken['draw.AddText'] == windows, 'the words dropped a pixel')
    -- a shadow: the words twice more in the dark, at its offset and a pixel short of it
    look.TitleShadow, look.TitleShadowOffset = true, 2
    local shadowed = Drawn(true, 'outline')
    assert(shadowed['draw.AddText'] - outline['draw.AddText'] == 2 * windows, 'shadowed: ' .. shadowed['draw.AddText'] - outline['draw.AddText'])
    look.TitleShadowOffset = 1
    shadowed = Drawn(true, 'outline')
    assert(shadowed['draw.AddText'] - outline['draw.AddText'] == windows, 'a one pixel shadow once')
    look.TitleShadow = false
    -- a font and size of their own: pushed around each title, and let go
    local pushes, pops = H.calls.PushFont or 0, H.calls.PopFont or 0
    look.TitleSize = 20
    Drawn(true, 'outline')
    assert((H.calls.PushFont or 0) - pushes - ((H.calls.PopFont or 0) - pops) == 0, 'fonts balanced')
    assert((H.calls.PushFont or 0) - pushes >= windows, 'a size of their own')
    look.TitleSize = 0
    look.FrameTitles, look.TitleStyle = true, 'outline'
    theme.Touch()
    H.print('frame titles: on the top edge of each window, outlined, breaking the border, with a shadow too, or on a plate; shadowed; their own size', true)
end

-- The main party frame follows actual membership, including an alliance with an empty second party.
do
    local roster, windows = require('roster'), require('windows')
    local organize = require('winxi.organize')
    local counts, active = roster.Counts, organize.IsActive()
    organize.SetActive(false)
    for _, case in ipairs({ {1, 0, 0, 'Solo'}, {2, 0, 0, 'Party'},
        {6, 1, 0, 'Alliance'}, {1, 0, 1, 'Alliance'}, {1, 0, 0, 'Solo'} }) do
        roster.Counts = function() return case[1], case[2], case[3] end
        H.frames(1)
        assert(windows.List.party1.label == case[4], 'main party title: ' .. case[4])
    end
    roster.Counts = counts
    organize.SetActive(active)
    H.print('main party title follows solo, party and alliance membership', true)
end
