local memory = AshitaCore.GetMemoryManager
AshitaCore.GetMemoryManager = function(self)
    local m = memory(self)
    local getPlayer, getParty = m.GetPlayer, m.GetParty
    m.GetPlayer = function(s)
        local p = getPlayer(s)
        p.GetMainJobLevel = function() return 30 end
        p.GetSubJob = function() return 13 end
        p.GetSubJobLevel = function() return 15 end
        p.GetExpCurrent = function() return 1500 end
        p.GetExpNeeded = function() return 6000 end
        return p
    end
    m.GetParty = function(s)
        local p = getParty(s)
        p.GetMemberServerId = function() return 42 end
        return p
    end
    return m
end
local window = require('winxi.window')
local text = require('winxi.text')
local bars = require('winxi.bars')
local originalWindow = window.Full
local look, bar, words
window.Full = function(name, open, flags, draw, options)
    if name == 'expbar.window' then
        look = { background = options.background, border = options.border,
            shadow = options.shadow, padding = options.padding, locked = options.locked,
            clickThrough = options.clickThrough }
        draw()
        return true
    end
    return originalWindow(name, open, flags, draw, options)
end
bars.Draw = function(_, x, y, width, height, fraction, color, texture)
    bar = { x = x, y = y, width = width, height = height, fraction = fraction, color = color, texture = texture }
    return true
end
text.Draw = function(_, x, y, _, value)
    words[#words + 1] = { x = x, y = y, value = value }
end
text.Outlined = function(value) words[#words + 1] = { value = value } end
local function frame()
    words = {}
    H.frames(1)
end
H.load()
local options = H.options()
options.fadeInOut[1] = false
H.play(true); H.login(2)
frame()
assert(words[1].value:find('PUP30/NIN15', 1, true))
assert(bar.height == 16 and look.background == nil and bar.texture == nil)
options.texture = 'chrome'
frame()
assert(bar.texture == 'chrome')
options.texture = ''
H.command('/expbar pos 450 220')
assert(options.pos[1] == 450 and options.pos[2] == 220)
H.command('/expbar pos invalid 220')
assert(options.pos[1] == 450 and options.pos[2] == 220)
H.command('/expbar mode overlay')
options.width[1], options.height[1] = 600, 80
options.barColor = { 1, 0.2, 0.3, 0.8 }
options.locked[1] = true
frame()
assert(options.overlay[1] and bar.width >= 600 and bar.height == 80)
assert(bar.fraction == 0.25 and bar.color == options.barColor)
assert(look.background[4] == 0 and look.border[4] == 0 and look.shadow == false and look.padding == 0)
assert(look.locked and look.clickThrough)
assert(#words == 4 and words[1].value == 'PUP30/NIN15')
local calc = require('imgui').CalcTextSize
local _, jobHeight = calc(words[1].value)
assert(words[1].x == bar.x and words[1].y + jobHeight < bar.y)
local valueWidth, valueHeight = calc(words[2].value)
assert(words[2].value:find('XP 1,500 / 6,000', 1, true))
assert(words[2].x == bar.x + (bar.width - valueWidth) / 2)
assert(words[2].y == bar.y + (bar.height - valueHeight) / 2)
assert(words[3].x == bar.x and words[3].y > bar.y + bar.height)
local rateWidth = calc(words[4].value)
assert(words[4].value:find('XP/hr', 1, true))
assert(words[4].x + rateWidth == bar.x + bar.width and words[4].y == words[3].y)
H.command('/expbar rate off')
frame()
assert(#words == 3 and not words[3].value:find('XP/hr', 1, true))
H.command('/expbar rate on')
H.command('/expbar mode invalid')
assert(options.overlay[1])
H.command('/expbar mode window')
frame()
assert(not options.overlay[1] and bar.height == 16)
assert(look.background == nil and look.border == nil and look.shadow == nil and look.padding == nil)
assert(H.command('/expbar rate off'))
assert(not H.options().showRate[1])
H.command('/expbar rate on')
assert(H.options().showRate[1])
H.command('/expbar hide')
assert(not H.options().isVisible[1])
H.command('/expbar show')
assert(H.options().isVisible[1])
H.command('/expbar reset')
H.command('/expbar')
H.frames(3)
H.unload()
H.print('expbar window/overlay layouts, colour, jobs, bounds, locking, settings and commands: true')
