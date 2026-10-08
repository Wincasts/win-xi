require('common')
local bit = require('bit')
local imgui = require('imgui')
local ui = require('ui')
local packets = require('utils/packets')

local LastProgress = nil
local LastActionName = ''
local ActionTypes = {
    [packets.inbound.action.actionTypes.SpellStart] = true,
    [packets.inbound.action.actionTypes.ItemStart] = true,
}

---@type xitool
local cast = {
    Name = 'cast',
    DefaultSettings = T{
        isEnabled = T{ false },
        isVisible = T{ true },
        name = 'xitools.cast',
        size = T{ -1, -1 },
        barSize = T{ 256, 12 },
        pos = T{ 100, 100 },
        color = T{ 0.83, 0.33, 0.28, 1.0 },
        flags = bit.bor(ImGuiWindowFlags_NoDecoration),
    },
    HandlePacket = function(e, options, gOptions)
        if e.id == packets.inbound.action.id then
            local player = GetPlayerEntity()
            local action = packets.inbound.action.shared(e)

            if player
            and action.actor_id == player.ServerId
            and ActionTypes[action.category]
            and bit.band(action.param, 0xFFFF) == 0x6163 then
                local res = AshitaCore:GetResourceManager()

                -- a packet with no target, or naming something the client has no entry for,
                -- leaves the last name as it was
                local target = action.targets[1]
                local result = target and target.actions[1]
                if result then
                    local entry
                    if action.category == packets.inbound.action.actionTypes.SpellStart then
                        entry = res:GetSpellById(result.param)
                    else
                        entry = res:GetItemById(result.param)
                    end

                    if entry and entry.Name and entry.Name[1] then
                        LastActionName = entry.Name[1]
                    end
                end
            end
        end
    end,
    DrawConfig = function(options, gOptions)
        if imgui.BeginTabItem('cast') then
            ui.BeginLabels('xitools.cast')
            ui.Label('Enabled')
            imgui.Checkbox('##cast.1', options.isEnabled)

            ui.Gap()
            ui.Label('Bar Color')
            imgui.ColorEdit4('##cast.2', options.color)
            ui.Label('Bar Size')
            imgui.InputInt2('##cast.3', options.barSize)

            ui.Gap()
            ui.Label('Position')
            if imgui.InputInt2('##cast.4', options.pos) then
                imgui.SetWindowPos(options.name, options.pos)
            end

            imgui.EndTabItem()
        end
    end,
    DrawMain = function(options, gOptions)
        local castBar = AshitaCore:GetMemoryManager():GetCastBar()
        local progress = castBar:GetPercent()

        if progress == LastProgress then return end

        ui.DrawInvisWindow(options, gOptions, function()
            imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.08, 0.08, 0.08, 0.8 })
            imgui.PushStyleColor(ImGuiCol_Border, { 0.69, 0.68, 0.78, 1.0 })
            imgui.PushStyleColor(ImGuiCol_PlotHistogram, options.color)
            imgui.Text(LastActionName)
            imgui.ProgressBar(progress, options.barSize)
            imgui.PopStyleColor(3)

            LastProgress = progress
        end)
    end,
    -- The cast bar part-way through a made-up spell; the real one only shows while casting
    DrawSample = function(options, gOptions)
        ui.DrawInvisWindow(options, gOptions, function()
            imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.08, 0.08, 0.08, 0.8 })
            imgui.PushStyleColor(ImGuiCol_Border, { 0.69, 0.68, 0.78, 1.0 })
            imgui.PushStyleColor(ImGuiCol_PlotHistogram, options.color)
            imgui.Text('Sample Spell')
            imgui.ProgressBar(0.6, options.barSize)
            imgui.PopStyleColor(3)
        end)
    end,
}

return cast
