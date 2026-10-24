-- Run with luajit tests/name_icons_check.lua; no game or Direct3D device needed.
package.path = 'addons/name/?.lua;' .. package.path
ashita = { memory = setmetatable({}, { __index = function() error('must not scan game memory') end }) }
package.preload.d3d8 = function() error('PNG icons must use the shared sheet loader') end
local loads, releases, gameReady = 0, 0, false
local gamePlaces = { [0x92] = { .5, .5, .75, .75 }, [0xAD] = { 0, 0, .25, .25 } }
local gameOverlays = { [0x92] = { { 0, 0, .5, .5, .25, .25, .5, .5 } } }
package.preload.playerdat = function() return {
    Load = function()
        loads = loads + 1
        if not gameReady then return nil, 'mock DAT unavailable' end
        return { address = 0x9876, places = gamePlaces, overlays = gameOverlays }
    end,
    Release = function() releases = releases + 1 end,
} end
local icons = require('icons')
local texture, customTexture, calls = 0, 0, 0
local function sheet(file)
    calls = calls + 1
    if file == 'player-icons.png' then return texture end
    assert(file == 'player-icons-custom.png')
    return customTexture
end
assert(#icons.Sources == 3 and icons.ValidSource('game') and icons.ValidSource('custom'))
assert(not icons.ValidSource('unknown'))
assert(not icons.Begin(sheet, 'bundled'))
assert(icons.Texture() == nil and not icons.Place(0x92))
texture = 0x1234
assert(icons.Begin(sheet, 'bundled'))
assert(icons.Texture() == texture and icons.Place(0x92))
local pearl, star = icons.Place(0x92), icons.Place(0xAD)
assert(pearl[1] == 0 and pearl[2] == .25 and pearl[3] == .125 and pearl[4] == .375)
assert(star[1] == .75 and star[2] == .25 and star[3] == .875 and star[4] == .375)
local badge = icons.Overlays(0xAC)[1]
assert(badge[1] == -1/16 and badge[2] == -1/16 and badge[3]-badge[1] == .5 and badge[4]-badge[2] == .5)
assert(not icons.Overlays(0x91) and not icons.Overlays(0xAD))
assert(not icons.Place(0x20) and not icons.Place(0xFF))
for byte = 0x8E, 0xB1 do
    local uv = assert(icons.Place(byte))
    assert(uv[1] >= 0 and uv[2] >= 0 and uv[3] <= 1 and uv[4] <= 1 and uv[1] < uv[3] and uv[2] < uv[4])
end
texture = 0
assert(not icons.Begin(sheet, 'bundled') and not icons.Place(0x92))
texture = 0x5678
assert(icons.Begin(sheet, 'bundled') and icons.Texture() == texture and calls == 4)
assert(loads == 0, 'bundled mode never loads DATs')
assert(icons.Begin(sheet, 'custom') and icons.Texture() == texture and icons.Problem('custom'))
assert(icons.Place(0x92) == pearl, 'custom failures restore bundled mapping too')
customTexture = 0x2222
assert(icons.Begin(sheet, 'custom') and icons.Texture() == customTexture and not icons.Problem())
assert(icons.Place(0x92) == pearl and icons.Overlays(0xAC)[1] == badge, 'custom PNG uses bundled layout')
assert(loads == 0, 'custom mode never reads DATs')
local clock = os.clock
local now = 0
os.clock = function() return now end
assert(icons.Begin(sheet, 'game') and icons.Texture() == texture and loads == 1)
assert(icons.Problem('game') == 'mock DAT unavailable' and not icons.Problem('custom'))
for _ = 1, 100 do assert(icons.Begin(sheet, 'game')) end
assert(loads == 1, 'failures must not retry/read DATs each frame')
gameReady, now = true, 11
assert(icons.Begin(sheet, 'game') and icons.Texture() == 0x9876 and loads == 2)
assert(icons.Place(0x92) == gamePlaces[0x92] and icons.Overlays(0x92) == gameOverlays[0x92])
assert(not icons.Overlays(0xAC) and not icons.Place(0x91), 'no stale bundled shapes on a game texture')
local warmCalls = calls
now = 100
for _ = 1, 100 do assert(icons.Begin(sheet, 'game')) end
assert(loads == 2 and calls == warmCalls and not icons.Problem(), 'successful DAT cache has no file/texture work')
assert(icons.Begin(sheet, 'custom') and icons.Texture() == customTexture and releases == 1)
assert(icons.Place(0x92) == pearl and icons.Overlays(0xAC)[1] == badge, 'switch restores custom/bundled UVs and overlays')
assert(icons.Begin(sheet, 'game') and loads == 3, 'switching back builds a fresh DAT atlas')
assert(icons.Begin(sheet, 'bundled') and releases == 2 and icons.Texture() == texture)
-- An unexpected loader exception must also leave a working bundled fallback.
package.loaded.playerdat.Load = function() error('bad mod') end
assert(icons.Begin(sheet, 'game') and icons.Texture() == texture and icons.Problem():find('bad mod'))
assert(icons.Begin(sheet, 'bundled'))
assert(icons.Begin(sheet, 'invalid') and icons.Texture() == texture, 'invalid keys safely default to game with fallback')
local coldLoads, coldCalls = loads, calls
assert(not icons.Begin(sheet, 'game', false) and icons.Texture() == nil)
assert(loads == coldLoads and calls == coldCalls, 'disabled artwork must not read DATs or PNGs')
assert(icons.Begin(sheet, 'custom', true) and icons.Texture() == customTexture)
os.clock = clock
local captured
package.loaded['winxi.nameplates'] = { Quad = function(...) captured = {...} end }
local outline = { iconOutline = {3}, iconOutlineOpacity = {50} }
icons.ConfigureOutline(outline, 32, 1, 1)
icons.Quad(1,2,3,4,.1,.2,.3,.4,0xAABBCCDD,3,true)
assert(captured[9]==0xAABBCCDD and captured[11] and captured[12]==.5 and captured[14] and captured[15]==3)
outline.outline={0}
icons.ConfigureOutline(outline,32,2,1)
icons.Quad(1,2,3,4,0,0,1,1,0xFFFFFFFF,1)
assert(captured[11] and captured[15]==6, 'icon width scales independently of disabled text edges')
outline.iconOutlineOpacity[1]=0
icons.ConfigureOutline(outline,32,1,1)
icons.Quad(1,2,3,4,0,0,1,1,0xAABBCCDD,1)
assert(not captured[11] and captured[9]==0xAABBCCDD, 'zero opacity skips edges, not fills')
outline.iconOutlineOpacity[1],outline.iconOutline[1]=100,0
icons.ConfigureOutline(outline,32,1,1)
icons.Quad(1,2,3,4,0,0,1,1,0xFFFFFFFF,1)
assert(not captured[11] and captured[15]==0)
outline.iconOutline[1]=3
icons.ConfigureOutline(outline,32,1,.5)
icons.Quad(1,2,3,4,0,0,1,1,0xFFFFFFFF,1)
assert(captured[15]==2, 'icon thickness shrinks at the existing distance rungs')
print('name icons: three sources, DAT caching/retry/release, custom PNG, bundled fallback, UVs/overlays and no game-memory scans\ttrue')
