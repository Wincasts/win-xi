-- Configurable three-slot info panel. Geometry is independent of ImGui for tests.
local M = {}
M.Names = { 'Left', 'Middle', 'Right' }
M.Alignments = { 'Left', 'Center', 'Right' }
M.IconPlaces = { 'Hidden', 'Native', 'Left', 'Middle', 'Right' }
function M.Defaults()
    return { enabled = { true }, attached = { true }, width = { 0 }, height = { 0 },
        x = { 100 }, y = { 100 }, offsetX = { 0 }, offsetY = { 0 }, padding = { 3 },
        separators = { true }, separatorStyle = { 2 }, separatorInset = { 4 },
        dayPlace = { 3 }, weatherPlace = { 5 }, dayAfter = { false }, weatherAfter = { true },
        dayX = { 0 }, dayY = { 0 }, weatherX = { 0 }, weatherY = { 0 },
        slots = {
            { format = '{time}  {grid}', align = { 1 }, weight = { 1 } },
            { format = '{day}  {date}', align = { 2 }, weight = { 1 } },
            { format = '{moon}', align = { 3 }, weight = { 1 } },
        } }
end
local function Clamp(v, low, high, fallback)
    v = tonumber(v)
    if not v or v ~= v or math.abs(v) == math.huge then v = fallback end
    return math.max(low, math.min(high, v))
end
function M.Complete(p)
    local defaults = M.Defaults()
    for key, value in pairs(defaults) do
        if key ~= 'slots' then
            if type(p[key]) ~= 'table' then p[key] = value end
            if type(value[1]) == 'boolean' then
                if p[key][1] == nil then p[key][1] = value[1] else p[key][1] = p[key][1] == true end
            end
        end
    end
    local ranges = { width={0,4096}, height={0,512}, x={-4096,8192}, y={-4096,8192},
        offsetX={-2048,2048}, offsetY={-2048,2048}, padding={1,32}, separatorStyle={1,3},
        separatorInset={0,64}, dayPlace={1,5}, weatherPlace={1,5},
        dayX={-128,128}, dayY={-128,128}, weatherX={-128,128}, weatherY={-128,128} }
    for key, range in pairs(ranges) do p[key][1] = math.floor(Clamp(p[key][1], range[1], range[2], defaults[key][1])) end
    if type(p.slots) ~= 'table' then p.slots = {} end
    for i=1,3 do
        if type(p.slots[i]) ~= 'table' then p.slots[i] = defaults.slots[i] end
        local s = p.slots[i]
        if type(s.format) ~= 'string' then s.format = defaults.slots[i].format end
        if type(s.align) ~= 'table' then s.align = defaults.slots[i].align end
        if type(s.weight) ~= 'table' then s.weight = { 1 } end
        s.align[1] = math.floor(Clamp(s.align[1],1,3,i))
        s.weight[1] = Clamp(s.weight[1],0.1,10,1)
    end
end
function M.Format(p)
    return table.concat({p.slots[1].format,p.slots[2].format,p.slots[3].format}, '  ')
end
function M.Layout(p, left, top, width, height)
    local padding = math.min(p.padding[1], math.max(0,(width-3)/2))
    local room = math.max(0,width-2*padding)
    local total = 0
    for i=1,3 do total = total+p.slots[i].weight[1] end
    local slots, x = {}, left+padding
    for i=1,3 do
        local w = room*p.slots[i].weight[1]/total
        slots[i] = {left=x,right=x+w,top=top+padding,bottom=top+height-padding}
        x = x+w
    end
    return slots
end
function M.Aligned(left, right, width, align)
    return left + math.max(0,right-left-width) * ((align-1)/2)
end
-- Turn literal pipes into styled separator segments without changing the field grammar. A word with a
-- tooltip (out.tooltips[i]) is kept whole.
function M.Segments(fields, context, format)
    local out = { tooltips = {} }
    local segments = fields.Segments(context,format)
    for i, segment in ipairs(segments) do
        if type(segment) ~= 'string' then out[#out+1] = segment
        elseif segments.tooltips and segments.tooltips[i] then
            out[#out+1] = segment
            out.tooltips[#out] = segments.tooltips[i]
        else
            local at = 1
            while true do
                local pipe = segment:find('|',at,true)
                local words = segment:sub(at,pipe and pipe-1 or #segment)
                if #words>0 then out[#out+1] = words end
                if not pipe then break end
                out[#out+1] = { separator=true }
                at = pipe+1
            end
        end
    end
    return out
end
function M.Build(p, fields, context)
    local slots = {}
    for i=1,3 do slots[i] = M.Segments(fields,context,p.slots[i].format) end
    local function Icon(kind, handle)
        local place = p[kind..'Place'][1]
        if place < 3 or not handle then return end
        -- A manually placed token takes precedence over automatic placement.
        if fields.Has(M.Format(p),kind..'icon') then return end
        local segment = { icon=handle, kind=kind,
            tooltip=kind=='weather' and fields.Tooltip and fields.Tooltip('weather',context)
                or fields.IconTooltip and fields.IconTooltip(kind,context) or nil }
        local slot = slots[place-2]
        if p[kind..'After'][1] then
            if #slot>0 then slot[#slot+1]='  ' end
            slot[#slot+1]=segment
        else
            -- put before the words: their tooltips move along with them
            local shift = #slot>0 and 2 or 1
            if #slot>0 then table.insert(slot,1,'  ') end
            table.insert(slot,1,segment)
            if slot.tooltips then
                local moved = {}
                for index, tooltip in pairs(slot.tooltips) do moved[index+shift] = tooltip end
                slot.tooltips = moved
            end
        end
    end
    Icon('day',context.dayIcon); Icon('weather',context.weatherIcon)
    return slots
end
-- Required on first draw: the geometry above needs no ImGui
local imgui, theme, outlined
-- A slot's words measured once in the font and size they are drawn in, kept on its segments (made afresh as the
-- fields are read again), not every frame
local function TextWidths(segments, font, size)
    if segments.widthsFont == font and segments.widthsSize == size and segments.widths then return segments.widths end
    local widths = {}
    for j, s in ipairs(segments) do
        if type(s) == 'string' then widths[j] = imgui.CalcTextSize(s) end
    end
    segments.widthsFont, segments.widthsSize, segments.widths = font, size, widths
    return widths
end
-- The points and sizes handed to imgui, which copies them as it is given them: the same few tables
-- every frame, as this is drawn every frame
local pointA, pointB, pointC, room = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
local shadeLine = { 0, 0, 0, 0.45 } -- the dark line beside a beveled separator
local function Divider(list, p, tint, x, top, bottom)
    if bottom<=top then return end
    local color = imgui.GetColorU32(tint)
    pointA[1], pointA[2], pointB[1], pointB[2] = x, top, x, bottom
    list:AddLine(pointA,pointB,color,1)
    if p.separatorStyle[1] >= 2 and bottom-top>4 then
        pointA[1], pointA[2], pointB[1], pointB[2] = x+2, top+2, x+2, bottom-2
        list:AddLine(pointA,pointB,imgui.GetColorU32(shadeLine),1)
    end
    if p.separatorStyle[1] == 3 then
        pointA[1], pointA[2], pointB[1], pointB[2], pointC[1], pointC[2] = x, top-2, x-2, top+1, x+2, top+1
        list:AddTriangleFilled(pointA,pointB,pointC,color)
        pointA[1], pointA[2], pointB[1], pointB[2], pointC[1], pointC[2] = x, bottom+2, x-2, bottom-1, x+2, bottom-1
        list:AddTriangleFilled(pointA,pointB,pointC,color)
    end
end
-- Draw-list text and icons are not ImGui items: the mouse is tested against their visible, slot-clipped
-- area; no buttons or invisible items, which would take native chat and menu input. options.tooltip is
-- given the hovered one's tooltip (words, or a table for the panel's owner to draw).
local function Hovered(options, left, right, top, bottom, x0, y0, x1, y1)
    if not options.tooltip then return false end
    local io = imgui.GetIO()
    local mouse = io.MousePos
    local mx, my = mouse and (mouse.x or mouse[1]), mouse and (mouse.y or mouse[2])
    return not io.WantCaptureMouse and mx ~= nil and my ~= nil
        and mx >= math.max(left,x0) and mx < math.min(right,x1) and my >= math.max(top,y0) and my < math.min(bottom,y1)
end
function M.Draw(p, slots, rect, options)
    imgui = imgui or require('imgui')
    theme = theme or require('winxi.theme')
    outlined = outlined or require('winxi.text')
    local list = imgui.GetWindowDrawList()
    local bounds = M.Layout(p,rect.left,rect.top,rect.width,rect.height)
    local size = imgui.GetFontSize()
    local font = imgui.GetFont and imgui.GetFont() or nil
    local tint = theme.GameBorderColor()
    for i=1,3 do
        local segments = slots[i]
        local b, widths, width = bounds[i], TextWidths(segments, font, size), 0
        for j, s in ipairs(segments) do
            if type(s)~='string' then
                widths[j] = s.separator and 8 or size*options.iconScale[1]*(s.kind=='weather' and options.weatherScale[1] or 1)
            end
            width = width+widths[j]
        end
        local left = math.min(b.right,b.left+4)
        local right = math.max(left,b.right-4)
        local x = M.Aligned(left,right,width,p.slots[i].align[1])
        local y = rect.top+(rect.height-size)/2
        pointA[1], pointA[2], pointB[1], pointB[2] = left, rect.top+1, right, rect.top+rect.height-1
        list:PushClipRect(pointA,pointB,true)
        local tooltips = segments.tooltips
        for j,s in ipairs(segments) do
            if type(s)=='string' then
                outlined.Draw(list,x,y,options.textColor,s) -- its edge the theme's Text Outline
                if tooltips and tooltips[j] and Hovered(options,left,right,rect.top+1,rect.top+rect.height-1,x,y,x+widths[j],y+size) then
                    options.tooltip(tooltips[j])
                end
            elseif s.separator then Divider(list,p,tint,x+4,rect.top+p.separatorInset[1],rect.top+rect.height-p.separatorInset[1])
            else
                local kind = s.kind or 'weather'
                local dx,dy = p[kind..'X'][1],p[kind..'Y'][1]+options.iconOffset[1]
                local h = widths[j]
                local iy = rect.top+(rect.height-h)/2+dy
                pointA[1], pointA[2], pointB[1], pointB[2] = x+dx, iy, x+dx+h, iy+h
                list:AddImage(s.icon,pointA,pointB)
                if s.tooltip and Hovered(options,left,right,rect.top+1,rect.top+rect.height-1,x+dx,iy,x+dx+h,iy+h) then
                    options.tooltip(s.tooltip)
                end
            end
            x=x+widths[j]
        end
        list:PopClipRect()
        if p.separators[1] and i<3 then
            Divider(list,p,tint,b.right,rect.top+p.separatorInset[1],rect.top+rect.height-p.separatorInset[1])
        end
    end
    if options.reserve ~= false then
        room[1], room[2] = math.max(0,rect.width-2*p.padding[1]), math.max(0,rect.height-2*p.padding[1])
        imgui.Dummy(room)
    end
end
return M
