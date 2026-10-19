-- Native party-order job labels: run through the Party harness.
local game = require('game')
local winxiGame = require('winxi.game')
local originalMenu, originalIndex = winxiGame.MenuName, game.StPartyIndex
-- Chat/menu names must never activate the labels. Slot zero is an active cursor too.
for _, menu in ipairs({'', 'menu    inline', 'menu    party', 'menu    map'}) do
    winxiGame.MenuName = function() return menu end
    game.StPartyIndex = function() return nil end
    assert(not game.IsPartyRearranging(), 'chat/menu name alone must not activate labels')
    for _, index in ipairs({0,5,6,17}) do
        game.StPartyIndex = function() return index end
        assert(game.IsPartyRearranging(), 'same cursor signal as hideparty, including alliance slots')
    end
end
winxiGame.MenuName, game.StPartyIndex = originalMenu, originalIndex
-- Validate the real pointer traversal and active flag used by hideparty.
local oldPointers = AshitaCore.GetPointerManager
local oldRead32, oldRead8 = ashita.memory.read_uint32, ashita.memory.read_uint8
local active, cursor, pointer = 0, 0, 100
AshitaCore.GetPointerManager = function() return {Get=function(_,name) assert(name=='party'); return pointer end} end
ashita.memory.read_uint32 = function(address)
    return ({[100]=200,[200]=300,[300+0x54]=active})[address] or 0
end
ashita.memory.read_uint8 = function(address) assert(address==300+0x50); return cursor end
assert(not game.IsPartyRearranging())
active = 1
for _, index in ipairs({0,6,17}) do
    cursor = index
    assert(game.IsPartyRearranging() and game.StPartyIndex()==index)
end
active = 0
assert(not game.IsPartyRearranging(), 'closing cursor restores normal buffs')
active, pointer = 1, 0
assert(not game.IsPartyRearranging(), 'missing pointer fails closed')
AshitaCore.GetPointerManager = oldPointers
ashita.memory.read_uint32, ashita.memory.read_uint8 = oldRead32, oldRead8
assert(game.JobText('WAR',15,'RDM',7) == '[WAR15/RDM7]')
assert(game.JobText(nil,0,nil,0) == '[---/---]')
assert(game.JobText('WAR',15,nil,0) == '[WAR15/---]')
assert(game.JobText('WAR',0,'RDM',7) == '[---/RDM7]')
local frames, draw = require('frames'), require('draw')
local options = require('options')
local style = options.Style(H.options())
style.showJobs, style.outline = true, false
local members = {
    {name='Known',serverId=1,isInZone=true,hpp=80,hp=1000,mpp=60,mp=500,tp=1000,
        statusIds={33,40},jobText=game.JobText('WAR',15,'RDM',7)},
    {name='Unknown',serverId=2,isInZone=false,zoneId=100,statusIds={33}},
}
local originalResources = AshitaCore.GetResourceManager
AshitaCore.GetResourceManager = function() return {GetString=function() return 'Elsewhere' end} end
local originalText = draw.Text
local labels, buffRequests = {}, 0
local function statusTexture() buffRequests=buffRequests+1; return 1,true end
for _, kind in ipairs({'party','alliance'}) do
    labels, buffRequests = {}, 0
    draw.Text = function(x,y,color,words,edge,dark)
        if words == '[WAR15/RDM7]' or words == '[---/---]' then
            assert(edge and edge >= 1 and dark, 'job labels outlined even when general outlines are disabled')
            labels[words] = (labels[words] or 0) + 1
        end
        return originalText(x,y,color,words,edge,dark)
    end
    frames.Draw(members,kind,statusTexture,style)
    assert(labels['[WAR15/RDM7]'] == 1 and labels['[---/---]'] == 1, kind .. ' job labels include out-of-zone members')
    assert(buffRequests == 0, 'buffs suppressed during rearrangement')
end
style.showJobs = false
labels, buffRequests = {}, 0
frames.Draw(members,'party',statusTexture,style)
assert(buffRequests > 0 and next(labels) == nil, 'buffs restored outside rearrangement')
-- Short Zone Names: the game's own short form of a member's area, its whole name where it has none, or off
local zoneNames = { ['zones.names'] = { [230] = 'Southern San d\'Oria', [231] = 'Northern San d\'Oria' },
    ['zones.names_abbr'] = { [230] = 'S.Sandy', [231] = '' } }
AshitaCore.GetResourceManager = function() return {GetString=function(_, table, id) return zoneNames[table][id] end} end
local written = {}
draw.Text = function(x,y,color,words,...) written[words] = true; return originalText(x,y,color,words,...) end
local away = {
    {name='Known',serverId=1,isInZone=true,hpp=80,hp=1000,mpp=60,mp=500,tp=1000,statusIds={}},
    {name='South',serverId=3,isInZone=false,zoneId=230,statusIds={}},
    {name='North',serverId=4,isInZone=false,zoneId=231,statusIds={}},
}
local saved = H.options()
assert(saved.style.zoneAbbr[1] == true, 'Short Zone Names on to begin with')
frames.Draw(away,'party',statusTexture,options.Style(saved))
assert(written['(S.Sandy)'] and written['(Northern San d...'],
    'Short Zone Names: the game\'s short form, the whole name where it has none')
assert(not written['(Southern San d\'Oria)'], 'the whole name not written where the short form is')
saved.style.zoneAbbr[1], written = false, {}
frames.Draw(away,'party',statusTexture,options.Style(saved))
assert(not written['(S.Sandy)'] and next(written) ~= nil, 'Short Zone Names off: the whole name')
saved.style.zoneAbbr[1] = true
draw.Text = originalText
AshitaCore.GetResourceManager = originalResources
assert(options.Style(H.options()).showJobs == false, 'temporary job-label flag never leaks into other frame kinds')
H.print('Native party cursor: hideparty-compatible detection, chat excluded, job formatting, outlined labels and buff restoration passed')
