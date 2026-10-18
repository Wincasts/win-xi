-- Draw a Winxi frame attachment on the CURRENT window's list. No extra ImGui window,
-- layout item or native capture slot: its host captures background/content/border/shadow together.
-- rect = {left,top,width,height}; draw() must not reserve space in the host's layout.
local imgui = require('imgui')
local theme = require('winxi.theme')
local backgrounds = require('winxi.backgrounds')
local borders = require('winxi.borders')
local shadow = require('winxi.shadow')
local M = {}
function M.Draw(rect, draw, options)
    options = options or {}
    if rect.width <= 0 or rect.height <= 0 then return end
    local list = imgui.GetWindowDrawList()
    local display = imgui.GetIO().DisplaySize
    list:PushClipRect({0,0},{display.x or display[1],display.y or display[2]},false)
    local ok, err = pcall(function()
        if options.shadow ~= false then shadow.Draw(true,rect) end
        local color = options.background or theme.Get().BackgroundColor
        local background = backgrounds.For(options)
        if background then backgrounds.Draw(background,color,rect)
        else list:AddRectFilled({rect.left,rect.top},{rect.left+rect.width,rect.top+rect.height},imgui.GetColorU32(color),3) end
        draw()
        borders.Draw(borders.Texture(theme.Get().BorderStyle),nil,nil,options.border,rect)
    end)
    list:PopClipRect()
    if not ok then error(err,0) end
end
return M
