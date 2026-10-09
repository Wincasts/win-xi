addon.name    = 'winxidev'
addon.author  = 'Win'
addon.version = '0.1'
addon.desc    = 'Development only: dummy copies of the UI windows, to lay out and restyle by hand.'
addon.link    = 'https://github.com/Wincasts/ffxi-addons'

-- A workbench, not a tool to play with. It draws stand-ins for the UI windows (me, us, tgt, pet, inv,
-- treas, recast) out of plain pieces: text, bars, blocks of icons, spacers, rows and columns. Every
-- piece's padding, offset and size, and every window's look and place, can be changed in the editor,
-- and pieces added, moved and taken away. What is settled on here is then written into the real
-- windows' code by hand.
--
--   /winxidev    opens or closes the editor (the dummy windows show while it is open)
--
-- The layouts are kept in config\addons\winxidev\layouts.lua, written by the editor's Save button and
-- when the addon is unloaded.

require('common')
local bit = require('bit')
local imgui = require('imgui')

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
local function Bar(label, w, h, fraction, color) return Node('bar', { label = label, w = w, h = h, fraction = fraction, color = color, back = { 0.15, 0.15, 0.15, 0.9 }, text = label, rounding = 0 }) end
local function Icons(label, count, size, gap, perRow) return Node('icons', { label = label, count = count, size = size, gap = gap or 2, perRow = perRow or 0, color = { 0.45, 0.55, 0.75, 1.0 } }) end
local function Spacer(w, h, fill) return Node('spacer', { label = fill and 'fill' or 'spacer', w = w or 0, h = h or 0, fill = fill or false }) end
local function Fill() return Spacer(4, 0, true) end

local hp = { 0.83, 0.33, 0.28, 1.0 }
local mp = { 0.82, 0.60, 0.27, 1.0 }
local tp = { 0.23, 0.67, 0.91, 1.0 }
local xp = { 0.01, 0.67, 0.07, 1.0 }
local dim = { 0.70, 0.70, 0.70, 1.0 }

local function Window(name, x, y, root)
    return {
        name = name, visible = true, pos = { x, y }, width = 0, padding = 10, rounding = 0, borderSize = 1,
        back = { 0.08, 0.08, 0.08, 0.8 }, border = { 0.69, 0.68, 0.78, 1.0 }, text = { 1, 1, 1, 1 },
        root = root,
    }
end

local function DefaultWindows()
    return {
        Window('me', 60, 60, Column('me', 4, {
            Row('header', 4, { Text('Win'), Fill(), Text('PUP75/WAR37') }),
            Bar('HP 1400', 256, 14, 0.9, hp), Bar('MP  800', 256, 14, 0.6, mp),
            Bar('TP 1200', 256, 14, 0.4, tp), Bar('XP 12.3k', 256, 14, 0.3, xp),
        })),
        Window('us', 360, 60, Column('us', 4, {
            Repeat('members', 6, 6, {
                Row('name line', 4, { Text('Sample'), Fill(), Text('WAR75/NIN37') }),
                Row('bars', 4, { Bar('1400', 82, 14, 0.9, hp), Bar('800', 82, 14, 0.6, mp), Bar('1200', 82, 14, 0.4, tp) }),
                Icons('buffs', 8, 14, 2, 0),
            }),
        })),
        Window('tgt', 60, 220, Column('tgt', 4, {
            Row('header', 4, { Text('Target Name'), Fill(), Text('12.3m', dim) }),
            Bar('76%', 256, 14, 0.76, hp),
            Icons('statuses', 10, 16, 2, 0),
        })),
        Window('pet', 60, 330, Column('pet', 4, {
            Row('header', 4, { Text('Lobo'), Fill(), Text('Automaton', dim) }),
            Bar('HP 900', 256, 14, 0.8, hp),
            Row('bars', 4, { Bar('MP 300', 126, 14, 0.5, mp), Bar('TP 800', 126, 14, 0.27, tp) }),
        })),
        Window('inv', 700, 60, Column('inv', 6, {
            Row('tabs', 10, { Text('bag'), Text('satchel', dim), Text('ward', dim), Text('house', dim) }),
            Icons('slots', 30, 32, 8, 5),
            Row('foot', 4, { Text('1,234,567 G'), Fill(), Text('18/30') }),
        })),
        Window('treas', 700, 380, Column('treas', 6, {
            Row('buttons', 8, { Text('[Roll All]'), Text('[Pass All]') }),
            Repeat('pool', 3, 4, {
                Row('item', 10, { Text('Item Name'), Fill(), Text(' 254', dim), Text('Winner'), Text('[Roll]'), Text('[Pass]') }),
            }),
        })),
        Window('recast', 360, 420, Column('recast', 2, {
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

local function SaveLayouts(quiet)
    local folder = Folder()
    ashita.fs.create_directory(folder)
    local out = { 'return ' }
    Serialize(windows, '', out)
    out[#out + 1] = '\n'

    local file, problem = io.open(folder .. 'layouts.lua', 'w')
    if file == nil then
        Say(('Could not save: %s'):format(tostring(problem)))
        return
    end
    file:write(table.concat(out))
    file:close()
    if not quiet then
        Say('Saved to config\\addons\\winxidev\\layouts.lua')
    end
end

local function LoadLayouts()
    local chunk = loadfile(Folder() .. 'layouts.lua')
    local ok, saved = false, nil
    if chunk ~= nil then
        ok, saved = pcall(chunk)
    end
    windows = (ok and type(saved) == 'table' and #saved > 0) and saved or DefaultWindows()
    for _, window in ipairs(windows) do
        AssignIds(window.root)
    end
end

----------------------------------------------------------------------------------------------------
-- Laying out and drawing
----------------------------------------------------------------------------------------------------

local selected = nil         -- the piece being edited
local selectedWindow = 1     -- the window being edited, by its place in windows
local showBoxes = { false }  -- outline every piece
local dragPieces = { false } -- dragging in a dummy window moves the selected piece, not the window
local hits = { }             -- every piece drawn this frame: { node, x, y, w, h, depth, window }

local function OuterSize(node)
    return node._w + node.pad[1] + node.pad[3], node._h + node.pad[2] + node.pad[4]
end

-- Works out each piece's own size (without its padding), from the leaves up
local function Measure(node)
    local w, h = 0, 0
    local kind = node.type
    if kind == 'text' then
        w, h = imgui.CalcTextSize(node.text or '')
        h = h or 14
    elseif kind == 'bar' then
        w, h = node.w, node.h
    elseif kind == 'spacer' then
        w, h = node.w, node.h
    elseif kind == 'icons' then
        local count = math.max(0, node.count)
        local per = (node.perRow > 0) and math.min(node.perRow, count) or count
        local rows = (per > 0) and math.ceil(count / per) or 0
        w = per * node.size + math.max(0, per - 1) * node.gap
        h = rows * node.size + math.max(0, rows - 1) * node.gap
    else
        local children = node.children
        for index, child in ipairs(children) do
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
local outerColor = { 1.0, 0.6, 0.1, 1.0 }   -- the selected piece with its padding
local innerColor = { 0.3, 0.9, 0.4, 1.0 }   -- the selected piece itself

local Draw

local function DrawChildren(node, drawList, window, x, y, width, depth)
    local children = node.children
    if node.type == 'row' then
        local spare, fills = width - node._w, 0
        for _, child in ipairs(children) do
            if child.type == 'spacer' and child.fill then
                fills = fills + 1
            end
        end
        local across = x
        for _, child in ipairs(children) do
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
        for _, child in ipairs(children) do
            local _, ch = OuterSize(child)
            Draw(child, drawList, window, x, down, width, depth)
            down = down + ch + node.gap
        end
    end
end

-- Draws a piece with its top left corner (padding and all) at x, y, in the width it has been given
Draw = function(node, drawList, window, x, y, width, depth)
    local ow, oh = OuterSize(node)
    local kind = node.type
    local container = (kind == 'column' or kind == 'row' or kind == 'repeat')
    if container or (kind == 'spacer' and node.fill) then
        ow = math.max(ow, width or ow)
    end

    local cx, cy = x + node.pad[1] + node.off[1], y + node.pad[2] + node.off[2]
    local cw, ch = ow - node.pad[1] - node.pad[3], node._h

    hits[#hits + 1] = { node = node, x = x, y = y, w = ow, h = oh, depth = depth, window = window }

    if kind == 'text' then
        a[1], a[2] = cx, cy
        drawList:AddText(a, imgui.GetColorU32(node.color or window.text), node.text or '')
    elseif kind == 'bar' then
        Rect(drawList, cx, cy, node.w, node.h, node.back, true, node.rounding)
        Rect(drawList, cx, cy, node.w * math.max(0, math.min(1, node.fraction)), node.h, node.color, true, node.rounding)
        if node.text and node.text ~= '' then
            local _, th = imgui.CalcTextSize(node.text)
            a[1], a[2] = cx + 4, cy + math.floor((node.h - (th or 14)) / 2)
            drawList:AddText(a, imgui.GetColorU32(window.text), node.text)
        end
    elseif kind == 'icons' then
        local per = (node.perRow > 0) and node.perRow or math.max(1, node.count)
        for index = 0, node.count - 1 do
            local column, row = index % per, math.floor(index / per)
            Rect(drawList, cx + column * (node.size + node.gap), cy + row * (node.size + node.gap), node.size, node.size, node.color, true, 2)
        end
    elseif kind == 'repeat' then
        for index = 0, node.count - 1 do
            DrawChildren(node, drawList, window, cx, cy + index * (node._itemHeight + node.itemGap), cw, depth + 1)
        end
    elseif container then
        DrawChildren(node, drawList, window, cx, cy, cw, depth + 1)
    end

    if node == selected then
        Rect(drawList, x, y, ow, oh, outerColor, false)
        Rect(drawList, cx, cy, cw, ch, innerColor, false)
    elseif showBoxes[1] then
        Rect(drawList, x, y, ow, oh, boxColor, false)
    end
end

local padding = { 0, 0 }
local size = { 0, 0 }
local lastMouseX, lastMouseY = 0, 0
local dragging = false
local dummyOpen = { true }

local function DrawDummyWindow(index, window)
    if not window.visible then
        return
    end

    local flags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings)
    if dragPieces[1] then
        flags = bit.bor(flags, ImGuiWindowFlags_NoMove)
    end

    padding[1], padding[2] = window.padding, window.padding
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, padding)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, window.rounding)
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, window.borderSize)
    imgui.PushStyleColor(ImGuiCol_WindowBg, window.back)
    imgui.PushStyleColor(ImGuiCol_Border, window.border)

    if window._place then
        -- typed into the editor: put there once
        imgui.SetNextWindowPos(window.pos, ImGuiCond_Always)
        window._place = nil
    else
        imgui.SetNextWindowPos(window.pos, ImGuiCond_FirstUseEver)
    end

    dummyOpen[1] = true
    if imgui.Begin(('winxidev.%s.%d'):format(window.name, window.root._id), dummyOpen, flags) then
        Measure(window.root)
        local ow, oh = OuterSize(window.root)
        local width = math.max(ow, window.width - 2 * window.padding)

        local x, y = imgui.GetCursorScreenPos()
        size[1], size[2] = width, oh
        imgui.Dummy(size)
        Draw(window.root, imgui.GetWindowDrawList(), window, x, y, width, 0)

        window.pos[1], window.pos[2] = imgui.GetWindowPos()

        -- a click picks the piece under the mouse: the innermost one
        if imgui.IsWindowHovered() and imgui.IsMouseClicked(0) then
            local mx, my = imgui.GetMousePos()
            local best = nil
            for _, hit in ipairs(hits) do
                if hit.window == window and mx >= hit.x and mx <= hit.x + hit.w and my >= hit.y and my <= hit.y + hit.h
                and (best == nil or hit.depth >= best.depth) then
                    best = hit
                end
            end
            if best ~= nil then
                selected = best.node
                selectedWindow = index
                dragging = dragPieces[1]
                lastMouseX, lastMouseY = mx, my
            end
        end
    end
    imgui.End()

    imgui.PopStyleColor(2)
    imgui.PopStyleVar(3)
end

----------------------------------------------------------------------------------------------------
-- The editor
----------------------------------------------------------------------------------------------------

local showEditor = { false }
local box = { 0 }
local text = { '' }
local kinds = { 'text', 'bar', 'icons', 'spacer', 'fill', 'row', 'column', 'repeat' }
local addKind = 1

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

local function Colour(label, tbl, key, fallback)
    if tbl[key] == nil then
        if imgui.Button(('Give %s##%s'):format(label, label)) then
            tbl[key] = { fallback[1], fallback[2], fallback[3], fallback[4] }
        end
        return
    end
    imgui.ColorEdit4(label, tbl[key])
end

local function NewPiece(kind)
    local node
    if kind == 'text' then node = Text('Text')
    elseif kind == 'bar' then node = Bar('Bar', 120, 14, 0.5, hp)
    elseif kind == 'icons' then node = Icons('icons', 6, 16, 2, 0)
    elseif kind == 'spacer' then node = Spacer(8, 8, false)
    elseif kind == 'fill' then node = Fill()
    elseif kind == 'row' then node = Row('row', 4)
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
    local label = ('%s: %s##winxidev.node.%d'):format(node.type, node.label or '', node._id)
    if imgui.Selectable(label, node == selected) then
        selected = node
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
    Int('Padding##winxidev.w', window, 'padding', 0, 60)
    Int('Rounding##winxidev.w', window, 'rounding', 0, 20)
    Int('Border Size##winxidev.w', window, 'borderSize', 0, 6)
    imgui.ColorEdit4('Background##winxidev.w', window.back)
    imgui.ColorEdit4('Border##winxidev.w', window.border)
    imgui.ColorEdit4('Text##winxidev.w', window.text)
end

local function DrawPieceSettings(window, node)
    String('Label##winxidev.p', node, 'label')

    imgui.Text('Padding')
    Int('Left##winxidev.pad', node.pad, 1, 0, 200)
    Int('Top##winxidev.pad', node.pad, 2, 0, 200)
    Int('Right##winxidev.pad', node.pad, 3, 0, 200)
    Int('Bottom##winxidev.pad', node.pad, 4, 0, 200)
    imgui.Text('Offset (moves it without moving anything else)')
    Int('X##winxidev.off', node.off, 1, -400, 400)
    Int('Y##winxidev.off', node.off, 2, -400, 400)

    local kind = node.type
    imgui.Text(kind)
    if kind == 'text' then
        String('Text##winxidev.p', node, 'text')
        Colour('Colour', node, 'color', window.text)
    elseif kind == 'bar' then
        Int('Width##winxidev.p', node, 'w', 1, 1000)
        Int('Height##winxidev.p', node, 'h', 1, 200)
        Int('Rounding##winxidev.p', node, 'rounding', 0, 20)
        Float('Filled##winxidev.p', node, 'fraction', 0, 1)
        String('Text##winxidev.p', node, 'text')
        imgui.ColorEdit4('Colour##winxidev.p', node.color)
        imgui.ColorEdit4('Background##winxidev.p', node.back)
    elseif kind == 'icons' then
        Int('Count##winxidev.p', node, 'count', 0, 200)
        Int('Size##winxidev.p', node, 'size', 1, 128)
        Int('Gap##winxidev.p', node, 'gap', 0, 60)
        Int('Per Row (0: All)##winxidev.p', node, 'perRow', 0, 40)
        imgui.ColorEdit4('Colour##winxidev.p', node.color)
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
        selected = target.children[#target.children]
    end
    imgui.SameLine()
    if imgui.Button('Add After') and parent ~= nil then
        table.insert(parent.children, place + 1, NewPiece(kinds[addKind]))
        selected = parent.children[place + 1]
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
            selected = copy
        end
        imgui.SameLine()
        if imgui.Button('Delete') then
            table.remove(parent.children, place)
            selected = parent
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

local function DrawEditor()
    imgui.SetNextWindowSize({ 430, 760 }, ImGuiCond_FirstUseEver)
    if imgui.Begin('winxi dev', showEditor, ImGuiWindowFlags_NoSavedSettings) then
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
        imgui.SameLine()
        imgui.Checkbox('Drag Moves The Piece', dragPieces)
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Off: dragging a dummy window moves the window.\nOn: dragging moves the piece that was clicked, by its offset.')
        end

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
                imgui.BeginChild('winxidev.tree', { 0, 200 }, ImGuiChildFlags_Borders)
                DrawTree(window.root, 0)
                imgui.EndChild()
            end

            if selected ~= nil and imgui.CollapsingHeader('Selected Piece', ImGuiTreeNodeFlags_DefaultOpen) then
                DrawPieceSettings(window, selected)
            end
        end
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

    -- a piece being dragged follows the mouse by its offset
    if dragging then
        if imgui.IsMouseDown(0) and selected ~= nil then
            local mx, my = imgui.GetMousePos()
            selected.off[1] = selected.off[1] + (mx - lastMouseX)
            selected.off[2] = selected.off[2] + (my - lastMouseY)
            lastMouseX, lastMouseY = mx, my
        else
            dragging = false
        end
    end

    for index = #hits, 1, -1 do
        hits[index] = nil
    end
    for index, window in ipairs(windows) do
        DrawDummyWindow(index, window)
    end

    DrawEditor()
end)
