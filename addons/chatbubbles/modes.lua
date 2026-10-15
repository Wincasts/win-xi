-- Player packet channels and NPC text-log channels use separate settings keys.
local M = { All = {}, Outgoing = {
    [0] = true, [1] = true, [4] = true, [5] = true, [8] = true,
    [26] = true, [27] = true, [33] = true, [34] = true, [35] = true,
} };
local labels = {
    [0] = 'Say', [1] = 'Shout', [2] = 'Unknown 2', [3] = 'Tell', [4] = 'Party / Alliance',
    [5] = 'Linkshell 1', [6] = 'System 1', [7] = 'System 2', [8] = 'Emote',
    [12] = 'GM prompt', [13] = 'Say (no speaker object)', [14] = 'Shout (no speaker object)',
    [15] = 'Party (no speaker object)', [16] = 'Linkshell 1 (no speaker object)',
    [26] = 'Yell', [27] = 'Linkshell 2', [28] = 'Linkshell 2 (no speaker object)',
    [29] = 'System 3', [30] = 'Linkshell 3 (reserved)', [31] = 'Linkshell 3 (no speaker object)',
    [33] = 'Unity', [34] = 'Assist (Japanese)', [35] = 'Assist (English)',
};
for id = 0, 35 do
    M.All[#M.All + 1] = { id = id, key = tostring(id), label = labels[id] or ('Unknown / reserved ' .. id), default = id == 0 };
end
M.Npc = { [142] = true, [144] = true, [150] = true, [151] = true, [152] = true, [210] = true };
for _, id in ipairs({ 150, 151, 152, 142, 144, 210 }) do
    local label = (id == 150 or id == 151) and 'NPC dialogue (text channel)'
        or id == 152 and 'NPC prompt / dialogue (text channel)'
        or id == 210 and 'Party / trust NPC text' or 'NPC system text';
    M.All[#M.All + 1] = { id = id, key = 'npc:' .. id, label = label, source = 'text', default = id == 150 or id == 151 };
end
return M;
