addon.name    = 'chime'
addon.author  = 'Win'
addon.version = '1.0'
addon.desc    = 'Plays a sound when something happens: a tell, an invite, a skillchain, low HP and the like.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- A sound for each of a few things worth hearing about. Each event has its own switch and its own
-- sound, any wav in the addon's sounds folder. It needs only winxi.
--
--   /chime           opens or closes the settings
--   /chime test      plays every event's sound in turn, to hear them
--
-- What sets a sound off is read from packets (chat, invitations, actions) and from the party's
-- numbers as the game keeps them (TP, HP and MP), looked at a few times a second.
--
-- Ashita plays one sound at a time, at the volume of the file: a sound cuts short the one before it.

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
    { key = 'skillchain', group = 'Combat', label = 'Skillchain', file = 'skillchain.wav',
      tooltip = 'A skillchain is made by someone in your party or alliance, or on whatever you have targeted.' },
    { key = 'tp', group = 'Combat', label = 'TP Ready', file = 'tp.wav',
      tooltip = 'Your TP reaches 1000.' },
    { key = 'lowhp', group = 'Combat', label = 'Low HP', file = 'lowhp.wav', threshold = 'lowHpPercent',
      tooltip = 'Your HP falls to the percentage below, or under it. It sounds once, and not again until your HP has been back over that.' },
    { key = 'lowmp', group = 'Combat', label = 'Low MP', file = 'lowmp.wav', threshold = 'lowMpPercent',
      tooltip = 'Your MP falls to the percentage below, or under it. It sounds once, and not again until your MP has been back over that.\nNothing sounds on a job with no MP.' },
    { key = 'ko', group = 'Combat', label = 'Party Member KO', file = 'ko.wav',
      tooltip = 'Someone else in your party is knocked out, in the area you are in.' },
}

local defaults = T{
    enabled = T{ true },
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

local function PlayFile(file)
    local path = soundFolder .. file
    if not ashita.fs.exists(path) then
        return false
    end
    ashita.misc.play_sound(path)
    return true
end

-- An event has happened: its sound, if it is switched on
local function Sound(key)
    local options = app.options
    local chosen = options.events[key]
    if not options.enabled[1] or not chosen.enabled[1] then
        return
    end

    local now = os.clock()
    if lastPlayed[key] ~= nil and now - lastPlayed[key] < minimumGap then
        return
    end
    lastPlayed[key] = now
    PlayFile(chosen.sound)
end

---------------------------------------------------------------------------------------------------
-- Chat, invitations and skillchains: from packets
---------------------------------------------------------------------------------------------------

local packetChat = 0x017
local packetAction = 0x028
local packetInvite = 0x0DC

local chatTell = 3
-- party and linkshell chat, with and without the speaker shown
local chatAmongFriends = { [4] = true, [5] = true, [15] = true, [16] = true, [27] = true, [28] = true }

local function OwnName()
    local name = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0)
    if type(name) ~= 'string' or name == '' then
        return nil
    end
    return name
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
        own = own:lower()
        if Text(data, 0x08 + 1, 0x08 + 15):lower() == own then
            return
        end
        -- the name as a word of its own, not as part of another
        if Text(data, 0x17 + 1, #data):lower():find('%f[%a]' .. own .. '%f[%A]') then
            Sound('mention')
        end
    end
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

-- The messages that say a skillchain was made, as an action's additional effect
local function IsSkillchain(message)
    return (message >= 288 and message <= 302) or (message >= 385 and message <= 398) or (message >= 767 and message <= 770)
end

-- Whether an id is someone in the party or alliance, the player among them
local function IsInAlliance(serverId)
    local party = AshitaCore:GetMemoryManager():GetParty()
    for place = 0, 17 do
        if party:GetMemberIsActive(place) == 1 and party:GetMemberServerId(place) == serverId then
            return true
        end
    end
    return false
end

local function TargetServerId()
    local target = AshitaCore:GetMemoryManager():GetTarget()
    local entity = GetEntity(target:GetTargetIndex(0))
    return entity ~= nil and entity.ServerId or nil
end

-- The action packet: who acted, then each target, and for each target each result, some with an
-- additional effect, which is where a skillchain is told of. Only as much is read as finds one.
local function OnAction(data)
    local actor = Bits(data, 40, 32)
    local targets = Bits(data, 72, 10)
    local allied = nil -- found out once, and only if there is a skillchain to ask about

    local offset = 150
    for _ = 1, targets do
        local targetId = Bits(data, offset, 32)
        local results = Bits(data, offset + 32, 4)
        offset = offset + 36
        for _ = 1, results do
            local hasAdded = Bits(data, offset + 85, 1) == 1
            offset = offset + 86
            if hasAdded then
                if IsSkillchain(Bits(data, offset + 27, 10)) then
                    if allied == nil then
                        allied = IsInAlliance(actor)
                    end
                    if allied or targetId == TargetServerId() then
                        Sound('skillchain')
                        return
                    end
                end
                offset = offset + 37
            end
            local hasSpikes = Bits(data, offset, 1) == 1
            offset = offset + 1
            if hasSpikes then
                offset = offset + 34
            end
        end
        if offset >= #data * 8 then
            return
        end
    end
end

ashita.events.register('packet_in', 'chime_packet_in', function(e)
    if app == nil or not app.options.enabled[1] then
        return
    end
    if e.id == packetChat then
        OnChat(e.data)
    elseif e.id == packetInvite then
        Sound('invite')
    elseif e.id == packetAction and app.options.events.skillchain.enabled[1] then
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

local function Forget()
    lastTp, lowHp, lowMp = nil, nil, nil
    for place = 1, 5 do
        lastHp[place] = nil
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
    local zone = party:GetMemberZone(0)
    for place = 1, 5 do
        local memberHp = nil
        if party:GetMemberIsActive(place) == 1 and party:GetMemberZone(place) == zone then
            memberHp = party:GetMemberHPPercent(place)
            if memberHp == 0 and lastHp[place] ~= nil and lastHp[place] > 0 then
                Sound('ko')
            end
        end
        lastHp[place] = memberHp
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

    if event.threshold ~= nil then
        widgets.Label(event.label .. ' Threshold (%)')
        imgui.SetNextItemWidth(170)
        imgui.SliderInt(id.threshold, options[event.threshold], 5, 90, '%d%%')
    end
end

local function DrawSettings(options)
    widgets.Label('Enabled')
    imgui.Checkbox('##chime.enabled', options.enabled)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Off, nothing sounds, whatever is switched on below.')
    end

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
    if type(options.enabled) ~= 'table' then options.enabled = T{ true } end
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
    if app.options.enabled[1] then
        Look()
    end
end)
