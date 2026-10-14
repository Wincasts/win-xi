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

addon.name      = 'recast';
addon.author    = 'atom0s, Thorny, RZN, lin, win (and claude)';
addon.version   = '2.0';
addon.desc      = 'Displays ability and spell recast times.';
addon.link      = 'https://ashitaxi.com/';

require('common')
local Settings = require('settings')
local Game = require('winxi.game')
local Imgui = require('imgui')

-- The window's look (colours, padding, drop shadow) is winxi's theme: the one shared with other addons,
-- or this addon's own, as chosen in the appearance window
local Theme = require('winxi.theme')
local Window = require('winxi.window')
local Widgets = require('winxi.widgets')

---@class RecastSettings
---@field windowName string
---@field windowSize Vec2
---@field windowPos Vec2
---@field useSharedTheme boolean whether the window follows the theme shared with other winxi addons
---@field theme table this addon's own colours, padding and drop shadow, used when it does not

---@type RecastSettings
local Defaults = {
    windowName = 'Recast',
    windowSize = { -1, -1 },
    windowPos = { 100, 100 },
    useSharedTheme = true,
    theme = { },
}

---@type RecastSettings
local Config = Settings.load(Defaults)

-- The colours and padding were this addon's own settings before the theme moved to winxi. What was saved
-- then is kept as this addon's own theme, for use with "Use Shared Theme" off, and the old settings are
-- dropped.
local function MigrateTheme()
    if Config.useSharedTheme == nil then
        Config.useSharedTheme = true
    end
    if type(Config.theme) ~= 'table' then
        Config.theme = { }
    end

    local own = Config.theme
    for old, new in pairs({ bgColor = 'BackgroundColor', borderColor = 'BorderColor', textColor = 'TextColor' }) do
        local color = Config[old]
        if type(color) == 'table' then
            if own[new] == nil and color[1] and color[2] and color[3] then
                own[new] = { color[1], color[2], color[3], color[4] or 1 }
            end
            Config[old] = nil
        end
    end
    if Config.padding ~= nil then
        if own.Padding == nil then
            own.Padding = tonumber(Config.padding)
        end
        Config.padding = nil
    end
end

MigrateTheme()

-- A timer's text in its last 20 seconds, and in its last 5
local Yellow = { 1.00, 1.00, 0.00, 1.0 }
local Red = { 0.95, 0.20, 0.20, 1.0 }

---@type integer
local SchJp = 0

-- The /imrecast appearance window: whether it is open
local ShowConfig = { false }

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

---@param s RecastSettings?
local function UpdateSettings(s)
    if (s ~= nil) then
        Config = s
        MigrateTheme()
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
    local t = timer / 60
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
* @return {object} The ability if found, nil otherwise.
* @note
*
* This is not guaranteed to get the desired ability as the game shares recast timer ids based on the players
* job combo. Because of this, another ability may be returned instead of what was expected if it was found first.
--]]
local function get_ability_fallback(id)
    local resMgr = AshitaCore:GetResourceManager()
    for x = 0, 2048 do
        local ability = resMgr:GetAbilityById(x)
        if (ability ~= nil and ability.RecastTimerId == id) then
            return ability
        end
    end
    return nil
end

local function DrawTimer(timer)
    -- The theme's text colour, turning yellow in the last 20 seconds and red in the last 5
    local color = nil
    if timer.timer <= 300 then
        color = Red
    elseif timer.timer < 1200 then
        color = Yellow
    end

    local text = string.format('%s - %s', timer.name, format_timestamp(timer.timer))
    if color then
        Imgui.PushStyleColor(ImGuiCol_Text, color)
        Imgui.Text(text)
        Imgui.PopStyleColor()
    else
        Imgui.Text(text)
    end
end

local function DrawRecast(timers)
    for _, timer in pairs(timers) do
        DrawTimer(timer)
    end
end

local RecastOpen = { true }
local ItemSpacing = { 8, 4 }
local FramePadding = { 0, 0 }

-- What the recast window shows this frame, for DrawRecastContent
local CurrentTimers = nil

local function DrawRecastContent()
    Imgui.PushStyleVar(ImGuiStyleVar_FramePadding, FramePadding)
    DrawRecast(CurrentTimers)
    Imgui.PopStyleVar()
end

-- The recast window, drawn with winxi's theme
local function DrawRecastWindow(timers)
    CurrentTimers = timers

    Imgui.SetNextWindowSize(Config.windowSize, ImGuiCond_Always)
    Imgui.SetNextWindowPos(Config.windowPos, ImGuiCond_FirstUseEver)

    Imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, ItemSpacing)
    RecastOpen[1] = true
    Window.Plain(Config.windowName, RecastOpen, ImGuiWindowFlags_NoDecoration, DrawRecastContent)
    Imgui.PopStyleVar()
end

-- What winxi's theme controls call: to keep the choice of theme, and to save this addon's own theme
local AppearanceHooks = {
    onUseShared = function(useShared)
        Config.useSharedTheme = useShared
        Settings.save()
    end,
    onOwnChanged = function()
        Settings.save()
    end,
}

-- The appearance window keeps the default padding, whatever the theme's: the padding slider must not
-- squeeze the window it is in
local ConfigStyle = { padding = Theme.Defaults.Padding, kind = Window.Settings }
local ConfigFlags = ImGuiWindowFlags_NoSavedSettings -- a settings window: winxi.window sizes it

-- winxi's Theme and Window sections. This addon has no appearance settings of its own to follow them.
local function DrawConfigContent()
    Widgets.Appearance(AppearanceHooks)
end

-- The appearance window opened by /imrecast
local function DrawConfig()
    if not ShowConfig[1] then
        return
    end

    Window.Full('Recast Appearance', ShowConfig, ConfigFlags, DrawConfigContent, ConfigStyle)
end

local function OnPresent()
    -- Every frame, cheaply: nothing happens unless the choice of theme or the settings table has changed
    Theme.Configure(Config.useSharedTheme, Config.theme)

    DrawConfig()

    local resMgr    = AshitaCore:GetResourceManager()
    local mmPlayer  = AshitaCore:GetMemoryManager():GetPlayer()
    local mmRecast  = AshitaCore:GetMemoryManager():GetRecast()
    local timers    = T{}

    local playerJob = mmPlayer:GetMainJob()

    if playerJob == nil
    or playerJob == 0
    or Game.IsChatExpanded()
    or Game.IsMapOpen()
    or Game.IsEventHappening()
    or Game.IsInterfaceHidden() then
        return
    end

    -- Obtain the players ability recasts..
    for x = 0, 31 do
        local id = mmRecast:GetAbilityTimerId(x)
        local timer = mmRecast:GetAbilityTimer(x)

        -- Ensure the ability is valid and has a current recast timer..
        if ((id ~= 0 or x == 0) and timer > 0) then
            -- Obtain the resource entry for the ability..
            local ability = resMgr:GetAbilityByTimerId(id)
            local name = ('(Unknown: %d)'):fmt(id)

            -- Determine the name to be displayed..
            if (x == 0) then
                name = TwoHours[playerJob]
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
            elseif (ability ~= nil) then
                name = ability.Name[1]
            elseif (ability == nil) then
                ability = get_ability_fallback(id)
                if (ability ~= nil) then
                    name = ability.Name[1]
                end
            end

            -- Append the timer to the table..
            local newTimer = {
                name = name,
                timer = timer,
            }
            timers:insert(newTimer)
        end
    end

    -- Obtain the players spell recasts..
    for x = 0, 1024 do
        local id = x
        local timer = mmRecast:GetSpellTimer(x)

        -- Ensure the spell has a current recast timer..
        if (timer > 0) then
            local spell = resMgr:GetSpellById(id)
            local name = '(Unknown Spell)'

            -- Determine the name to be displayed..
            if (spell ~= nil) then
                name = spell.Name[1]
            end
            if (spell == nil or name:len() == 0) then
                name = ('Unknown Spell: %d'):fmt(id)
            end

            -- Append the timer to the table..
            local newTimer = {
                name = name,
                timer = timer,
            }
            timers:insert(newTimer)
        end
    end

    -- With nothing on recast there is no window to look at, so the appearance window gets a sample line
    if #timers == 0 and ShowConfig[1] then
        timers:insert({ name = 'Sample', timer = 3600 })
    end

    if #timers > 0 then
        DrawRecastWindow(timers)
    end
end

local function OnLoad()
end

local function OnUnload()
    UpdateSettings()
end

-- /imrecast opens or closes the appearance window
local function OnCommand(e)
    local args = e.command:args()
    if (#args == 0 or args[1]:lower() ~= '/imrecast') then
        return
    end

    e.blocked = true
    ShowConfig[1] = not ShowConfig[1]
end

---@param e PacketInEventArgs
local function OnPacket(e)
    -- Packet: Job Points
    if (e.id == 0x0063) then
        if (struct.unpack('B', e.data_modified, 0x04 + 0x01) == 5) then
            SchJp = struct.unpack('H', e.data_modified, 0x88 + 0x01)
        end
    end
end

Settings.register('settings', 'settings_update', UpdateSettings)
ashita.events.register('load', 'on_load', OnLoad)
ashita.events.register('unload', 'on_unload', OnUnload)
ashita.events.register('packet_in', 'on_packet_in', OnPacket)
ashita.events.register('command', 'on_command', OnCommand)
ashita.events.register('d3d_present', 'on_d3d_present', OnPresent)
