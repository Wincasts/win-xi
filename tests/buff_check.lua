-- buff: loads, shows the player's statuses with their icons and times, removes one on a right click,
-- and switches the game's own icons off and on again
local o = H.options()
assert(o.hide.UnderMap == true and o.hide.UnderChat == true)
H.print('defaults: size', o.iconSize[1], '| per row', o.perRow[1], '| timers', o.showTimers[1], '| status icons', require('winxi.theme').Get().StatusIcons)
H.print('nowhere to hide the game\'s icons, said once:', H.printed[#H.printed])

-- a player under Protect (40, no end), Haste (33, 90 seconds left) and a food (251, two hours)
local stamp, epoch = 2000000000, 0x3C307D70
local ids, timers = {}, {}
for slot = 1, 32 do ids[slot], timers[slot] = 255, 0 end
local function under(slot, id, seconds) ids[slot] = id; timers[slot] = seconds and (stamp - epoch) * 60 + seconds * 60 or 0x7FFFFFFF end
local serverId, zoning = 0, 0
local memory = { GetParty = function() return { GetMemberServerId = function() return serverId end } end,
    GetPlayer = function() return { GetIsZoning = function() return zoning end, GetStatusIcons = function() return ids end, GetStatusTimers = function() return timers end,
        GetLoginStatus = function() return 2 end } end }
AshitaCore.GetMemoryManager = function() return memory end
local asked = {}
AshitaCore.GetResourceManager = function() return { GetString = function(_, _, id) return 'Status ' .. id end,
    GetStatusIconByIndex = function(_, id) asked[#asked + 1] = id; return { CanCancel = id == 33 and 1 or 0, HideTimer = id == 251 and 1 or 0, Description = { 'What it does.' } } end } end

local statuses = require('statuses')
local list = {}
H.print('no player: statuses', statuses.Read(list))
serverId = 1; under(1, 40); under(2, 33, 90); under(5, 251, 7200)
H.print('three statuses read', statuses.Read(list) == 3, '| in order', list[1].id, list[2].id, list[3].id, '| no time read without the game\'s clock', list[2].seconds == nil)
zoning = 1; H.print('between areas: statuses', statuses.Read(list), '| list emptied', #list == 0); zoning = 0

H.play(true); H.frames(3)
H.print('window begun', (H.calls.Begin or 0) > 0, '| an item for each status a frame', H.calls.Dummy % 3 == 0, '| on a row', (H.calls.SameLine or 0) > 0)
H.print('no device: no icon drawn', (H.calls['draw.AddImage'] or 0) == 0)

-- winxi's own set, ffxiv, has what the build tool made
local icons = require('winxi.statusicons')
local function made(id) local f = io.open('addons/libs/winxi/statusicons/ffxiv/' .. id .. '.png', 'rb') if f then f:close() end return f ~= nil end
H.print('an icon made for Haste', made(33), '| none for KO', not made(0))
H.print('icon shape', icons.OwnAspect, icons.OwnLeft, icons.OwnRight)

-- The Winxi toggle is read live, in both positioning modes. A legacy addon setting must not win.
local theme = require('winxi.theme')
local oldGet, look = icons.Get, theme.Get()
local oldStatusIcons, oldAnchor = look.StatusIcons, o.anchorToDefault[1]
local oldX, oldY = o.pos[1], o.pos[2]
o.ffxivIcons = { false }
for _, anchored in ipairs({ true, false }) do
    o.anchorToDefault[1] = anchored
    for _, enabled in ipairs({ true, false, true }) do
        look.StatusIcons = enabled
        local requested = 0
        icons.Get = function(_, useOwn)
            assert(useOwn == enabled, 'buff must follow Winxi StatusIcons')
            requested = requested + 1
            return nil
        end
        H.frames(3)
        assert(requested >= 3 and requested % 3 == 0, 'all statuses must use the current Winxi toggle')
    end
end
icons.Get, look.StatusIcons, o.anchorToDefault[1] = oldGet, oldStatusIcons, oldAnchor
o.ffxivIcons = nil
o.pos[1], o.pos[2] = oldX, oldY
H.frames(3)
H.print('Winxi icon toggle follows live in both positioning modes', true)

-- a right click on each status: only the one that can be removed is
H.ret.IsItemHovered = { true }; H.ret.IsItemClicked = { true }; H.frames(1); H.ret.IsItemHovered = { false }; H.ret.IsItemClicked = { false }
H.print('right click removes Haste alone: packets', #H.sent, H.sent[1], '| tooltips', H.calls.BeginTooltip)

o.perRow[1] = 1; local before = H.calls.SameLine or 0; H.frames(1); H.print('one to a row: none beside another', (H.calls.SameLine or 0) == before)
for slot = 1, 32 do ids[slot] = 255 end
local begun = H.calls.Begin; H.frames(20); H.print('no status: no window', H.calls.Begin == begun)

-- The default anchor is a separate, chrome-free window; it must not overwrite the saved free
-- position. Menu hiding is optional, immediate, and independent of positioning.
assert(o.anchorToDefault[1] and o.pos[1] == 100 and o.pos[2] == 100)
local anchoring = require('anchoring')
assert(o.anchorAdjustment[1] == 0 and o.anchorAdjustment[2] == 0)
-- Native-menu coordinates scale with the current display, not a fixed screen fraction.
local ax, ay = anchoring.Position({0,0}, {x=2304,y=1296}, {w=2304,h=1296})
assert(ax == 148 and ay == 50)
ax, ay = anchoring.Position({12,18}, {x=2304,y=1296}, {w=1152,h=648})
assert(ax == 308 and ay == 118)
ax, ay = anchoring.Position({-8,3}, {1920,1080}, {w=960,h=1080})
assert(ax == 288 and ay == 53) -- independent axes, unscaled pixel nudge
for _, bad in ipairs({{w=0,h=0}, {w=0/0,h=1080}, {w=math.huge,h=1080}}) do
    ax, ay = anchoring.Position({0,0}, {x=1920,y=1080}, bad)
    assert(ax == 148 and ay == 50)
end
local game = require('winxi.game')
local original, state = {}, {}
for _, key in ipairs({ 'IsLoading', 'IsInterfaceHidden', 'IsEventHappening' }) do
    original[key] = game[key]
    game[key] = function() return state[key] or false end
end
original.MenuName = game.MenuName
local menu = ''
game.MenuName = function() return menu end
assert(not anchoring.IsHidden())
menu = 'menu    buff    '; assert(not anchoring.IsHidden())
menu = 'menu    item    '; assert(not anchoring.IsHidden())
assert(o.hideWithMenus[1] and anchoring.HideForMenu(o))
for _, name in ipairs({ '', 'menu    buff    ', 'menu    inline  ' }) do
    menu = name; assert(not anchoring.HideForMenu(o), name .. ' should leave buffs visible')
end
for _, name in ipairs({ 'menu item', 'menu    inventor', 'menu    bank    ', 'menu    equip   ', 'menu    status  ',
    'menu    magic   ', 'menu    ability ', 'menu    trade   ', 'menu    map     ',
    'menu    mcr1pall', 'menu    mcr2pall', 'menu    submenu ' }) do
    menu = name; assert(anchoring.HideForMenu(o), name .. ' should hide anchored buffs')
end
menu = 'menu    item    '; o.hideWithMenus[1] = false
assert(not anchoring.HideForMenu(o))
menu = ''; for key in pairs(original) do
    if key ~= 'MenuName' then
        state[key] = true; assert(anchoring.IsHidden(), key); state[key] = false
    end
end
local imgui = require('imgui')
local originalPlace, placed = imgui.SetNextWindowPos, nil
imgui.SetNextWindowPos = function(pos, condition)
    placed = { pos[1], pos[2], condition }
    originalPlace(pos, condition)
end
local drawn = 0
local function draw() drawn = drawn + 1 end
local savedX, savedY = o.pos[1], o.pos[2]
o.anchorAdjustment[1], o.anchorAdjustment[2] = 12, 18
-- Old saved absolute coordinates must not be interpreted as a new nudge.
o.anchorOffset = { 900, 900 }
o.fadeInOut[1] = false
assert(anchoring.Draw('buffs.anchor.test', o, draw))
assert(placed[1] == 160 and placed[2] == 68 and placed[3] == ImGuiCond_Always)
assert(o.pos[1] == savedX and o.pos[2] == savedY)
local begins = H.calls.Begin
menu = 'menu    item    '
assert(anchoring.Draw('buffs.anchor.test', o, draw))
assert(H.calls.Begin == begins + 1 and drawn == 2)
o.hideWithMenus[1] = true
assert(not anchoring.Draw('buffs.anchor.test', o, draw))
assert(H.calls.Begin == begins + 1 and drawn == 2, 'menu hides without drawing or interaction')
-- Native menus and macro palettes only suppress anchored drawing; chat/maps use shared rules.
under(1, 40)
local oldChat = game.IsChatExpanded
local chat = false
game.IsChatExpanded = function() return chat end
for _, anchored in ipairs({ false, true }) do
    o.anchorToDefault[1] = anchored
    local before
    for _, name in ipairs({ 'menu    item    ', 'menu    inventor', 'menu    bank    ', 'menu    equip   ',
        'menu    status  ', 'menu    magic   ', 'menu    ability ', 'menu    trade   ',
        'menu    mcr1pall', 'menu    mcr2pall', 'menu    submenu ' }) do
        menu = name
        before = H.calls.Begin
        H.frames(1)
        assert(H.calls.Begin == before + (anchored and 0 or 1), 'menus and palettes hide anchored mode only')
    end
    for _, name in ipairs({ 'menu    inline  ', 'menu    buff    ' }) do
        menu = name
        before = H.calls.Begin
        H.frames(1); assert(H.calls.Begin == before + 1, 'other menus stay visible')
    end
    menu = 'menu    map     '
    before = H.calls.Begin
    H.frames(1); assert(H.calls.Begin == before, 'maps hide both modes')
    menu = ''; chat = true
    before = H.calls.Begin
    H.frames(1); assert(H.calls.Begin == before, 'expanded chat hides both modes')
    chat = false
end
game.IsChatExpanded = oldChat
begins = H.calls.Begin
o.anchorToDefault[1] = true
menu = ''
state.IsInterfaceHidden = true
assert(not anchoring.Draw('buffs.anchor.test', o, draw))
assert(H.calls.Begin == begins and drawn == 2)
state.IsInterfaceHidden = false
menu = ''; o.fadeInOut[1] = false; o.isVisible[1] = false
assert(not anchoring.Draw('buffs.anchor.test', o, draw))
o.isVisible[1] = true
-- Free-position mode still routes through the shared shell and keeps its original behaviour.
under(1, 40); o.anchorToDefault[1] = false
H.frames(1); assert(o.pos[1] == 100 and o.pos[2] == 200)
o.anchorToDefault[1] = true; o.fadeInOut[1] = true
for key, fn in pairs(original) do game[key] = fn end
-- Exercise real anchored-window placement with the existing scaling helper supplied.
local savedScaling, savedIO = package.loaded.scaling, imgui.GetIO
package.loaded.scaling = {menu={w=1152,h=648}}
local scaledAnchoring = dofile('addons/buff/anchoring.lua')
imgui.GetIO = function() return {DisplaySize={x=2304,y=1296}} end
o.fadeInOut[1] = false
assert(scaledAnchoring.Draw('buffs.scaled.test', o, function() end))
assert(placed[1] == 308 and placed[2] == 118)
imgui.GetIO = function() return {DisplaySize={x=1152,y=648}} end
assert(scaledAnchoring.Draw('buffs.scaled.test', o, function() end))
assert(placed[1] == 160 and placed[2] == 68, 'live window resize')
package.loaded.scaling, imgui.GetIO = savedScaling, savedIO
o.fadeInOut[1] = true
imgui.SetNextWindowPos = originalPlace

-- the game's own icons: three places changed, and put back
local native = require('native')
local written, at = {}, { ['75??8B4E0851B9'] = 100, ['7D??33C05EC20400C6'] = 200, ['85C00F??????????6A0232DBE8'] = 300 }
ashita.memory.find = function(_, _, pattern) return at[pattern] or 0 end
ashita.memory.read_uint16 = function(pointer) return written[pointer] or pointer + 1 end
ashita.memory.write_uint16 = function(pointer, value) written[pointer] = value end
H.print('hidden', native.Set(true), native.IsHidden(), '|', written[100] == 0x9090, written[200] == 0x9090, written[300] == 0xC031)
H.print('hidden already by another: left alone', (function() local n = dofile('addons/buff/native.lua') return n.Set(true) == false and written[100] == 0x9090 end)())
H.unload(); H.print('unload puts them back', native.IsHidden() == false, written[100] == 101, written[200] == 201, written[300] == 301)

assert(addon.name == 'buff')
assert(H.command('/buff config'))
assert(H.command('/buff') and o.isVisible[1] == false)
assert(not H.command('/buffs') and not H.command('/buffx'))
H.print('/buff config and toggle handled; /buffs and /buffx left alone: passed')
