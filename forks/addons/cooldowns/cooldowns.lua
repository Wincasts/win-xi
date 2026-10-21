--[[
* Addons - Copyright (c) 2021 Ashita Development Team
* Contact: https://www.ashitaxi.com/
* Contact: https://discord.gg/Ashita
*
* This file is part of Ashita.
*
* Ashita is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Ashita is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with Ashita.  If not, see <https://www.gnu.org/licenses/>.
--]]

addon.name      = 'cooldowns';
addon.author    = 'atom0s, Thorny, RZN, lin, win';
addon.version   = '2.1';
addon.desc      = 'Displays ability and spell recast times.';
addon.link      = 'https://ashitaxi.com/';

require('common')
local Settings = require('settings')
local Game = require('winxi.game')
local Imgui = require('imgui')

-- Window styling belongs to winxi. Skill-name and countdown urgency colors are configured here.
local Theme = require('winxi.theme')
local Window = require('winxi.window')
local Style = require('winxi.style')
local PetRecasts = require('winxi.automaton.recasts')
local ElementColors = require('winxi.automaton.colors')
local ManeuverColors = {}
for i, element in ipairs({ 'fire', 'ice', 'wind', 'earth', 'thunder', 'water', 'light', 'dark' }) do
    ManeuverColors[element] = ElementColors[i]
end

---@class RecastSettings
---@field windowName string
---@field windowSize Vec2
---@field windowPos Vec2
---@field abilityNameColor table RGBA color for player ability names
---@field spellNameColor table RGBA color for player spell names

local DefaultColors = {
    abilityNameColor = { 1, 1, 1, 1 },
    spellNameColor = { 1, 1, 1, 1 },
    warningColor = { 1.00, 1.00, 0.00, 1.0 },
    criticalColor = { 0.95, 0.20, 0.20, 1.0 },
}

---@type RecastSettings
-- Ashita's settings loader calls :copy(true) on defaults for a fresh settings directory.
local Defaults = T{
    windowName = 'Cooldowns',
    legacySettingsChecked = false,
    windowSize = { -1, -1 },
    windowPos = { 100, 100 },
    abilityNameColor = { unpack(DefaultColors.abilityNameColor) },
    spellNameColor = { unpack(DefaultColors.spellNameColor) },
    showPetCooldowns = true,
    sortByTime = false,
    sortDescending = false,
    warningSeconds = 20,
    criticalSeconds = 5,
    warningColor = { unpack(DefaultColors.warningColor) },
    criticalColor = { unpack(DefaultColors.criticalColor) },
    petAutomaton = { attachments = {} },
}

---@type RecastSettings
local Config = Settings.load(Defaults)

local function Threshold(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return fallback end
    return math.max(0, math.min(2147483647, math.floor(number)))
end

local function MigrateSettings()
    -- Import the old character's settings once, without changing or deleting the source files.
    if not Config.legacySettingsChecked then
        if type(Settings.settings_path) == 'function' then
            local path = Settings.settings_path()
            for _, oldName in ipairs({ 'recast', 'imrecast' }) do
                local oldPath = path:gsub('\\cooldowns\\', '\\' .. oldName .. '\\')
                local loader = oldPath ~= path and loadfile(oldPath .. 'settings.lua')
                if loader then
                    local ok, old = pcall(loader)
                    if ok and type(old) == 'table' then
                        for _, key in ipairs({ 'windowSize', 'windowPos', 'abilityNameColor', 'spellNameColor',
                            'showPetCooldowns', 'petAutomaton' }) do
                            if old[key] ~= nil then Config[key] = old[key] end
                        end
                        break
                    end
                end
            end
        end
        Config.legacySettingsChecked = true
    end
    Config.windowName = 'Cooldowns'
    if Config.showPetCooldowns == nil then Config.showPetCooldowns = true end
    if type(Config.sortByTime) ~= 'boolean' then Config.sortByTime = false end
    if type(Config.sortDescending) ~= 'boolean' then Config.sortDescending = false end
    Config.warningSeconds = Threshold(Config.warningSeconds, 20)
    Config.criticalSeconds = math.min(Threshold(Config.criticalSeconds, 5), Config.warningSeconds)
    if type(Config.petAutomaton) ~= 'table' then Config.petAutomaton = { attachments = {} } end
    for _, key in ipairs({ 'abilityNameColor', 'spellNameColor', 'warningColor', 'criticalColor' }) do
        if type(Config[key]) ~= 'table' then Config[key] = {} end
        for channel = 1, 4 do
            local value = tonumber(Config[key][channel])
            if not value or value ~= value or value == math.huge or value == -math.huge then
                value = DefaultColors[key][channel]
            end
            Config[key][channel] = math.max(0, math.min(1, value))
        end
    end
    -- Old local style overrides no longer apply; winxi owns the shared look.
    for _, key in ipairs({ 'useSharedTheme', 'theme', 'bgColor', 'borderColor', 'textColor', 'padding' }) do
        Config[key] = nil
    end
end

MigrateSettings()
Settings.save()

---@type integer
local SchJp = 0

-- The /cooldowns settings window: whether it is open
local ShowConfig = { false }
local ShowSamples = { false } -- preview only; never saved
local ShowPetCooldowns = { Config.showPetCooldowns }
local SortByTime = { Config.sortByTime }
local WarningSeconds = { Config.warningSeconds }
local CriticalSeconds = { Config.criticalSeconds }

local TwoHours = {
    [ 1] = 'Mighty Strikes',
    [ 2] = 'Hundred Fists',
    [ 3] = 'Benediction',
    [ 4] = 'Manafont',
    [ 5] = 'Chainspell',
    [ 6] = 'Perfect Dodge',
    [ 7] = 'Invincible',
    [ 8] = 'Blood Weapon',
    [ 9] = 'Familiar',
    [10] = 'Soul Voice',
    [11] = 'Eagle Eye Shot',
    [12] = 'Meikyo Shisui',
    [13] = 'Mijin Gakure',
    [14] = 'Spirit Surge',
    [15] = 'Astral Flow',
    [16] = 'Azure Lore',
    [17] = 'Wild Card',
    [18] = 'Overdrive',
    [19] = 'Trance',
    [20] = 'Tabula Rasa',
    [21] = 'Bolster',
    [22] = 'Elemental Sforzo',
}

-- Recast timers that several abilities share, and what to call them. The game's resources would give the
-- first ability on the timer, whichever was used: every puppetmaster maneuver showed as Fire Maneuver.
local SharedTimers = {
    [210] = 'Maneuver',
}

local PlayerTimers, PlayerCollectedAt, NextPlayerScan = {}, 0, 0
local LastJob, LastSubJob, LastOwner
local AbilityNames, SpellNames, FallbackNames = {}, {}, nil
local ScanInterval = 0.1

local function ResetCollection()
    PlayerTimers, PlayerCollectedAt, NextPlayerScan = {}, 0, 0
    AbilityNames, SpellNames, FallbackNames = {}, {}, nil
    LastJob, LastSubJob, LastOwner = nil, nil, nil
end

---@param s RecastSettings?
local function UpdateSettings(s)
    if (s ~= nil) then
        Config = s
        MigrateSettings()
        ShowPetCooldowns[1] = Config.showPetCooldowns
        SortByTime[1] = Config.sortByTime
        WarningSeconds[1], CriticalSeconds[1] = Config.warningSeconds, Config.criticalSeconds
        PetRecasts.Clear()
        ResetCollection()
    end

    Settings.save()
end

--[[
* Returns a formatted recast timestamp.
*
* @param {number} timer - The recast timestamp to format.
* @return {string} The formatted timestamp.
--]]
local function format_timestamp(timer)
    local t = math.floor(timer / 60)
    local h = math.floor(t / (60 * 60))
    local m = math.floor(t / 60 - h * 60)
    local s = math.floor(t - (m + h * 60) * 60)

    if h > 0 then
        return ('%ih %im %is'):fmt(h, m, s)
    elseif m > 0 then
        return ('%im %is'):fmt(m, s)
    else
        return ('%is'):fmt(s)
    end
end

--[[
* Returns an abilities name as a fallback if the ability is not known to the player.
*
* @param {number} id - The recast timer id of the ability to obtain.
* @return {string} The ability name if found, nil otherwise.
* @note
*
* This is not guaranteed to get the desired ability as the game shares recast timer ids based on the players
* job combo. Because of this, another ability may be returned instead of what was expected if it was found first.
--]]
local function get_ability_fallback(id)
    if FallbackNames == nil then
        FallbackNames = {}
        local resMgr = AshitaCore:GetResourceManager()
        for x = 0, 2048 do
            local ability = resMgr:GetAbilityById(x)
            if ability and FallbackNames[ability.RecastTimerId] == nil then
                FallbackNames[ability.RecastTimerId] = ability.Name[1]
            end
        end
    end
    return FallbackNames[id]
end

local function AbilityName(resources, id)
    local name = AbilityNames[id]
    if name == nil then
        local ability = resources:GetAbilityByTimerId(id)
        name = ability and ability.Name[1] or get_ability_fallback(id)
        if not name or name == '' then name = ('(Unknown: %d)'):fmt(id) end
        AbilityNames[id] = name
    end
    return name
end

local function SpellName(resources, id)
    local name = SpellNames[id]
    if name == nil then
        local spell = resources:GetSpellById(id)
        name = spell and spell.Name[1]
        if not name or name == '' then name = ('Unknown Spell: %d'):fmt(id) end
        SpellNames[id] = name
    end
    return name
end

local function TimerText(timer)
    local second = math.floor(timer.timer / 60)
    if timer.textSecond ~= second then
        timer.textSecond, timer.text = second, format_timestamp(timer.timer)
    end
    return timer.text
end

local timerRight = 0 -- shared content right edge for both groups this frame
local ColumnGap = 8

local function DrawTimer(timer)
    -- Only the countdown changes urgency color; the skill name keeps its semantic color.
    local color = nil
    if timer.timer <= Config.criticalSeconds * 60 then
        color = Config.criticalColor
    elseif timer.timer < Config.warningSeconds * 60 then
        color = Config.warningColor
    end

    local nameColor = ManeuverColors[timer.element]
        or (timer.kind == 'spell' and Config.spellNameColor)
        or (timer.kind == 'ability' and Config.abilityNameColor)
    if nameColor then Imgui.TextColored(nameColor, timer.name) else Imgui.Text(timer.name) end
    Imgui.SameLine(0, 0)
    local text = TimerText(timer)
    Imgui.SetCursorPosX(timerRight - Imgui.CalcTextSize(text))
    if color then
        Imgui.PushStyleColor(ImGuiCol_Text, color)
        Imgui.Text(text)
        Imgui.PopStyleColor()
    else
        Imgui.Text(text)
    end
end

local function CompareTimers(a, b)
    -- Equal durations retain their normal collection order in either direction.
    if a.timer == b.timer then return a.sortOrder < b.sortOrder end
    if Config.sortDescending then return a.timer > b.timer end
    return a.timer < b.timer
end

local function SortTimers(timers)
    if not Config.sortByTime or #timers < 2 then return end
    for i, timer in ipairs(timers) do timer.sortOrder = i end
    table.sort(timers, CompareTimers)
end

local function DrawRecast(timers)
    for _, timer in ipairs(timers) do
        DrawTimer(timer)
    end
end

local RecastOpen = { true }
local ItemSpacing = { 8, 4 }
local FramePadding = { 0, 0 }

-- What the recast window shows this frame, for DrawRecastContent
local CurrentTimers = nil
local CurrentPetTimers = {}
local RecastStyle = { title = 'Cooldowns' }

local function DrawRecastContent()
    Imgui.PushStyleVar(ImGuiStyleVar_FramePadding, FramePadding)
    -- Measure in the active winxi font. Reserve enough room for the widest name and countdown,
    -- including hours-long recasts, without letting either column overlap on auto-fit frames.
    local nameWidth, timeWidth = 0, 0
    for _, group in ipairs({ CurrentTimers, CurrentPetTimers }) do
        for _, timer in ipairs(group) do
            nameWidth = math.max(nameWidth, (Imgui.CalcTextSize(timer.name)))
            timeWidth = math.max(timeWidth, (Imgui.CalcTextSize(TimerText(timer))))
        end
    end
    timerRight = Imgui.GetCursorPosX() + math.max(Imgui.GetContentRegionAvail(), nameWidth + ColumnGap + timeWidth)
    DrawRecast(CurrentTimers)
    if #CurrentPetTimers > 0 then
        if #CurrentTimers > 0 then
            local padding = { 0, Style.Padding() }
            Imgui.Dummy(padding)
            Imgui.Separator()
            Imgui.Dummy(padding)
        end
        DrawRecast(CurrentPetTimers)
    end
    Imgui.PopStyleVar()
end

-- The recast window, drawn with winxi's theme
local function DrawRecastWindow(timers, petTimers)
    CurrentTimers, CurrentPetTimers = timers, petTimers

    Imgui.SetNextWindowSize(Config.windowSize, ImGuiCond_Always)
    Imgui.SetNextWindowPos(Config.windowPos, ImGuiCond_FirstUseEver)

    Imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, ItemSpacing)
    RecastOpen[1] = true
    Window.Full(Config.windowName, RecastOpen, ImGuiWindowFlags_NoDecoration, DrawRecastContent, RecastStyle)
    Imgui.PopStyleVar()
end

local ConfigStyle = { kind = Window.Settings }
local ConfigFlags = ImGuiWindowFlags_NoSavedSettings -- a settings window: winxi.window sizes it

local function DrawConfigContent()
    Imgui.TextDisabled('Window styling is managed by winxi.')
    if Imgui.ColorEdit4('Ability name color', Config.abilityNameColor) then Settings.save() end
    if Imgui.ColorEdit4('Spell name color', Config.spellNameColor) then Settings.save() end
    Imgui.Separator()
    local thresholdsChanged = Imgui.InputInt('Warning below (seconds)', WarningSeconds)
    if Imgui.ColorEdit4('Warning countdown color', Config.warningColor) then Settings.save() end
    if Imgui.InputInt('Critical at or below (seconds)', CriticalSeconds) then thresholdsChanged = true end
    if Imgui.ColorEdit4('Critical countdown color', Config.criticalColor) then Settings.save() end
    if thresholdsChanged then
        Config.warningSeconds = Threshold(WarningSeconds[1], 20)
        Config.criticalSeconds = math.min(Threshold(CriticalSeconds[1], 5), Config.warningSeconds)
        WarningSeconds[1], CriticalSeconds[1] = Config.warningSeconds, Config.criticalSeconds
        Settings.save()
    end
    Imgui.TextDisabled('Countdowns only. Critical cannot exceed warning; values must be non-negative.')
    Imgui.Separator()
    if Imgui.Checkbox('Show pet cooldowns', ShowPetCooldowns) then
        Config.showPetCooldowns = ShowPetCooldowns[1]
        Settings.save()
    end
    Imgui.TextDisabled('Observed automaton cooldowns, below player recasts.')
    Imgui.Checkbox('Show sample data', ShowSamples)
    Imgui.Separator()
    if Imgui.Checkbox('Sort by time remaining', SortByTime) then
        Config.sortByTime = SortByTime[1]
        Settings.save()
    end
    if Config.sortByTime then
        if Imgui.RadioButton('Ascending (shortest first)', not Config.sortDescending) then
            Config.sortDescending = false
            Settings.save()
        end
        if Imgui.RadioButton('Descending (longest first)', Config.sortDescending) then
            Config.sortDescending = true
            Settings.save()
        end
        Imgui.TextDisabled('Player and pet cooldowns are sorted separately.')
    end
end

-- The settings window opened by /cooldowns
local function DrawConfig()
    if not ShowConfig[1] then
        return
    end

    Window.Full('Cooldowns Settings', ShowConfig, ConfigFlags, DrawConfigContent, ConfigStyle)
end

local function CollectPlayerTimers(mmPlayer, mmRecast, resMgr, playerJob)
    local timers = {}
    -- Obtain the players ability recasts..
    for x = 0, 31 do
        local id = mmRecast:GetAbilityTimerId(x)
        local timer = mmRecast:GetAbilityTimer(x)

        -- Ensure the ability is valid and has a current recast timer..
        if ((id ~= 0 or x == 0) and timer > 0) then
            -- Obtain the resource entry for the ability..
            local name

            -- Determine the name to be displayed..
            if (x == 0) then
                name = TwoHours[playerJob] or AbilityName(resMgr, id)
            elseif (id == 231) then
                -- Determine the players SCH level..
                local lvl = (playerJob == 20) and mmPlayer:GetMainJobLevel() or mmPlayer:GetSubJobLevel()

                -- Adjust the timer offset by the players level..
                local val = 48
                if (lvl < 30) then
                    val = 240
                elseif (lvl < 50) then
                    val = 120
                elseif (lvl < 70)then
                    val = 80
                elseif (lvl < 90) then
                    val = 60
                end

                -- Calculate the stratagems amount..
                local stratagems = 0
                if (lvl == 99 and SchJp >= 550) then
                    val = 33
                    stratagems = math.floor((165 - (timer / 60)) / val)
                else
                    stratagems = math.floor((240 - (timer / 60)) / val)
                end

                -- Update the name and timer..
                name = ('Stratagems[%d]'):fmt(stratagems)
                timer = math.fmod(timer, val * 60)
            elseif (SharedTimers[id] ~= nil) then
                name = SharedTimers[id]
            else
                name = AbilityName(resMgr, id)
            end

            -- Append the timer to the table..
            local newTimer = {
                name = name,
                timer = timer,
            }
            newTimer.kind, newTimer.collectedTimer = 'ability', timer
            timers[#timers + 1] = newTimer
        end
    end

    -- Obtain the players spell recasts..
    for x = 0, 1024 do
        local id = x
        local timer = mmRecast:GetSpellTimer(x)

        -- Ensure the spell has a current recast timer..
        if (timer > 0) then
            local name = SpellName(resMgr, id)

            -- Append the timer to the table..
            local newTimer = {
                name = name,
                timer = timer,
            }
            newTimer.kind, newTimer.collectedTimer = 'spell', timer
            timers[#timers + 1] = newTimer
        end
    end

    return timers
end

local function OnPresent()
    Theme.Configure(true)
    DrawConfig()
    local memory = AshitaCore:GetMemoryManager()
    local mmPlayer = memory:GetPlayer()
    local playerJob = mmPlayer:GetMainJob()
    if playerJob == nil or playerJob == 0 or Game.IsChatExpanded() or Game.IsMapOpen()
        or Game.IsEventHappening() or Game.IsInterfaceHidden() then
        -- Refresh immediately when the game UI returns; never display an old snapshot.
        NextPlayerScan = 0
        return
    end
    local subjob, owner = mmPlayer:GetSubJob(), memory:GetParty():GetMemberServerId(0)
    if playerJob ~= LastJob or subjob ~= LastSubJob or owner ~= LastOwner then
        ResetCollection()
        LastJob, LastSubJob, LastOwner = playerJob, subjob, owner
    end
    local now = os.clock()
    if now >= NextPlayerScan then
        PlayerTimers = CollectPlayerTimers(mmPlayer, memory:GetRecast(), AshitaCore:GetResourceManager(), playerJob)
        PlayerCollectedAt, NextPlayerScan = now, now + ScanInterval
    end
    local timers = {}
    for _, timer in ipairs(PlayerTimers) do
        timer.timer = math.max(0, timer.collectedTimer - (now - PlayerCollectedAt) * 60)
        if timer.timer > 0 then timers[#timers + 1] = timer end
    end
    -- Packet observation continues while the pet section is disabled, but row calculation does not.
    local petTimers = Config.showPetCooldowns and PetRecasts.Timers(Config.petAutomaton) or {}
    if ShowConfig[1] and ShowSamples[1] then
        timers = { { name = TwoHours[playerJob] or 'Two-hour ability', timer = 7157 * 60, kind = 'ability' },
            { name = 'Maneuver (sample)', timer = 1800, kind = 'ability' },
            { name = 'Cure IV (sample)', timer = 720, kind = 'spell' } }
        petTimers = PetRecasts.Samples()
    elseif #timers == 0 and #petTimers == 0 and ShowConfig[1] then
        timers[#timers + 1] = { name = 'Sample', timer = 3600 }
    end
    if not Config.showPetCooldowns then petTimers = {} end

    SortTimers(timers)
    SortTimers(petTimers)
    if #timers > 0 or #petTimers > 0 then
        DrawRecastWindow(timers, petTimers)
    end
end

local function OnLoad()
end

local function OnUnload()
    UpdateSettings()
end

-- /cooldowns opens or closes settings; no differently named addon or command alias.
local function OnCommand(e)
    local args = e.command:args()
    if (#args == 0 or args[1]:lower() ~= '/cooldowns') then
        return
    end

    e.blocked = true
    ShowConfig[1] = not ShowConfig[1]
end

---@param e PacketInEventArgs
local function OnPacket(e)
    if e.id == 0x00A then ResetCollection() end
    if PetRecasts.Packet(e, Config.petAutomaton) then Settings.save() end
    -- Packet: Job Points
    local data = e.data_modified or e.data
    if (e.id == 0x0063 and type(data) == 'string' and #data >= 0x8A) then
        if (struct.unpack('B', data, 0x04 + 0x01) == 5) then
            SchJp = struct.unpack('H', data, 0x88 + 0x01)
        end
    end
end

Settings.register('settings', 'settings_update', UpdateSettings)
ashita.events.register('load', 'on_load', OnLoad)
ashita.events.register('unload', 'on_unload', OnUnload)
ashita.events.register('packet_in', 'on_packet_in', OnPacket)
ashita.events.register('command', 'on_command', OnCommand)
ashita.events.register('d3d_present', 'on_d3d_present', OnPresent)
