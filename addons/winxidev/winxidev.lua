addon.name    = 'winxidev'
addon.author  = 'Win'
addon.version = '0.1'
addon.desc    = 'Development only: dummy copies of the UI windows, to lay out and restyle by hand.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- A workbench, not a tool to play with. It draws copies of the UI windows (me, us, tgt, pet, inv,
-- treas, recast) out of pieces: text, bars, icons, buttons, tabs, spacers, rows and columns, drawn with
-- the same widgets, colours and theme as the real windows. A piece is picked up and moved with the
-- mouse, resized and padded by the handles around it, and can carry a note. What is settled on here
-- is then written into the real windows' code by hand.
--
--   /winxidev    opens or closes the editor (the copies show while it is open)
--
-- The layouts are kept in config\addons\winxidev\layouts.lua and the notes, set out to be read, in
-- notes.txt beside it: both written by the editor's Save button and when the addon is unloaded.

require('common')
local bit = require('bit')
local ffi = require('ffi')
local d3d8 = require('d3d8')
local imgui = require('imgui')
local theme = require('winxi.theme')
local style = require('winxi.style')
local shadow = require('winxi.shadow')

-- The sizes and colours the real windows use (xitools' ui.lua)
local txtW, txtH = imgui.CalcTextSize('HP 100%')
txtH = txtH or 14
local barBackground = { 0.16, 0.17, 0.20, 1.0 }
local barBorder = { 0.07, 0.07, 0.07, 1.0 }
local framePaddingNone = { 0, 0 }
local framePaddingSome = { 4, 2 }
local itemSpacing = { 8, 4 }

----------------------------------------------------------------------------------------------------
-- The pieces
----------------------------------------------------------------------------------------------------

local nextId = 0

local function Node(kind, fields)
    local node = fields or { }
    node.type = kind
    node.pad = node.pad or { 0, 0, 0, 0 } -- left, top, right, bottom
    node.off = node.off or { 0, 0 }
    return node
end

local function Column(label, gap, children) return Node('column', { label = label, gap = gap or 4, children = children or { } }) end
local function Row(label, gap, children) return Node('row', { label = label, gap = gap or 4, center = true, children = children or { } }) end
local function Repeat(label, count, gap, children) return Node('repeat', { label = label, count = count, gap = 2, itemGap = gap or 4, children = children or { } }) end
local function Text(text, color) return Node('text', { label = text, text = text, color = color }) end
local function Bar(label, w, h, fraction, color, overlay) return Node('bar', { label = label, w = w, h = h, fraction = fraction, color = color, text = overlay or '' }) end
local function Icons(label, source, count, size, gap, perRow) return Node('icons', { label = label, source = source, count = count, size = size, gap = gap or 2, perRow = perRow or 0, color = { 0.45, 0.55, 0.75, 1.0 } }) end
local function Button(text) return Node('button', { label = text, text = text }) end
local function Tabs(text) return Node('tabs', { label = 'tabs', text = text }) end
local function Spacer(w, h, fill) return Node('spacer', { label = fill and 'fill' or 'spacer', w = w or 0, h = h or 0, fill = fill or false }) end
local function Fill() return Spacer(4, 0, true) end

local hp = { 0.83, 0.33, 0.28, 1.0 }
local mp = { 0.82, 0.60, 0.27, 1.0 }
local tp = { 1.00, 1.00, 1.00, 1.0 }
local xp = { 0.01, 0.67, 0.07, 1.0 }
local dim = { 0.70, 0.70, 0.70, 1.0 }

-- A line of the me and tgt windows: what the bar is for, then the bar
local function TitledBar(title, fraction, color)
    return Row(title, 8, { Text(title), Bar('bar', 248 - txtW, txtH, fraction, color, '') })
end

local function Window(name, x, y, root)
    return {
        name = name, visible = true, pos = { x, y }, width = 0, note = '',
        -- its look is the shared theme's unless it is given one of its own
        useTheme = true, padding = 10, rounding = 0, borderSize = 1,
        back = { 0.08, 0.08, 0.08, 0.8 }, border = { 0.69, 0.68, 0.78, 1.0 }, text = { 1, 1, 1, 1 },
        root = root,
    }
end

local function DefaultWindows()
    return {
        Window('me', 60, 60, Column('me', 4, {
            Row('header', 4, { Text('Win'), Fill(), Text('PUP75/WAR37') }),
            TitledBar('HP 1400', 0.9, hp), TitledBar('MP  800', 0.6, mp),
            TitledBar('TP 1200', 0.4, tp), TitledBar('XP 12.3', 0.3, xp),
        })),
        Window('us', 360, 60, Column('us', 4, {
            Repeat('members', 6, 4, {
                Row('name line', 4, { Text('Sample'), Fill(), Text('WAR75/NIN37') }),
                Row('bars', 8, { Bar('hp', 80, txtH, 0.9, hp, '1400'), Bar('mp', 80, txtH, 0.6, mp, '800'), Bar('tp', 80, txtH, 0.4, tp, '1200') }),
                Icons('buffs', 'status', 8, txtH, 2, 0),
            }),
        })),
        Window('tgt', 60, 220, Column('tgt', 4, {
            Row('header', 4, { Text('Target Name'), Fill(), Text('12.3m') }),
            TitledBar('HP  76%', 0.76, hp),
            Icons('statuses', 'status', 10, 16, 2, 0),
        })),
        Window('pet', 60, 330, Column('pet', 4, {
            Row('header', 4, { Text('Lobo'), Fill(), Text('5.2m') }),
            Row('bars', 8, { Bar('hp', 80, txtH, 0.8, hp, '900'), Bar('mp', 80, txtH, 0.5, mp, '300'), Bar('tp', 80, txtH, 0.27, tp, '800') }),
        })),
        Window('inv', 700, 60, Column('inv', 4, {
            Tabs('bag,satchel,ward,house'),
            Icons('slots', 'item', 30, 32, 8, 5),
            Spacer(0, 3, false),
            Row('foot', 4, { Text('1,234,567 G'), Fill(), Text('18/30') }),
        })),
        Window('treas', 700, 380, Column('treas', 4, {
            Row('buttons', 8, { Button('Roll All'), Button('Pass All') }),
            Repeat('pool', 3, 4, {
                Row('item', 10, { Text('Item Name'), Fill(), Text(' 254'), Text(' 731'), Text('Winner'), Button('Roll'), Button('Pass') }),
            }),
        })),
        Window('recast', 360, 420, Column('recast', 4, {
            Text('Provoke - 24s'), Text('Maneuver - 8s'), Text('Cure IV - 3s'), Text('Deploy - 1m 2s'),
        })),
    }
end

local windows = nil

local function AssignIds(node)
    nextId = nextId + 1
    node._id = nextId
    node.pad = node.pad or { 0, 0, 0, 0 }
    node.off = node.off or { 0, 0 }
    for _, child in ipairs(node.children or { }) do
        AssignIds(child)
    end
end

local function Copy(value)
    if type(value) ~= 'table' then
        return value
    end
    local copy = { }
    for key, inner in pairs(value) do
        if type(key) ~= 'string' or key:sub(1, 1) ~= '_' then
            copy[key] = Copy(inner)
        end
    end
    return copy
end

----------------------------------------------------------------------------------------------------
-- Keeping the layouts
----------------------------------------------------------------------------------------------------

local function Folder()
    return ('%s\\config\\addons\\winxidev\\'):format(AshitaCore:GetInstallPath())
end

local function Serialize(value, indent, out)
    if type(value) == 'table' then
        out[#out + 1] = '{\n'
        local inner = indent .. '    '
        -- the numbered part in order, then the named part in the order of the names
        for _, item in ipairs(value) do
            out[#out + 1] = inner
            Serialize(item, inner, out)
            out[#out + 1] = ',\n'
        end
        local keys = { }
        for key in pairs(value) do
            if type(key) == 'string' and key:sub(1, 1) ~= '_' then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            out[#out + 1] = ('%s%s = '):format(inner, key)
            Serialize(value[key], inner, out)
            out[#out + 1] = ',\n'
        end
        out[#out + 1] = indent .. '}'
    elseif type(value) == 'string' then
        out[#out + 1] = ('%q'):format(value)
    elseif type(value) == 'number' then
        out[#out + 1] = (value == math.floor(value)) and ('%d'):format(value) or ('%.3f'):format(value)
    else
        out[#out + 1] = tostring(value)
    end
end

local function Say(text)
    print(('\30\81[winxidev]\30\01 %s'):format(text))
end

-- Every note, with where it is, one to a paragraph: for reading rather than loading
local function CollectNotes(node, path, out)
    local here = ('%s > %s %s'):format(path, node.type, node.label or '')
    if node.note and node.note ~= '' then
        out[#out + 1] = ('%s\n    %s\n'):format(here, node.note:gsub('\n', '\n    '))
    end
    for _, child in ipairs(node.children or { }) do
        CollectNotes(child, here, out)
    end
end

local function SaveLayouts(quiet)
    local folder = Folder()
    ashita.fs.create_directory(folder)
    local out = { 'return ' }
    Serialize({ version = 2, windows = windows }, '', out)
    out[#out + 1] = '\n'

    local file, problem = io.open(folder .. 'layouts.lua', 'w')
    if file == nil then
        Say(('Could not save: %s'):format(tostring(problem)))
        return
    end
    file:write(table.concat(out))
    file:close()

    local notes = { }
    for _, window in ipairs(windows) do
        if window.note and window.note ~= '' then
            notes[#notes + 1] = ('%s (the window)\n    %s\n'):format(window.name, window.note:gsub('\n', '\n    '))
        end
        CollectNotes(window.root, window.name, notes)
    end
    file = io.open(folder .. 'notes.txt', 'w')
    if file ~= nil then
        file:write(table.concat(notes, '\n'))
        file:close()
    end

    if not quiet then
        Say(('Saved to config\\addons\\winxidev: layouts.lua, and %d note(s) in notes.txt'):format(#notes))
    end
end

local function LoadLayouts()
    local chunk = loadfile(Folder() .. 'layouts.lua')
    local ok, saved = false, nil
    if chunk ~= nil then
        ok, saved = pcall(chunk)
    end
    -- only what this version saved: the first one's pieces were of other kinds
    if ok and type(saved) == 'table' and saved.version == 2 and type(saved.windows) == 'table' and #saved.windows > 0 then
        windows = saved.windows
    else
        windows = DefaultWindows()
    end
    for _, window in ipairs(windows) do
        AssignIds(window.root)
    end
end


----------------------------------------------------------------------------------------------------
-- Icons: the game's own, as the real windows draw them
----------------------------------------------------------------------------------------------------

local device = d3d8.get_device()
local textures = { } -- 'status.40' and the like -> a texture's pointer, or false where there is none

local statusIds = { 40, 41, 33, 43, 42, 37, 39, 36, 251, 253 }
local itemIds = { 4096, 4097, 4098, 4099, 4100, 4101, 4102, 4103, 4112, 4116, 4128, 4148, 4150, 4509, 12289, 12432, 12560, 12688, 12816, 12944, 13193, 16385, 16448, 16512, 16640, 16768, 17024, 17152, 17280, 17336 }

local function MakeTexture(bitmap, size)
    local pointer = ffi.new('IDirect3DTexture8*[1]')
    local c = ffi.C
    if c.D3DXCreateTextureFromFileInMemoryEx(device, bitmap, size, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0, c.D3DFMT_A8R8G8B8,
        c.D3DPOOL_MANAGED, c.D3DX_DEFAULT, c.D3DX_DEFAULT, 0xFF000000, nil, nil, pointer) ~= c.S_OK then
        return nil
    end
    return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]))
end

-- The picture for the nth icon of a block, or nil for a plain square in its place
local function IconTexture(source, index)
    if source ~= 'status' and source ~= 'item' then
        return nil
    end

    local ids = (source == 'status') and statusIds or itemIds
    local id = ids[(index % #ids) + 1]
    local key = ('%s.%d'):format(source, id)
    local texture = textures[key]
    if texture == nil then
        texture = false
        local ok, made = pcall(function()
            local resources = AshitaCore:GetResourceManager()
            if source == 'status' then
                local icon = resources:GetStatusIconByIndex(id)
                return icon and MakeTexture(icon.Bitmap, icon.ImageSize)
            end
            local item = resources:GetItemById(id)
            return item and MakeTexture(item.Bitmap, item.ImageSize)
        end)
        if ok and made ~= nil then
            -- the texture is kept as well as its number, or it would be let go
            texture = { made, tonumber(ffi.cast('uint32_t', made)) }
        end
        textures[key] = texture
    end
    return texture and texture[2] or nil
end

----------------------------------------------------------------------------------------------------
-- Laying out and drawing
----------------------------------------------------------------------------------------------------

local selected = nil         -- the piece being edited
local selectedCopy = 1       -- which drawing of it, for a piece inside a repeat: the one that was clicked
local selectedWindow = 1     -- the window being edited, by its place in windows
local showBoxes = { false }  -- outline every piece
local hits = { }             -- every piece drawn this frame: { node, x, y, w, h, depth, window }
local handles = { }          -- the selected piece's handles this frame: { mode, x, y, what }
local copiesDrawn = 0        -- how many times the selected piece has been drawn this frame

local function OuterSize(node)
    return node._w + node.pad[1] + node.pad[3], node._h + node.pad[2] + node.pad[4]
end

local function TabLabels(node)
    local labels = { }
    for label in (node.text or ''):gmatch('[^,]+') do
        labels[#labels + 1] = label
    end
    return labels
end

-- Works out each piece's own size (without its padding), from the leaves up
local function Measure(node)
    local w, h = 0, 0
    local kind = node.type
    if kind == 'text' then
        w, h = imgui.CalcTextSize(node.text or '')
        h = h or txtH
    elseif kind == 'button' then
        w = imgui.CalcTextSize(node.text or '') + 2 * framePaddingSome[1]
        h = txtH + 2 * framePaddingSome[2]
    elseif kind == 'tabs' then
        for _, label in ipairs(TabLabels(node)) do
            w = w + imgui.CalcTextSize(label) + 2 * framePaddingSome[1] + 1
        end
        h = txtH + 2 * framePaddingSome[2] + 2
    elseif kind == 'bar' or kind == 'spacer' then
        w, h = node.w, node.h
    elseif kind == 'icons' then
        local count = math.max(0, node.count)
        local per = (node.perRow > 0) and math.min(node.perRow, count) or count
        local rows = (per > 0) and math.ceil(count / per) or 0
        w = per * node.size + math.max(0, per - 1) * node.gap
        h = rows * node.size + math.max(0, rows - 1) * node.gap
    else
        for index, child in ipairs(node.children) do
            Measure(child)
            local cw, ch = OuterSize(child)
            if kind == 'row' then
                w = w + cw + (index > 1 and node.gap or 0)
                h = math.max(h, ch)
            else
                w = math.max(w, cw)
                h = h + ch + (index > 1 and node.gap or 0)
            end
        end
        if kind == 'repeat' then
            node._itemHeight = h
            local count = math.max(0, node.count)
            h = h * count + math.max(0, count - 1) * node.itemGap
        end
    end
    node._w, node._h = w, h
end

local a, b = { 0, 0 }, { 0, 0 }

local function Rect(drawList, x, y, w, h, color, filled, rounding)
    a[1], a[2], b[1], b[2] = x, y, x + w, y + h
    if filled then
        drawList:AddRectFilled(a, b, imgui.GetColorU32(color), rounding or 0)
    else
        drawList:AddRect(a, b, imgui.GetColorU32(color), rounding or 0)
    end
end

local boxColor = { 1, 1, 1, 0.25 }
local outerColor = { 1.0, 0.6, 0.1, 1.0 }   -- the selected piece with its padding, and the padding handles
local innerColor = { 0.3, 0.9, 0.4, 1.0 }   -- the selected piece itself, and the size handles
local noteColor = { 1.0, 0.9, 0.2, 1.0 }    -- the corner of a piece that has a note

-- What dragging a piece's size handles changes, across and down
local function Resizes(node, isRoot)
    local kind = node.type
    if kind == 'bar' or kind == 'spacer' or kind == 'icons' then
        return true, true
    elseif kind == 'row' then
        return true, false
    elseif kind == 'column' or kind == 'repeat' then
        return isRoot, true
    end
    return false, false
end

local Draw

local function DrawChildren(node, drawList, window, x, y, width, depth)
    if node.type == 'row' then
        local spare, fills = width - node._w, 0
        for _, child in ipairs(node.children) do
            if child.type == 'spacer' and child.fill then
                fills = fills + 1
            end
        end
        local across = x
        for _, child in ipairs(node.children) do
            local cw, ch = OuterSize(child)
            if child.type == 'spacer' and child.fill and spare > 0 then
                cw = cw + spare / fills
            end
            local down = node.center and math.floor((node._h - ch) / 2) or 0
            Draw(child, drawList, window, across, y + down, cw, depth)
            across = across + cw + node.gap
        end
    else
        local down = y
        for _, child in ipairs(node.children) do
            local _, ch = OuterSize(child)
            Draw(child, drawList, window, x, down, width, depth)
            down = down + ch + node.gap
        end
    end
end

local iconSize = { 0, 0 }
local barSize = { 0, 0 }

-- Draws a piece with its top left corner (padding and all) at x, y, in the width it has been given.
-- The pieces are the real widgets, put where they belong one by one.
Draw = function(node, drawList, window, x, y, width, depth)
    local ow, oh = OuterSize(node)
    local kind = node.type
    local container = (kind == 'column' or kind == 'row' or kind == 'repeat')
    if container or (kind == 'spacer' and node.fill) then
        ow = math.max(ow, width or ow)
    end

    local cx, cy = math.floor(x + node.pad[1] + node.off[1]), math.floor(y + node.pad[2] + node.off[2])
    local cw, ch = ow - node.pad[1] - node.pad[3], node._h

    hits[#hits + 1] = { node = node, x = x, y = y, w = ow, h = oh, depth = depth, window = window }

    a[1], a[2] = cx, cy
    if kind == 'text' then
        imgui.SetCursorScreenPos(a)
        if node.color then
            imgui.TextColored(node.color, node.text or '')
        else
            imgui.Text(node.text or '')
        end
    elseif kind == 'bar' then
        imgui.SetCursorScreenPos(a)
        imgui.PushStyleColor(ImGuiCol_FrameBg, barBackground)
        imgui.PushStyleColor(ImGuiCol_Border, barBorder)
        imgui.PushStyleColor(ImGuiCol_PlotHistogram, node.color)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePaddingNone)
        barSize[1], barSize[2] = node.w, node.h
        imgui.ProgressBar(math.max(0, math.min(1, node.fraction)), barSize, node.text or '')
        imgui.PopStyleVar()
        imgui.PopStyleColor(3)
    elseif kind == 'button' then
        imgui.SetCursorScreenPos(a)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePaddingSome)
        imgui.Button(('%s##winxidev.button.%d.%d'):format(node.text or '', node._id, #hits))
        imgui.PopStyleVar()
    elseif kind == 'tabs' then
        imgui.SetCursorScreenPos(a)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePaddingSome)
        if imgui.BeginTabBar(('##winxidev.tabs.%d.%d'):format(node._id, #hits), ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
            for _, label in ipairs(TabLabels(node)) do
                if imgui.BeginTabItem(label) then
                    imgui.EndTabItem()
                end
            end
            imgui.EndTabBar()
        end
        imgui.PopStyleVar()
    elseif kind == 'icons' then
        local per = (node.perRow > 0) and node.perRow or math.max(1, node.count)
        iconSize[1], iconSize[2] = node.size, node.size
        for index = 0, node.count - 1 do
            local column, row = index % per, math.floor(index / per)
            local ix, iy = cx + column * (node.size + node.gap), cy + row * (node.size + node.gap)
            local texture = IconTexture(node.source, index)
            if texture ~= nil then
                a[1], a[2] = ix, iy
                imgui.SetCursorScreenPos(a)
                imgui.Image(texture, iconSize)
            else
                Rect(drawList, ix, iy, node.size, node.size, node.color, true, 2)
            end
        end
    elseif kind == 'repeat' then
        for index = 0, node.count - 1 do
            DrawChildren(node, drawList, window, cx, cy + index * (node._itemHeight + node.itemGap), cw, depth + 1)
        end
    elseif container then
        DrawChildren(node, drawList, window, cx, cy, cw, depth + 1)
    end

    if node.note and node.note ~= '' then
        Rect(drawList, x + ow - 6, y, 6, 6, noteColor, true)
    end

    if node == selected then
        copiesDrawn = copiesDrawn + 1
        Rect(drawList, x, y, ow, oh, outerColor, false)
        Rect(drawList, cx, cy, cw, ch, innerColor, false)

        if copiesDrawn == selectedCopy then
            -- the handles: size on the piece's own edges, padding just outside its padded box
            local canWide, canTall = Resizes(node, node == window.root)
            if canWide then
                handles[#handles + 1] = { mode = 'w', x = cx + cw, y = cy + ch / 2, what = 'width' }
            end
            if canTall then
                handles[#handles + 1] = { mode = 'h', x = cx + cw / 2, y = cy + ch, what = 'height' }
            end
            if canWide and canTall and not container then
                handles[#handles + 1] = { mode = 'wh', x = cx + cw, y = cy + ch, what = 'size' }
            end
            handles[#handles + 1] = { mode = 'padL', x = x - 8, y = y + oh / 2, what = 'padding left', pad = true }
            handles[#handles + 1] = { mode = 'padT', x = x + ow / 2, y = y - 8, what = 'padding top', pad = true }
            handles[#handles + 1] = { mode = 'padR', x = x + ow + 8, y = y + oh / 2, what = 'padding right', pad = true }
            handles[#handles + 1] = { mode = 'padB', x = x + ow / 2, y = y + oh + 8, what = 'padding bottom', pad = true }
        end
    elseif showBoxes[1] then
        Rect(drawList, x, y, ow, oh, boxColor, false)
    end
end

----------------------------------------------------------------------------------------------------
-- Picking up, moving and resizing with the mouse
----------------------------------------------------------------------------------------------------

local drag = nil -- { mode, node, window, lastX, lastY, restX, restY }
local handleReach = 7
local editorHovered = false

local function Whole(value)
    return (value >= 0) and math.floor(value) or math.ceil(value)
end

-- Moves what is being dragged by as many whole pixels as the mouse has gone
local function ApplyDrag(mx, my)
    local node, window, mode = drag.node, drag.window, drag.mode
    drag.restX = drag.restX + (mx - drag.lastX)
    drag.restY = drag.restY + (my - drag.lastY)
    drag.lastX, drag.lastY = mx, my

    local dx, dy = Whole(drag.restX), Whole(drag.restY)
    drag.restX, drag.restY = drag.restX - dx, drag.restY - dy
    if dx == 0 and dy == 0 then
        return
    end

    local kind = node.type
    if mode == 'move' then
        if node == window.root then
            -- the whole window
            window.pos[1], window.pos[2] = window.pos[1] + dx, window.pos[2] + dy
            window._place = true
        else
            node.off[1], node.off[2] = node.off[1] + dx, node.off[2] + dy
        end
    elseif mode == 'padL' then
        node.pad[1] = math.max(0, node.pad[1] + dx)
    elseif mode == 'padT' then
        node.pad[2] = math.max(0, node.pad[2] + dy)
    elseif mode == 'padR' then
        node.pad[3] = math.max(0, node.pad[3] + dx)
    elseif mode == 'padB' then
        node.pad[4] = math.max(0, node.pad[4] + dy)
    else
        local wide = (mode == 'w' or mode == 'wh') and dx or 0
        local tall = (mode == 'h' or mode == 'wh') and dy or 0
        if kind == 'bar' or kind == 'spacer' then
            node.w = math.max(kind == 'bar' and 1 or 0, node.w + wide)
            node.h = math.max(kind == 'bar' and 1 or 0, node.h + tall)
        elseif kind == 'icons' then
            node.size = math.max(1, node.size + ((math.abs(wide) > math.abs(tall)) and wide or tall))
        elseif kind == 'row' then
            node.gap = math.max(0, node.gap + wide)
        elseif kind == 'repeat' then
            node.itemGap = math.max(0, node.itemGap + tall)
        elseif kind == 'column' then
            node.gap = math.max(0, node.gap + tall)
            if node == window.root and wide ~= 0 then
                window.width = math.max(0, (window._drawnWidth or 0) + wide)
            end
        end
    end
end

-- What is changing, by the mouse, while something is dragged
local function DragReadout()
    local node, window, mode = drag.node, drag.window, drag.mode
    if mode == 'move' then
        if node == window.root then
            return ('window at %d, %d'):format(window.pos[1], window.pos[2])
        end
        return ('offset %d, %d'):format(node.off[1], node.off[2])
    elseif mode:sub(1, 3) == 'pad' then
        return ('padding  left %d  top %d  right %d  bottom %d'):format(node.pad[1], node.pad[2], node.pad[3], node.pad[4])
    elseif node.type == 'bar' or node.type == 'spacer' then
        return ('%d x %d'):format(node.w, node.h)
    elseif node.type == 'icons' then
        return ('icon size %d'):format(node.size)
    elseif node.type == 'repeat' then
        return ('gap between copies %d'):format(node.itemGap)
    elseif node == window.root and mode == 'w' then
        return ('window width %d'):format(window.width)
    end
    return ('gap %d'):format(node.gap)
end

local function HandleUnder(mx, my)
    for _, handle in ipairs(handles) do
        if math.abs(mx - handle.x) <= handleReach and math.abs(my - handle.y) <= handleReach then
            return handle
        end
    end
    return nil
end

-- Before the windows are drawn: carries on a drag, or begins one on a handle
local function UpdateMouse()
    local mx, my = imgui.GetMousePos()

    if drag ~= nil then
        if imgui.IsMouseDown(0) then
            ApplyDrag(mx, my)
            imgui.SetTooltip(DragReadout())
        else
            drag = nil
        end
        return
    end

    local handle = HandleUnder(mx, my)
    if handle ~= nil and selected ~= nil and not editorHovered then
        imgui.SetTooltip(('Drag: %s'):format(handle.what))
        if imgui.IsMouseClicked(0) then
            drag = { mode = handle.mode, node = selected, window = windows[selectedWindow], lastX = mx, lastY = my, restX = 0, restY = 0 }
        end
    end
end

-- After the windows: the handles, over everything
local function DrawHandles()
    if #handles == 0 or imgui.GetForegroundDrawList == nil then
        return
    end
    local drawList = imgui.GetForegroundDrawList()
    for _, handle in ipairs(handles) do
        Rect(drawList, handle.x - 4, handle.y - 4, 8, 8, handle.pad and outerColor or innerColor, true)
        Rect(drawList, handle.x - 4, handle.y - 4, 8, 8, barBorder, false)
    end
end

local size = { 0, 0 }
local start = { 0, 0 }
local dummyOpen = { true }
local ownPadding = { 0, 0 }
local dummyFlags = nil

local function DrawDummyWindow(index, window)
    if not window.visible then
        return
    end

    -- never moved by imgui: a drag on its outermost piece moves it, as a drag on any other moves that
    dummyFlags = dummyFlags or bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoMove)

    -- the theme's look, as the real windows have it, or the window's own
    if window.useTheme then
        style.PushFull()
    else
        ownPadding[1], ownPadding[2] = window.padding, window.padding
        imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ownPadding)
        imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, window.rounding)
        imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, window.borderSize)
        imgui.PushStyleColor(ImGuiCol_WindowBg, window.back)
        imgui.PushStyleColor(ImGuiCol_Border, window.border)
        imgui.PushStyleColor(ImGuiCol_Text, window.text)
    end
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, itemSpacing)

    if window._place then
        imgui.SetNextWindowPos(window.pos, ImGuiCond_Always)
        window._place = nil
    else
        imgui.SetNextWindowPos(window.pos, ImGuiCond_FirstUseEver)
    end

    dummyOpen[1] = true
    if imgui.Begin(('winxidev.%s.%d'):format(window.name, window.root._id), dummyOpen, dummyFlags) then
        if window.useTheme then
            shadow.Draw()
        end

        Measure(window.root)
        local ow, oh = OuterSize(window.root)
        local inset = window.useTheme and style.Padding() or window.padding
        local width = math.max(ow, window.width - 2 * inset)
        window._drawnWidth = width + 2 * inset

        local x, y = imgui.GetCursorScreenPos()
        Draw(window.root, imgui.GetWindowDrawList(), window, x, y, width, 0)

        -- the room the pieces take, so that the window is the size of them
        start[1], start[2] = x, y
        imgui.SetCursorScreenPos(start)
        size[1], size[2] = width, oh
        imgui.Dummy(size)

        if drag == nil then
            window.pos[1], window.pos[2] = imgui.GetWindowPos()
        end

        -- over a button or a tab as well: those take the click for themselves otherwise
        if imgui.IsWindowHovered(ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 0) and drag == nil then
            local mx, my = imgui.GetMousePos()
            local best, copy, seen = nil, 1, { }
            for _, hit in ipairs(hits) do
                if hit.window == window then
                    seen[hit.node] = (seen[hit.node] or 0) + 1
                    if mx >= hit.x and mx <= hit.x + hit.w and my >= hit.y and my <= hit.y + hit.h
                    and (best == nil or hit.depth >= best.depth) then
                        best, copy = hit, seen[hit.node]
                    end
                end
            end

            if best ~= nil then
                -- a note shows as the mouse rests on its piece
                if best.node.note and best.node.note ~= '' then
                    imgui.SetTooltip(best.node.note)
                end
                -- a click picks the innermost piece under the mouse up, to be moved while it is held
                if imgui.IsMouseClicked(0) and HandleUnder(mx, my) == nil then
                    selected, selectedCopy, selectedWindow = best.node, copy, index
                    drag = { mode = 'move', node = best.node, window = window, lastX = mx, lastY = my, restX = 0, restY = 0 }
                end
            end
        end
    end
    imgui.End()

    imgui.PopStyleVar()
    if window.useTheme then
        style.Pop()
    else
        imgui.PopStyleColor(3)
        imgui.PopStyleVar(3)
    end
end

----------------------------------------------------------------------------------------------------
-- The editor
----------------------------------------------------------------------------------------------------

local showEditor = { false }
local box = { 0 }
local text = { '' }
local kinds = { 'text', 'bar', 'icons', 'button', 'tabs', 'spacer', 'fill', 'row', 'column', 'repeat' }
local sources = { 'status', 'item', 'plain' }
local addKind = 1
local noteSize = { 0, 70 }

local function Int(label, tbl, key, min, max)
    box[1] = tbl[key]
    if imgui.DragInt(label, box, 0.25, min, max) then
        tbl[key] = math.max(min, math.min(max, box[1]))
    end
end

local function Float(label, tbl, key, min, max)
    box[1] = tbl[key]
    if imgui.SliderFloat(label, box, min, max, '%.2f') then
        tbl[key] = box[1]
    end
end

local function Check(label, tbl, key)
    box[1] = tbl[key] and true or false
    if imgui.Checkbox(label, box) then
        tbl[key] = box[1] and true or false
    end
end

local function String(label, tbl, key)
    text[1] = tbl[key] or ''
    if imgui.InputText(label, text, 128) then
        tbl[key] = text[1]
    end
end

local function Note(label, tbl)
    imgui.Text('Note')
    text[1] = tbl.note or ''
    if imgui.InputTextMultiline(label, text, 2048, noteSize) then
        tbl.note = text[1]
    end
end

local function Colour(label, tbl, key, fallback)
    if tbl[key] == nil then
        if imgui.Button(('Give It A %s Of Its Own'):format(label)) then
            tbl[key] = { fallback[1], fallback[2], fallback[3], fallback[4] }
        end
        return
    end
    imgui.ColorEdit4(label, tbl[key])
    imgui.SameLine()
    if imgui.Button(('Theme\'s##%s'):format(label)) then
        tbl[key] = nil
    end
end

local function NewPiece(kind)
    local node
    if kind == 'text' then node = Text('Text')
    elseif kind == 'bar' then node = Bar('bar', 80, txtH, 0.5, hp, '')
    elseif kind == 'icons' then node = Icons('icons', 'status', 6, 16, 2, 0)
    elseif kind == 'button' then node = Button('Button')
    elseif kind == 'tabs' then node = Tabs('one,two')
    elseif kind == 'spacer' then node = Spacer(8, 8, false)
    elseif kind == 'fill' then node = Fill()
    elseif kind == 'row' then node = Row('row', 8)
    elseif kind == 'repeat' then node = Repeat('repeat', 3, 4)
    else node = Column('column', 4) end
    AssignIds(node)
    return node
end

-- The piece that holds another, and the other's place in it
local function FindParent(node, wanted)
    for index, child in ipairs(node.children or { }) do
        if child == wanted then
            return node, index
        end
        local parent, place = FindParent(child, wanted)
        if parent ~= nil then
            return parent, place
        end
    end
    return nil
end

local function DrawTree(node, depth)
    if depth > 0 then
        imgui.Indent(14)
    end
    local noted = (node.note and node.note ~= '') and '  *' or ''
    local label = ('%s: %s%s##winxidev.node.%d'):format(node.type, node.label or '', noted, node._id)
    if imgui.Selectable(label, node == selected) then
        selected, selectedCopy = node, 1
    end
    for _, child in ipairs(node.children or { }) do
        DrawTree(child, depth + 1)
    end
    if depth > 0 then
        imgui.Unindent(14)
    end
end

local function DrawWindowSettings(window)
    String('Name##winxidev.w', window, 'name')
    Check('Visible##winxidev.w', window, 'visible')
    if imgui.InputInt2('Position##winxidev.w', window.pos) then
        window._place = true
    end
    Int('Width (0: To Fit)##winxidev.w', window, 'width', 0, 1200)
    Check('Shared Theme\'s Look##winxidev.w', window, 'useTheme')
    if not window.useTheme then
        Int('Padding##winxidev.w', window, 'padding', 0, 60)
        Int('Rounding##winxidev.w', window, 'rounding', 0, 20)
        Int('Border Size##winxidev.w', window, 'borderSize', 0, 6)
        imgui.ColorEdit4('Background##winxidev.w', window.back)
        imgui.ColorEdit4('Border##winxidev.w', window.border)
        imgui.ColorEdit4('Text##winxidev.w', window.text)
    end
    Note('##winxidev.w.note', window)
end

local function DrawPieceSettings(window, node)
    String('Label##winxidev.p', node, 'label')
    Note('##winxidev.p.note', node)

    imgui.Text('Padding')
    Int('Left##winxidev.pad', node.pad, 1, 0, 200)
    Int('Top##winxidev.pad', node.pad, 2, 0, 200)
    Int('Right##winxidev.pad', node.pad, 3, 0, 200)
    Int('Bottom##winxidev.pad', node.pad, 4, 0, 200)
    imgui.Text('Offset (moves it without moving anything else)')
    Int('X##winxidev.off', node.off, 1, -600, 600)
    Int('Y##winxidev.off', node.off, 2, -600, 600)
    if imgui.Button('Back Where It Belongs') then
        node.off[1], node.off[2] = 0, 0
    end

    local kind = node.type
    imgui.Text(kind)
    if kind == 'text' then
        String('Text##winxidev.p', node, 'text')
        Colour('Colour', node, 'color', window.text)
    elseif kind == 'button' then
        String('Text##winxidev.p', node, 'text')
    elseif kind == 'tabs' then
        String('Tabs (With Commas)##winxidev.p', node, 'text')
    elseif kind == 'bar' then
        Int('Width##winxidev.p', node, 'w', 1, 1000)
        Int('Height##winxidev.p', node, 'h', 1, 200)
        Float('Filled##winxidev.p', node, 'fraction', 0, 1)
        String('Text Over It##winxidev.p', node, 'text')
        imgui.ColorEdit4('Colour##winxidev.p', node.color)
    elseif kind == 'icons' then
        if imgui.BeginCombo('Pictures##winxidev.p', node.source or 'plain', ImGuiComboFlags_None) then
            for _, source in ipairs(sources) do
                if imgui.Selectable(source, source == node.source) then
                    node.source = source
                end
            end
            imgui.EndCombo()
        end
        Int('Count##winxidev.p', node, 'count', 0, 200)
        Int('Size##winxidev.p', node, 'size', 1, 128)
        Int('Gap##winxidev.p', node, 'gap', 0, 60)
        Int('Per Row (0: All)##winxidev.p', node, 'perRow', 0, 40)
    elseif kind == 'spacer' then
        Int('Width##winxidev.p', node, 'w', 0, 1000)
        Int('Height##winxidev.p', node, 'h', 0, 400)
        Check('Fill (takes the room left in a row)##winxidev.p', node, 'fill')
    else
        Int('Gap Between Pieces##winxidev.p', node, 'gap', 0, 100)
        if kind == 'row' then
            Check('Centre Pieces Vertically##winxidev.p', node, 'center')
        elseif kind == 'repeat' then
            Int('Times##winxidev.p', node, 'count', 0, 30)
            Int('Gap Between Copies##winxidev.p', node, 'itemGap', 0, 100)
        end
    end
end

local function DrawPieceButtons(window)
    local node = selected
    local container = node ~= nil and node.children ~= nil
    local parent, place = nil, nil
    if node ~= nil then
        parent, place = FindParent(window.root, node)
    end

    imgui.SetNextItemWidth(110)
    if imgui.BeginCombo('##winxidev.kind', kinds[addKind], ImGuiComboFlags_None) then
        for index, kind in ipairs(kinds) do
            if imgui.Selectable(kind, index == addKind) then
                addKind = index
            end
        end
        imgui.EndCombo()
    end
    imgui.SameLine()
    if imgui.Button('Add Inside') then
        local target = container and node or window.root
        table.insert(target.children, NewPiece(kinds[addKind]))
        selected, selectedCopy = target.children[#target.children], 1
    end
    imgui.SameLine()
    if imgui.Button('Add After') and parent ~= nil then
        table.insert(parent.children, place + 1, NewPiece(kinds[addKind]))
        selected, selectedCopy = parent.children[place + 1], 1
    end

    if parent ~= nil then
        if imgui.Button('Up') and place > 1 then
            parent.children[place], parent.children[place - 1] = parent.children[place - 1], parent.children[place]
        end
        imgui.SameLine()
        if imgui.Button('Down') and place < #parent.children then
            parent.children[place], parent.children[place + 1] = parent.children[place + 1], parent.children[place]
        end
        imgui.SameLine()
        if imgui.Button('Duplicate') then
            local copy = Copy(node)
            AssignIds(copy)
            table.insert(parent.children, place + 1, copy)
            selected, selectedCopy = copy, 1
        end
        imgui.SameLine()
        if imgui.Button('Delete') then
            table.remove(parent.children, place)
            selected, selectedCopy = parent, 1
        end
    end
end

local function ResetWindow(index)
    local name = windows[index].name
    for _, fresh in ipairs(DefaultWindows()) do
        if fresh.name == name then
            fresh.pos = windows[index].pos
            AssignIds(fresh.root)
            windows[index] = fresh
            selected = nil
            return
        end
    end
    Say(('There is no window called %s to go back to.'):format(name))
end

local editorSize = { 430, 780 }

local function DrawEditor()
    imgui.SetNextWindowSize(editorSize, ImGuiCond_FirstUseEver)
    if imgui.Begin('winxi dev', showEditor, ImGuiWindowFlags_NoSavedSettings) then
        editorHovered = imgui.IsWindowHovered(ImGuiHoveredFlags_ChildWindows or 0)

        if selectedWindow > #windows then
            selectedWindow = math.max(1, #windows)
        end
        local window = windows[selectedWindow]

        if imgui.Button('Save') then
            SaveLayouts(false)
        end
        imgui.SameLine()
        if imgui.Button('Reset Window') and window ~= nil then
            ResetWindow(selectedWindow)
            window = windows[selectedWindow]
        end
        imgui.SameLine()
        if imgui.Button('Reset All') then
            windows = DefaultWindows()
            for _, fresh in ipairs(windows) do
                AssignIds(fresh.root)
            end
            selected, selectedWindow = nil, 1
            window = windows[1]
        end
        imgui.SameLine()
        if imgui.Button('New Window') then
            local fresh = Window('new', 200, 200, Column('new', 4, { Text('Text') }))
            AssignIds(fresh.root)
            windows[#windows + 1] = fresh
            selectedWindow, selected = #windows, nil
            window = fresh
        end
        imgui.SameLine()
        if imgui.Button('Copy Window') and window ~= nil then
            local copy = Copy(window)
            copy.name = window.name .. ' copy'
            copy.pos = { window.pos[1] + 30, window.pos[2] + 30 }
            AssignIds(copy.root)
            windows[#windows + 1] = copy
            selectedWindow, selected = #windows, nil
            window = copy
        end

        imgui.Checkbox('Outline Every Piece', showBoxes)
        imgui.TextDisabled('Click a piece and drag it. Green handles: size. Orange: padding.')
        imgui.TextDisabled('Drag a window by its outermost piece.')

        if window ~= nil then
            if imgui.BeginCombo('Window##winxidev.pick', window.name, ImGuiComboFlags_None) then
                for index, each in ipairs(windows) do
                    if imgui.Selectable(('%s##winxidev.pick.%d'):format(each.name, index), index == selectedWindow) then
                        selectedWindow, selected = index, nil
                        window = each
                    end
                end
                imgui.EndCombo()
            end

            if imgui.CollapsingHeader('Window', ImGuiTreeNodeFlags_DefaultOpen) then
                DrawWindowSettings(window)
            end

            if imgui.CollapsingHeader('Pieces', ImGuiTreeNodeFlags_DefaultOpen) then
                DrawPieceButtons(window)
                imgui.BeginChild('winxidev.tree', { 0, 180 }, ImGuiChildFlags_Borders)
                DrawTree(window.root, 0)
                imgui.EndChild()
            end

            if selected ~= nil and imgui.CollapsingHeader('Selected Piece', ImGuiTreeNodeFlags_DefaultOpen) then
                DrawPieceSettings(window, selected)
            end
        end
    else
        editorHovered = false
    end
    imgui.End()
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

LoadLayouts()

ashita.events.register('unload', 'winxidev_unload', function()
    SaveLayouts(true)
end)

ashita.events.register('command', 'winxidev_command', function(e)
    local args = e.command:args()
    if #args == 0 or args[1]:lower() ~= '/winxidev' then
        return
    end
    e.blocked = true
    showEditor[1] = not showEditor[1]
end)

ashita.events.register('d3d_present', 'winxidev_present', function()
    if not showEditor[1] then
        return
    end

    -- the shared theme, as the real windows have it
    theme.Configure(true, nil)

    -- against where the handles were a frame ago
    UpdateMouse()

    for index = #hits, 1, -1 do
        hits[index] = nil
    end
    for index = #handles, 1, -1 do
        handles[index] = nil
    end
    copiesDrawn = 0

    for index, window in ipairs(windows) do
        DrawDummyWindow(index, window)
    end
    DrawHandles()

    DrawEditor()
end)
