addon.name    = 'chime'
addon.author  = 'win (and claude)'
addon.version = '1.0'
addon.desc    = 'Plays a sound when something happens: a tell, an invite, a trade, being examined, low HP and the like.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- A sound for each of a few things worth hearing about. Each event has its own switch and its own
-- sound, any wav in the addon's sounds folder. It needs only winxi.
--
--   /chime           opens or closes the settings
--   /chime test      plays every event's sound in turn, to hear them
--
-- What sets a sound off is read from packets (chat, invitations, trades, being examined, messages) and from the party's
-- numbers as the game keeps them (TP, HP and MP), looked at a few times a second.
--
-- Ashita plays one sound at a time, at the volume of the file: a sound cuts short the one before it.
-- So that one event's sound is not lost to another's, a sound asked for while one is playing waits
-- for it to finish.

require('common')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local shell = require('winxi.shell')
local game = require('winxi.game')

-- The events, in the order the settings list them. file is the sound an event starts with.
local events = {
    { key = 'tell', group = 'Chat', label = 'Tell Received', file = 'tell.wav',
      tooltip = 'Someone sends you a tell.' },
    { key = 'mention', group = 'Chat', label = 'Name Mentioned', file = 'mention.wav',
      tooltip = 'Someone else says your character\'s name in party or linkshell chat.' },
    { key = 'invite', group = 'Chat', label = 'Party Invite', file = 'invite.wav',
      tooltip = 'You are invited to a party or an alliance.' },
    { key = 'trade', group = 'Chat', label = 'Trade Request', file = 'voice-trade.wav',
      tooltip = 'Someone asks to trade with you.' },
    { key = 'examine', group = 'Chat', label = 'Examined', file = 'voice-examine.wav',
      tooltip = 'Someone examines you.' },
    { key = 'tp', group = 'Combat', label = 'TP Ready', file = 'tp.wav',
      tooltip = 'Your TP reaches 1000.' },
    { key = 'lowhp', group = 'Combat', label = 'Low HP', file = 'lowhp.wav', threshold = 'lowHpPercent',
      tooltip = 'Your HP falls to the percentage below, or under it. It sounds once, and not again until your HP has been back over that.' },
    { key = 'lowmp', group = 'Combat', label = 'Low MP', file = 'lowmp.wav', threshold = 'lowMpPercent',
      tooltip = 'Your MP falls to the percentage below, or under it. It sounds once, and not again until your MP has been back over that.\nNothing sounds on a job with no MP.' },
    { key = 'ko', group = 'Combat', label = 'Party Member KO', file = 'ko.wav',
      tooltip = 'Someone else in your party is knocked out, in the area you are in.' },
    { key = 'skillup', group = 'Combat', label = 'Skill Up', file = 'skillup.wav',
      tooltip = 'One of your skills rises, or reaches a new level: a combat or magic skill, or a craft.' },
}

local defaults = T{
    events = T{ },
    lowHpPercent = T{ 25 },
    lowMpPercent = T{ 20 },
}
for _, event in ipairs(events) do
    defaults.events[event.key] = T{ enabled = T{ true }, sound = event.file }
end

local function Say(text)
    print(('\30\81[chime]\30\01 %s'):format(text))
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

-- An event has happened: its sound, if it is switched on
local function Sound(key)
    local chosen = app.options.events[key]
    if not chosen.enabled[1] then
        return
    end

    local now = os.clock()
    if lastPlayed[key] ~= nil and now - lastPlayed[key] < minimumGap then
        return
    end
    lastPlayed[key] = now
    if now >= playingUntil and #waiting == 0 then
        PlayFile(chosen.sound)
    else
        waiting[#waiting + 1] = { file = chosen.sound, asked = now }
    end
end

---------------------------------------------------------------------------------------------------
-- Chat, invitations and messages: from packets
---------------------------------------------------------------------------------------------------

local packetSystemMessage = 0x009
local packetChat = 0x017
local packetTrade = 0x021 -- someone asks to trade
local packetMessage = 0x029
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

ashita.events.register('packet_in', 'chime_packet_in', function(e)
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
        enabled = ('##chime.%s.enabled'):format(event.key),
        sound = ('##chime.%s.sound'):format(event.key),
        test = ('Test##chime.%s.test'):format(event.key),
        threshold = ('##chime.%s.threshold'):format(event.key),
        thresholdLabel = event.label .. ' Threshold (%)',
    }
end

local function DrawEvent(options, event)
    local chosen = options.events[event.key]
    local id = ids[event.key]

    widgets.Label(event.label)
    imgui.Checkbox(id.enabled, chosen.enabled)
    if imgui.IsItemHovered() then
        imgui.SetTooltip(event.tooltip)
    end

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
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The sound played: any wav file in the addon\'s sounds folder. Put your own there to use them.')
    end

    imgui.SameLine()
    if imgui.Button(id.test) and not PlayFile(chosen.sound) then
        Say(('There is no %s in the sounds folder.'):format(chosen.sound))
    end

    -- the threshold only while the event is switched on: off, there is nothing for it to set
    if event.threshold ~= nil and chosen.enabled[1] then
        widgets.Label(id.thresholdLabel)
        imgui.SetNextItemWidth(170)
        imgui.SliderInt(id.threshold, options[event.threshold], 5, 90, '%d%%')
    end
end

local function DrawSettings(options)
    local group = nil
    for _, event in ipairs(events) do
        if event.group ~= group then
            group = event.group
            widgets.Header(group)
        end
        DrawEvent(options, event)
    end
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
    end
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
    configTitle = 'Chime Settings',
    command = '/chime',
    help = '/chime opens or closes the settings; /chime test plays every event\'s sound in turn.',
    drawSettings = DrawSettings,
    onSettings = function(options)
        Complete(options)
        -- another character's numbers are not this one's
        Forget()
    end,
    commands = { test = TestAll },
})

ashita.events.register('d3d_present', 'chime_present', function()
    app:BeginFrame()
    Look()
    PlayWaiting()
end)
