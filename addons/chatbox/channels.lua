-- Channel names and tabs, by the game's chat mode (text_in's mode, low byte). Outgoing and incoming
-- lines have their own modes: 4 a tell sent, 12 one received, and so on. No Ashita dependency.
local M = {}

local function Set(list)
    local set = {}
    for _, mode in ipairs(list) do set[mode] = true end
    return set
end

-- Sent and received modes: 1 a line said, 9 one heard, and so on (received is sent + 8). Yell, Phoenix's
-- cross-zone shout, is 3 and 11.
local say, shout, yell, tell, party = Set{ 1, 9 }, Set{ 2, 10 }, Set{ 3, 11 }, Set{ 4, 12 }, Set{ 5, 13 }
local linkshell, linkshell2 = Set{ 6, 14, 205 }, Set{ 213, 214, 217 }
local unity = Set{ 211, 212 }

-- The game's full log has a tab for each channel, Square moving between them left to right. Its filter
-- is the channel's number, not the tab's place: as seen in the game (Square through every tab, the
-- title each showed), Window 0, Party 1, Linkshell 2, Say 3, Tell 4, Shout 5, Unity 6, Linkshell 2 7,
-- Assist J 9. Assist E was not one of these; 10 is taken for it. The tabs run, left to right, Window,
-- Say, Tell, Party, Linkshell 1, Linkshell 2, Assist (J), Assist (E), Unity and Shout: place is that,
-- for the title, and name what the tab says. Each shows the modes of its channel, sent and received;
-- Window shows everything. Which Assist channel has modes 220/221 and which 222/223 is a guess,
-- FancyChat listing 220 and 222 as assist without saying which is which.
M.Filters = {
    [0] = { name = 'Window', place = 1 },
    [3] = { name = 'Say', place = 2, modes = say },
    [4] = { name = 'Tell', place = 3, modes = tell },
    [1] = { name = 'Party', place = 4, modes = party },
    [2] = { name = 'Linkshell 1', place = 5, modes = linkshell },
    [7] = { name = 'Linkshell 2', place = 6, modes = linkshell2 },
    [9] = { name = 'Assist (J)', place = 7, modes = Set{ 222, 223 } },
    [10] = { name = 'Assist (E)', place = 8, modes = Set{ 220, 221 } },
    [6] = { name = 'Unity', place = 9, modes = unity },
    [5] = { name = 'Shout', place = 10, modes = Set{ 2, 10, 3, 11 } }, -- yells too: the game has no Yell tab
}
local tabCount = 0
for _ in pairs(M.Filters) do tabCount = tabCount + 1 end

-- The expanded title: the tab's name and its place along the top, 'Window 1/10'; made once each.
local titles = {}
function M.FilterTitle(filterValue)
    local filter = M.Filters[filterValue]
    if not filter then return nil end
    titles[filterValue] = titles[filterValue] or ('%s %d/%d'):format(filter.name, filter.place, tabCount)
    return titles[filterValue]
end

-- The channel a line the player sent went out on, by its mode; nil for anything else.
local sent = { [1] = 'Say', [2] = 'Shout', [3] = 'Yell', [4] = 'Tell', [5] = 'Party', [6] = 'Linkshell',
    [213] = 'Linkshell 2' }
function M.Sent(mode) return sent[mode] end

-- The channel a typed line names with its command (/p hello), or nil where it names none.
local commands = { s = 'Say', say = 'Say', sh = 'Shout', shout = 'Shout', y = 'Yell', yell = 'Yell',
    p = 'Party', party = 'Party', l = 'Linkshell', linkshell = 'Linkshell', l2 = 'Linkshell 2',
    linkshell2 = 'Linkshell 2', t = 'Tell', tell = 'Tell', u = 'Unity', unity = 'Unity' }
function M.Typed(text)
    if type(text) ~= 'string' then return nil end
    local command = text:match('^%s*/(%w+)%s') or text:match('^%s*/(%w+)$')
    return command and commands[command:lower()] or nil
end

-- Observe /cm without consuming it: FFXI still changes the actual input mode.
function M.ModeCommand(text)
    if type(text) ~= 'string' then return nil end
    local command, mode = text:lower():match('^%s*/(%w+)%s+(%w+)%s*$')
    if command == 'cm' or command == 'chatmode' then return commands[mode] end
end

-- The 0x0E0 equipped-linkshell packet identifies the bag/slot for each pearl.
-- These are NOT equipment slots in Ashita's inventory API (which has only 16).
local pearls = {}
function M.ResetLinkshells() pearls = {} end
function M.LinkshellPacket(data)
    if type(data) ~= 'string' or #data < 7 then return end
    local number, index, bag = data:byte(5, 7)
    if number == 1 or number == 2 then
        pearls[number] = index ~= 0 and { bag = bag, index = index } or nil
    end
end

-- Extra data stores a little-endian six-bit alphabet at byte offset 9.
function M.LinkshellName(inventory, number)
    local bit = require('bit')
    local entry = pearls[number]
    if not entry then return nil end
    local item = inventory:GetContainerItem(entry.bag, entry.index)
    if not item or not item.Extra or not item.Id or item.Id == 0 or item.Id == 65535 then return nil end
    local extra = item.Extra
    local function byte(offset)
        if type(extra) == 'string' then return extra:byte(offset + 1) or 0 end
        return tonumber(extra[offset]) or 0
    end
    local alphabet, name = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', {}
    for i = 0, 19 do
        local offset, shift = 9 + math.floor(i * 6 / 8), (i * 6) % 8
        local code = bit.band(bit.rshift(byte(offset) + byte(offset + 1) * 256, shift), 63)
        if code == 0 or code == 63 then break end
        name[#name + 1] = alphabet:sub(code, code)
    end
    local value = table.concat(name)
    return value ~= '' and value or nil
end

function M.Title(channel)
    local number = channel == 'Linkshell' and 1 or channel == 'Linkshell 2' and 2
    if not number then return channel end
    local ok, name = pcall(function()
        return M.LinkshellName(AshitaCore:GetMemoryManager():GetInventory(), number)
    end)
    return ('Linkshell %d'):format(number) .. (ok and name and (': ' .. name) or '')
end

return M
