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
addon.author    = 'atom0s, Thorny, RZN, lin';
addon.version   = '2.0';
addon.desc      = 'Displays ability and spell recast times.';
addon.link      = 'https://ashitaxi.com/';

require('common')
local Settings = require('settings')
local Ffxi = require('lin.ffxi')
local Imgui = require('lin.imgui')

---@class RecastSettings
---@field windowName string
---@field windowSize Vec2
---@field windowPos Vec2
---@field bgColor number[] background colour as red, green, blue, alpha from 0 to 1
---@field borderColor number[] border colour as red, green, blue, alpha from 0 to 1
---@field textColor number[] colour of a timer with plenty of time left, as red, green, blue, alpha from 0 to 1
---@field padding integer space between the border and the timers, the same on every side

---@type RecastSettings
local Defaults = {
    windowName = 'Recast',
    windowSize = { -1, -1 },
    windowPos = { 100, 100 },
    bgColor = { 0.08, 0.08, 0.08, 0.8 },
    borderColor = { 0.69, 0.68, 0.78, 1.0 },
    textColor = { 1.00, 1.00, 1.00, 1.0 },
    padding = 10,
}

local MaxPadding = 40

---@type RecastSettings
local Config = Settings.load(Defaults)

---@type integer
local SchJp = 0

-- The /imrecast appearance window: whether it is open, and whether a change is waiting to be saved
local ShowConfig = { false }
local ConfigUnsaved = false

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

-- A colour setting as a fresh red, green, blue, alpha table, falling back to the default if it is missing
local function GetColor(key)
    local color = Config[key]
    if type(color) ~= 'table' or not (color[1] and color[2] and color[3]) then
        color = Defaults[key]
    end
    return { color[1], color[2], color[3], color[4] or 1 }
end

local function DrawTimer(timer)
    -- The chosen text colour, turning yellow in the last 20 seconds and red in the last 5
    if timer.timer >= 1200 then
        Imgui.PushStyleColor(ImGuiCol_Text, GetColor('textColor'))
    elseif timer.timer < 1200 and timer.timer > 300 then
        Imgui.PushStyleColor(ImGuiCol_Text, Imgui.Lin.Colors.Yellow)
    else
        Imgui.PushStyleColor(ImGuiCol_Text, Imgui.Lin.Colors.Red)
    end

    local text = string.format('%s - %s', timer.name, format_timestamp(timer.timer))
    Imgui.Text(text)
    Imgui.PopStyleColor()
end

local function DrawRecast(timers)
    for _, timer in pairs(timers) do
        DrawTimer(timer)
    end
end

local function GetPadding()
    return math.max(0, math.min(MaxPadding, tonumber(Config.padding) or Defaults.padding))
end

-- The recast window. Drawn here rather than with Imgui.Lin.DrawWindow, which fixes the colours and padding.
local function DrawRecastWindow(drawStuff)
    local padding = GetPadding()

    Imgui.SetNextWindowSize(Config.windowSize, ImGuiCond_Always)
    Imgui.SetNextWindowPos(Config.windowPos, ImGuiCond_FirstUseEver)

    Imgui.PushStyleColor(ImGuiCol_WindowBg, GetColor('bgColor'))
    Imgui.PushStyleColor(ImGuiCol_Border, GetColor('borderColor'))
    Imgui.PushStyleColor(ImGuiCol_BorderShadow, Imgui.Lin.Colors.BorderShadow)
    Imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, Imgui.Lin.Styles.ItemSpacing)
    Imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { padding, padding })

    if Imgui.Begin(Config.windowName, { true }, bit.bor(ImGuiWindowFlags_NoDecoration)) then
        Imgui.PopStyleColor(3)
        Imgui.PushStyleColor(ImGuiCol_Text, Imgui.Lin.Colors.White)
        Imgui.PushStyleVar(ImGuiStyleVar_FramePadding, Imgui.Lin.Styles.FramePadding)

        drawStuff()

        Imgui.PopStyleVar()
        Imgui.PopStyleColor()
    else
        Imgui.PopStyleColor(3)
    end

    Imgui.End()
    Imgui.PopStyleVar(2)
end

-- The appearance window opened by /imrecast. Changes show at once and are saved when the mouse is released.
local function DrawConfig()
    if not ShowConfig[1] then
        return
    end

    if Imgui.Begin('Recast Appearance', ShowConfig, bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings)) then
        local bgColor = GetColor('bgColor')
        if Imgui.ColorEdit4('Background', bgColor, ImGuiColorEditFlags_AlphaBar or 0) then
            Config.bgColor = bgColor
            ConfigUnsaved = true
        end
        if Imgui.IsItemHovered() then
            Imgui.SetTooltip('Colour behind the timers. The fourth value (A) is how solid it is: 0 is invisible.')
        end

        local borderColor = GetColor('borderColor')
        if Imgui.ColorEdit4('Border', borderColor, ImGuiColorEditFlags_AlphaBar or 0) then
            Config.borderColor = borderColor
            ConfigUnsaved = true
        end

        local textColor = GetColor('textColor')
        if Imgui.ColorEdit4('Text', textColor, ImGuiColorEditFlags_AlphaBar or 0) then
            Config.textColor = textColor
            ConfigUnsaved = true
        end
        if Imgui.IsItemHovered() then
            Imgui.SetTooltip('Colour of a timer with more than 20 seconds left. Timers still turn yellow, then red, as they run out.')
        end

        local padding = { GetPadding() }
        if Imgui.SliderInt('Padding', padding, 0, MaxPadding) then
            Config.padding = padding[1]
            ConfigUnsaved = true
        end
        if Imgui.IsItemHovered() then
            Imgui.SetTooltip('Space between the border and the timers, the same on every side.')
        end

        if Imgui.Button('Reset') then
            Config.bgColor = { Defaults.bgColor[1], Defaults.bgColor[2], Defaults.bgColor[3], Defaults.bgColor[4] }
            Config.borderColor = { Defaults.borderColor[1], Defaults.borderColor[2], Defaults.borderColor[3], Defaults.borderColor[4] }
            Config.textColor = { Defaults.textColor[1], Defaults.textColor[2], Defaults.textColor[3], Defaults.textColor[4] }
            Config.padding = Defaults.padding
            ConfigUnsaved = true
        end
    end
    Imgui.End()

    if ConfigUnsaved and not Imgui.IsMouseDown(0) then
        ConfigUnsaved = false
        Settings.save()
    end
end

local function OnPresent()
    DrawConfig()

    local resMgr    = AshitaCore:GetResourceManager()
    local mmPlayer  = AshitaCore:GetMemoryManager():GetPlayer()
    local mmRecast  = AshitaCore:GetMemoryManager():GetRecast()
    local timers    = T{}

    local playerJob = mmPlayer:GetMainJob()

    if playerJob == nil
    or playerJob == 0
    or Ffxi.IsChatExpanded()
    or Ffxi.IsMapOpen()
    or Ffxi.IsEventHappening()
    or Ffxi.IsInterfaceHidden() then
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
        DrawRecastWindow(function()
            DrawRecast(timers)
        end)
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
