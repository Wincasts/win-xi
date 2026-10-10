addon.name    = 'twister'
addon.author  = 'win (and claude)'
addon.version = '1.0'
addon.desc    = 'Plays a sound when something happens: a tell, an invite, a trade, being examined, an item you are after dropping, low HP and the like.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- A sound for each of a few things worth hearing about. Each event has its own switch and its own
-- sound, any wav in the addon's sounds folder. It needs only winxi.
--
--   /twister           opens or closes the settings
--   /twister test      plays every event's sound in turn, to hear them
--
-- Beside the events there are triggers, which are experimental: a sound of your choosing when a mob
-- of a kind of your choosing begins a spell or a weaponskill of your choosing, or uses an ability,
-- in any area. They are made in the settings' Triggers tab, from what mobs.lua says each kind can do.
--
-- What sets a sound off is read from packets (chat, invitations, trades, being examined, messages, treasure, actions) and from the party's
-- numbers as the game keeps them (TP, HP and MP), looked at a few times a second.
--
-- Ashita plays one sound at a time, at the volume of the file: a sound cuts short the one before it.
-- So that one event's sound is not lost to another's, a sound asked for while one is playing waits
-- for it to finish.

require('common')
local bit = require('bit')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local shell = require('winxi.shell')
local game = require('winxi.game')

-- The events, in the order the settings list them. file is the sound an event starts with: its spoken one.
local events = {
    { key = 'tell', group = 'Chat', label = 'Tell Received', file = 'voice-tell.wav',
      tooltip = 'Someone sends you a tell.' },
    { key = 'mention', group = 'Chat', label = 'Name Mentioned', file = 'voice-mention.wav',
      tooltip = 'Someone else says your character\'s name in party or linkshell chat.' },
    { key = 'invite', group = 'Chat', label = 'Party Invite', file = 'voice-invite.wav',
      tooltip = 'You are invited to a party or an alliance.' },
    { key = 'trade', group = 'Chat', label = 'Trade Request', file = 'voice-trade.wav',
      tooltip = 'Someone asks to trade with you.' },
    { key = 'examine', group = 'Chat', label = 'Examined', file = 'voice-examine.wav',
      tooltip = 'Someone examines you.' },
    { key = 'tp', group = 'Combat', label = 'TP Ready', file = 'voice-tp.wav',
      tooltip = 'Your TP reaches 1000.' },
    { key = 'lowhp', group = 'Combat', label = 'Low HP', file = 'voice-lowhp.wav', threshold = 'lowHpPercent', thresholdLabel = 'HP Threshold',
      thresholdTooltip = 'How low your HP has to fall for this to sound: to this percentage, or under it.',
      tooltip = 'Your HP falls to the percentage below, or under it. It sounds once, and not again until your HP has been back over that.' },
    { key = 'lowmp', group = 'Combat', label = 'Low MP', file = 'voice-lowmp.wav', threshold = 'lowMpPercent', thresholdLabel = 'MP Threshold',
      thresholdTooltip = 'How low your MP has to fall for this to sound: to this percentage, or under it.',
      tooltip = 'Your MP falls to the percentage below, or under it. It sounds once, and not again until your MP has been back over that.\nNothing sounds on a job with no MP.' },
    { key = 'ko', group = 'Combat', label = 'Party Member KO', file = 'voice-ko.wav',
      tooltip = 'Someone else in your party is knocked out, in the area you are in.' },
    { key = 'skillup', group = 'Other', label = 'Skill Up', file = 'voice-skillup.wav',
      tooltip = 'One of your skills rises, or reaches a new level: a combat or magic skill, or a craft.' },
    { key = 'drop', group = 'Other', label = 'Item Drop', file = 'voice-drop.wav', items = 'dropItems',
      tooltip = 'One of the items named below drops: it lands in the treasure pool, yours alone or the party\'s.' },
}

local defaults = T{
    events = T{ },
    lowHpPercent = T{ 25 },
    lowMpPercent = T{ 20 },
    dropItems = T{ '' },
    triggers = T{ },
}
for _, event in ipairs(events) do
    defaults.events[event.key] = T{ enabled = T{ true }, sound = event.file }
end

local function Say(text)
    print(('\30\81[twister]\30\01 %s'):format(text))
end

---------------------------------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------------------------------

local soundFolder = addon.path .. 'sounds\\'
local minimumGap = 1.0 -- seconds between two soundings of one event: packets come in bursts, and twice over
local lastPlayed = { } -- event key -> when

local app -- made below, once the settings can be drawn

-- How long a sound lasts, in seconds, read from its file the first time it is wanted: the bytes it
-- plays a second are in its 'fmt ' part, and how many bytes there are of it in its 'data' part
local usualLength = 0.5 -- for a file that cannot be read
local lengths = { }     -- file -> seconds

local function Number(text, at)
    local a, b, c, d = text:byte(at, at + 3)
    if d == nil then
        return nil
    end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function Length(file)
    local length = lengths[file]
    if length == nil then
        length = usualLength
        local opened = io.open(soundFolder .. file, 'rb')
        if opened ~= nil then
            local head = opened:read(4096) or ''
            opened:close()
            local format = head:find('fmt ', 1, true)
            local data = head:find('data', 1, true)
            local rate = format and Number(head, format + 16)
            local size = data and Number(head, data + 4)
            if rate and size and rate > 0 then
                length = size / rate
            end
        end
        lengths[file] = length
    end
    return length
end

local playingUntil = 0 -- when the sound last started will have finished
local waiting = { }    -- sounds asked for while one was playing, the first asked for first
local waitAtMost = 3   -- seconds: a sound that has waited longer says nothing worth hearing any more

local function PlayFile(file)
    local path = soundFolder .. file
    if not ashita.fs.exists(path) then
        return false
    end
    ashita.misc.play_sound(path)
    playingUntil = os.clock() + Length(file)
    return true
end

-- Starts whatever has been waiting, once the sound before it is over: looked at every frame
local function PlayWaiting()
    local now = os.clock()
    while #waiting > 0 and now >= playingUntil do
        local nextUp = table.remove(waiting, 1)
        if now - nextUp.asked <= waitAtMost then
            PlayFile(nextUp.file)
        end
    end
end

-- A sound is wanted, for whatever key stands for: an event's name, or a trigger. At once if nothing
-- is playing, after what is if something is, and not at all if the same was wanted a moment ago.
local function Ask(file, key)
    local now = os.clock()
    if lastPlayed[key] ~= nil and now - lastPlayed[key] < minimumGap then
        return
    end
    lastPlayed[key] = now
    if now >= playingUntil and #waiting == 0 then
        PlayFile(file)
    else
        waiting[#waiting + 1] = { file = file, asked = now }
    end
end

-- An event has happened: its sound, if it is switched on
local function Sound(key)
    local chosen = app.options.events[key]
    if chosen.enabled[1] then
        Ask(chosen.sound, key)
    end
end

---------------------------------------------------------------------------------------------------
-- Chat, invitations and messages: from packets
---------------------------------------------------------------------------------------------------

local packetSystemMessage = 0x009
local packetChat = 0x017
local packetTrade = 0x021 -- someone asks to trade
local packetAction = 0x028
local packetMessage = 0x029
local packetTreasure = 0x0D2 -- an item is in the treasure pool
local packetInvite = 0x0DC

local chatTell = 3
-- party and linkshell chat, with and without the speaker shown
local chatAmongFriends = { [4] = true, [5] = true, [15] = true, [16] = true, [27] = true, [28] = true }

-- The player's name in small letters, and the pattern that finds it as a word of its own, not as
-- part of another: made again only when the name is another one
local knownName, ownName, namePattern = nil, nil, nil

local function OwnName()
    local name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    if type(name) ~= 'string' or name == '' then
        return nil
    end
    if name ~= knownName then
        knownName, ownName = name, name:lower()
        namePattern = '%f[%a]' .. ownName:gsub('%p', '%%%0') .. '%f[%A]'
    end
    return ownName
end

-- A string of bytes that ends at its first zero
local function Text(data, first, last)
    local text = data:sub(first, last)
    local zero = text:find('\0', 1, true)
    return zero and text:sub(1, zero - 1) or text
end

-- The chat packet: the kind of message at 0x04, who said it at 0x08 (15 bytes), what they said from 0x17
local function OnChat(data)
    local kind = data:byte(0x04 + 1)
    if kind == chatTell then
        Sound('tell')
    elseif chatAmongFriends[kind] and app.options.events.mention.enabled[1] then
        local own = OwnName()
        if own == nil then
            return
        end
        if Text(data, 0x08 + 1, 0x08 + 15):lower() == own then
            return
        end
        if Text(data, 0x17 + 1, #data):lower():find(namePattern) then
            Sound('mention')
        end
    end
end

-- The message packet: who it is about at 0x08, and which message at 0x18, in its low 15 bits. A skill
-- rising and a skill reaching a level are two of them, and the player's own are the ones wanted.
local messageSkillRises, messageSkillLevel = 38, 53

local function OnMessage(data)
    local message = struct.unpack('H', data, 0x18 + 1) % 0x8000
    if message ~= messageSkillRises and message ~= messageSkillLevel then
        return
    end
    if struct.unpack('I', data, 0x08 + 1) == AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0) then
        Sound('skillup')
    end
end

-- The system message packet: which message at 0x0A. One of them says that someone examines you, and
-- it is sent only to the one examined.
local systemMessageExamines = 89

local function OnSystemMessage(data)
    if struct.unpack('H', data, 0x0A + 1) == systemMessageExamines then
        Sound('examine')
    end
end

-- The items listened for, by name in small letters: read from what is written in the settings, names
-- with commas between them, and read again only when that is something else
local wantedText, wanted = nil, { }

local function Wanted(text)
    if text ~= wantedText then
        wantedText, wanted = text, { }
        for name in text:gmatch('[^,]+') do
            name = name:match('^%s*(.-)%s*$'):lower()
            if name ~= '' then
                wanted[name] = true
            end
        end
    end
    return wanted
end

-- The treasure packet: which item at 0x10, and at 0x15 whether it was in the pool already, as every
-- item in it is told of again on arriving in an area. A place in the pool with nothing in it is item 0.
local function OnTreasure(data)
    if not app.options.events.drop.enabled[1] or data:byte(0x15 + 1) ~= 0 then
        return
    end
    local id = struct.unpack('H', data, 0x10 + 1)
    local item = id ~= 0 and AshitaCore:GetResourceManager():GetItemById(id) or nil
    local name = item ~= nil and item.Name ~= nil and item.Name[1] or nil
    if type(name) == 'string' and Wanted(app.options.dropItems[1])[name:lower()] then
        Sound('drop')
    end
end

---------------------------------------------------------------------------------------------------
-- Triggers: a mob begins a spell or a weaponskill, or uses an ability
---------------------------------------------------------------------------------------------------

-- What is known of the game's mobs is in mobs.lua, which generate_mobs.py makes and says the layout
-- of: the kinds of mob there are (sheep, crabs, quadav) with what each kind's mobs can do, and for
-- every area the names of its mobs of each kind.
--
-- It is read when it is wanted and not kept: by the Triggers tab, to make a trigger with, which lets
-- go of it when the settings are closed; and once in an area, the first time a mob there does what a
-- trigger is for, to find out which kind each of the area's mobs is. That is kept for the one area,
-- being small: a few dozen names.
local mobData = nil -- mobs.lua as it is, or false if it cannot be read
local area = nil    -- the one area: { zone, kindOf = a mob's name in small letters -> its kind, among = kind -> its mobs there, as written }

local function MobData()
    if mobData == nil then
        mobData = false
        local chunk = loadfile(addon.path .. 'mobs.lua')
        if chunk ~= nil then
            local ok, found = pcall(chunk)
            if ok and type(found) == 'table' and type(found.zones) == 'table' and type(found.kinds) == 'table' then
                mobData = found
            end
        end
    end
    return mobData or nil
end

local function ForgetMobData()
    mobData = nil
end

-- An area's mobs: which kind each is, and each kind's mobs. Nothing in either for an area nothing
-- is known of.
local function Area(zone)
    if area == nil or area.zone ~= zone then
        area = { zone = zone, kindOf = { }, among = { } }
        local data = MobData()
        local written = data ~= nil and data.zones[zone] or nil
        if written ~= nil then
            for kind, names in written:gmatch('([^:;]+):([^;]*);') do
                area.among[kind] = names
                for name in names:gmatch('[^|]+') do
                    area.kindOf[name:lower()] = kind
                end
            end
        end
    end
    return area
end

local function CurrentZone()
    return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
end

-- A name out of the game's own files, or nil: some come with what ends them still on the end
local function GameName(read, ...)
    local ok, name = pcall(read, ...)
    if not ok or type(name) ~= 'string' then
        return nil
    end
    name = name:gsub('[%z\1-\31].*', '')
    return name ~= '' and name or nil
end

-- What a spell, a weaponskill or an ability is called. A mob's weaponskills and abilities over 256
-- are named in the game's list of monsters' abilities, and those under it are the players' own. Where
-- the game has no name, the server's is used, from mobs.lua.
local actionNames = { spell = { }, move = { } }

local function ActionName(kind, id)
    local names = actionNames[kind == 'spell' and 'spell' or 'move']
    local name = names[id]
    if name ~= nil then
        return name
    end
    local resources = AshitaCore:GetResourceManager()
    if kind == 'spell' then
        name = GameName(function() return resources:GetSpellById(id).Name[1] end)
            or ('Spell %d'):format(id)
    else
        if id > 256 then
            name = GameName(function() return resources:GetString('monsters.abilities', id - 256, 2) end)
        else
            name = GameName(function() return resources:GetAbilityById(id).Name[1] end)
        end
        if name == nil then
            local data = MobData()
            name = data ~= nil and type(data.names) == 'string' and data.names:match((';%d=([^;]*);'):format(id))
                or ('%s %d'):format(kind == 'skill' and 'Weaponskill' or 'Ability', id)
        end
    end
    names[id] = name
    return name
end

-- The name of whoever has a server id: a mob's place among the area's entities is in the low bits
-- of its id
local function EntityName(serverId)
    local entity = GetEntity(bit.band(serverId, 0xFFF))
    if entity ~= nil and entity.ServerId == serverId and type(entity.Name) == 'string' then
        return entity.Name:lower()
    end
    return nil
end

-- Some bits of a packet, as a number: offset is counted in bits from the packet's start, the low bit
-- of each byte first, which is how the action packet is packed. Up to 32 bits.
local function Bits(data, offset, length)
    local first = math.floor(offset / 8)
    local value = 0
    for index = 4, 0, -1 do
        value = value * 256 + (data:byte(first + index + 1) or 0)
    end
    return math.floor(value / 2 ^ (offset % 8)) % 2 ^ length
end

-- The action packet: who acted at bit 40, how many targets at 72, the kind of action at 82, what the
-- action is at 86, and from 150 each target (its id, how many results, then each result).
--
-- Beginning a weaponskill and beginning a spell are two kinds, and which weaponskill or spell is the
-- first result's number, 27 bits into it. One broken off is sent as the same kind: a weaponskill then
-- has no number, and a spell no message (the ten bits after the number).
--
-- An ability is used at once, with no beginning sent, so it is heard as it is used: the kinds that
-- say a mob's move is done (of a move numbered under 256, and of the others), which name the move as
-- what the action is.
local beginsKinds = { [7] = 'skill', [8] = 'spell' }
local doneKinds = { [3] = true, [11] = true }

-- Whether a number is among a trigger's: a few at most
local function Has(ids, id)
    for index = 1, #ids do
        if ids[index] == id then
            return true
        end
    end
    return false
end

local function OnAction(data)
    local triggers = app.options.triggers
    if #triggers == 0 then
        return
    end
    local category = Bits(data, 82, 4)
    local kind, id = beginsKinds[category], 0
    if kind ~= nil then
        if Bits(data, 72, 6) == 0 or Bits(data, 182, 4) == 0 then
            return
        end
        id = Bits(data, 213, 17)
        if kind == 'spell' and Bits(data, 230, 10) == 0 then
            return
        end
    elseif doneKinds[category] then
        kind, id = 'ability', Bits(data, 86, 32)
    end
    if id == 0 then
        return
    end

    -- which kind of mob it is that acts: found out once, and only if a trigger is for this spell or move
    local actorKind = nil
    for _, trigger in ipairs(triggers) do
        if trigger.kind == kind and trigger.enabled[1] and Has(trigger.ids, id) then
            if actorKind == nil then
                local actor = EntityName(Bits(data, 40, 32))
                actorKind = actor ~= nil and Area(CurrentZone()).kindOf[actor] or false
                if not actorKind then
                    return
                end
            end
            if trigger.mob == actorKind then
                Ask(trigger.sound, trigger)
            end
        end
    end
end

ashita.events.register('packet_in', 'twister_packet_in', function(e)
    if app == nil then
        return
    end
    if e.id == packetChat then
        OnChat(e.data)
    elseif e.id == packetInvite then
        Sound('invite')
    elseif e.id == packetTrade then
        Sound('trade')
    elseif e.id == packetSystemMessage then
        OnSystemMessage(e.data)
    elseif e.id == packetMessage then
        OnMessage(e.data)
    elseif e.id == packetTreasure then
        OnTreasure(e.data)
    elseif e.id == packetAction then
        OnAction(e.data)
    end
end)

---------------------------------------------------------------------------------------------------
-- TP, HP, MP and the party's HP: from the game's own numbers
---------------------------------------------------------------------------------------------------

local lookEvery = 0.1  -- seconds between looks
local settleFor = 3    -- seconds after arriving in an area before anything is believed
local rearmOver = 5    -- how far over its threshold HP or MP has to climb before it can sound again

local lastLook, arrived = 0, nil
local lastTp = nil
local lowHp, lowMp = nil, nil -- whether each was low when last looked at; nil: not looked at yet
local lastHp = { }            -- party place (1 to 5) -> that member's HP percentage, or nil

-- A member arriving in the area is shown with no HP for a moment before their own is known, and so
-- may one who is leaving it. So a member is not believed until they have been here a while, and one
-- with no HP is not taken for knocked out until they have had none for a second.
local memberSettle = 5 -- seconds a member has to have been in the area before their HP is believed
local downFor = 1      -- seconds without HP before it is a knockout
local memberId = { }   -- party place -> who is in it
local memberSince = { } -- party place -> when they were first seen in this area
local downSince = { }  -- party place -> when their HP went from some to none

local function ForgetMember(place)
    lastHp[place], memberId[place], memberSince[place], downSince[place] = nil, nil, nil, nil
end

local function Forget()
    lastTp, lowHp, lowMp = nil, nil, nil
    for place = 1, 5 do
        ForgetMember(place)
    end
end

-- Low is at or under the threshold; once low, not low again until over it by a margin, so that a
-- number hovering at the threshold does not sound over and over
local function IsLow(percent, threshold, wasLow)
    if wasLow then
        return percent < threshold + rearmOver
    end
    return percent <= threshold
end

local function Look()
    local now = os.clock()
    if now - lastLook < lookEvery then
        return
    end
    lastLook = now

    if game.IsLoading() then
        arrived = nil
        Forget()
        return
    end
    arrived = arrived or now
    if now - arrived < settleFor then
        return
    end

    local options = app.options
    local party = AshitaCore:GetMemoryManager():GetParty()

    local tp = party:GetMemberTP(0)
    if lastTp ~= nil and lastTp < 1000 and tp >= 1000 then
        Sound('tp')
    end
    lastTp = tp

    -- knocked out is not low: there is nothing left to warn of
    local hp = party:GetMemberHPPercent(0)
    local hpLow = hp > 0 and IsLow(hp, options.lowHpPercent[1], lowHp)
    if hpLow and lowHp == false then
        Sound('lowhp')
    end
    lowHp = hpLow

    if AshitaCore:GetMemoryManager():GetPlayer():GetMPMax() > 0 then
        local mpLow = hp > 0 and IsLow(party:GetMemberMPPercent(0), options.lowMpPercent[1], lowMp)
        if mpLow and lowMp == false then
            Sound('lowmp')
        end
        lowMp = mpLow
    else
        lowMp = nil
    end

    -- the others of the party: one who was standing and has no HP now. Someone in another area has
    -- none either, as far as the game here knows, so only those in this one are watched.
    if not options.events.ko.enabled[1] then
        -- nothing is kept of them meanwhile: what was true before it was switched off may not be now
        for place = 1, 5 do
            ForgetMember(place)
        end
        return
    end
    local zone = party:GetMemberZone(0)
    for place = 1, 5 do
        if party:GetMemberIsActive(place) == 1 and party:GetMemberZone(place) == zone then
            -- someone else in this place of the party is someone new
            local id = party:GetMemberServerId(place)
            if id ~= memberId[place] then
                ForgetMember(place)
                memberId[place], memberSince[place] = id, now
            end

            if now - memberSince[place] >= memberSettle then
                local memberHp = party:GetMemberHPPercent(place)
                if memberHp > 0 then
                    downSince[place] = nil
                elseif lastHp[place] ~= nil and lastHp[place] > 0 then
                    downSince[place] = now
                end
                if downSince[place] ~= nil and now - downSince[place] >= downFor then
                    downSince[place] = nil
                    Sound('ko')
                end
                lastHp[place] = memberHp
            end
        else
            ForgetMember(place)
        end
    end
end

---------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------

-- The wav files in the sounds folder, looked for again every few seconds while the settings are open
local files, filesRead = { }, -10

local function Files()
    local now = os.clock()
    if now - filesRead > 3 then
        filesRead = now
        files = { }
        local found = ashita.fs.get_directory(soundFolder, '.*\\.wav')
        if type(found) == 'table' then
            for _, name in pairs(found) do
                files[#files + 1] = name
            end
            table.sort(files)
        end
    end
    return files
end

local ids = { } -- the hidden labels of the controls: made once
for _, event in ipairs(events) do
    ids[event.key] = {
        enabled = ('##twister.%s.enabled'):format(event.key),
        sound = ('##twister.%s.sound'):format(event.key),
        test = ('Test##twister.%s.test'):format(event.key),
        threshold = ('##twister.%s.threshold'):format(event.key),
        items = ('##twister.%s.items'):format(event.key),
    }
end

-- A mark at the end of a line that tells, when hovered, what the line is for. Every line's is at the
-- same place: a little past where an event's own line ends, at its Test button, which is the longest.
local lineEnd = 0  -- where the event's line ends, measured as it is drawn
local markGap = 8  -- between that and the mark

-- beside: true for a mark straight after what is before it, where the lines are not events'
local function Mark(text, beside)
    imgui.SameLine(beside and 0 or lineEnd + markGap)
    imgui.TextDisabled('(?)')
    if imgui.IsItemHovered() then
        imgui.SetTooltip(text)
    end
end

-- The width of a control under an event's line that ends where that line does
local function ToLineEnd()
    return math.max(lineEnd - imgui.GetCursorPosX(), 100)
end

local function DrawEvent(options, event)
    local chosen = options.events[event.key]
    local id = ids[event.key]

    widgets.Label(event.label)
    imgui.Checkbox(id.enabled, chosen.enabled)

    imgui.SameLine()
    imgui.SetNextItemWidth(170)
    if imgui.BeginCombo(id.sound, chosen.sound) then
        for _, file in ipairs(Files()) do
            if imgui.Selectable(file, file == chosen.sound) then
                chosen.sound = file
                PlayFile(file)
                app:Save()
            end
        end
        imgui.EndCombo()
    end

    imgui.SameLine()
    if imgui.Button(id.test) and not PlayFile(chosen.sound) then
        Say(('There is no %s in the sounds folder.'):format(chosen.sound))
    end
    imgui.SameLine(0, 0)
    lineEnd = imgui.GetCursorPosX()

    -- what sets the event off
    Mark(event.tooltip)

    -- the threshold only while the event is switched on: off, there is nothing for it to set
    if event.threshold ~= nil and chosen.enabled[1] then
        widgets.Label(event.thresholdLabel)
        imgui.SetNextItemWidth(ToLineEnd())
        imgui.SliderInt(id.threshold, options[event.threshold], 5, 90, '%d%%')
        Mark(event.thresholdTooltip)
    end

    -- and so the names of the items listened for
    if event.items ~= nil and chosen.enabled[1] then
        widgets.Label('Items')
        imgui.SetNextItemWidth(ToLineEnd())
        imgui.InputText(id.items, options[event.items], 1024)
        if imgui.IsItemDeactivatedAfterEdit() then
            app:Save()
        end
        Mark('The items to listen for, by name, with a comma between one and the next:\nKindred\'s Seal, Beastmen\'s Seal\nA name is the whole of the item\'s name as the game shows it, in capitals or not.')
    end
end

local function DrawSettings(options)
    local group = nil
    for _, event in ipairs(events) do
        if event.group ~= group then
            -- the first heads the tab: no blank line over it
            widgets.Header(event.group, group == nil)
            group = event.group
        end
        DrawEvent(options, event)
    end
end

---------------------------------------------------------------------------------------------------
-- Settings: the Triggers tab
---------------------------------------------------------------------------------------------------

local triggerSound = 'voice-trigger.wav' -- what a trigger starts with

-- The trigger being made
local making = { mob = nil, action = nil, sound = triggerSound }

-- What a kind of mob can do, each with its name, in the order of their names: found out once for a
-- kind, and kept with what is known of it. The game has some things under more than one number (a
-- weaponskill, and the same again for the mobs of Dynamis): what has one name is one thing to choose,
-- with every number it goes by.
local kindLabels = { spell = 'Spell', skill = 'Weaponskill', ability = 'Ability' }

local function MobActions(known)
    local actions = known.actions
    if actions == nil then
        actions = { }
        local named = { } -- kind and name -> the action
        local function Add(kind, id)
            local name = ActionName(kind, id)
            local action = named[kind .. name]
            if action == nil then
                action = { kind = kind, ids = T{ }, name = name,
                    label = ('%s (%s)##%s%d'):format(name, kindLabels[kind], kind, id) }
                named[kind .. name] = action
                actions[#actions + 1] = action
            end
            action.ids[#action.ids + 1] = id
        end
        for id in known.spells:gmatch('%d+') do
            Add('spell', tonumber(id))
        end
        for ability, id in known.moves:gmatch('(a?)(%d+)') do
            Add(ability == 'a' and 'ability' or 'skill', tonumber(id))
        end
        table.sort(actions, function(a, b) return a.label < b.label end)
        known.actions = actions
    end
    return actions
end

local zoneNames = { }

local function ZoneName(zone)
    local name = zoneNames[zone]
    if name == nil then
        local resources = AshitaCore:GetResourceManager()
        name = GameName(function() return resources:GetString('zones.names', zone) end) or ('Area %d'):format(zone)
        zoneNames[zone] = name
    end
    return name
end

-- A list of sounds to choose from. Returns the file chosen, or nil.
local function SoundCombo(id, current)
    local picked = nil
    imgui.SetNextItemWidth(170)
    if imgui.BeginCombo(id, current) then
        for _, file in ipairs(Files()) do
            if imgui.Selectable(file, file == current) then
                picked = file
                PlayFile(file)
            end
        end
        imgui.EndCombo()
    end
    return picked
end

local function TestButton(file)
    if imgui.Button('Test') and not PlayFile(file) then
        Say(('There is no %s in the sounds folder.'):format(file))
    end
end

local function HasTrigger(triggers, mob, action)
    for _, trigger in ipairs(triggers) do
        if trigger.mob == mob and trigger.kind == action.kind and trigger.name == action.name then
            return true
        end
    end
    return false
end

-- The kinds of mob to choose among, in two lists, each in the order of their names: those with mobs
-- in the area, and the rest. Put together once for an area, and kept with what is known of the mobs.
local function KindLists(data, zone)
    local lists = data.lists
    if lists == nil or lists.zone ~= zone then
        lists = { zone = zone, here = { }, elsewhere = { } }
        local among = Area(zone).among
        for kind in pairs(data.kinds) do
            local list = among[kind] ~= nil and lists.here or lists.elsewhere
            list[#list + 1] = kind
        end
        table.sort(lists.here)
        table.sort(lists.elsewhere)
        data.lists = lists
    end
    return lists
end

local function KindChoices(kinds)
    for _, kind in ipairs(kinds) do
        if imgui.Selectable(kind, kind == making.mob) and kind ~= making.mob then
            making.mob, making.action = kind, nil
        end
    end
end

local function DrawMaking(options)
    local data = MobData()
    if data == nil then
        imgui.TextDisabled('mobs.lua, which says what mobs can do, cannot be read.')
        return
    end
    local zone = CurrentZone()
    local lists = KindLists(data, zone)

    widgets.Label('Mob Type')
    imgui.SetNextItemWidth(260)
    if imgui.BeginCombo('##twister.making.mob', making.mob or 'Choose One') then
        -- the area's own first, under its name, then the rest
        if #lists.here > 0 then
            imgui.TextDisabled(ZoneName(zone))
            KindChoices(lists.here)
            imgui.Separator()
            imgui.TextDisabled('Elsewhere')
        end
        KindChoices(lists.elsewhere)
        imgui.EndCombo()
    end
    local here = making.mob ~= nil and Area(zone).among[making.mob] or nil
    Mark(making.mob == nil and 'The kinds of mob that cast spells, ready weaponskills or use abilities: those of the area you are in first.\nA trigger is for every mob of the kind, in any area.'
        or here ~= nil and ('In %s: %s'):format(ZoneName(zone), (here:gsub('|', ', ')))
        or ('There are none in %s.'):format(ZoneName(zone)), true)

    widgets.Label('Action')
    imgui.SetNextItemWidth(260)
    if imgui.BeginCombo('##twister.making.action', making.action and making.action.label or 'Choose One') then
        if making.mob ~= nil and data.kinds[making.mob] ~= nil then
            for _, action in ipairs(MobActions(data.kinds[making.mob])) do
                if imgui.Selectable(action.label, making.action ~= nil and action.label == making.action.label) then
                    making.action = action
                end
            end
        end
        imgui.EndCombo()
    end
    Mark('What a mob of the kind does that sets the sound off: everything its mobs do between them, wherever they are, so more than any one of them does.\nA spell or a weaponskill sounds as the mob begins it, not as it lands.\nAn ability is used at once, with nothing readied first, and sounds as it is used.', true)

    widgets.Label('Sound')
    making.sound = SoundCombo('##twister.making.sound', making.sound) or making.sound
    imgui.SameLine()
    imgui.PushID('twister.making')
    TestButton(making.sound)
    imgui.PopID()

    if imgui.Button('Add Trigger') then
        if making.mob == nil or making.action == nil then
            Say('Choose a kind of mob and what it does first.')
        elseif HasTrigger(options.triggers, making.mob, making.action) then
            Say(('There is a trigger for %s and %s already.'):format(making.mob, making.action.name))
        else
            options.triggers[#options.triggers + 1] = T{ mob = making.mob, kind = making.action.kind,
                ids = T{ unpack(making.action.ids) }, name = making.action.name, sound = making.sound, enabled = T{ true } }
            making.action = nil
            app:Save()
        end
    end
end

-- What a trigger is shown as: put together once for each
local triggerTexts = setmetatable({ }, { __mode = 'k' })

local function TriggerText(trigger)
    local text = triggerTexts[trigger]
    if text == nil then
        text = ('%s: %s'):format(trigger.mob, trigger.name)
        triggerTexts[trigger] = text
    end
    return text
end

local function DrawTriggers(options)
    -- [Experimental], as every addon here marks what is
    imgui.TextColored(widgets.ExperimentalColor, '[Experimental]')
    imgui.SameLine()
    imgui.Text('A sound when a mob begins a spell or a weaponskill, or uses an ability.')

    widgets.Header('New Trigger')
    DrawMaking(options)

    widgets.Header('Triggers')
    local triggers = options.triggers
    if #triggers == 0 then
        imgui.TextDisabled('None yet.')
        return
    end
    local removed = nil
    for index, trigger in ipairs(triggers) do
        imgui.PushID(index)
        imgui.Checkbox('##enabled', trigger.enabled)
        imgui.SameLine()
        local picked = SoundCombo('##sound', trigger.sound)
        if picked ~= nil then
            trigger.sound = picked
            app:Save()
        end
        imgui.SameLine()
        TestButton(trigger.sound)
        imgui.SameLine()
        if imgui.Button('Remove') then
            removed = index
        end
        imgui.SameLine()
        imgui.Text(TriggerText(trigger))
        imgui.PopID()
    end
    if removed ~= nil then
        table.remove(triggers, removed)
        app:Save()
    end
end

-- A trigger as the settings hold it, or nil if it is not one
local function IsTrigger(trigger)
    return type(trigger) == 'table' and (type(trigger.id) == 'number' or type(trigger.ids) == 'table' and type(trigger.ids[1]) == 'number')
        and type(trigger.mob) == 'string' and kindLabels[trigger.kind] ~= nil
end

-- Whatever saved settings lack, or have as the wrong kind of thing
local function Complete(options)
    if type(options.events) ~= 'table' then options.events = T{ } end
    for _, event in ipairs(events) do
        local chosen = options.events[event.key]
        if type(chosen) ~= 'table' then
            chosen = T{ }
            options.events[event.key] = chosen
        end
        if type(chosen.enabled) ~= 'table' then chosen.enabled = T{ true } end
        if type(chosen.sound) ~= 'string' or chosen.sound == '' then chosen.sound = event.file end
        if event.threshold ~= nil and (type(options[event.threshold]) ~= 'table' or type(options[event.threshold][1]) ~= 'number') then
            options[event.threshold] = T{ defaults[event.threshold][1] }
        end
        if event.items ~= nil and (type(options[event.items]) ~= 'table' or type(options[event.items][1]) ~= 'string') then
            options[event.items] = T{ '' }
        end
    end

    -- the triggers: what is not one is dropped, and each is given what it is shown as
    local triggers = T{ }
    for _, trigger in ipairs(type(options.triggers) == 'table' and options.triggers or { }) do
        if IsTrigger(trigger) then
            if type(trigger.enabled) ~= 'table' then trigger.enabled = T{ true } end
            if type(trigger.sound) ~= 'string' or trigger.sound == '' then trigger.sound = triggerSound end
            -- one made when a trigger was for a single number
            if type(trigger.ids) ~= 'table' then trigger.ids = T{ trigger.id } end
            trigger.id = nil
            if type(trigger.name) ~= 'string' then trigger.name = ActionName(trigger.kind, trigger.ids[1]) end
            -- one made when a trigger was for an area, and at first for one mob of it: it is for that
            -- mob's kind now, or the kind it was for, everywhere
            if type(trigger.zone) == 'number' then
                trigger.mob = Area(trigger.zone).kindOf[trigger.mob:lower()] or trigger.mob
            end
            trigger.zone, trigger.mobs = nil, nil
            triggers[#triggers + 1] = trigger
        end
    end
    options.triggers = triggers
end

-- The sounds of every event in turn, a second apart, whether switched on or not
local function TestAll()
    for index, event in ipairs(events) do
        local file = app.options.events[event.key].sound
        ashita.tasks.once((index - 1) * 1.0, function()
            Say(('%s: %s'):format(event.label, file))
            PlayFile(file)
        end)
    end
end

app = shell.New({
    defaults = defaults,
    configTitle = 'Twister Settings',
    command = '/twister',
    help = '/twister opens or closes the settings; /twister test plays every event\'s sound in turn.',
    drawSettings = DrawSettings,
    tabs = { { label = 'Triggers', draw = DrawTriggers } },
    onSettings = function(options)
        Complete(options)
        -- another character's numbers are not this one's
        Forget()
    end,
    commands = { test = TestAll },
})

ashita.events.register('d3d_present', 'twister_present', function()
    app:BeginFrame()
    Look()
    -- what is known of the mobs is not kept: let go of once the settings are closed, and the frame after
    -- it was read to find out an area's mobs
    if mobData ~= nil and not app.showConfig[1] then
        ForgetMobData()
    end
    PlayWaiting()
end)
