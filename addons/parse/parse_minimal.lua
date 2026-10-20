-- Quiet, background-free presentation of the same encounter snapshot.
local imgui = require('imgui')
local bit = require('bit')
local window = require('winxi.window')
local style = require('winxi.style')
local fade = require('winxi.fade')
local fonts = require('winxi.fonts')
local outlined = require('winxi.text')
local M = {}
local clear = { 0, 0, 0, 0 }
local foreground = { 0.9, 0.94, 0.97, 1 }
local muted = { 0.75, 0.8, 0.85, 0.7 }
-- Words with the theme's Text Outline round them, or plain where that is 0
function M.Text(words, color)
    if outlined.Edge() <= 0 then imgui.TextColored(color, words); return end
    local x, y = imgui.GetCursorScreenPos()
    local width, height = imgui.CalcTextSize(words)
    imgui.Dummy({ width, height })
    outlined.Draw(imgui.GetWindowDrawList(), x, y, color, words)
end
function M.Number(value, compact)
    if compact then
        if value >= 1000000 then return ('%.1fM'):format(value / 1000000) end
        if value >= 1000 then return ('%.1fK'):format(value / 1000) end
    end
    return ('%.0f'):format(value)
end
function M.Draw(options, snapshot, preview)
    local wanted = options.isVisible[1] and not (options.minimalHideEmpty[1] and #snapshot.rows == 0)
    local alpha = options.fadeInOut[1] and fade.Presence('winxi.parse.minimal', wanted) or (wanted and 1 or 0)
    if alpha <= 0.01 then return end
    imgui.SetNextWindowPos(options.minimalPos, ImGuiCond_FirstUseEver)
    local flags = bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoBackground,
        ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoBringToFrontOnFocus)
    window.Plain('winxi.parse.minimal', options.isVisible, flags, function()
        options.minimalPos[1], options.minimalPos[2] = imgui.GetWindowPos()
        local font = fonts.Get(options.minimalFontFile)
        if font then imgui.PushFont(font, options.minimalFontSize[1]) end
        local function text(words, color) M.Text(words, color or foreground) end
        imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 4, options.minimalRowSpacing[1] })
        imgui.PushStyleVar(ImGuiStyleVar_CellPadding, { 3, options.minimalRowSpacing[1] / 2 })
        local function number(value) return M.Number(value, options.minimalCompact[1]) end
        if options.minimalSummary[1] then
            text(('%s%s  /  %.0fs  /  %s'):format(
                preview and 'TEST  /  ' or '', number(snapshot.total), snapshot.duration,
                snapshot.running and 'damage' or 'PAUSED'), muted)
        elseif preview or not snapshot.running then
            -- Never disguise test data or a paused encounter when the summary is hidden.
            text(preview and 'TEST' or 'PAUSED', muted)
        end
        local count = math.min(#snapshot.rows, options.minimalRows[1])
        local scale = options.minimalFontSize[1] / 12
        local columns = { { label = 'Actor', width = options.minimalNameWidth[1] * scale } }
        for _, column in ipairs({
            { label = 'Share', width = 38 * scale, option = 'minimalShare', key = 'share' },
            { label = 'Damage', width = 58 * scale, option = 'minimalDamage', key = 'damage' },
            { label = 'DPS', width = 56 * scale, option = 'minimalDPS', key = 'dps' },
        }) do
            if options[column.option][1] then columns[#columns + 1] = column end
        end
        if count == 0 then
            text(snapshot.running and 'Waiting for damage' or '/parse resume to record', muted)
        elseif imgui.BeginTable('##parse.minimal.rows', #columns, ImGuiTableFlags_SizingFixedFit) then
            for _, column in ipairs(columns) do
                imgui.TableSetupColumn(column.label, ImGuiTableColumnFlags_WidthFixed, column.width)
            end
            for i = 1, count do
                local row = snapshot.rows[i]
                imgui.TableNextRow()
                for index, column in ipairs(columns) do
                    imgui.TableSetColumnIndex(index - 1)
                    local text = row.name
                    if column.key == 'share' then text = ('%.0f%%'):format(row.share or 0)
                    elseif column.key == 'damage' then text = number(row.damage)
                    elseif column.key == 'dps' then text = row.dps and (number(row.dps) .. '/s') or '--/s'
                    elseif options.minimalRanks[1] then text = i .. '. ' .. text end
                    if column.key then
                        local x = imgui.GetCursorPosX()
                        imgui.SetCursorPosX(x + math.max(0, column.width - imgui.CalcTextSize(text)))
                    end
                    M.Text(text, foreground)
                end
            end
            imgui.EndTable()
        end
        if options.minimalMore[1] and #snapshot.rows > count then text((' +%d more'):format(#snapshot.rows - count), muted) end
        imgui.PopStyleVar(2)
        if font then imgui.PopFont() end
    end, { padding = 2, fontSize = options.minimalFontSize[1], alpha = alpha * options.minimalOpacity[1],
        background = clear, border = clear, textColor = { 0.9, 0.94, 0.97, 1 }, shadow = false,
        locked = options.minimalLocked[1], clickThrough = options.minimalLocked[1] }) -- Lock Window
end
return M
